part of '../../engine.dart';

/// Pure-Dart decoded RGBA8 texture payload used by VFS texture loaders.
final class DecodedTextureData {
  final int width;
  final int height;
  final Uint8List rgbaPixels;

  const DecodedTextureData({
    required this.width,
    required this.height,
    required this.rgbaPixels,
  });
}

final class _ManagedTextureRecord {
  final int width;
  final int height;
  final int layers;
  bool hasMips;
  final GpuTextureFilter minFilter;
  final GpuTextureFilter magFilter;
  final GpuTextureWrap wrap;
  final double anisotropy;
  Uint8List? pixels;
  bool mipsFinalized = false;
  final String? debugLabel;

  _ManagedTextureRecord({
    required this.width,
    required this.height,
    required this.layers,
    required this.hasMips,
    required this.minFilter,
    required this.magFilter,
    required this.wrap,
    required this.anisotropy,
    required this.pixels,
    required this.debugLabel,
  });
}

/// Pure-Dart in-memory [ResourceLibrary] tracking allocated meshes, materials,
/// textures, and model bindings with optional pass-through to a host [Graphics].
final class MemoryResourceLibrary implements ResourceLibrary {
  final Graphics? graphics;
  final bool anisotropicFiltering;
  final double maxAnisotropy;

  int _nextSlot = 0;
  final Map<MeshHandle, MeshData> _meshes = {};
  final Map<MaterialHandle, MaterialDefinition> _materials = {};
  final Map<TextureHandle, _ManagedTextureRecord> _textures = {};
  final Map<String, ModelDefinition> _boundModels = {};

  MemoryResourceLibrary({
    this.graphics,
    this.anisotropicFiltering = false,
    this.maxAnisotropy = 1.0,
  });

  Set<MeshHandle> get liveMeshes => Set.unmodifiable(_meshes.keys);
  Set<MaterialHandle> get liveMaterials => Set.unmodifiable(_materials.keys);
  Set<TextureHandle> get liveTextures => Set.unmodifiable(_textures.keys);

  int get liveMeshCount => _meshes.length;
  int get liveMaterialCount => _materials.length;
  int get liveTextureCount => _textures.length;

  MeshData? meshDataOf(MeshHandle handle) => _meshes[handle];
  MaterialDefinition? materialOf(MaterialHandle handle) => _materials[handle];
  Uint8List? texturePixelsOf(TextureHandle handle) => _textures[handle]?.pixels;
  bool isTextureMipsFinalized(TextureHandle handle) =>
      _textures[handle]?.mipsFinalized ?? false;
  ModelDefinition? boundModelDefinition(String key) => _boundModels[key];

  @override
  MeshHandle registerMesh(MeshData data, {String? debugLabel}) {
    final handle =
        graphics?.createMesh(data, debugLabel: debugLabel) ??
        MeshHandle(_nextSlot++, 1, debugLabel);
    _meshes[handle] = data;
    return handle;
  }

  @override
  void releaseMesh(MeshHandle handle) {
    if (_meshes.remove(handle) != null) {
      graphics?.releaseMesh(handle);
    }
  }

  @override
  MaterialHandle registerMaterial(MaterialDefinition definition) {
    final handle =
        graphics?.createMaterial(definition) ??
        MaterialHandle(_nextSlot++, 1, definition.key);
    _materials[handle] = definition;
    return handle;
  }

  @override
  void releaseMaterial(MaterialHandle handle) {
    if (_materials.remove(handle) != null) {
      graphics?.releaseMaterial(handle);
    }
  }

  @override
  ModelBinding bindModel(ModelDefinition definition) {
    _boundModels[definition.key] = definition;
    return ModelBinding(definition, const []);
  }

  @override
  TextureHandle registerTexture({
    required int width,
    required int height,
    int layers = 1,
    bool hasMips = false,
    GpuTextureFilter minFilter = GpuTextureFilter.linear,
    GpuTextureFilter magFilter = GpuTextureFilter.linear,
    GpuTextureWrap wrap = GpuTextureWrap.clampToEdge,
    double anisotropy = 1,
    Uint8List? pixels,
    String? debugLabel,
  }) {
    final copy = pixels == null ? null : Uint8List.fromList(pixels);
    final handle =
        graphics?.createTexture(
          width: width,
          height: height,
          pixels: copy,
          hasMips: hasMips,
          minFilter: minFilter,
          magFilter: magFilter,
          wrap: wrap,
          anisotropy: anisotropy,
          debugLabel: debugLabel,
        ) ??
        TextureHandle(_nextSlot++, 1, debugLabel);
    _textures[handle] = _ManagedTextureRecord(
      width: width,
      height: height,
      layers: layers,
      hasMips: hasMips,
      minFilter: minFilter,
      magFilter: magFilter,
      wrap: wrap,
      anisotropy: anisotropy,
      pixels: copy,
      debugLabel: debugLabel,
    );
    return handle;
  }

  @override
  void updateTexturePixels(TextureHandle handle, Uint8List pixels) {
    final rec = _textures[handle];
    if (rec == null) return;
    rec.pixels = Uint8List.fromList(pixels);
  }

  @override
  void finalizeTextureMips(TextureHandle handle) {
    final rec = _textures[handle];
    if (rec == null) return;
    rec.hasMips = true;
    rec.mipsFinalized = true;
  }

  @override
  AnisotropyDecision anisotropyOf(TextureHandle handle) {
    final requested = (_textures[handle]?.anisotropy ?? 1.0).clamp(1.0, 16.0);
    return AnisotropyDecision.resolve(
      requested: requested,
      extensionAvailable: anisotropicFiltering,
      maxSupported: maxAnisotropy,
    );
  }

  @override
  void releaseTexture(TextureHandle handle) {
    if (_textures.remove(handle) != null) {
      graphics?.releaseTexture(handle);
    }
  }

  // `TextureResidencyManager` and `MaterialResidencyManager` are not exported
  // into the pure-Dart engine core; infer return types from [ResourceLibrary].
  @override
  get textureResidency => throw UnsupportedError(
    'MemoryResourceLibrary does not expose pixeldart TextureResidencyManager.',
  );

  @override
  get materialResidency => throw UnsupportedError(
    'MemoryResourceLibrary does not expose pixeldart MaterialResidencyManager.',
  );

  @override
  void dispose() {
    for (final handle in List<MeshHandle>.of(_meshes.keys)) {
      releaseMesh(handle);
    }
    for (final handle in List<MaterialHandle>.of(_materials.keys)) {
      releaseMaterial(handle);
    }
    for (final handle in List<TextureHandle>.of(_textures.keys)) {
      releaseTexture(handle);
    }
    _boundModels.clear();
  }
}

final class _TrackedModelResources {
  final ResourceLibrary resources;
  final List<MeshHandle> meshes = [];
  final List<MaterialHandle> materials = [];
  final List<TextureHandle> textures = [];

  _TrackedModelResources(this.resources);
}

final Expando<_TrackedModelResources> _modelResourceExpando =
    Expando<_TrackedModelResources>('ModelAssetResources');

final class _RecordingResourceLibrary implements ResourceLibrary {
  final ResourceLibrary inner;
  final _TrackedModelResources tracked;

  _RecordingResourceLibrary(this.inner)
    : tracked = _TrackedModelResources(inner);

  @override
  MeshHandle registerMesh(MeshData data, {String? debugLabel}) {
    final handle = inner.registerMesh(data, debugLabel: debugLabel);
    tracked.meshes.add(handle);
    return handle;
  }

  @override
  void releaseMesh(MeshHandle handle) => inner.releaseMesh(handle);

  @override
  MaterialHandle registerMaterial(MaterialDefinition definition) {
    final handle = inner.registerMaterial(definition);
    tracked.materials.add(handle);
    return handle;
  }

  @override
  void releaseMaterial(MaterialHandle handle) => inner.releaseMaterial(handle);

  @override
  ModelBinding bindModel(ModelDefinition definition) =>
      inner.bindModel(definition);

  @override
  TextureHandle registerTexture({
    required int width,
    required int height,
    int layers = 1,
    bool hasMips = false,
    GpuTextureFilter minFilter = GpuTextureFilter.linear,
    GpuTextureFilter magFilter = GpuTextureFilter.linear,
    GpuTextureWrap wrap = GpuTextureWrap.clampToEdge,
    double anisotropy = 1,
    Uint8List? pixels,
    String? debugLabel,
  }) {
    final handle = inner.registerTexture(
      width: width,
      height: height,
      layers: layers,
      hasMips: hasMips,
      minFilter: minFilter,
      magFilter: magFilter,
      wrap: wrap,
      anisotropy: anisotropy,
      pixels: pixels,
      debugLabel: debugLabel,
    );
    tracked.textures.add(handle);
    return handle;
  }

  @override
  void updateTexturePixels(TextureHandle handle, Uint8List pixels) =>
      inner.updateTexturePixels(handle, pixels);

  @override
  void finalizeTextureMips(TextureHandle handle) =>
      inner.finalizeTextureMips(handle);

  @override
  AnisotropyDecision anisotropyOf(TextureHandle handle) =>
      inner.anisotropyOf(handle);

  @override
  void releaseTexture(TextureHandle handle) => inner.releaseTexture(handle);

  @override
  get textureResidency => inner.textureResidency;

  @override
  get materialResidency => inner.materialResidency;

  @override
  void dispose() => inner.dispose();
}

/// Decodes an uncompressed `.tga`, `.bmp`, or `VTXR` texture buffer into top-to-bottom RGBA8.
DecodedTextureData decodeVfsTextureBytes(
  Uint8List bytes, {
  String? path,
  String? mimeType,
}) {
  final decoded = tryDecodeVfsTextureBytes(
    bytes,
    path: path,
    mimeType: mimeType,
  );
  if (decoded != null) return decoded;
  throw FormatException(
    'Unsupported texture format${path == null ? '' : ' for "$path"'}'
    '${mimeType == null || mimeType.isEmpty ? '' : ' ($mimeType)'}.',
  );
}

/// Attempts to decode an uncompressed `.tga`, `.bmp`, or `VTXR` texture buffer;
/// returns `null` for unsupported compressed image encodings.
DecodedTextureData? tryDecodeVfsTextureBytes(
  Uint8List bytes, {
  String? path,
  String? mimeType,
}) {
  if (_matchesMagic(bytes, const [0x56, 0x54, 0x58, 0x52])) {
    return _decodeVtxr(bytes);
  }
  if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return _decodeBmp(bytes);
  }
  final lowerPath = path?.toLowerCase() ?? '';
  final lowerMime = mimeType?.toLowerCase() ?? '';
  if (lowerPath.endsWith('.tga') ||
      lowerMime == 'image/tga' ||
      lowerMime == 'image/x-tga') {
    return _decodeTga(bytes);
  }
  if (lowerPath.endsWith('.vtxr') || lowerPath.endsWith('.rgba')) {
    return _decodeVtxr(bytes);
  }
  if (_looksLikeUncompressedTga(bytes)) {
    return _decodeTga(bytes);
  }
  return null;
}

bool _matchesMagic(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

bool _looksLikeUncompressedTga(Uint8List bytes) {
  if (bytes.length < 18) return false;
  final colorMapType = bytes[1];
  final imageType = bytes[2];
  if (colorMapType != 0 || (imageType != 2 && imageType != 3)) return false;
  final bd = ByteData.sublistView(bytes);
  final w = bd.getUint16(12, Endian.little);
  final h = bd.getUint16(14, Endian.little);
  final bpp = bytes[16];
  if (w == 0 || h == 0) return false;
  final validBpp = imageType == 2 ? (bpp == 24 || bpp == 32) : bpp == 8;
  if (!validBpp) return false;
  final expected = 18 + bytes[0] + w * h * (bpp ~/ 8);
  return bytes.length == expected;
}

DecodedTextureData _decodeVtxr(Uint8List bytes) {
  if (bytes.length < 12 ||
      !_matchesMagic(bytes, const [0x56, 0x54, 0x58, 0x52])) {
    throw const FormatException('Invalid VTXR texture header.');
  }
  final bd = ByteData.sublistView(bytes);
  final width = bd.getUint32(4, Endian.little);
  final height = bd.getUint32(8, Endian.little);
  final expected = 12 + width * height * 4;
  if (width == 0 || height == 0 || bytes.length < expected) {
    throw const FormatException('Truncated VTXR RGBA8 texture payload.');
  }
  return DecodedTextureData(
    width: width,
    height: height,
    rgbaPixels: Uint8List.sublistView(bytes, 12, expected),
  );
}

DecodedTextureData _decodeTga(Uint8List bytes) {
  if (bytes.length < 18) {
    throw const FormatException('Truncated TGA header.');
  }
  final idLen = bytes[0];
  final colorMapType = bytes[1];
  final imageType = bytes[2];
  if (colorMapType != 0 || (imageType != 2 && imageType != 3)) {
    throw FormatException('Unsupported TGA imageType=$imageType.');
  }
  final bd = ByteData.sublistView(bytes);
  final width = bd.getUint16(12, Endian.little);
  final height = bd.getUint16(14, Endian.little);
  final bpp = bytes[16];
  final validBpp = imageType == 2 ? (bpp == 24 || bpp == 32) : bpp == 8;
  if (width == 0 || height == 0 || !validBpp) {
    throw FormatException(
      'Unsupported TGA dimensions/bpp (${width}x$height@$bpp).',
    );
  }
  final bytesPerPx = bpp ~/ 8;
  final pixelStart = 18 + idLen;
  if (bytes.length < pixelStart + width * height * bytesPerPx) {
    throw const FormatException('Truncated TGA pixel data.');
  }
  final topOrigin = (bytes[17] & 0x20) != 0;
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final srcY = topOrigin ? y : (height - 1 - y);
    for (var x = 0; x < width; x++) {
      final srcIdx = pixelStart + (srcY * width + x) * bytesPerPx;
      final dstIdx = (y * width + x) * 4;
      if (bpp == 8) {
        final l = bytes[srcIdx];
        out[dstIdx] = l;
        out[dstIdx + 1] = l;
        out[dstIdx + 2] = l;
        out[dstIdx + 3] = 255;
      } else {
        out[dstIdx] = bytes[srcIdx + 2];
        out[dstIdx + 1] = bytes[srcIdx + 1];
        out[dstIdx + 2] = bytes[srcIdx];
        out[dstIdx + 3] = bpp == 32 ? bytes[srcIdx + 3] : 255;
      }
    }
  }
  return DecodedTextureData(width: width, height: height, rgbaPixels: out);
}

DecodedTextureData _decodeBmp(Uint8List bytes) {
  if (bytes.length < 54 || bytes[0] != 0x42 || bytes[1] != 0x4D) {
    throw const FormatException('Invalid BMP header.');
  }
  final bd = ByteData.sublistView(bytes);
  final pixelOffset = bd.getUint32(10, Endian.little);
  final dibSize = bd.getUint32(14, Endian.little);
  if (dibSize < 40) {
    throw FormatException('Unsupported BMP DIB header size: $dibSize');
  }
  final rawW = bd.getInt32(18, Endian.little);
  final rawH = bd.getInt32(22, Endian.little);
  final bpp = bd.getUint16(28, Endian.little);
  final compression = bd.getUint32(30, Endian.little);
  final topDown = rawH < 0;
  final width = rawW;
  final height = rawH.abs();
  if (width <= 0 ||
      height <= 0 ||
      compression != 0 ||
      (bpp != 24 && bpp != 32)) {
    throw FormatException(
      'Unsupported BMP encoding (${width}x$height@$bpp compression=$compression).',
    );
  }
  final rowStride = ((width * bpp + 31) ~/ 32) * 4;
  if (bytes.length < pixelOffset + rowStride * height) {
    throw const FormatException('Truncated BMP pixel payload.');
  }
  final bytesPerPx = bpp ~/ 8;
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final srcY = topDown ? y : (height - 1 - y);
    final rowStart = pixelOffset + srcY * rowStride;
    for (var x = 0; x < width; x++) {
      final srcIdx = rowStart + x * bytesPerPx;
      final dstIdx = (y * width + x) * 4;
      out[dstIdx] = bytes[srcIdx + 2];
      out[dstIdx + 1] = bytes[srcIdx + 1];
      out[dstIdx + 2] = bytes[srcIdx];
      out[dstIdx + 3] = bpp == 32 ? bytes[srcIdx + 3] : 255;
    }
  }
  return DecodedTextureData(width: width, height: height, rgbaPixels: out);
}

/// Parses a standard `.cube` text 3D LUT into a [LutAsset].
LutAsset parseCubeLutText(String key, String text, {String defaultTitle = ''}) {
  var title = defaultTitle;
  int? size;
  final floats = <double>[];

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('TITLE')) {
      final firstQuote = line.indexOf('"');
      final lastQuote = line.lastIndexOf('"');
      if (firstQuote >= 0 && lastQuote > firstQuote) {
        title = line.substring(firstQuote + 1, lastQuote);
      } else {
        title = line.substring(5).trim();
      }
      continue;
    }
    if (line.startsWith('LUT_3D_SIZE')) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        throw const FormatException('Malformed LUT_3D_SIZE directive.');
      }
      size = int.parse(parts[1]);
      continue;
    }
    if (line.startsWith('DOMAIN_MIN') ||
        line.startsWith('DOMAIN_MAX') ||
        line.startsWith('LUT_1D_SIZE')) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      floats
        ..add(double.parse(parts[0]))
        ..add(double.parse(parts[1]))
        ..add(double.parse(parts[2]));
    }
  }

  if (size == null || size < 2) {
    throw const FormatException('Missing or invalid LUT_3D_SIZE in .cube LUT.');
  }
  final expectedFloats = size * size * size * 3;
  if (floats.length != expectedFloats) {
    throw FormatException(
      'LUT triplet count mismatch: expected ${size * size * size} RGB entries, got ${floats.length ~/ 3}.',
    );
  }
  return LutAsset(
    key: key,
    size: size,
    rgbData: Float32List.fromList(floats),
    title: title,
  );
}

/// Parses either a `VLUT` binary LUT or a UTF-8 `.cube` LUT into a [LutAsset].
LutAsset parseLutBytes(
  String key,
  Uint8List bytes, {
  String defaultTitle = '',
}) {
  if (_matchesMagic(bytes, const [0x56, 0x4C, 0x55, 0x54])) {
    if (bytes.length < 8) {
      throw const FormatException('Truncated VLUT binary header.');
    }
    final bd = ByteData.sublistView(bytes);
    final size = bd.getUint32(4, Endian.little);
    final floatCount = size * size * size * 3;
    final expectedBytes = 8 + floatCount * 4;
    if (size < 2 || bytes.length < expectedBytes) {
      throw const FormatException('Truncated VLUT binary LUT payload.');
    }
    final rgb = Float32List(floatCount);
    for (var i = 0; i < floatCount; i++) {
      rgb[i] = bd.getFloat32(8 + i * 4, Endian.little);
    }
    return LutAsset(key: key, size: size, rgbData: rgb, title: defaultTitle);
  }
  return parseCubeLutText(key, utf8.decode(bytes), defaultTitle: defaultTitle);
}

/// Layered [AssetLoader] backed by [pack.VirtualFileSystem] with optional fallback
/// to a host [AssetLoader] for unbundled assets (E48-2).
final class VfsAssetLoader implements AssetLoader {
  final pack.VirtualFileSystem vfs;
  final AssetLoader? fallback;
  final ResourceLibrary? _providedResources;
  final Graphics? graphics;
  late final MemoryResourceLibrary _defaultResources = MemoryResourceLibrary(
    graphics: graphics,
  );

  VfsAssetLoader({
    pack.VirtualFileSystem? vfs,
    this.fallback,
    ResourceLibrary? resources,
    this.graphics,
  }) : vfs = vfs ?? pack.VirtualFileSystem(),
       _providedResources = resources;

  /// Active [ResourceLibrary] used to allocate GPU/in-memory resources for models
  /// and textures decoded from mounted `.pak` archives.
  ResourceLibrary get resources => _providedResources ?? _defaultResources;

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

  /// Decodes and registers a texture directly from mounted VFS archives (falling
  /// back to [fallback.loadBytes] only when absent in [vfs]).
  Future<TextureHandle> loadTexture(
    String path, {
    bool hasMips = false,
    GpuTextureFilter minFilter = GpuTextureFilter.linear,
    GpuTextureFilter magFilter = GpuTextureFilter.linear,
    GpuTextureWrap wrap = GpuTextureWrap.clampToEdge,
    double anisotropy = 1,
    ResourceLibrary? targetResources,
  }) async {
    final normPath = pack.VfsPath.normalize(path);
    final vfsBytes = vfs.readBytes(normPath);
    final Uint8List bytes;
    if (vfsBytes != null) {
      bytes = vfsBytes;
    } else if (fallback != null) {
      bytes = await fallback!.loadBytes(path);
    } else {
      throw StateError('Texture asset not found in VFS: "$normPath"');
    }

    final decoded = decodeVfsTextureBytes(bytes, path: normPath);
    return (targetResources ?? resources).registerTexture(
      width: decoded.width,
      height: decoded.height,
      hasMips: hasMips,
      minFilter: minFilter,
      magFilter: magFilter,
      wrap: wrap,
      anisotropy: anisotropy,
      pixels: decoded.rgbaPixels,
      debugLabel: normPath,
    );
  }

  /// Parses a `.cube` text or `VLUT` binary 3D LUT directly from mounted VFS
  /// archives (delegating to [fallback.loadBytes] only when absent in [vfs]).
  Future<LutAsset> loadLut(String path, {String? key}) async {
    final normPath = pack.VfsPath.normalize(path);
    final vfsBytes = vfs.readBytes(normPath);
    final Uint8List bytes;
    if (vfsBytes != null) {
      bytes = vfsBytes;
    } else if (fallback != null) {
      bytes = await fallback!.loadBytes(path);
    } else {
      throw StateError('LUT asset not found in VFS: "$normPath"');
    }
    return parseLutBytes(key ?? normPath, bytes);
  }

  /// Loads a [ModelAsset] directly from mounted `.pak` VFS archives (`.glb`,
  /// `.qmesh`, `pixeldart-model-package-v1` `.json`, or `.obj`) without requiring
  /// [fallback]. Delegates to [fallback] only when [path] is absent from [vfs].
  @override
  Future<ModelAsset> loadModel(
    String path, {
    MaterialOverride? materialOverride,
  }) async {
    final normPath = pack.VfsPath.normalize(path);
    final bytes = vfs.readBytes(normPath);
    if (bytes == null) {
      if (fallback != null) {
        return fallback!.loadModel(path, materialOverride: materialOverride);
      }
      throw StateError('Model asset not found in VFS: "$normPath"');
    }

    final recorder = _RecordingResourceLibrary(resources);
    final dir = _directoryOf(normPath);
    final baseName = _baseNameWithoutExtension(normPath);
    final lowerPath = normPath.toLowerCase();

    final ModelAsset asset;
    if (_matchesMagic(bytes, const [0x67, 0x6C, 0x54, 0x46]) ||
        lowerPath.endsWith('.glb')) {
      asset = _decodeGlbModel(
        bytes,
        recorder,
        baseName: baseName,
        dir: dir,
        materialOverride: materialOverride,
      );
    } else if (_matchesMagic(bytes, const [0x51, 0x4D, 0x53, 0x48]) ||
        lowerPath.endsWith('.qmesh')) {
      asset = _decodeSingleQmeshModel(
        bytes,
        recorder,
        baseName: baseName,
        materialOverride: materialOverride,
      );
    } else if (lowerPath.endsWith('.json')) {
      asset = _decodeModelPackageJson(
        bytes,
        recorder,
        normPath: normPath,
        dir: dir,
        materialOverride: materialOverride,
      );
    } else if (lowerPath.endsWith('.obj')) {
      asset = _decodeObjModel(
        bytes,
        recorder,
        baseName: baseName,
        dir: dir,
        materialOverride: materialOverride,
      );
    } else {
      throw FormatException('Unsupported VFS model format for "$normPath".');
    }

    _modelResourceExpando[asset] = recorder.tracked;
    return asset;
  }

  ModelAsset _decodeGlbModel(
    Uint8List bytes,
    _RecordingResourceLibrary recorder, {
    required String baseName,
    required String dir,
    MaterialOverride? materialOverride,
  }) {
    final glb = GlbDecoder.decode(bytes);
    final images = List<TextureHandle?>.filled(glb.images.length, null);
    for (var i = 0; i < glb.images.length; i++) {
      final img = glb.images[i];
      final imgBytes = _resolveGlbImageBytes(img, dir);
      if (imgBytes == null) continue;
      final decoded = tryDecodeVfsTextureBytes(
        imgBytes,
        path: img.uri ?? img.name,
        mimeType: img.mimeType,
      );
      if (decoded == null) continue;
      images[i] = recorder.registerTexture(
        width: decoded.width,
        height: decoded.height,
        pixels: decoded.rgbaPixels,
        debugLabel: img.name.isEmpty ? '$baseName/image_$i' : img.name,
      );
    }
    return ModelAsset.fromGlb(
      glb,
      recorder,
      name: baseName,
      images: images,
      materialOverride: materialOverride,
    );
  }

  Uint8List? _resolveGlbImageBytes(GlbImage img, String dir) {
    if (img.bytes.isNotEmpty) return img.bytes;
    final uri = img.uri;
    if (uri == null || uri.isEmpty) return null;
    if (uri.startsWith('data:')) {
      final comma = uri.indexOf(',');
      if (comma < 0) return null;
      final header = uri.substring(0, comma).toLowerCase();
      final payload = uri.substring(comma + 1);
      return header.contains(';base64')
          ? base64Decode(payload)
          : Uint8List.fromList(utf8.encode(Uri.decodeFull(payload)));
    }
    return _readRelativeBytes(dir, uri);
  }

  ModelAsset _decodeSingleQmeshModel(
    Uint8List bytes,
    _RecordingResourceLibrary recorder, {
    required String baseName,
    MaterialOverride? materialOverride,
  }) {
    final meshData = _decodeQmeshBytes(bytes);
    final root = SceneNode.group(name: baseName);
    final meshNode = SceneNode(name: baseName, meshData: meshData);
    root.addChild(meshNode);
    final glb = GlbResult(
      rootNode: root,
      meshes: [meshData],
      materials: [MaterialDefinition(key: '$baseName/default')],
      nodeMaterials: {meshNode: 0},
    );
    return ModelAsset.fromGlb(
      glb,
      recorder,
      name: baseName,
      materialOverride: materialOverride,
    );
  }

  ModelAsset _decodeModelPackageJson(
    Uint8List bytes,
    _RecordingResourceLibrary recorder, {
    required String normPath,
    required String dir,
    MaterialOverride? materialOverride,
  }) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Model package manifest "$normPath" must be JSON.');
    }
    final manifest = ModelPackageManifest.fromJson(decoded);
    final materials = manifest.materials.isEmpty
        ? [MaterialDefinition(key: '${manifest.assetId}/default')]
        : [for (final key in manifest.materials) MaterialDefinition(key: key)];

    final root = SceneNode.group(name: manifest.assetId);
    final meshes = <MeshData>[];
    final nodeMaterials = <SceneNode, int>{};

    for (final part in manifest.parts) {
      final relPath =
          part.lodFiles['LOD0'] ??
          (part.lodFiles.isEmpty ? null : part.lodFiles.values.first);
      if (relPath == null) {
        throw StateError(
          'Part "${part.id}" has no LOD payload in "$normPath".',
        );
      }
      final qmeshBytes = _readRelativeBytes(dir, relPath);
      if (qmeshBytes == null) {
        throw StateError(
          'Missing model package part payload "$relPath" in VFS for "$normPath".',
        );
      }
      final meshData = _decodeQmeshBytes(qmeshBytes);
      meshes.add(meshData);
      final child = SceneNode(name: part.id, meshData: meshData);
      root.addChild(child);
      nodeMaterials[child] = part.materialSlot.clamp(0, materials.length - 1);
    }

    final glb = GlbResult(
      rootNode: root,
      meshes: meshes,
      materials: materials,
      nodeMaterials: nodeMaterials,
    );
    return ModelAsset.fromGlb(
      glb,
      recorder,
      name: manifest.assetId,
      materialOverride: materialOverride,
    );
  }

  ModelAsset _decodeObjModel(
    Uint8List bytes,
    _RecordingResourceLibrary recorder, {
    required String baseName,
    required String dir,
    MaterialOverride? materialOverride,
  }) {
    final text = utf8.decode(bytes);
    final positions = <Vec3>[];
    final texCoords = <(double, double)>[];
    final normals = <Vec3>[];
    final materialsByName = <String, MaterialDefinition>{};
    final materialOrder = <MaterialDefinition>[];

    int ensureMaterial(String name) {
      final existing = materialsByName[name];
      if (existing != null) return materialOrder.indexOf(existing);
      final def = MaterialDefinition(key: name);
      materialsByName[name] = def;
      materialOrder.add(def);
      return materialOrder.length - 1;
    }

    var currentMaterialIdx = ensureMaterial('default');
    final verticesByMat = <int, List<double>>{};

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      switch (parts[0]) {
        case 'v' when parts.length >= 4:
          positions.add(
            Vec3(
              double.parse(parts[1]),
              double.parse(parts[2]),
              double.parse(parts[3]),
            ),
          );
        case 'vt' when parts.length >= 3:
          texCoords.add((double.parse(parts[1]), double.parse(parts[2])));
        case 'vn' when parts.length >= 4:
          normals.add(
            Vec3(
              double.parse(parts[1]),
              double.parse(parts[2]),
              double.parse(parts[3]),
            ),
          );
        case 'mtllib' when parts.length >= 2:
          final mtlBytes = _readRelativeBytes(dir, parts.sublist(1).join(' '));
          if (mtlBytes != null) {
            _parseMtlInto(
              utf8.decode(mtlBytes),
              materialsByName,
              materialOrder,
            );
          }
        case 'usemtl' when parts.length >= 2:
          currentMaterialIdx = ensureMaterial(parts.sublist(1).join(' '));
        case 'f' when parts.length >= 4:
          final faceTokens = parts.sublist(1);
          final out = verticesByMat.putIfAbsent(currentMaterialIdx, () => []);
          for (var i = 1; i + 1 < faceTokens.length; i++) {
            final tri = [faceTokens[0], faceTokens[i], faceTokens[i + 1]];
            _emitObjTriangle(tri, positions, texCoords, normals, out);
          }
      }
    }

    if (verticesByMat.isEmpty) {
      throw FormatException('OBJ model "$baseName" contains no faces.');
    }

    final root = SceneNode.group(name: baseName);
    final meshes = <MeshData>[];
    final nodeMaterials = <SceneNode, int>{};
    for (final entry in verticesByMat.entries) {
      final floats = Float32List.fromList(entry.value);
      final bounds = _computeBounds(floats, 14);
      final meshData = MeshData(
        layout: VertexLayoutDescriptor.compatibility14,
        vertices: floats,
        localBounds: bounds,
      );
      meshes.add(meshData);
      final node = SceneNode(
        name: '${baseName}_${materialOrder[entry.key].key}',
        meshData: meshData,
      );
      root.addChild(node);
      nodeMaterials[node] = entry.key;
    }

    final glb = GlbResult(
      rootNode: root,
      meshes: meshes,
      materials: materialOrder,
      nodeMaterials: nodeMaterials,
    );
    return ModelAsset.fromGlb(
      glb,
      recorder,
      name: baseName,
      materialOverride: materialOverride,
    );
  }

  static void _parseMtlInto(
    String mtlText,
    Map<String, MaterialDefinition> byName,
    List<MaterialDefinition> order,
  ) {
    String? currentName;
    var r = 1.0, g = 1.0, b = 1.0;

    void flush() {
      if (currentName == null) return;
      final def = MaterialDefinition(
        key: currentName,
        tintR: r,
        tintG: g,
        tintB: b,
      );
      if (!byName.containsKey(currentName)) {
        order.add(def);
      } else {
        final idx = order.indexOf(byName[currentName]!);
        if (idx >= 0) order[idx] = def;
      }
      byName[currentName] = def;
    }

    for (final raw in mtlText.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts[0] == 'newmtl' && parts.length >= 2) {
        flush();
        currentName = parts.sublist(1).join(' ');
        r = 1.0;
        g = 1.0;
        b = 1.0;
      } else if (parts[0] == 'Kd' && parts.length >= 4) {
        r = double.parse(parts[1]);
        g = double.parse(parts[2]);
        b = double.parse(parts[3]);
      }
    }
    flush();
  }

  static void _emitObjTriangle(
    List<String> tokens,
    List<Vec3> positions,
    List<(double, double)> texCoords,
    List<Vec3> normals,
    List<double> out,
  ) {
    int resolveIdx(String token, int length) {
      final raw = int.parse(token);
      return raw < 0 ? length + raw : raw - 1;
    }

    final pIdx = <int>[];
    final tIdx = <int?>[];
    final nIdx = <int?>[];
    for (final tok in tokens) {
      final segs = tok.split('/');
      pIdx.add(resolveIdx(segs[0], positions.length));
      tIdx.add(
        segs.length > 1 && segs[1].isNotEmpty
            ? resolveIdx(segs[1], texCoords.length)
            : null,
      );
      nIdx.add(
        segs.length > 2 && segs[2].isNotEmpty
            ? resolveIdx(segs[2], normals.length)
            : null,
      );
    }

    final p0 = positions[pIdx[0]];
    final p1 = positions[pIdx[1]];
    final p2 = positions[pIdx[2]];
    var faceNormal = (p1 - p0).cross(p2 - p0);
    final len = faceNormal.length;
    faceNormal = len > 1e-8 ? faceNormal * (1.0 / len) : const Vec3(0, 1, 0);

    for (var i = 0; i < 3; i++) {
      final pos = positions[pIdx[i]];
      final uv = tIdx[i] != null ? texCoords[tIdx[i]!] : (0.0, 0.0);
      var n = nIdx[i] != null ? normals[nIdx[i]!] : faceNormal;
      final nLen = n.length;
      if (nLen > 1e-8) {
        n = n * (1.0 / nLen);
      } else {
        n = faceNormal;
      }
      out
        ..add(pos.x)
        ..add(pos.y)
        ..add(pos.z)
        ..add(n.x)
        ..add(n.y)
        ..add(n.z)
        ..add(1.0)
        ..add(1.0)
        ..add(1.0)
        ..add(1.0)
        ..add(1.0)
        ..add(uv.$1)
        ..add(uv.$2)
        ..add(0.0);
    }
  }

  static Aabb _computeBounds(Float32List verts, int stride) {
    var minX = verts[0], minY = verts[1], minZ = verts[2];
    var maxX = minX, maxY = minY, maxZ = minZ;
    for (var i = stride; i < verts.length; i += stride) {
      final x = verts[i];
      final y = verts[i + 1];
      final z = verts[i + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    return Aabb(Vec3(minX, minY, minZ), Vec3(maxX, maxY, maxZ));
  }

  static MeshData _decodeQmeshBytes(Uint8List bytes) {
    final cache = ModelCache();
    final cached = cache.decodeAndCache(bytes);
    cache.release(cached);
    return cached.deduplicated;
  }

  Uint8List? _readRelativeBytes(String dir, String relativePath) {
    if (dir.isNotEmpty) {
      final joined = pack.VfsPath.normalize('$dir/$relativePath');
      final resolved = vfs.readBytes(joined);
      if (resolved != null) return resolved;
    }
    return vfs.readBytes(pack.VfsPath.normalize(relativePath));
  }

  static String _directoryOf(String normPath) {
    final slash = normPath.lastIndexOf('/');
    return slash <= 0 ? '' : normPath.substring(0, slash);
  }

  static String _baseNameWithoutExtension(String normPath) {
    final fileName = normPath.split('/').last;
    final dot = fileName.lastIndexOf('.');
    return dot <= 0 ? fileName : fileName.substring(0, dot);
  }
}

/// Automatically upgrades versioned JSON save slots using [pack.SaveMigrator] (E48-2).
final class MigratedSaveStore {
  final KeyValueStore storage;
  final pack.SaveMigrator migrator;

  MigratedSaveStore({required this.storage, required this.migrator});

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
