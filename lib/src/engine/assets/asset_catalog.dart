part of '../../engine.dart';

sealed class AssetEntry {
  const AssetEntry();
}

final class ModelEntry extends AssetEntry {
  final String path;
  final MaterialOverride? materialOverride;
  const ModelEntry(this.path, {this.materialOverride});
}

final class AudioEntry extends AssetEntry {
  final String path;
  final double volume;
  final int voices;
  const AudioEntry(this.path, {this.volume = 1.0, this.voices = 3});
}

final class ProceduralTextureEntry extends AssetEntry {
  final int width;
  final int height;
  final Uint8List Function() generatePixels;
  final GpuTextureFilter minFilter;
  final GpuTextureFilter magFilter;
  final GpuTextureWrap wrap;
  final bool hasMips;

  const ProceduralTextureEntry({
    required this.width,
    required this.height,
    required this.generatePixels,
    this.minFilter = GpuTextureFilter.linearMipmapLinear,
    this.magFilter = GpuTextureFilter.linear,
    this.wrap = GpuTextureWrap.repeat,
    this.hasMips = true,
  });
}

final class TextEntry extends AssetEntry {
  final String path;
  const TextEntry(this.path);
}

final class BytesEntry extends AssetEntry {
  final String path;
  const BytesEntry(this.path);
}

/// Preloads models, audio clips, procedural textures, meshes, and materials by
/// logical string key so `awake()` / `start()` / `Prefab.builder` can look them
/// up synchronously without `async`/`await` (E3-4).
final class AssetCatalog {
  final Engine _engine;

  final Map<String, ModelAsset> _models = {};
  final Map<String, AudioClip> _clips = {};
  final Map<String, TextureHandle> _textures = {};
  final Map<String, MeshHandle> _meshes = {};
  final Map<String, MeshData> _meshData = {};
  final Map<String, MaterialHandle> _materials = {};
  final Map<String, String> _texts = {};
  final Map<String, Uint8List> _bytes = {};
  final Map<String, Prefab> _prefabs = {};

  AssetCatalog._(this._engine);

  /// Loads every entry in [entries] and invokes [onProgress] after each item
  /// completes.
  Future<void> load(
    Map<String, AssetEntry> entries, {
    void Function(int loaded, int total)? onProgress,
  }) async {
    final total = entries.length;
    var completed = 0;
    onProgress?.call(0, total);
    if (total == 0) return;

    await Future.wait(
      entries.entries.map((entry) async {
        final key = entry.key;
        switch (entry.value) {
          case ModelEntry e:
            _models[key] = await _engine.assets.loadModel(
              e.path,
              materialOverride: e.materialOverride,
            );
          case AudioEntry e:
            _clips[key] = _engine.audio.clip(
              e.path,
              volume: e.volume,
              voices: e.voices,
            );
          case ProceduralTextureEntry e:
            _textures[key] = _engine.graphics.createTexture(
              width: e.width,
              height: e.height,
              pixels: e.generatePixels(),
              minFilter: e.minFilter,
              magFilter: e.magFilter,
              wrap: e.wrap,
              hasMips: e.hasMips,
              debugLabel: key,
            );
          case TextEntry e:
            _texts[key] = await _engine.assets.loadText(e.path);
          case BytesEntry e:
            _bytes[key] = await _engine.assets.loadBytes(e.path);
        }
        completed++;
        onProgress?.call(completed, total);
      }),
    );
  }

  void putModel(String key, ModelAsset asset) => _models[key] = asset;
  void putClip(String key, AudioClip clip) => _clips[key] = clip;
  void putTexture(String key, TextureHandle handle) => _textures[key] = handle;

  MeshHandle registerMesh(String key, MeshData data) {
    final handle = _engine.graphics.createMesh(data, debugLabel: key);
    _meshes[key] = handle;
    _meshData[key] = data;
    return handle;
  }

  MaterialHandle registerMaterial(String key, MaterialDefinition definition) {
    final handle = _engine.graphics.createMaterial(definition);
    _materials[key] = handle;
    return handle;
  }

  ModelAsset model(String key) =>
      _models[key] ?? (throw ArgumentError.value(key, 'key', 'ModelAsset not found in catalog'));

  AudioClip clip(String key) =>
      _clips[key] ?? (throw ArgumentError.value(key, 'key', 'AudioClip not found in catalog'));

  TextureHandle texture(String key) =>
      _textures[key] ?? (throw ArgumentError.value(key, 'key', 'TextureHandle not found in catalog'));

  MeshHandle mesh(String key) =>
      _meshes[key] ?? (throw ArgumentError.value(key, 'key', 'MeshHandle not found in catalog'));

  MeshData? meshData(String key) => _meshData[key];

  MaterialHandle material(String key) =>
      _materials[key] ?? (throw ArgumentError.value(key, 'key', 'MaterialHandle not found in catalog'));

  String text(String key) =>
      _texts[key] ?? (throw ArgumentError.value(key, 'key', 'Text asset not found in catalog'));

  Uint8List bytes(String key) =>
      _bytes[key] ?? (throw ArgumentError.value(key, 'key', 'Bytes asset not found in catalog'));

  void putPrefab(String key, Prefab prefab) => _prefabs[key] = prefab;

  bool hasPrefab(String key) => _prefabs.containsKey(key) || _models.containsKey(key);

  /// Returns the [Prefab] registered under [key], or lazily builds (and
  /// caches) one from the [ModelAsset] loaded under the same key so a loaded
  /// GLB spawns in one line: `scene.instantiate(catalog.prefab('ship'))`
  /// (E15-2).
  Prefab prefab(String key) {
    final cached = _prefabs[key];
    if (cached != null) return cached;
    final asset = _models[key];
    if (asset == null) {
      throw ArgumentError.value(key, 'key', 'Prefab/ModelAsset not found in catalog');
    }
    return _prefabs[key] = Prefab.fromModelAsset(asset, name: key);
  }

  /// Instantiates the prefab for [key] into [scene] (defaults to the active
  /// scene).
  GameObject spawn(
    String key, {
    Scene? scene,
    GameObject? parent,
    Vec3? position,
    Quat? rotation,
    double? scale,
    String? name,
  }) =>
      (scene ?? _engine.scene).instantiate(
        prefab(key),
        parent: parent,
        position: position,
        rotation: rotation,
        scale: scale,
        name: name,
      );

  /// Releases all GPU meshes, materials, and textures owned by this catalog.
  void clear() {
    for (final m in _meshes.values) {
      _engine.graphics.releaseMesh(m);
    }
    for (final m in _materials.values) {
      _engine.graphics.releaseMaterial(m);
    }
    for (final t in _textures.values) {
      _engine.graphics.releaseTexture(t);
    }
    _models.clear();
    _prefabs.clear();
    _clips.clear();
    _textures.clear();
    _meshes.clear();
    _meshData.clear();
    _materials.clear();
    _texts.clear();
    _bytes.clear();
  }
}
