/// Pure-Dart project filesystem abstraction (S1-0) so `AssetDatabase` and
/// Studio project logic run identically in memory (tests/web) and on disk
/// (`tool/studio/io_project_fs.dart`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

enum ProjectFsEntryKind { file, directory }

final class ProjectFsEntry {
  final String path;
  final ProjectFsEntryKind kind;

  const ProjectFsEntry({required this.path, required this.kind});
}

final class ProjectFsStat {
  final String path;
  final ProjectFsEntryKind kind;
  final int sizeBytes;
  final DateTime modifiedUtc;

  const ProjectFsStat({
    required this.path,
    required this.kind,
    required this.sizeBytes,
    required this.modifiedUtc,
  });
}

enum ProjectFsEventKind { created, modified, deleted, moved }

final class ProjectFsEvent {
  final ProjectFsEventKind kind;
  final String path;
  final String? previousPath;

  const ProjectFsEvent({
    required this.kind,
    required this.path,
    this.previousPath,
  });
}

/// Platform-agnostic filesystem interface rooted at a Volition project.
/// All paths are normalized POSIX-style project-relative paths (e.g.
/// `assets/meshes/hero.glb`).
abstract interface class ProjectFileSystem {
  Future<Uint8List> readBytes(String path);
  Future<String> readString(String path);
  Future<void> writeBytes(String path, Uint8List bytes);
  Future<void> writeString(String path, String contents);
  Future<bool> exists(String path);
  Future<List<ProjectFsEntry>> list(
    String directoryPath, {
    bool recursive = false,
  });
  Future<ProjectFsStat?> stat(String path);
  Stream<ProjectFsEvent> watch(String directoryPath);
  Future<void> move(String fromPath, String toPath);
  Future<void> delete(String path, {bool recursive = false});
  Future<void> createDirectory(String path, {bool recursive = true});
}

/// Normalizes a project-relative path to POSIX forward slashes with no leading
/// `./` or `/`. Rejects parent-traversal (`..`) escapes.
String normalizeProjectPath(String raw) {
  var p = raw.replaceAll('\\', '/').trim();
  while (p.startsWith('./')) {
    p = p.substring(2);
  }
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  while (p.endsWith('/') && p.isNotEmpty) {
    p = p.substring(0, p.length - 1);
  }
  if (p.isEmpty || p == '.') return '';
  final parts = <String>[];
  for (final seg in p.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isEmpty) {
        throw ArgumentError.value(
          raw,
          'path',
          'Path escapes project root via ..',
        );
      }
      parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

/// Deterministic in-memory [ProjectFileSystem] for pure-Dart tests and browser
/// previews.
final class MemoryProjectFileSystem implements ProjectFileSystem {
  final Map<String, _MemFile> _files = {};
  final Set<String> _dirs = {''};
  final StreamController<ProjectFsEvent> _events =
      StreamController<ProjectFsEvent>.broadcast();
  final DateTime Function() _clock;

  MemoryProjectFileSystem({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  @override
  Future<Uint8List> readBytes(String path) async {
    final norm = normalizeProjectPath(path);
    final file = _files[norm];
    if (file == null) {
      throw StateError('File not found in MemoryProjectFileSystem: $norm');
    }
    return Uint8List.fromList(file.bytes);
  }

  @override
  Future<String> readString(String path) async =>
      utf8.decode(await readBytes(path));

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    final norm = normalizeProjectPath(path);
    if (norm.isEmpty) {
      throw ArgumentError('Cannot write bytes to project root directory');
    }
    _ensureParentDirs(norm);
    final existed = _files.containsKey(norm);
    _files[norm] = _MemFile(Uint8List.fromList(bytes), _clock());
    _events.add(
      ProjectFsEvent(
        kind: existed
            ? ProjectFsEventKind.modified
            : ProjectFsEventKind.created,
        path: norm,
      ),
    );
  }

  @override
  Future<void> writeString(String path, String contents) =>
      writeBytes(path, Uint8List.fromList(utf8.encode(contents)));

  @override
  Future<bool> exists(String path) async {
    final norm = normalizeProjectPath(path);
    return _files.containsKey(norm) || _dirs.contains(norm);
  }

  @override
  Future<List<ProjectFsEntry>> list(
    String directoryPath, {
    bool recursive = false,
  }) async {
    final dir = normalizeProjectPath(directoryPath);
    if (!_dirs.contains(dir)) return const [];
    final prefix = dir.isEmpty ? '' : '$dir/';
    final entries = <ProjectFsEntry>[];

    for (final d in _dirs) {
      if (d == dir || d.isEmpty) continue;
      if (prefix.isNotEmpty && !d.startsWith(prefix)) continue;
      final rel = prefix.isEmpty ? d : d.substring(prefix.length);
      if (!recursive && rel.contains('/')) continue;
      entries.add(ProjectFsEntry(path: d, kind: ProjectFsEntryKind.directory));
    }

    for (final f in _files.keys) {
      if (prefix.isNotEmpty && !f.startsWith(prefix)) continue;
      final rel = prefix.isEmpty ? f : f.substring(prefix.length);
      if (!recursive && rel.contains('/')) continue;
      entries.add(ProjectFsEntry(path: f, kind: ProjectFsEntryKind.file));
    }

    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  @override
  Future<ProjectFsStat?> stat(String path) async {
    final norm = normalizeProjectPath(path);
    final file = _files[norm];
    if (file != null) {
      return ProjectFsStat(
        path: norm,
        kind: ProjectFsEntryKind.file,
        sizeBytes: file.bytes.length,
        modifiedUtc: file.modifiedUtc,
      );
    }
    if (_dirs.contains(norm)) {
      return ProjectFsStat(
        path: norm,
        kind: ProjectFsEntryKind.directory,
        sizeBytes: 0,
        modifiedUtc: _clock(),
      );
    }
    return null;
  }

  @override
  Stream<ProjectFsEvent> watch(String directoryPath) {
    final dir = normalizeProjectPath(directoryPath);
    if (dir.isEmpty) return _events.stream;
    final prefix = '$dir/';
    return _events.stream.where(
      (ev) =>
          ev.path == dir ||
          ev.path.startsWith(prefix) ||
          (ev.previousPath != null &&
              (ev.previousPath == dir || ev.previousPath!.startsWith(prefix))),
    );
  }

  @override
  Future<void> move(String fromPath, String toPath) async {
    final from = normalizeProjectPath(fromPath);
    final to = normalizeProjectPath(toPath);
    final file = _files.remove(from);
    if (file != null) {
      _ensureParentDirs(to);
      _files[to] = _MemFile(file.bytes, _clock());
      _events.add(
        ProjectFsEvent(
          kind: ProjectFsEventKind.moved,
          path: to,
          previousPath: from,
        ),
      );
      return;
    }
    if (_dirs.contains(from)) {
      final fromPrefix = '$from/';
      _ensureParentDirs(to);
      _dirs.remove(from);
      _dirs.add(to);
      final movedDirs = _dirs.where((d) => d.startsWith(fromPrefix)).toList();
      for (final d in movedDirs) {
        _dirs.remove(d);
        _dirs.add('$to/${d.substring(fromPrefix.length)}');
      }
      final movedFiles = _files.keys
          .where((f) => f.startsWith(fromPrefix))
          .toList();
      for (final f in movedFiles) {
        final data = _files.remove(f)!;
        final dest = '$to/${f.substring(fromPrefix.length)}';
        _files[dest] = _MemFile(data.bytes, _clock());
      }
      _events.add(
        ProjectFsEvent(
          kind: ProjectFsEventKind.moved,
          path: to,
          previousPath: from,
        ),
      );
      return;
    }
    throw StateError('Source path not found in MemoryProjectFileSystem: $from');
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    final norm = normalizeProjectPath(path);
    if (_files.remove(norm) != null) {
      _events.add(ProjectFsEvent(kind: ProjectFsEventKind.deleted, path: norm));
      return;
    }
    if (_dirs.contains(norm) && norm.isNotEmpty) {
      final prefix = '$norm/';
      final hasChildren =
          _files.keys.any((f) => f.startsWith(prefix)) ||
          _dirs.any((d) => d.startsWith(prefix));
      if (hasChildren && !recursive) {
        throw StateError('Directory is not empty: $norm');
      }
      _dirs.remove(norm);
      _dirs.removeWhere((d) => d.startsWith(prefix));
      _files.removeWhere((f, _) => f.startsWith(prefix));
      _events.add(ProjectFsEvent(kind: ProjectFsEventKind.deleted, path: norm));
    }
  }

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    final norm = normalizeProjectPath(path);
    if (norm.isEmpty) return;
    if (recursive) {
      _ensureParentDirs(norm);
    }
    _dirs.add(norm);
  }

  void _ensureParentDirs(String normPath) {
    final parts = normPath.split('/');
    var current = '';
    for (var i = 0; i < parts.length - 1; i++) {
      current = current.isEmpty ? parts[i] : '$current/${parts[i]}';
      _dirs.add(current);
    }
  }

  Future<void> close() => _events.close();
}

final class _MemFile {
  final Uint8List bytes;
  final DateTime modifiedUtc;
  const _MemFile(this.bytes, this.modifiedUtc);
}
