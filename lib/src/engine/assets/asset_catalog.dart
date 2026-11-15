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

final class TextureEntry extends AssetEntry {
  final String path;
  final GpuTextureFilter minFilter;
  final GpuTextureFilter magFilter;
  final GpuTextureWrap wrap;
  final bool hasMips;
  final double anisotropy;

  const TextureEntry(
    this.path, {
    this.minFilter = GpuTextureFilter.linear,
    this.magFilter = GpuTextureFilter.linear,
    this.wrap = GpuTextureWrap.clampToEdge,
    this.hasMips = false,
    this.anisotropy = 1.0,
  });
}

final class LutEntry extends AssetEntry {
  final String path;
  const LutEntry(this.path);
}

final class TextEntry extends AssetEntry {
  final String path;
  const TextEntry(this.path);
}

final class BytesEntry extends AssetEntry {
  final String path;
  const BytesEntry(this.path);
}

final class _CatalogSlot<T> {
  T value;
  int refCount;
  AssetResidencyState state;

  _CatalogSlot(
    this.value, {
    this.refCount = 0,
    this.state = AssetResidencyState.unreferenced,
  });
}

final class _RefCountedStore<T> {
  final String label;
  final void Function(String key, T value)? onDispose;
  final void Function(String key, T value)? onAnyEvict;

  final Map<String, _CatalogSlot<T>> _slots = {};
  final Map<String, AssetResidencyState> _states = {};
  final List<AssetEvictionCallback<T>> _callbacks = [];

  _RefCountedStore(this.label, {this.onDispose, this.onAnyEvict});

  Iterable<T> valuesExcluding(String excludedKey) sync* {
    for (final entry in _slots.entries) {
      if (entry.key != excludedKey) yield entry.value.value;
    }
  }

  void put(String key, T value) {
    final existing = _slots[key];
    if (existing != null) {
      if (identical(existing.value, value)) return;
      if (existing.refCount == 0) {
        onDispose?.call(key, existing.value);
        _notifyCallbacks(key, existing.value);
      } else {
        onDispose?.call(key, existing.value);
      }
      existing.value = value;
      existing.state = existing.refCount > 0
          ? AssetResidencyState.resident
          : AssetResidencyState.unreferenced;
      _states[key] = existing.state;
      return;
    }
    _slots[key] = _CatalogSlot<T>(value);
    _states[key] = AssetResidencyState.unreferenced;
  }

  bool contains(String key) => _slots.containsKey(key);

  bool hasStateRecord(String key) =>
      _slots.containsKey(key) || _states.containsKey(key);

  T require(String key) =>
      _slots[key]?.value ??
      (throw ArgumentError.value(key, 'key', '$label not found in catalog'));

  T? getOrNull(String key) => _slots[key]?.value;

  int refCount(String key) => _slots[key]?.refCount ?? 0;

  AssetResidencyState residencyState(String key) =>
      _slots[key]?.state ?? _states[key] ?? AssetResidencyState.unreferenced;

  AssetHandle<T> acquire(String key) {
    final slot = _slots[key];
    if (slot == null) {
      throw ArgumentError.value(key, 'key', '$label not found in catalog');
    }
    slot.refCount++;
    slot.state = AssetResidencyState.resident;
    _states[key] = AssetResidencyState.resident;
    return _createHandle(key, slot.value);
  }

  AssetHandle<T> _createHandle(String key, T value) {
    return AssetHandle<T>(
      key: key,
      value: value,
      onAcquire: (_) {
        final current = _slots[key];
        if (current == null) {
          throw StateError(
            'Cannot acquire already-evicted $label asset "$key".',
          );
        }
        current.refCount++;
        current.state = AssetResidencyState.resident;
        _states[key] = AssetResidencyState.resident;
      },
      onRelease: (_) => _releaseOne(key),
      refCountLookup: (_) => _slots[key]?.refCount ?? 0,
    );
  }

  void _releaseOne(String key) {
    final current = _slots[key];
    if (current == null || current.refCount <= 0) return;
    current.refCount--;
    if (current.refCount == 0) {
      evict(key);
    }
  }

  bool evict(String key) {
    final removed = _slots.remove(key);
    if (removed == null) return false;
    removed.refCount = 0;
    removed.state = AssetResidencyState.evicted;
    _states[key] = AssetResidencyState.evicted;
    onDispose?.call(key, removed.value);
    _notifyCallbacks(key, removed.value);
    return true;
  }

  int evictUnreferenced() {
    final keys = [
      for (final entry in _slots.entries)
        if (entry.value.refCount == 0) entry.key,
    ];
    for (final key in keys) {
      evict(key);
    }
    return keys.length;
  }

  void clear() {
    if (_slots.isEmpty) return;
    final snapshot = List<MapEntry<String, _CatalogSlot<T>>>.of(_slots.entries);
    _slots.clear();
    for (final entry in snapshot) {
      entry.value.refCount = 0;
      entry.value.state = AssetResidencyState.evicted;
      _states[entry.key] = AssetResidencyState.evicted;
      onDispose?.call(entry.key, entry.value.value);
      _notifyCallbacks(entry.key, entry.value.value);
    }
  }

  void addEvictionCallback(AssetEvictionCallback<T> callback) {
    if (!_callbacks.contains(callback)) {
      _callbacks.add(callback);
    }
  }

  bool removeEvictionCallback(AssetEvictionCallback<T> callback) =>
      _callbacks.remove(callback);

  void _notifyCallbacks(String key, T asset) {
    for (final callback in List<AssetEvictionCallback<T>>.of(_callbacks)) {
      callback(key, asset);
    }
    onAnyEvict?.call(key, asset);
  }
}

/// Slices a texture or atlas into uniform grid-aligned [SpriteRegion] cells (E21-1).
final class SpriteSheet {
  final TextureHandle? texture;
  final int cellWidth;
  final int cellHeight;
  final int columns;
  final int rows;
  final double textureWidth;
  final double textureHeight;

  final List<SpriteRegion> _regions;

  SpriteSheet({
    required this.texture,
    required this.cellWidth,
    required this.cellHeight,
    required this.columns,
    required this.rows,
    double? textureWidth,
    double? textureHeight,
  }) : textureWidth = textureWidth ?? (columns * cellWidth).toDouble(),
       textureHeight = textureHeight ?? (rows * cellHeight).toDouble(),
       _regions = [] {
    final tw = this.textureWidth;
    final th = this.textureHeight;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final u0 = (c * cellWidth) / tw;
        final v0 = (r * cellHeight) / th;
        final u1 = ((c + 1) * cellWidth) / tw;
        final v1 = ((r + 1) * cellHeight) / th;
        _regions.add(
          SpriteRegion(
            texture: texture,
            width: cellWidth.toDouble(),
            height: cellHeight.toDouble(),
            u0: u0,
            v0: v0,
            u1: u1,
            v1: v1,
          ),
        );
      }
    }
  }

  int get count => _regions.length;

  /// Returns the [SpriteRegion] at linear [index].
  SpriteRegion get(int index) => _regions[index.clamp(0, _regions.length - 1)];

  /// Returns the [SpriteRegion] at grid coordinate `(column, row)`.
  SpriteRegion cell(int column, int row) {
    final idx = row * columns + column;
    return get(idx);
  }

  /// Returns an immutable sublist of regions representing an animation clip.
  List<SpriteRegion> slice(int start, int end) => List.unmodifiable(
    _regions.sublist(
      start.clamp(0, _regions.length),
      end.clamp(0, _regions.length),
    ),
  );

  /// All generated [SpriteRegion]s.
  List<SpriteRegion> get all => List.unmodifiable(_regions);
}

/// Preloads models, audio clips, procedural textures, meshes, materials, texts,
/// bytes, and 3D LUTs by logical string key with ref-counted [AssetHandle]s,
/// [AssetResidencyState] tracking, and [AssetEvictionCallback] notifications (E3-4).
final class AssetCatalog {
  final Engine _engine;

  final List<AssetEvictionCallback<Object?>> _anyEvictionCallbacks = [];

  late final _RefCountedStore<ModelAsset> _models =
      _RefCountedStore<ModelAsset>(
        'ModelAsset',
        onDispose: _disposeModelAsset,
        onAnyEvict: _notifyAnyEvict,
      );
  late final _RefCountedStore<AudioClip> _clips = _RefCountedStore<AudioClip>(
    'AudioClip',
    onAnyEvict: _notifyAnyEvict,
  );
  late final _RefCountedStore<TextureHandle> _textures =
      _RefCountedStore<TextureHandle>(
        'TextureHandle',
        onDispose: (key, handle) => _releaseTextureIfUnused(key, handle),
        onAnyEvict: _notifyAnyEvict,
      );
  late final _RefCountedStore<MeshHandle> _meshes =
      _RefCountedStore<MeshHandle>(
        'MeshHandle',
        onDispose: (key, handle) {
          _meshData.remove(key);
          _releaseMeshIfUnused(key, handle);
        },
        onAnyEvict: _notifyAnyEvict,
      );
  final Map<String, MeshData> _meshData = {};
  late final _RefCountedStore<MaterialHandle> _materials =
      _RefCountedStore<MaterialHandle>(
        'MaterialHandle',
        onDispose: (key, handle) => _releaseMaterialIfUnused(key, handle),
        onAnyEvict: _notifyAnyEvict,
      );
  late final _RefCountedStore<String> _texts = _RefCountedStore<String>(
    'Text asset',
    onAnyEvict: _notifyAnyEvict,
  );
  late final _RefCountedStore<Uint8List> _bytes = _RefCountedStore<Uint8List>(
    'Bytes asset',
    onAnyEvict: _notifyAnyEvict,
  );
  late final _RefCountedStore<LutAsset> _luts = _RefCountedStore<LutAsset>(
    'LutAsset',
    onAnyEvict: _notifyAnyEvict,
  );
  final Map<String, Prefab> _prefabs = {};
  final Map<String, SpriteSheet> _sheets = {};

  AssetCatalog._(this._engine);

  List<_RefCountedStore<dynamic>> get _allStores => [
    _models,
    _clips,
    _textures,
    _meshes,
    _materials,
    _texts,
    _bytes,
    _luts,
  ];

  void _notifyAnyEvict(String key, Object? asset) {
    for (final cb in List<AssetEvictionCallback<Object?>>.of(
      _anyEvictionCallbacks,
    )) {
      cb(key, asset);
    }
  }

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
            _models.put(
              key,
              await _engine.assets.loadModel(
                e.path,
                materialOverride: e.materialOverride,
              ),
            );
          case AudioEntry e:
            _clips.put(
              key,
              _engine.audio.clip(e.path, volume: e.volume, voices: e.voices),
            );
          case ProceduralTextureEntry e:
            _textures.put(
              key,
              _engine.graphics.createTexture(
                width: e.width,
                height: e.height,
                pixels: e.generatePixels(),
                minFilter: e.minFilter,
                magFilter: e.magFilter,
                wrap: e.wrap,
                hasMips: e.hasMips,
                debugLabel: key,
              ),
            );
          case TextureEntry e:
            final texBytes = await _engine.assets.loadBytes(e.path);
            final decoded = decodeVfsTextureBytes(texBytes, path: e.path);
            _textures.put(
              key,
              _engine.graphics.createTexture(
                width: decoded.width,
                height: decoded.height,
                pixels: decoded.rgbaPixels,
                minFilter: e.minFilter,
                magFilter: e.magFilter,
                wrap: e.wrap,
                hasMips: e.hasMips,
                anisotropy: e.anisotropy,
                debugLabel: key,
              ),
            );
          case LutEntry e:
            final lutBytes = await _engine.assets.loadBytes(e.path);
            _luts.put(key, parseLutBytes(key, lutBytes));
          case TextEntry e:
            _texts.put(key, await _engine.assets.loadText(e.path));
          case BytesEntry e:
            _bytes.put(key, await _engine.assets.loadBytes(e.path));
        }
        completed++;
        onProgress?.call(completed, total);
      }),
    );
  }

  /// Loads a [ModelAsset] from [path] (if not already present under [key]) and
  /// returns a retained [AssetHandle].
  Future<AssetHandle<ModelAsset>> loadModel(
    String key,
    String path, {
    MaterialOverride? materialOverride,
  }) async {
    if (!_models.contains(key)) {
      _models.put(
        key,
        await _engine.assets.loadModel(
          path,
          materialOverride: materialOverride,
        ),
      );
    }
    return acquireModel(key);
  }

  /// Loads and registers a decoded `.tga`/`.bmp`/`VTXR` texture from [path] (if
  /// not already present under [key]) and returns a retained [AssetHandle].
  Future<AssetHandle<TextureHandle>> loadTexture(
    String key,
    String path, {
    GpuTextureFilter minFilter = GpuTextureFilter.linear,
    GpuTextureFilter magFilter = GpuTextureFilter.linear,
    GpuTextureWrap wrap = GpuTextureWrap.clampToEdge,
    bool hasMips = false,
    double anisotropy = 1.0,
  }) async {
    if (!_textures.contains(key)) {
      final bytes = await _engine.assets.loadBytes(path);
      final decoded = decodeVfsTextureBytes(bytes, path: path);
      registerTexture(
        key,
        width: decoded.width,
        height: decoded.height,
        pixels: decoded.rgbaPixels,
        minFilter: minFilter,
        magFilter: magFilter,
        wrap: wrap,
        hasMips: hasMips,
        anisotropy: anisotropy,
      );
    }
    return acquireTexture(key);
  }

  /// Loads a `.cube` or `VLUT` 3D LUT from [path] (if not already present under
  /// [key]) and returns a retained [AssetHandle].
  Future<AssetHandle<LutAsset>> loadLut(String key, String path) async {
    if (!_luts.contains(key)) {
      final bytes = await _engine.assets.loadBytes(path);
      _luts.put(key, parseLutBytes(key, bytes));
    }
    return acquireLut(key);
  }

  void putModel(String key, ModelAsset asset) => _models.put(key, asset);
  void putClip(String key, AudioClip clip) => _clips.put(key, clip);
  void putTexture(String key, TextureHandle handle) =>
      _textures.put(key, handle);
  void putText(String key, String text) => _texts.put(key, text);
  void putBytes(String key, Uint8List bytes) => _bytes.put(key, bytes);
  void putLut(String key, LutAsset lut) => _luts.put(key, lut);

  MeshHandle registerMesh(String key, MeshData data) {
    final handle = _engine.graphics.createMesh(data, debugLabel: key);
    _meshes.put(key, handle);
    _meshData[key] = data;
    return handle;
  }

  MaterialHandle registerMaterial(String key, MaterialDefinition definition) {
    final handle = _engine.graphics.createMaterial(definition);
    _materials.put(key, handle);
    return handle;
  }

  TextureHandle registerTexture(
    String key, {
    required int width,
    required int height,
    Uint8List? pixels,
    bool hasMips = false,
    GpuTextureFilter minFilter = GpuTextureFilter.linear,
    GpuTextureFilter magFilter = GpuTextureFilter.linear,
    GpuTextureWrap wrap = GpuTextureWrap.clampToEdge,
    double anisotropy = 1.0,
  }) {
    final handle = _engine.graphics.createTexture(
      width: width,
      height: height,
      pixels: pixels,
      hasMips: hasMips,
      minFilter: minFilter,
      magFilter: magFilter,
      wrap: wrap,
      anisotropy: anisotropy,
      debugLabel: key,
    );
    _textures.put(key, handle);
    return handle;
  }

  bool hasModel(String key) => _models.contains(key);
  bool hasClip(String key) => _clips.contains(key);
  bool hasTexture(String key) => _textures.contains(key);
  bool hasMesh(String key) => _meshes.contains(key);
  bool hasMaterial(String key) => _materials.contains(key);
  bool hasText(String key) => _texts.contains(key);
  bool hasBytes(String key) => _bytes.contains(key);
  bool hasLut(String key) => _luts.contains(key);

  ModelAsset model(String key) => _models.require(key);
  AudioClip clip(String key) => _clips.require(key);
  TextureHandle texture(String key) => _textures.require(key);
  MeshHandle mesh(String key) => _meshes.require(key);
  MeshData? meshData(String key) => _meshData[key];
  MaterialHandle material(String key) => _materials.require(key);
  String text(String key) => _texts.require(key);
  Uint8List bytes(String key) => _bytes.require(key);
  LutAsset lut(String key) => _luts.require(key);

  AssetHandle<ModelAsset> acquireModel(String key) => _models.acquire(key);
  AssetHandle<AudioClip> acquireClip(String key) => _clips.acquire(key);
  AssetHandle<TextureHandle> acquireTexture(String key) =>
      _textures.acquire(key);
  AssetHandle<MeshHandle> acquireMesh(String key) => _meshes.acquire(key);
  AssetHandle<MaterialHandle> acquireMaterial(String key) =>
      _materials.acquire(key);
  AssetHandle<String> acquireText(String key) => _texts.acquire(key);
  AssetHandle<Uint8List> acquireBytes(String key) => _bytes.acquire(key);
  AssetHandle<LutAsset> acquireLut(String key) => _luts.acquire(key);

  /// Acquires a ref-counted [AssetHandle] for [key] matching asset type [T].
  AssetHandle<T> acquire<T>(String key) {
    if (T == ModelAsset) return acquireModel(key) as AssetHandle<T>;
    if (T == AudioClip) return acquireClip(key) as AssetHandle<T>;
    if (T == TextureHandle) return acquireTexture(key) as AssetHandle<T>;
    if (T == MeshHandle) return acquireMesh(key) as AssetHandle<T>;
    if (T == MaterialHandle) return acquireMaterial(key) as AssetHandle<T>;
    if (T == String) return acquireText(key) as AssetHandle<T>;
    if (T == Uint8List) return acquireBytes(key) as AssetHandle<T>;
    if (T == LutAsset) return acquireLut(key) as AssetHandle<T>;
    throw ArgumentError.value(
      T,
      'T',
      'Unsupported AssetCatalog asset handle type for "$key"',
    );
  }

  /// Current global reference count for [key] (optionally scoped by asset type [T]).
  int refCount<T>(String key) {
    final typedStore = _storeForType<T>();
    if (typedStore != null) return typedStore.refCount(key);
    if (T == dynamic || T == Object) {
      var total = 0;
      for (final store in _allStores) {
        if (store.contains(key)) total += store.refCount(key);
      }
      return total;
    }
    return 0;
  }

  /// Current [AssetResidencyState] for [key] (optionally scoped by asset type [T]).
  AssetResidencyState residencyState<T>(String key) {
    final typedStore = _storeForType<T>();
    if (typedStore != null) return typedStore.residencyState(key);
    if (T == dynamic || T == Object) {
      for (final store in _allStores) {
        if (store.contains(key)) return store.residencyState(key);
      }
      for (final store in _allStores) {
        if (store.hasStateRecord(key)) return store.residencyState(key);
      }
    }
    return AssetResidencyState.unreferenced;
  }

  /// Registers [callback] to be invoked when an asset of type [T] (or any
  /// asset when [T] is `Object?` / `dynamic`) is evicted or cleared.
  void onEvict<T>(AssetEvictionCallback<T> callback) {
    if (T == dynamic || T == Object || T == _nullableObjectType) {
      final untyped = callback as AssetEvictionCallback<Object?>;
      if (!_anyEvictionCallbacks.contains(untyped)) {
        _anyEvictionCallbacks.add(untyped);
      }
      return;
    }
    if (T == ModelAsset) {
      _models.addEvictionCallback(
        callback as AssetEvictionCallback<ModelAsset>,
      );
      return;
    }
    if (T == AudioClip) {
      _clips.addEvictionCallback(callback as AssetEvictionCallback<AudioClip>);
      return;
    }
    if (T == TextureHandle) {
      _textures.addEvictionCallback(
        callback as AssetEvictionCallback<TextureHandle>,
      );
      return;
    }
    if (T == MeshHandle) {
      _meshes.addEvictionCallback(
        callback as AssetEvictionCallback<MeshHandle>,
      );
      return;
    }
    if (T == MaterialHandle) {
      _materials.addEvictionCallback(
        callback as AssetEvictionCallback<MaterialHandle>,
      );
      return;
    }
    if (T == String) {
      _texts.addEvictionCallback(callback as AssetEvictionCallback<String>);
      return;
    }
    if (T == Uint8List) {
      _bytes.addEvictionCallback(callback as AssetEvictionCallback<Uint8List>);
      return;
    }
    if (T == LutAsset) {
      _luts.addEvictionCallback(callback as AssetEvictionCallback<LutAsset>);
      return;
    }
    throw ArgumentError.value(T, 'T', 'Unsupported AssetCatalog eviction type');
  }

  bool removeEvictionCallback<T>(AssetEvictionCallback<T> callback) {
    if (T == dynamic || T == Object || T == _nullableObjectType) {
      return _anyEvictionCallbacks.remove(
        callback as AssetEvictionCallback<Object?>,
      );
    }
    if (T == ModelAsset) {
      return _models.removeEvictionCallback(
        callback as AssetEvictionCallback<ModelAsset>,
      );
    }
    if (T == AudioClip) {
      return _clips.removeEvictionCallback(
        callback as AssetEvictionCallback<AudioClip>,
      );
    }
    if (T == TextureHandle) {
      return _textures.removeEvictionCallback(
        callback as AssetEvictionCallback<TextureHandle>,
      );
    }
    if (T == MeshHandle) {
      return _meshes.removeEvictionCallback(
        callback as AssetEvictionCallback<MeshHandle>,
      );
    }
    if (T == MaterialHandle) {
      return _materials.removeEvictionCallback(
        callback as AssetEvictionCallback<MaterialHandle>,
      );
    }
    if (T == String) {
      return _texts.removeEvictionCallback(
        callback as AssetEvictionCallback<String>,
      );
    }
    if (T == Uint8List) {
      return _bytes.removeEvictionCallback(
        callback as AssetEvictionCallback<Uint8List>,
      );
    }
    if (T == LutAsset) {
      return _luts.removeEvictionCallback(
        callback as AssetEvictionCallback<LutAsset>,
      );
    }
    return false;
  }

  /// Forcefully evicts the cached entry for [key] (scoped by [T], or across all
  /// stores if [T] is `dynamic`/`Object`).
  bool evict<T>(String key) {
    final typedStore = _storeForType<T>();
    if (typedStore != null) return typedStore.evict(key);
    if (T == dynamic || T == Object || T == _nullableObjectType) {
      var any = false;
      for (final store in _allStores) {
        if (store.evict(key)) any = true;
      }
      return any;
    }
    return false;
  }

  /// Evicts and disposes all cached entries whose reference count is `0`.
  int evictUnreferenced() {
    var evictedCount = 0;
    for (final store in _allStores) {
      evictedCount += store.evictUnreferenced();
    }
    return evictedCount;
  }

  _RefCountedStore<dynamic>? _storeForType<T>() {
    if (T == ModelAsset) return _models;
    if (T == AudioClip) return _clips;
    if (T == TextureHandle) return _textures;
    if (T == MeshHandle) return _meshes;
    if (T == MaterialHandle) return _materials;
    if (T == String) return _texts;
    if (T == Uint8List) return _bytes;
    if (T == LutAsset) return _luts;
    return null;
  }

  void _disposeModelAsset(String key, ModelAsset asset) {
    _prefabs.remove(key);

    final stillUsedMeshes = <MeshHandle>{..._meshes.valuesExcluding('')};
    final stillUsedMaterials = <MaterialHandle>{
      ..._materials.valuesExcluding(''),
    };
    final stillUsedTextures = <TextureHandle>{..._textures.valuesExcluding('')};

    for (final other in _models.valuesExcluding(key)) {
      final tracked = _modelResourceExpando[other];
      if (tracked != null) {
        stillUsedMeshes.addAll(tracked.meshes);
        stillUsedMaterials.addAll(tracked.materials);
        stillUsedTextures.addAll(tracked.textures);
      }
    }

    final tracked = _modelResourceExpando[asset];
    if (tracked != null) {
      for (final mesh in tracked.meshes.toSet()) {
        if (!stillUsedMeshes.contains(mesh)) {
          tracked.resources.releaseMesh(mesh);
          _engine.graphics.releaseMesh(mesh);
        }
      }
      for (final mat in tracked.materials.toSet()) {
        if (!stillUsedMaterials.contains(mat)) {
          tracked.resources.releaseMaterial(mat);
          _engine.graphics.releaseMaterial(mat);
        }
      }
      for (final tex in tracked.textures.toSet()) {
        if (!stillUsedTextures.contains(tex)) {
          tracked.resources.releaseTexture(tex);
          _engine.graphics.releaseTexture(tex);
        }
      }
      return;
    }

    final collectedMeshes = <MeshHandle>{};
    final collectedMaterials = <MaterialHandle>{};
    asset.instantiate().traverse((node) {
      final m = node.mesh;
      if (m != null && m.isValid) collectedMeshes.add(m);
      final mat = node.material;
      if (mat != null && mat.isValid) collectedMaterials.add(mat);
    });
    for (final mesh in collectedMeshes) {
      if (!stillUsedMeshes.contains(mesh)) {
        _engine.graphics.releaseMesh(mesh);
      }
    }
    for (final mat in collectedMaterials) {
      if (!stillUsedMaterials.contains(mat)) {
        _engine.graphics.releaseMaterial(mat);
      }
    }
  }

  void _releaseMeshIfUnused(String key, MeshHandle handle) {
    if (!handle.isValid) return;
    if (_meshes.valuesExcluding(key).contains(handle)) return;
    for (final model in _models.valuesExcluding('')) {
      final tracked = _modelResourceExpando[model];
      if (tracked != null && tracked.meshes.contains(handle)) return;
    }
    _engine.graphics.releaseMesh(handle);
  }

  void _releaseMaterialIfUnused(String key, MaterialHandle handle) {
    if (!handle.isValid) return;
    if (_materials.valuesExcluding(key).contains(handle)) return;
    for (final model in _models.valuesExcluding('')) {
      final tracked = _modelResourceExpando[model];
      if (tracked != null && tracked.materials.contains(handle)) return;
    }
    _engine.graphics.releaseMaterial(handle);
  }

  void _releaseTextureIfUnused(String key, TextureHandle handle) {
    if (!handle.isValid) return;
    if (_textures.valuesExcluding(key).contains(handle)) return;
    for (final model in _models.valuesExcluding('')) {
      final tracked = _modelResourceExpando[model];
      if (tracked != null && tracked.textures.contains(handle)) return;
    }
    _engine.graphics.releaseTexture(handle);
  }

  void putPrefab(String key, Prefab prefab) => _prefabs[key] = prefab;

  bool hasPrefab(String key) =>
      _prefabs.containsKey(key) || _models.contains(key);

  void putSpriteSheet(String key, SpriteSheet sheet) => _sheets[key] = sheet;

  SpriteSheet spriteSheet(String key) =>
      _sheets[key] ??
      (throw ArgumentError.value(
        key,
        'key',
        'SpriteSheet not found in catalog',
      ));

  SpriteSheet registerSpriteSheet(
    String key, {
    required TextureHandle texture,
    required int cellWidth,
    required int cellHeight,
    required int columns,
    required int rows,
    double? textureWidth,
    double? textureHeight,
  }) {
    final sheet = SpriteSheet(
      texture: texture,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      columns: columns,
      rows: rows,
      textureWidth: textureWidth,
      textureHeight: textureHeight,
    );
    _sheets[key] = sheet;
    return sheet;
  }

  /// Returns the [Prefab] registered under [key], or lazily builds (and
  /// caches) one from the [ModelAsset] loaded under the same key so a loaded
  /// GLB spawns in one line: `scene.instantiate(catalog.prefab('ship'))`
  /// (E15-2).
  Prefab prefab(String key) {
    final cached = _prefabs[key];
    if (cached != null) return cached;
    final asset = _models.getOrNull(key);
    if (asset == null) {
      throw ArgumentError.value(
        key,
        'key',
        'Prefab/ModelAsset not found in catalog',
      );
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
  }) => (scene ?? _engine.scene).instantiate(
    prefab(key),
    parent: parent,
    position: position,
    rotation: rotation,
    scale: scale,
    name: name,
  );

  /// Releases all GPU meshes, materials, and textures owned by this catalog.
  void clear() {
    _prefabs.clear();
    _sheets.clear();
    _meshData.clear();
    for (final store in _allStores) {
      store.clear();
    }
  }
}

final Type _nullableObjectType = _typeOf<Object?>();
Type _typeOf<T>() => T;
