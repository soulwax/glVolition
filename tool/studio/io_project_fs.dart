/// `dart:io` implementation of [ProjectFileSystem] for CLI/daemon use (S1-C).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gl_volition/src/studio/project/project_fs.dart';

final class IoProjectFileSystem implements ProjectFileSystem {
  final Directory rootDirectory;

  IoProjectFileSystem(Directory root) : rootDirectory = root.absolute;

  String _resolveAbsolute(String projectRelativePath) {
    final norm = normalizeProjectPath(projectRelativePath);
    if (norm.isEmpty) return rootDirectory.path;
    final sep = Platform.pathSeparator;
    return '${rootDirectory.path}$sep${norm.replaceAll('/', sep)}';
  }

  String _toRelative(String absolutePath) {
    final normRoot = rootDirectory.path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final normAbs = absolutePath.replaceAll('\\', '/');
    if (normAbs == normRoot) return '';
    if (normAbs.startsWith('$normRoot/')) {
      return normAbs.substring(normRoot.length + 1);
    }
    return normAbs;
  }

  @override
  Future<Uint8List> readBytes(String path) =>
      File(_resolveAbsolute(path)).readAsBytes();

  @override
  Future<String> readString(String path) =>
      File(_resolveAbsolute(path)).readAsString(encoding: utf8);

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    final file = File(_resolveAbsolute(path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> writeString(String path, String contents) =>
      writeBytes(path, Uint8List.fromList(utf8.encode(contents)));

  @override
  Future<bool> exists(String path) async {
    final abs = _resolveAbsolute(path);
    return File(abs).existsSync() || Directory(abs).existsSync();
  }

  @override
  Future<List<ProjectFsEntry>> list(
    String directoryPath, {
    bool recursive = false,
  }) async {
    final dir = Directory(_resolveAbsolute(directoryPath));
    if (!dir.existsSync()) return const [];
    final entries = <ProjectFsEntry>[];
    await for (final entity in dir.list(
      recursive: recursive,
      followLinks: false,
    )) {
      final rel = _toRelative(entity.path);
      if (entity is Directory) {
        entries.add(
          ProjectFsEntry(path: rel, kind: ProjectFsEntryKind.directory),
        );
      } else if (entity is File) {
        entries.add(ProjectFsEntry(path: rel, kind: ProjectFsEntryKind.file));
      }
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  @override
  Future<ProjectFsStat?> stat(String path) async {
    final abs = _resolveAbsolute(path);
    final st = await FileStat.stat(abs);
    if (st.type == FileSystemEntityType.notFound) return null;
    return ProjectFsStat(
      path: normalizeProjectPath(path),
      kind: st.type == FileSystemEntityType.directory
          ? ProjectFsEntryKind.directory
          : ProjectFsEntryKind.file,
      sizeBytes: st.type == FileSystemEntityType.file ? st.size : 0,
      modifiedUtc: st.modified.toUtc(),
    );
  }

  @override
  Stream<ProjectFsEvent> watch(String directoryPath) {
    final dir = Directory(_resolveAbsolute(directoryPath));
    if (!dir.existsSync()) return const Stream.empty();
    return dir.watch(recursive: true).map((ev) {
      final rel = _toRelative(ev.path);
      if (ev is FileSystemMoveEvent) {
        return ProjectFsEvent(
          kind: ProjectFsEventKind.moved,
          path: ev.destination != null ? _toRelative(ev.destination!) : rel,
          previousPath: rel,
        );
      }
      final kind = switch (ev.type) {
        FileSystemEvent.create => ProjectFsEventKind.created,
        FileSystemEvent.delete => ProjectFsEventKind.deleted,
        _ => ProjectFsEventKind.modified,
      };
      return ProjectFsEvent(kind: kind, path: rel);
    });
  }

  @override
  Future<void> move(String fromPath, String toPath) async {
    final fromAbs = _resolveAbsolute(fromPath);
    final toAbs = _resolveAbsolute(toPath);
    final toParent = File(toAbs).parent;
    await toParent.create(recursive: true);
    if (File(fromAbs).existsSync()) {
      await File(fromAbs).rename(toAbs);
    } else if (Directory(fromAbs).existsSync()) {
      await Directory(fromAbs).rename(toAbs);
    } else {
      throw StateError('Source path not found: $fromPath');
    }
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    final abs = _resolveAbsolute(path);
    if (File(abs).existsSync()) {
      await File(abs).delete();
    } else if (Directory(abs).existsSync()) {
      await Directory(abs).delete(recursive: recursive);
    }
  }

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    await Directory(_resolveAbsolute(path)).create(recursive: recursive);
  }
}
