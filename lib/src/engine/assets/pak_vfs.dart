part of '../../engine.dart';

/// Layered [AssetLoader] backed by [pack.VirtualFileSystem] with optional fallback
/// to a host [AssetLoader] for unbundled assets (E48-2).
final class VfsAssetLoader implements AssetLoader {
  final pack.VirtualFileSystem vfs;
  final AssetLoader? fallback;

  VfsAssetLoader({
    pack.VirtualFileSystem? vfs,
    this.fallback,
  }) : vfs = vfs ?? pack.VirtualFileSystem();

  pack.PakMount mountPakBytes(
    String id,
    Uint8List pakBytes, {
    int priority = 0,
    int? xorKey,
    bool verifyChecksums = true,
  }) {
    final archive = pack.PakArchive.parse(pakBytes, xorKey: xorKey);
    final layer = pack.PakMount(
      id: id,
      archive: archive,
      priority: priority,
      verifyChecksums: verifyChecksums,
    );
    vfs.mount(layer);
    return layer;
  }

  pack.MemoryMount mountMemoryOverlay(String id, {int priority = 100}) {
    final layer = pack.MemoryMount(id: id, priority: priority);
    vfs.mount(layer);
    return layer;
  }

  @override
  Future<Uint8List> loadBytes(String path) async {
    final bytes = vfs.readBytes(path);
    if (bytes != null) return bytes;
    if (fallback != null) return fallback!.loadBytes(path);
    throw StateError('Asset not found in VFS: "$path"');
  }

  @override
  Future<String> loadText(String path) async {
    final text = vfs.readText(path);
    if (text != null) return text;
    if (fallback != null) return fallback!.loadText(path);
    throw StateError('Asset not found in VFS: "$path"');
  }

  @override
  Future<ModelAsset> loadModel(String path, {MaterialOverride? materialOverride}) {
    if (fallback != null) {
      return fallback!.loadModel(path, materialOverride: materialOverride);
    }
    throw UnimplementedError('VfsAssetLoader requires fallback AssetLoader for ModelAsset.');
  }
}

/// Automatically upgrades versioned JSON save slots using [pack.SaveMigrator] (E48-2).
final class MigratedSaveStore {
  final KeyValueStore storage;
  final pack.SaveMigrator migrator;

  MigratedSaveStore({
    required this.storage,
    required this.migrator,
  });

  void save(String key, Map<String, Object?> data) {
    final stamped = <String, Object?>{
      ...data,
      migrator.versionField: migrator.targetVersion,
    };
    storage.write(key, jsonEncode(stamped));
  }

  pack.SaveMigrationResult? load(
    String key, {
    int defaultInitialVersion = 0,
    bool persistUpgraded = true,
  }) {
    final raw = storage.read(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return null;

    final result = migrator.migrate(
      decoded,
      defaultInitialVersion: defaultInitialVersion,
    );
    if (result.didMigrate && persistUpgraded) {
      storage.write(key, jsonEncode(result.data));
    }
    return result;
  }
}

/// Immediate-mode `voxui` mounted VFS / `.pak` asset browser overlay (E48-2).
final class AssetBrowserUI {
  static String render(
    VoxUiContext ui,
    pack.VirtualFileSystem vfs, {
    String globFilter = '*',
    String title = 'VFS Asset Browser',
    double x = 20.0,
    double y = 20.0,
    double width = 380.0,
    double height = 280.0,
  }) {
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return globFilter;
    }

    final updatedFilter = ui.inputText('Filter', globFilter);
    final pattern = updatedFilter.trim().isEmpty ? '**' : updatedFilter.trim();

    ui.text('Mounts (${vfs.mounts.length}):', color: VoxColor.cyan);
    for (final m in vfs.mounts) {
      ui.labelValue('p=${m.priority}', m.id, valueColor: VoxColor.lightGray);
    }

    ui.separator();
    final files = vfs.list(globPattern: pattern);
    ui.text('Assets (${files.length}):', color: VoxColor.green);
    for (final f in files.take(12)) {
      final mountId = vfs.resolveMountId(f) ?? '?';
      ui.labelValue(mountId, f, valueColor: ui.style.text);
    }

    ui.endWindow();
    return updatedFilter;
  }
}
