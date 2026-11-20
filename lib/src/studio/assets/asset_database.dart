/// Pure-Dart GUID AssetDatabase with Importer Registry, Dependency Graph &
/// Incremental Import Cache under `.volition/library/` (S1-C).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../project/project_fs.dart';
import 'asset_meta.dart';

const String kLibraryCacheDir = '.volition/library';

/// Output produced by an [AssetImporter] during an import pass.
final class AssetImportOutput {
  final Map<String, Object?> artifactMetadata;
  final List<AssetSubId> subAssets;
  final List<String> dependencyGuids;

  const AssetImportOutput({
    this.artifactMetadata = const {},
    this.subAssets = const [],
    this.dependencyGuids = const [],
  });
}

/// Pluggable asset importer interface for [AssetDatabase].
abstract interface class AssetImporter {
  String get id;
  int get version;
  Set<String> get extensions;

  Future<AssetImportOutput> importAsset({
    required String path,
    required Uint8List bytes,
    required Map<String, Object?> settings,
  });
}

/// Built-in lightweight importer that extracts JSON `"dependencyGuids"` (or
/// `"dependencies"`) when present and records basic artifact metadata.
final class DefaultAssetImporter implements AssetImporter {
  @override
  final String id;
  @override
  final int version;
  @override
  final Set<String> extensions;
  final bool inspectJsonDependencies;

  const DefaultAssetImporter({
    required this.id,
    this.version = 1,
    required this.extensions,
    this.inspectJsonDependencies = false,
  });

  @override
  Future<AssetImportOutput> importAsset({
    required String path,
    required Uint8List bytes,
    required Map<String, Object?> settings,
  }) async {
    final deps = <String>[];
    if (inspectJsonDependencies) {
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map) {
          final rawDeps = decoded['dependencyGuids'] ?? decoded['dependencies'];
          if (rawDeps is List) {
            for (final d in rawDeps) {
              if (d is String && d.isNotEmpty) deps.add(d);
            }
          }
        }
      } catch (_) {
        // Non-JSON or partial draft; treat as zero dependencies.
      }
    }
    return AssetImportOutput(
      artifactMetadata: {
        'importerId': id,
        'path': path,
        'byteLength': bytes.length,
        'settingsHash': computeSettingsHashHex(settings),
      },
      dependencyGuids: deps,
    );
  }
}

/// Indexed asset record maintained by [AssetDatabase].
final class AssetRecord {
  final String guid;
  final String path;
  final AssetMeta meta;
  final String cacheArtifactPath;

  const AssetRecord({
    required this.guid,
    required this.path,
    required this.meta,
    required this.cacheArtifactPath,
  });
}

/// Pure-Dart GUID asset database managing `.vmeta` sidecars, dependency
/// invalidation, orphan-meta detection, and `.volition/library/` cache.
final class AssetDatabase {
  final ProjectFileSystem fs;
  final String assetsRoot;
  final AssetGuidGenerator guidGenerator;

  final Map<String, AssetImporter> _importersById = {};
  final Map<String, AssetImporter> _importersByExt = {};
  final Map<String, AssetRecord> _byGuid = {};
  final Map<String, String> _guidByPath = {};
  final Map<String, Set<String>> _dependentsByGuid = {};
  final List<String> _orphanMetas = [];

  int _importCount = 0;
  StreamSubscription<ProjectFsEvent>? _watchSub;

  AssetDatabase(
    this.fs, {
    this.assetsRoot = 'assets',
    AssetGuidGenerator? guidGenerator,
    Iterable<AssetImporter>? importers,
  }) : guidGenerator = guidGenerator ?? AssetGuidGenerator() {
    for (final imp in importers ?? defaultImporters()) {
      registerImporter(imp);
    }
  }

  static List<AssetImporter> defaultImporters() => const [
    DefaultAssetImporter(
      id: 'texture',
      extensions: {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.tga'},
    ),
    DefaultAssetImporter(
      id: 'model',
      extensions: {'.glb', '.gltf', '.obj', '.qmesh'},
    ),
    DefaultAssetImporter(id: 'audio', extensions: {'.wav', '.ogg', '.mp3'}),
    DefaultAssetImporter(id: 'lut', extensions: {'.cube', '.lut'}),
    DefaultAssetImporter(
      id: 'scene',
      extensions: {'.scene.json', '.vscene'},
      inspectJsonDependencies: true,
    ),
    DefaultAssetImporter(
      id: 'prefab',
      extensions: {'.prefab.json', '.vprefab'},
      inspectJsonDependencies: true,
    ),
    DefaultAssetImporter(
      id: 'material',
      extensions: {'.vmat', '.mat.json'},
      inspectJsonDependencies: true,
    ),
    DefaultAssetImporter(
      id: 'data_asset',
      extensions: {'.vdata', '.json'},
      inspectJsonDependencies: true,
    ),
  ];

  void registerImporter(AssetImporter importer) {
    _importersById[importer.id] = importer;
    for (final ext in importer.extensions) {
      _importersByExt[ext.toLowerCase()] = importer;
    }
  }

  AssetImporter resolveImporterForPath(String path) {
    final lower = path.toLowerCase();
    // Match longest extension first (e.g. `.scene.json` before `.json`).
    String? bestExt;
    for (final ext in _importersByExt.keys) {
      if (lower.endsWith(ext)) {
        if (bestExt == null || ext.length > bestExt.length) {
          bestExt = ext;
        }
      }
    }
    if (bestExt != null) return _importersByExt[bestExt]!;
    return const DefaultAssetImporter(id: 'generic', extensions: {});
  }

  /// Total number of actual importer executions performed (excludes cache hits).
  int get importCount => _importCount;

  List<String> get orphanMetas => List<String>.unmodifiable(_orphanMetas);

  List<AssetRecord> get allAssets {
    final list = _byGuid.values.toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return List<AssetRecord>.unmodifiable(list);
  }

  AssetRecord? getByGuid(String guid) => _byGuid[guid];

  AssetRecord? getByPath(String path) {
    final guid = _guidByPath[normalizeProjectPath(path)];
    return guid == null ? null : _byGuid[guid];
  }

  String? resolvePath(String guid) => _byGuid[guid]?.path;

  String? resolveGuid(String path) => _guidByPath[normalizeProjectPath(path)];

  Set<String> dependentsOf(String guid) =>
      Set<String>.unmodifiable(_dependentsByGuid[guid] ?? const <String>{});

  /// Performs a full scan of [assetsRoot], allocating `.vmeta` sidecars for
  /// new assets, detecting orphan `.vmeta` files, and incrementally importing
  /// only changed assets.
  Future<void> refresh() async {
    _byGuid.clear();
    _guidByPath.clear();
    _dependentsByGuid.clear();
    _orphanMetas.clear();

    if (!await fs.exists(assetsRoot)) return;
    final entries = await fs.list(assetsRoot, recursive: true);
    final files = entries
        .where((e) => e.kind == ProjectFsEntryKind.file)
        .map((e) => e.path)
        .toList();

    final assetFiles = <String>{};
    final metaFiles = <String>{};
    for (final f in files) {
      if (f.endsWith(kAssetMetaExtension)) {
        metaFiles.add(f);
      } else {
        assetFiles.add(f);
      }
    }

    for (final m in metaFiles) {
      final assetPath = m.substring(0, m.length - kAssetMetaExtension.length);
      if (!assetFiles.contains(assetPath)) {
        _orphanMetas.add(m);
      }
    }
    _orphanMetas.sort();

    final sortedAssets = assetFiles.toList()..sort();
    for (final path in sortedAssets) {
      await _indexAndImportAsset(path, forceReimport: false);
    }
    _rebuildDependencyGraph();
  }

  /// Starts watching [assetsRoot] for filesystem changes and triggers
  /// incremental reimports automatically.
  void startWatching() {
    _watchSub?.cancel();
    _watchSub = fs.watch(assetsRoot).listen((event) async {
      if (event.path.endsWith(kAssetMetaExtension)) return;
      switch (event.kind) {
        case ProjectFsEventKind.created:
        case ProjectFsEventKind.modified:
          if (await fs.exists(event.path)) {
            await _indexAndImportAsset(event.path, forceReimport: false);
            _rebuildDependencyGraph();
          }
        case ProjectFsEventKind.deleted:
          final guid = _guidByPath.remove(event.path);
          if (guid != null) {
            _byGuid.remove(guid);
            _rebuildDependencyGraph();
          }
        case ProjectFsEventKind.moved:
          if (event.previousPath != null) {
            final guid = _guidByPath.remove(event.previousPath);
            if (guid != null) {
              _guidByPath[event.path] = guid;
              final existing = _byGuid[guid];
              if (existing != null) {
                _byGuid[guid] = AssetRecord(
                  guid: existing.guid,
                  path: event.path,
                  meta: existing.meta,
                  cacheArtifactPath: existing.cacheArtifactPath,
                );
              }
            }
          }
      }
    });
  }

  Future<void> stopWatching() async {
    await _watchSub?.cancel();
    _watchSub = null;
  }

  /// Moves/renames an asset along with its `.vmeta` sidecar while preserving
  /// its GUID and cached import artifact.
  Future<AssetRecord> moveAsset(String fromPath, String toPath) async {
    final from = normalizeProjectPath(fromPath);
    final to = normalizeProjectPath(toPath);
    await fs.move(from, to);
    final fromMeta = '$from$kAssetMetaExtension';
    final toMeta = '$to$kAssetMetaExtension';
    if (await fs.exists(fromMeta)) {
      await fs.move(fromMeta, toMeta);
    }
    final guid = _guidByPath.remove(from);
    if (guid != null) {
      final old = _byGuid[guid]!;
      final updated = AssetRecord(
        guid: old.guid,
        path: to,
        meta: old.meta,
        cacheArtifactPath: old.cacheArtifactPath,
      );
      _byGuid[guid] = updated;
      _guidByPath[to] = guid;
      return updated;
    }
    return _indexAndImportAsset(to, forceReimport: false);
  }

  /// Deletes an asset and its `.vmeta` sidecar.
  Future<void> deleteAsset(String path) async {
    final norm = normalizeProjectPath(path);
    await fs.delete(norm);
    final metaPath = '$norm$kAssetMetaExtension';
    if (await fs.exists(metaPath)) {
      await fs.delete(metaPath);
    }
    final guid = _guidByPath.remove(norm);
    if (guid != null) {
      _byGuid.remove(guid);
      _rebuildDependencyGraph();
    }
  }

  /// Updates an asset's import settings, reimports it, and transitively
  /// reimports all dependent assets.
  Future<List<String>> updateImportSettings(
    String guid,
    Map<String, Object?> newSettings,
  ) async {
    final record = _byGuid[guid];
    if (record == null) {
      throw StateError('Unknown asset GUID: $guid');
    }
    final updatedMeta = record.meta.copyWith(importSettings: newSettings);
    await fs.writeString(
      '${record.path}$kAssetMetaExtension',
      updatedMeta.toJsonString(),
    );

    final reimported = <String>[];
    final visited = <String>{};
    final queue = <String>[guid];

    while (queue.isNotEmpty) {
      final currentGuid = queue.removeAt(0);
      if (!visited.add(currentGuid)) continue;
      final currentRec = _byGuid[currentGuid];
      if (currentRec == null) continue;
      await _indexAndImportAsset(currentRec.path, forceReimport: true);
      reimported.add(currentGuid);
      final deps = _dependentsByGuid[currentGuid];
      if (deps != null) {
        for (final depGuid in deps) {
          if (!visited.contains(depGuid)) queue.add(depGuid);
        }
      }
    }
    _rebuildDependencyGraph();
    return reimported;
  }

  Future<AssetRecord> _indexAndImportAsset(
    String path, {
    required bool forceReimport,
  }) async {
    final norm = normalizeProjectPath(path);
    final bytes = await fs.readBytes(norm);
    final contentHash = computeContentHashHex(bytes);
    final importer = resolveImporterForPath(norm);
    final metaPath = '$norm$kAssetMetaExtension';

    AssetMeta? existingMeta;
    if (await fs.exists(metaPath)) {
      try {
        final decoded = jsonDecode(await fs.readString(metaPath));
        if (decoded is Map) {
          existingMeta = AssetMeta.fromJson(decoded.cast<String, Object?>());
        }
      } catch (_) {
        existingMeta = null;
      }
    }

    final guid = existingMeta?.guid ?? guidGenerator.nextGuid();
    final settings = existingMeta?.importSettings ?? const <String, Object?>{};
    final candidateMeta = AssetMeta(
      guid: guid,
      importerId: importer.id,
      importerVersion: importer.version,
      importSettings: settings,
      contentHash: contentHash,
      subAssets: existingMeta?.subAssets ?? const [],
      dependencyGuids: existingMeta?.dependencyGuids ?? const [],
    );

    final cachePath = '$kLibraryCacheDir/$guid.import.json';
    var cacheHit = false;
    if (!forceReimport && await fs.exists(cachePath)) {
      try {
        final cached = jsonDecode(await fs.readString(cachePath));
        if (cached is Map && cached['cacheKey'] == candidateMeta.cacheKey) {
          cacheHit = true;
        }
      } catch (_) {
        cacheHit = false;
      }
    }

    AssetMeta finalMeta = candidateMeta;
    if (!cacheHit) {
      _importCount++;
      final output = await importer.importAsset(
        path: norm,
        bytes: bytes,
        settings: settings,
      );
      finalMeta = candidateMeta.copyWith(
        subAssets: output.subAssets,
        dependencyGuids: output.dependencyGuids,
      );
      await fs.writeString(
        cachePath,
        jsonEncode({
          'guid': guid,
          'cacheKey': finalMeta.cacheKey,
          'artifact': output.artifactMetadata,
        }),
      );
    }

    if (existingMeta == null ||
        existingMeta.contentHash != finalMeta.contentHash ||
        existingMeta.importerId != finalMeta.importerId ||
        existingMeta.importerVersion != finalMeta.importerVersion ||
        !cacheHit) {
      await fs.writeString(metaPath, finalMeta.toJsonString());
    }

    final record = AssetRecord(
      guid: guid,
      path: norm,
      meta: finalMeta,
      cacheArtifactPath: cachePath,
    );
    _byGuid[guid] = record;
    _guidByPath[norm] = guid;
    return record;
  }

  void _rebuildDependencyGraph() {
    _dependentsByGuid.clear();
    for (final rec in _byGuid.values) {
      for (final dep in rec.meta.dependencyGuids) {
        _dependentsByGuid.putIfAbsent(dep, () => <String>{}).add(rec.guid);
      }
    }
  }
}
