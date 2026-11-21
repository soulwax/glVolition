/// Pure-Dart Project Window model (S2-D): GUID asset browser, folder tree,
/// search & type filters, asset create/rename/move/delete keeping GUIDs,
/// import settings updates, and cached `.volition/library/thumbnails/` access.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../assets/asset_database.dart';
import '../project/project_fs.dart';
import '../shell/dock_layout.dart';

const String kThumbnailsCacheDir = '.volition/library/thumbnails';

/// Visual item displayed in the Studio Project Window grid.
final class ProjectAssetItem {
  final String guid;
  final String path;
  final String name;
  final String folder;
  final String importerId;
  final String thumbnailCachePath;

  const ProjectAssetItem({
    required this.guid,
    required this.path,
    required this.name,
    required this.folder,
    required this.importerId,
    required this.thumbnailCachePath,
  });
}

/// Pure-Dart Project Window panel model backed by [AssetDatabase].
final class ProjectWindowModel implements StudioPanel {
  final AssetDatabase database;
  String currentFolder;
  String searchQuery = '';
  String? typeFilter;

  ProjectWindowModel(this.database, {String? initialFolder})
    : currentFolder = normalizeProjectPath(
        initialFolder ?? database.assetsRoot,
      );

  @override
  String get id => 'project';

  @override
  String get title => 'Project';

  /// Lists all folders under `database.assetsRoot` for the left folder tree.
  Future<List<String>> listFolders() async {
    final folders = <String>{normalizeProjectPath(database.assetsRoot)};
    if (await database.fs.exists(database.assetsRoot)) {
      final entries = await database.fs.list(
        database.assetsRoot,
        recursive: true,
      );
      for (final e in entries) {
        if (e.kind == ProjectFsEntryKind.directory) {
          folders.add(e.path);
        }
      }
    }
    final sorted = folders.toList()..sort();
    return sorted;
  }

  /// Returns filtered asset items in [currentFolder] (or across all folders
  /// when [searchQuery] or [typeFilter] is active).
  List<ProjectAssetItem> visibleAssets() {
    final needle = searchQuery.trim().toLowerCase();
    final filter = typeFilter?.trim().toLowerCase();
    final recursiveSearch =
        needle.isNotEmpty || (filter != null && filter.isNotEmpty);

    final out = <ProjectAssetItem>[];
    for (final rec in database.allAssets) {
      final slash = rec.path.lastIndexOf('/');
      final folder = slash < 0 ? '' : rec.path.substring(0, slash);
      final name = slash < 0 ? rec.path : rec.path.substring(slash + 1);

      if (!recursiveSearch && folder != currentFolder) continue;
      if (needle.isNotEmpty && !name.toLowerCase().contains(needle)) continue;
      if (filter != null &&
          filter.isNotEmpty &&
          rec.meta.importerId.toLowerCase() != filter) {
        continue;
      }

      out.add(
        ProjectAssetItem(
          guid: rec.guid,
          path: rec.path,
          name: name,
          folder: folder,
          importerId: rec.meta.importerId,
          thumbnailCachePath: '$kThumbnailsCacheDir/${rec.guid}.png',
        ),
      );
    }
    return out;
  }

  Future<String> createFolder(String folderName) async {
    final target = normalizeProjectPath('$currentFolder/$folderName');
    await database.fs.createDirectory(target, recursive: true);
    return target;
  }

  /// Creates a new asset (scene, material, prefab, or data asset) in
  /// [currentFolder] and indexes it into [AssetDatabase].
  Future<AssetRecord> createAsset({
    required String fileName,
    required String contents,
  }) async {
    final target = normalizeProjectPath('$currentFolder/$fileName');
    await database.fs.writeString(target, contents);
    await database.refresh();
    return database.getByPath(target)!;
  }

  Future<AssetRecord> createMaterialAsset(String baseName) => createAsset(
    fileName: baseName.endsWith('.vmat') ? baseName : '$baseName.vmat',
    contents: const JsonEncoder.withIndent('  ').convert({
      'name': baseName,
      'shader': 'lit',
      'roughness': 0.5,
      'metallic': 0.0,
      'dependencyGuids': const <String>[],
    }),
  );

  Future<AssetRecord> renameAsset(String fromPath, String newFileName) async {
    final norm = normalizeProjectPath(fromPath);
    final slash = norm.lastIndexOf('/');
    final dir = slash < 0 ? '' : norm.substring(0, slash);
    final dest = normalizeProjectPath(
      dir.isEmpty ? newFileName : '$dir/$newFileName',
    );
    return database.moveAsset(norm, dest);
  }

  Future<AssetRecord> moveAssetToFolder(
    String fromPath,
    String targetFolder,
  ) async {
    final norm = normalizeProjectPath(fromPath);
    final slash = norm.lastIndexOf('/');
    final name = slash < 0 ? norm : norm.substring(slash + 1);
    final dest = normalizeProjectPath('$targetFolder/$name');
    return database.moveAsset(norm, dest);
  }

  Future<void> deleteAsset(String path) => database.deleteAsset(path);

  Future<List<String>> updateImportSettings(
    String guid,
    Map<String, Object?> settings,
  ) => database.updateImportSettings(guid, settings);

  /// Returns cached thumbnail bytes from `.volition/library/thumbnails/<guid>.png`
  /// when up to date with `record.meta.cacheKey`, otherwise renders via
  /// [renderThumbnail] and caches the result.
  Future<Uint8List> getOrGenerateThumbnail(
    String guid,
    Future<Uint8List> Function(AssetRecord record) renderThumbnail,
  ) async {
    final record = database.getByGuid(guid);
    if (record == null) {
      throw StateError('Unknown asset GUID for thumbnail: $guid');
    }
    final thumbPath = '$kThumbnailsCacheDir/$guid.png';
    final stampPath = '$kThumbnailsCacheDir/$guid.key';
    if (await database.fs.exists(thumbPath) &&
        await database.fs.exists(stampPath)) {
      final cachedKey = await database.fs.readString(stampPath);
      if (cachedKey == record.meta.cacheKey) {
        return database.fs.readBytes(thumbPath);
      }
    }
    final rendered = await renderThumbnail(record);
    await database.fs.writeBytes(thumbPath, rendered);
    await database.fs.writeString(stampPath, record.meta.cacheKey);
    return rendered;
  }

  @override
  Map<String, Object?> saveState() => {
    'currentFolder': currentFolder,
    'searchQuery': searchQuery,
    if (typeFilter != null) 'typeFilter': typeFilter,
  };

  @override
  void restoreState(Map<String, Object?> state) {
    currentFolder = normalizeProjectPath(
      state['currentFolder'] as String? ?? database.assetsRoot,
    );
    searchQuery = state['searchQuery'] as String? ?? '';
    typeFilter = state['typeFilter'] as String?;
  }
}
