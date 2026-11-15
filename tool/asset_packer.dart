import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:pixeldart/assets/assets.dart';
import 'package:pixeldart/rendering/assets/qmesh.dart';

const List<int> _qlutMagic = [0x51, 0x4C, 0x55, 0x54]; // "QLUT"
const int _qlutVersion = 1;
const int _qlutHeaderBytes = 40;
const int _maxLutSize = 256;

const Set<String> _sourceAssetExtensions = {
  '.obj',
  '.mtl',
  '.fbx',
  '.gltf',
  '.glb',
  '.cube',
};

/// Parsed Adobe `.cube` 3D LUT representation prior to engine [LutAsset] loading.
final class CubeLutData {
  final String title;
  final int size;
  final List<double> domainMin;
  final List<double> domainMax;
  final Float32List rgbData;

  CubeLutData({
    required this.title,
    required this.size,
    required List<double> domainMin,
    required List<double> domainMax,
    required this.rgbData,
  }) : domainMin = List.unmodifiable(domainMin),
       domainMax = List.unmodifiable(domainMax);

  int get texelCount => size * size * size;

  /// Converts this parsed LUT into an engine [LutAsset] keyed by [key].
  LutAsset toLutAsset({required String key}) => LutAsset(
    key: key,
    size: size,
    rgbData: Float32List.fromList(rgbData),
    title: title,
  );

  Map<String, Object?> toMetadataJson({
    required String key,
    String? payloadSha256,
  }) => {
    'schema': 'volition-lut-v1',
    'key': key,
    'title': title,
    'size': size,
    'texelCount': texelCount,
    'domainMin': domainMin,
    'domainMax': domainMax,
    if (payloadSha256 != null) 'sha256': payloadSha256,
  };
}

/// Cooked OBJ -> QMSH model package output plus referenced texture sidecars.
final class CookedModelResult {
  final ModelPackageManifest manifest;
  final Map<String, Uint8List> payloads;
  final Map<String, Uint8List> sidecars;
  final List<AssetImportDiagnostic> diagnostics;

  const CookedModelResult({
    required this.manifest,
    required this.payloads,
    required this.sidecars,
    required this.diagnostics,
  });

  bool get isValid =>
      diagnostics.every((d) => d.severity != DiagnosticSeverity.error);
}

/// Single deterministic entry destined for (or decoded from) a `.pak` archive.
final class AssetPackEntry {
  final String virtualPath;
  final Uint8List bytes;
  final String kind;
  final String sha256;

  AssetPackEntry({
    required String virtualPath,
    required Uint8List bytes,
    required this.kind,
  }) : virtualPath = VfsPath.normalize(virtualPath),
       bytes = Uint8List.fromList(bytes),
       sha256 = Sha256.compute(bytes);
}

/// Summary report returned by [packAssetDirectory].
final class AssetPackReport {
  final bool dryRun;
  final String sourceDir;
  final String outputPakPath;
  final List<AssetPackEntry> entries;
  final List<String> cookedModels;
  final List<String> cookedLuts;
  final List<String> warnings;
  final String? sidecarManifestPath;
  final int? archiveSizeBytes;
  final String? archiveSha256;

  const AssetPackReport({
    required this.dryRun,
    required this.sourceDir,
    required this.outputPakPath,
    required this.entries,
    required this.cookedModels,
    required this.cookedLuts,
    this.warnings = const [],
    this.sidecarManifestPath,
    this.archiveSizeBytes,
    this.archiveSha256,
  });

  String formatSummary() {
    final buf = StringBuffer()
      ..writeln(
        dryRun
            ? 'Dry-run asset pack plan (${entries.length} entries)'
            : 'Packed ${entries.length} entries -> $outputPakPath',
      )
      ..writeln('  Source dir:    ${sourceDir.replaceAll('\\', '/')}')
      ..writeln('  Output .pak:   ${outputPakPath.replaceAll('\\', '/')}')
      ..writeln('  Cooked models: ${cookedModels.length}')
      ..writeln('  Cooked LUTs:   ${cookedLuts.length}');
    if (archiveSizeBytes != null) {
      buf.writeln('  Archive bytes: $archiveSizeBytes');
    }
    if (archiveSha256 != null) {
      buf.writeln('  Archive SHA:   $archiveSha256');
    }
    if (sidecarManifestPath != null) {
      buf.writeln(
        '  Sidecar JSON:  ${sidecarManifestPath!.replaceAll('\\', '/')}',
      );
    }
    for (final entry in entries) {
      buf.writeln(
        '  - [${entry.kind}] ${entry.virtualPath} (${entry.bytes.length} B)',
      );
    }
    for (final warning in warnings) {
      buf.writeln('  WARN: $warning');
    }
    return buf.toString().trimRight();
  }
}

/// Normalizes [raw] into a valid lowercase kebab-case package `assetId`.
String normalizeAssetId(String raw) {
  final lower = raw.trim().toLowerCase();
  final collapsed = lower
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return collapsed.isEmpty ? 'asset' : collapsed;
}

/// Parses an Adobe `.cube` 3D LUT text file into a validated [CubeLutData].
CubeLutData parseCubeLut(String source) {
  var text = source;
  if (text.startsWith('\uFEFF')) {
    text = text.substring(1);
  }

  String? title;
  int? size;
  List<double>? domainMin;
  List<double>? domainMax;
  final rgbValues = <double>[];
  var inData = false;
  var lineNo = 0;

  List<double> parseVec3(String keyword, List<String> fields) {
    if (fields.length != 4) {
      throw FormatException(
        'Line $lineNo: $keyword requires 3 float components',
      );
    }
    final result = <double>[];
    for (var i = 1; i <= 3; i++) {
      final value = double.tryParse(fields[i]);
      if (value == null || !value.isFinite) {
        throw FormatException(
          'Line $lineNo: $keyword has invalid float "${fields[i]}"',
        );
      }
      result.add(value);
    }
    return result;
  }

  for (final rawLine in text.split('\n')) {
    lineNo++;
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    if (trimmed == 'TITLE' || RegExp(r'^TITLE\s').hasMatch(trimmed)) {
      if (inData) {
        throw FormatException(
          'Line $lineNo: TITLE directive cannot appear after LUT data',
        );
      }
      final rest = trimmed.substring(5).trim();
      if (rest.isEmpty) {
        throw FormatException('Line $lineNo: TITLE requires a string value');
      }
      if (rest.startsWith('"')) {
        final closeQuote = rest.indexOf('"', 1);
        if (closeQuote < 0) {
          throw FormatException('Line $lineNo: unterminated TITLE quote');
        }
        final trailing = rest.substring(closeQuote + 1).trim();
        if (trailing.isNotEmpty && !trailing.startsWith('#')) {
          throw FormatException(
            'Line $lineNo: unexpected trailing tokens after TITLE',
          );
        }
        title = rest.substring(1, closeQuote);
      } else {
        final commentIdx = rest.indexOf('#');
        title = (commentIdx >= 0 ? rest.substring(0, commentIdx) : rest).trim();
      }
      continue;
    }

    final hashIdx = trimmed.indexOf('#');
    final cleanLine = (hashIdx >= 0 ? trimmed.substring(0, hashIdx) : trimmed)
        .trim();
    if (cleanLine.isEmpty) continue;

    final fields = cleanLine.split(RegExp(r'\s+'));
    final first = fields.first;

    switch (first) {
      case 'LUT_1D_SIZE':
        throw FormatException(
          'Line $lineNo: 1D .cube LUTs are not supported; expected LUT_3D_SIZE',
        );
      case 'LUT_3D_SIZE':
        if (inData) {
          throw FormatException(
            'Line $lineNo: LUT_3D_SIZE cannot appear after LUT data',
          );
        }
        if (size != null) {
          throw FormatException(
            'Line $lineNo: duplicate LUT_3D_SIZE directive',
          );
        }
        if (fields.length != 2) {
          throw FormatException(
            'Line $lineNo: LUT_3D_SIZE requires a single integer',
          );
        }
        final parsed = int.tryParse(fields[1]);
        if (parsed == null || parsed < 2 || parsed > _maxLutSize) {
          throw FormatException(
            'Line $lineNo: LUT_3D_SIZE must be an integer in [2, $_maxLutSize]',
          );
        }
        size = parsed;
      case 'DOMAIN_MIN':
        if (inData) {
          throw FormatException(
            'Line $lineNo: DOMAIN_MIN cannot appear after LUT data',
          );
        }
        if (domainMin != null) {
          throw FormatException('Line $lineNo: duplicate DOMAIN_MIN directive');
        }
        domainMin = parseVec3('DOMAIN_MIN', fields);
      case 'DOMAIN_MAX':
        if (inData) {
          throw FormatException(
            'Line $lineNo: DOMAIN_MAX cannot appear after LUT data',
          );
        }
        if (domainMax != null) {
          throw FormatException('Line $lineNo: duplicate DOMAIN_MAX directive');
        }
        domainMax = parseVec3('DOMAIN_MAX', fields);
      default:
        final maybeNum = double.tryParse(first);
        if (maybeNum == null) {
          throw FormatException(
            'Line $lineNo: unsupported .cube directive "$first"',
          );
        }
        if (size == null) {
          throw FormatException(
            'Line $lineNo: LUT data encountered before LUT_3D_SIZE',
          );
        }
        inData = true;
        if (fields.length != 3) {
          throw FormatException(
            'Line $lineNo: LUT entry must have 3 RGB components',
          );
        }
        for (final token in fields) {
          final v = double.tryParse(token);
          if (v == null || !v.isFinite) {
            throw FormatException(
              'Line $lineNo: LUT entry contains non-finite value "$token"',
            );
          }
          rgbValues.add(v);
        }
    }
  }

  if (size == null) {
    throw const FormatException('Missing required LUT_3D_SIZE directive');
  }
  final resolvedMin = domainMin ?? const [0.0, 0.0, 0.0];
  final resolvedMax = domainMax ?? const [1.0, 1.0, 1.0];
  for (var i = 0; i < 3; i++) {
    if (resolvedMin[i] >= resolvedMax[i]) {
      throw const FormatException(
        'DOMAIN_MIN must be strictly less than DOMAIN_MAX on every channel',
      );
    }
  }

  final expectedEntries = size * size * size;
  final actualEntries = rgbValues.length ~/ 3;
  if (actualEntries != expectedEntries) {
    throw FormatException(
      'Expected $expectedEntries RGB triplets for LUT_3D_SIZE $size, '
      'found $actualEntries',
    );
  }

  return CubeLutData(
    title: title ?? '',
    size: size,
    domainMin: resolvedMin,
    domainMax: resolvedMax,
    rgbData: Float32List.fromList(rgbValues),
  );
}

/// Serializes [lut] into deterministic `.qlut` binary bytes.
Uint8List encodePackedLut(CubeLutData lut) {
  if (lut.size < 2 || lut.size > _maxLutSize) {
    throw FormatException('LUT size must be in [2, $_maxLutSize]: ${lut.size}');
  }
  if (lut.domainMin.length != 3 ||
      lut.domainMax.length != 3 ||
      lut.domainMin.any((v) => !v.isFinite) ||
      lut.domainMax.any((v) => !v.isFinite)) {
    throw const FormatException(
      'LUT domain bounds must contain 3 finite values',
    );
  }
  for (var i = 0; i < 3; i++) {
    if (lut.domainMin[i] >= lut.domainMax[i]) {
      throw const FormatException(
        'LUT domainMin must be strictly less than domainMax',
      );
    }
  }
  final expectedFloats = lut.size * lut.size * lut.size * 3;
  if (lut.rgbData.length != expectedFloats) {
    throw FormatException(
      'LUT rgbData length ${lut.rgbData.length} != expected $expectedFloats',
    );
  }
  for (var i = 0; i < lut.rgbData.length; i++) {
    if (!lut.rgbData[i].isFinite) {
      throw FormatException('LUT rgbData[$i] is not finite');
    }
  }

  final titleBytes = utf8.encode(lut.title);
  final totalBytes = _qlutHeaderBytes + titleBytes.length + expectedFloats * 4;
  final out = Uint8List(totalBytes);
  final view = ByteData.sublistView(out);

  out.setAll(0, _qlutMagic);
  view.setUint16(4, _qlutVersion, Endian.little);
  view.setUint16(6, 0, Endian.little);
  view.setUint32(8, lut.size, Endian.little);
  for (var i = 0; i < 3; i++) {
    view.setFloat32(12 + i * 4, lut.domainMin[i], Endian.little);
    view.setFloat32(24 + i * 4, lut.domainMax[i], Endian.little);
  }
  view.setUint32(36, titleBytes.length, Endian.little);
  out.setRange(
    _qlutHeaderBytes,
    _qlutHeaderBytes + titleBytes.length,
    titleBytes,
  );

  var offset = _qlutHeaderBytes + titleBytes.length;
  for (var i = 0; i < lut.rgbData.length; i++) {
    view.setFloat32(offset, lut.rgbData[i], Endian.little);
    offset += 4;
  }
  return out;
}

/// Serializes an engine [LutAsset] directly into `.qlut` packed binary bytes.
Uint8List encodeLutAsset(
  LutAsset asset, {
  List<double> domainMin = const [0.0, 0.0, 0.0],
  List<double> domainMax = const [1.0, 1.0, 1.0],
}) => encodePackedLut(
  CubeLutData(
    title: asset.title,
    size: asset.size,
    domainMin: domainMin,
    domainMax: domainMax,
    rgbData: asset.rgbData,
  ),
);

/// Decodes deterministic `.qlut` binary bytes into a validated [CubeLutData].
CubeLutData decodePackedLut(Uint8List bytes) {
  if (bytes.length < _qlutHeaderBytes) {
    throw FormatException(
      'QLUT payload truncated (${bytes.length} < $_qlutHeaderBytes bytes)',
    );
  }
  for (var i = 0; i < 4; i++) {
    if (bytes[i] != _qlutMagic[i]) {
      throw const FormatException('Invalid QLUT magic header');
    }
  }
  final view = ByteData.sublistView(bytes);
  final version = view.getUint16(4, Endian.little);
  if (version != _qlutVersion) {
    throw FormatException('Unsupported QLUT version: $version');
  }
  final flags = view.getUint16(6, Endian.little);
  if (flags != 0) {
    throw FormatException('Unsupported QLUT flags: $flags');
  }
  final size = view.getUint32(8, Endian.little);
  if (size < 2 || size > _maxLutSize) {
    throw FormatException('Invalid QLUT size: $size');
  }
  final domainMin = <double>[
    for (var i = 0; i < 3; i++) view.getFloat32(12 + i * 4, Endian.little),
  ];
  final domainMax = <double>[
    for (var i = 0; i < 3; i++) view.getFloat32(24 + i * 4, Endian.little),
  ];
  for (var i = 0; i < 3; i++) {
    if (!domainMin[i].isFinite ||
        !domainMax[i].isFinite ||
        domainMin[i] >= domainMax[i]) {
      throw const FormatException('Invalid QLUT domain bounds');
    }
  }
  final titleLen = view.getUint32(36, Endian.little);
  final floatCount = size * size * size * 3;
  final expectedBytes = _qlutHeaderBytes + titleLen + floatCount * 4;
  if (titleLen > bytes.length - _qlutHeaderBytes ||
      bytes.length != expectedBytes) {
    throw FormatException(
      'QLUT byte length mismatch: expected $expectedBytes, got ${bytes.length}',
    );
  }
  final title = utf8.decode(
    Uint8List.sublistView(bytes, _qlutHeaderBytes, _qlutHeaderBytes + titleLen),
    allowMalformed: false,
  );
  final rgbData = Float32List(floatCount);
  var offset = _qlutHeaderBytes + titleLen;
  for (var i = 0; i < floatCount; i++) {
    final value = view.getFloat32(offset, Endian.little);
    if (!value.isFinite) {
      throw FormatException('QLUT contains non-finite float at index $i');
    }
    rgbData[i] = value;
    offset += 4;
  }

  return CubeLutData(
    title: title,
    size: size,
    domainMin: domainMin,
    domainMax: domainMax,
    rgbData: rgbData,
  );
}

/// Loads either packed `.qlut` binary or `.cube` UTF-8 text into [LutAsset].
LutAsset loadPackedLutAsset(Uint8List bytes, {required String key}) {
  if (_hasQlutMagic(bytes)) {
    return decodePackedLut(bytes).toLutAsset(key: key);
  }
  final text = utf8.decode(bytes, allowMalformed: false);
  return parseCubeLut(text).toLutAsset(key: key);
}

/// Reads and verifies a packed `.qlut` or `.cube` entry from [archive] into [LutAsset].
LutAsset loadLutAssetFromPak(
  PakArchive archive,
  String virtualPath, {
  String? key,
  bool verifyChecksum = true,
}) {
  final normPath = VfsPath.normalize(virtualPath);
  final bytes = archive.readBytes(normPath, verifyChecksum: verifyChecksum);
  if (bytes == null) {
    throw StateError('LUT entry not found in archive: "$normPath"');
  }
  return loadPackedLutAsset(bytes, key: key ?? normPath);
}

/// Loads a packed LUT asset asynchronously via [VfsAssetLoader].
Future<LutAsset> loadLutAssetFromVfs(
  VfsAssetLoader loader,
  String virtualPath, {
  String? key,
}) async {
  final bytes = await loader.loadBytes(virtualPath);
  return loadPackedLutAsset(bytes, key: key ?? VfsPath.normalize(virtualPath));
}

bool _hasQlutMagic(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == _qlutMagic[0] &&
    bytes[1] == _qlutMagic[1] &&
    bytes[2] == _qlutMagic[2] &&
    bytes[3] == _qlutMagic[3];

/// Cooks in-memory OBJ (+ optional MTL + optional texture sidecars) into a
/// validated QMSH model package.
Future<CookedModelResult> cookObjSource({
  required String assetId,
  required String objSource,
  String? mtlSource,
  Map<String, Uint8List> availableSidecars = const {},
  bool validateAvailableSidecars = false,
  String? licenseId,
  Map<String, String> extraProvenance = const {},
}) async {
  final scene = parseObj(objSource);
  final sidecarSet = validateAvailableSidecars || availableSidecars.isNotEmpty
      ? availableSidecars.keys.toSet()
      : null;
  final materials = mtlSource == null
      ? const <String, ObjMaterialRecord>{}
      : parseMtl(mtlSource, availableFiles: sidecarSet);

  final hashInput = <int>[
    ...utf8.encode(objSource),
    if (mtlSource != null) ...[0, ...utf8.encode(mtlSource)],
  ];
  final sourceHash = Sha256.compute(hashInput);

  final provenance = <String, String>{
    'sourceHash': sourceHash,
    'runtimeProfile': 'runtime',
    if (licenseId != null && licenseId.isNotEmpty) 'licenseId': licenseId,
    ...extraProvenance,
  };

  final emitted = ObjModelPackageEmitter.emit(
    assetId: assetId,
    scene: scene,
    materials: materials,
    provenance: provenance,
  );

  final diagnostics = <AssetImportDiagnostic>[
    ...validateModelPackageManifest(emitted.manifest),
    ...validateModelPackagePayloads(
      emitted.manifest,
      emitted.payloads,
      verifyQmesh: true,
      verifyPackageHash: true,
      verifyBounds: true,
      availableSidecars: sidecarSet,
    ),
  ];

  if (diagnostics.any((d) => d.severity == DiagnosticSeverity.error)) {
    throw FormatException(diagnostics.map((d) => d.message).join('; '));
  }

  // Exercise the runtime ModelPackageLoader with strict QMSH verification.
  await const ModelPackageLoader().load(
    ModelPackageSource(
      manifest: emitted.manifest,
      load: (path) async => emitted.payloads[path]!,
    ),
    limits: const ModelPackageLimits(requireQmeshPayloads: true),
  );

  final collectedSidecars = <String, Uint8List>{};
  for (final texturePath in emitted.manifest.textures) {
    final bytes = availableSidecars[texturePath];
    if (bytes != null) {
      collectedSidecars[texturePath] = Uint8List.fromList(bytes);
    }
  }

  return CookedModelResult(
    manifest: emitted.manifest,
    payloads: emitted.payloads,
    sidecars: collectedSidecars,
    diagnostics: diagnostics,
  );
}

/// Cooks an on-disk `.obj` file (resolving `mtllib` and texture sidecars) to
/// a QMSH model package directory.
Future<CookedModelResult> cookObjFileToDirectory({
  required File objFile,
  required Directory outputDir,
  File? mtlFile,
  String? assetId,
  String? licenseId,
  bool writeSidecarChecksums = true,
}) async {
  if (!objFile.existsSync()) {
    throw FileSystemException('OBJ input file not found', objFile.path);
  }
  final resolvedAssetId = normalizeAssetId(
    assetId ?? _stemOf(objFile.uri.pathSegments.last),
  );
  final objSource = await objFile.readAsString();
  final parsedPreview = parseObj(objSource);

  final mtlFiles = <File>[];
  if (mtlFile != null) {
    if (!mtlFile.existsSync()) {
      throw FileSystemException('MTL file not found', mtlFile.path);
    }
    mtlFiles.add(mtlFile);
  } else {
    for (final relMtl in parsedPreview.mtlLibraries) {
      final candidate = _resolveSafeChildFile(objFile.parent, relMtl);
      if (!candidate.existsSync()) {
        throw FormatException(
          'OBJ references missing MTL sidecar: $relMtl (expected at ${candidate.path})',
        );
      }
      mtlFiles.add(candidate);
    }
  }

  String? combinedMtlSource;
  final availableSidecars = <String, Uint8List>{};
  if (mtlFiles.isNotEmpty) {
    final mtlBuf = StringBuffer();
    for (final file in mtlFiles) {
      final text = await file.readAsString();
      mtlBuf.writeln(text);
      // Pre-parse without file availability to discover referenced texture paths.
      final parsedMtl = parseMtl(text);
      for (final record in parsedMtl.values) {
        for (final tex in [record.diffuseTexture, record.normalTexture]) {
          if (tex == null) continue;
          final resolved =
              _tryResolveTextureFile(file.parent, tex) ??
              _tryResolveTextureFile(objFile.parent, tex);
          if (resolved == null) {
            throw FormatException(
              'MTL texture sidecar is missing: $tex (referenced from ${file.path})',
            );
          }
          availableSidecars[tex] = await resolved.readAsBytes();
        }
      }
    }
    combinedMtlSource = mtlBuf.toString();
  }

  final cooked = await cookObjSource(
    assetId: resolvedAssetId,
    objSource: objSource,
    mtlSource: combinedMtlSource,
    availableSidecars: availableSidecars,
    validateAvailableSidecars: true,
    licenseId: licenseId,
  );

  await outputDir.create(recursive: true);
  final manifestJson = const JsonEncoder.withIndent(
    '  ',
  ).convert(cooked.manifest.toJson());
  final manifestBytes = Uint8List.fromList(utf8.encode('$manifestJson\n'));
  await _writeRelativeFile(outputDir, 'manifest.json', manifestBytes);

  for (final entry in cooked.payloads.entries) {
    await _writeRelativeFile(outputDir, entry.key, entry.value);
  }
  for (final entry in cooked.sidecars.entries) {
    await _writeRelativeFile(outputDir, entry.key, entry.value);
  }

  if (writeSidecarChecksums) {
    final checksumFiles = <String, Map<String, Object?>>{
      'manifest.json': {
        'byteLength': manifestBytes.length,
        'sha256': Sha256.compute(manifestBytes),
      },
      for (final entry in cooked.payloads.entries)
        entry.key: {
          'byteLength': entry.value.length,
          'sha256': Sha256.compute(entry.value),
        },
      for (final entry in cooked.sidecars.entries)
        entry.key: {
          'byteLength': entry.value.length,
          'sha256': Sha256.compute(entry.value),
        },
    };
    final sidecarDoc = {
      'schema': 'volition-model-sidecars-v1',
      'assetId': cooked.manifest.assetId,
      'packageHash': cooked.manifest.packageHash,
      'files': checksumFiles,
    };
    await _writeRelativeFile(
      outputDir,
      'sidecars.sha256.json',
      Uint8List.fromList(
        utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert(sidecarDoc)}\n',
        ),
      ),
    );
  }

  return cooked;
}

/// Validates an emitted QMSH model package directory (manifest, QMSH payloads,
/// bounds, packageHash, texture sidecars, and optional checksum manifest).
List<AssetImportDiagnostic> validateModelPackageDirectory(
  Directory packageDir,
) {
  final diagnostics = <AssetImportDiagnostic>[];
  void error(String code, String message, {String? relativePath}) {
    diagnostics.add(
      AssetImportDiagnostic(
        code: code,
        severity: DiagnosticSeverity.error,
        stage: 'sidecar-validation',
        relativePath: relativePath,
        message: message,
        remediation: 're-cook the model package and verify all sidecar files',
      ),
    );
  }

  if (!packageDir.existsSync()) {
    error(
      'PACKAGE_DIR_MISSING',
      'package directory does not exist: ${packageDir.path}',
    );
    return diagnostics;
  }

  final manifestFile = File(
    '${packageDir.path}${Platform.pathSeparator}manifest.json',
  );
  if (!manifestFile.existsSync()) {
    error(
      'PACKAGE_MANIFEST_MISSING',
      'manifest.json is missing',
      relativePath: 'manifest.json',
    );
    return diagnostics;
  }

  late final ModelPackageManifest manifest;
  try {
    final decoded = jsonDecode(manifestFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      error(
        'PACKAGE_MANIFEST_MALFORMED',
        'manifest.json root must be an object',
        relativePath: 'manifest.json',
      );
      return diagnostics;
    }
    manifest = ModelPackageManifest.fromJson(decoded);
  } catch (e) {
    error(
      'PACKAGE_MANIFEST_MALFORMED',
      'failed to parse manifest.json: $e',
      relativePath: 'manifest.json',
    );
    return diagnostics;
  }

  diagnostics.addAll(validateModelPackageManifest(manifest));

  final rootFiles = _collectRelativeFiles(packageDir);
  for (final relPath in rootFiles.keys) {
    final lower = relPath.toLowerCase();
    if (_sourceAssetExtensions.any(lower.endsWith)) {
      error(
        'MODEL_PACKAGE_SOURCE_LEAK',
        'source asset file leaked into cooked package directory: $relPath',
        relativePath: relPath,
      );
    }
  }

  final payloads = <String, Uint8List>{};
  for (final part in manifest.parts) {
    for (final path in part.lodFiles.values) {
      if (!_isSafeRelPath(path)) continue;
      final file = rootFiles[path];
      if (file != null) {
        payloads[path] = file.readAsBytesSync();
      }
    }
  }

  diagnostics.addAll(
    validateModelPackagePayloads(
      manifest,
      payloads,
      verifyQmesh: true,
      verifyPackageHash: true,
      verifyBounds: true,
      availableSidecars: rootFiles.keys.toSet(),
    ),
  );

  final sidecarFile = File(
    '${packageDir.path}${Platform.pathSeparator}sidecars.sha256.json',
  );
  if (sidecarFile.existsSync()) {
    try {
      final decoded = jsonDecode(sidecarFile.readAsStringSync());
      if (decoded is! Map || decoded['files'] is! Map) {
        error(
          'SIDECAR_MANIFEST_MALFORMED',
          'sidecars.sha256.json is malformed',
          relativePath: 'sidecars.sha256.json',
        );
      } else {
        if (decoded['packageHash'] != manifest.packageHash) {
          error(
            'SIDECAR_PACKAGE_HASH_MISMATCH',
            'sidecars.sha256.json packageHash disagrees with manifest.json',
            relativePath: 'sidecars.sha256.json',
          );
        }
        final files = decoded['files'] as Map;
        for (final entry in files.entries) {
          final rel = entry.key.toString();
          final meta = entry.value;
          if (!_isSafeRelPath(rel) || meta is! Map) {
            error(
              'SIDECAR_ENTRY_INVALID',
              'invalid sidecar entry: $rel',
              relativePath: rel,
            );
            continue;
          }
          final diskFile = rootFiles[rel];
          if (diskFile == null) {
            error(
              'SIDECAR_FILE_MISSING',
              'checksum sidecar references missing file: $rel',
              relativePath: rel,
            );
            continue;
          }
          final diskBytes = diskFile.readAsBytesSync();
          if (meta['byteLength'] != diskBytes.length) {
            error(
              'SIDECAR_LENGTH_MISMATCH',
              'byteLength mismatch for $rel: expected ${meta['byteLength']}, got ${diskBytes.length}',
              relativePath: rel,
            );
          }
          if (meta['sha256'] != Sha256.compute(diskBytes)) {
            error(
              'SIDECAR_CHECKSUM_MISMATCH',
              'SHA-256 mismatch for $rel',
              relativePath: rel,
            );
          }
        }
      }
    } catch (e) {
      error(
        'SIDECAR_MANIFEST_MALFORMED',
        'failed to parse sidecars.sha256.json: $e',
        relativePath: 'sidecars.sha256.json',
      );
    }
  }

  return diagnostics;
}

/// Validates a list of [AssetPackEntry] items (path safety, no duplicate paths,
/// no source leaks, valid `.qmesh` / `.qlut` / `manifest.json` model packages).
List<AssetImportDiagnostic> validatePackEntries(
  List<AssetPackEntry> entries, {
  bool allowSourceFiles = false,
}) {
  final diagnostics = <AssetImportDiagnostic>[];
  void error(String code, String message, {String? relativePath}) {
    diagnostics.add(
      AssetImportDiagnostic(
        code: code,
        severity: DiagnosticSeverity.error,
        stage: 'pack-validation',
        relativePath: relativePath,
        message: message,
        remediation: 'fix or re-cook the offending entry before packing',
      ),
    );
  }

  final seen = <String>{};
  final byPath = <String, AssetPackEntry>{};
  for (final entry in entries) {
    if (!_isSafeRelPath(entry.virtualPath)) {
      error(
        'PACK_UNSAFE_PATH',
        'unsafe virtual path: "${entry.virtualPath}"',
        relativePath: entry.virtualPath,
      );
      continue;
    }
    if (!seen.add(entry.virtualPath)) {
      error(
        'PACK_DUPLICATE_PATH',
        'duplicate virtual path: "${entry.virtualPath}"',
        relativePath: entry.virtualPath,
      );
      continue;
    }
    byPath[entry.virtualPath] = entry;
    final lower = entry.virtualPath.toLowerCase();
    if (!allowSourceFiles && _sourceAssetExtensions.any(lower.endsWith)) {
      error(
        'PACK_SOURCE_LEAK',
        'un-cooked source asset cannot enter .pak: ${entry.virtualPath}',
        relativePath: entry.virtualPath,
      );
    }
    if (lower.endsWith('.qmesh')) {
      try {
        decodeQmesh(entry.bytes);
      } on QmeshDecodeException catch (e) {
        error(
          'PACK_INVALID_QMESH',
          'invalid QMSH payload ${entry.virtualPath}: ${e.reason.name} (${e.detail})',
          relativePath: entry.virtualPath,
        );
      }
    } else if (lower.endsWith('.qlut')) {
      try {
        decodePackedLut(entry.bytes);
      } on FormatException catch (e) {
        error(
          'PACK_INVALID_QLUT',
          'invalid QLUT payload ${entry.virtualPath}: ${e.message}',
          relativePath: entry.virtualPath,
        );
      }
    }
  }

  // Validate any model package manifest.json entries against sibling payloads/sidecars.
  for (final entry in entries) {
    if (entry.virtualPath != 'manifest.json' &&
        !entry.virtualPath.endsWith('/manifest.json')) {
      continue;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(entry.bytes));
    } catch (_) {
      continue;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != 'pixeldart-model-package-v1') {
      continue;
    }
    late final ModelPackageManifest manifest;
    try {
      manifest = ModelPackageManifest.fromJson(decoded);
    } catch (e) {
      error(
        'PACK_INVALID_MODEL_MANIFEST',
        'malformed model manifest at ${entry.virtualPath}: $e',
        relativePath: entry.virtualPath,
      );
      continue;
    }
    final dirPrefix = entry.virtualPath == 'manifest.json'
        ? ''
        : entry.virtualPath.substring(
            0,
            entry.virtualPath.length - 'manifest.json'.length,
          );
    final siblingFiles = <String>{};
    final siblingPayloads = <String, Uint8List>{};
    final declaredPayloads = <String>{
      for (final part in manifest.parts) ...part.lodFiles.values,
    };
    for (final other in byPath.entries) {
      if (other.key.startsWith(dirPrefix) && other.key != entry.virtualPath) {
        final rel = other.key.substring(dirPrefix.length);
        siblingFiles.add(rel);
        if (declaredPayloads.contains(rel)) {
          siblingPayloads[rel] = other.value.bytes;
        }
      }
    }
    diagnostics.addAll(validateModelPackageManifest(manifest));
    diagnostics.addAll(
      validateModelPackagePayloads(
        manifest,
        siblingPayloads,
        verifyQmesh: true,
        verifyPackageHash: true,
        verifyBounds: true,
        availableSidecars: siblingFiles,
      ),
    );
  }

  return diagnostics;
}

/// Builds a deterministic `.pak` binary archive sorted by [AssetPackEntry.virtualPath].
Uint8List buildDeterministicPak(
  List<AssetPackEntry> entries, {
  bool compress = true,
  int? xorKey,
  bool validate = true,
}) {
  if (validate) {
    final diags = validatePackEntries(entries);
    if (diags.any((d) => d.severity == DiagnosticSeverity.error)) {
      throw FormatException(diags.map((d) => d.message).join('; '));
    }
  }
  final sorted = List<AssetPackEntry>.of(entries)
    ..sort((a, b) => a.virtualPath.compareTo(b.virtualPath));
  final builder = PakBuilder();
  for (final entry in sorted) {
    builder.addBytes(
      entry.virtualPath,
      entry.bytes,
      compress: compress,
      xorKey: xorKey,
    );
  }
  final pakBytes = builder.build();
  if (validate) {
    final verifyDiags = verifyPakArchiveBytes(pakBytes, xorKey: xorKey);
    if (verifyDiags.any((d) => d.severity == DiagnosticSeverity.error)) {
      throw FormatException(verifyDiags.map((d) => d.message).join('; '));
    }
  }
  return pakBytes;
}

/// Parses and thoroughly verifies a `.pak` archive buffer (TOC CRC32, entry
/// CRC32s, raw lengths, QMSH/QLUT/model-package validation, and optional sidecar
/// manifest entries).
List<AssetImportDiagnostic> verifyPakArchiveBytes(
  Uint8List pakBytes, {
  int? xorKey,
  Map<String, dynamic>? sidecarManifest,
}) {
  final diagnostics = <AssetImportDiagnostic>[];
  void error(String code, String message, {String? relativePath}) {
    diagnostics.add(
      AssetImportDiagnostic(
        code: code,
        severity: DiagnosticSeverity.error,
        stage: 'pak-verify',
        relativePath: relativePath,
        message: message,
        remediation: 'rebuild the .pak archive cleanly',
      ),
    );
  }

  late final PakArchive archive;
  try {
    archive = PakArchive.parse(
      pakBytes,
      xorKey: xorKey,
      verifyTocChecksum: true,
    );
  } catch (e) {
    error('PAK_PARSE_FAILED', 'failed to parse .pak archive: $e');
    return diagnostics;
  }

  final decodedEntries = <AssetPackEntry>[];
  final byPath = <String, AssetPackEntry>{};
  for (final info in archive.entries) {
    try {
      final bytes = archive.readBytes(info.path, verifyChecksum: true);
      if (bytes == null) {
        error(
          'PAK_ENTRY_MISSING',
          'entry unreadable: ${info.path}',
          relativePath: info.path,
        );
        continue;
      }
      if (bytes.length != info.rawSize) {
        error(
          'PAK_SIZE_MISMATCH',
          'entry ${info.path} raw size ${bytes.length} != header ${info.rawSize}',
          relativePath: info.path,
        );
      }
      final entry = AssetPackEntry(
        virtualPath: info.path,
        bytes: bytes,
        kind: _classifyPath(info.path),
      );
      decodedEntries.add(entry);
      byPath[entry.virtualPath] = entry;
    } catch (e) {
      error(
        'PAK_ENTRY_CORRUPT',
        'entry ${info.path} failed verification: $e',
        relativePath: info.path,
      );
    }
  }

  diagnostics.addAll(validatePackEntries(decodedEntries));

  if (sidecarManifest != null) {
    final expectedSha = sidecarManifest['archiveSha256'];
    if (expectedSha != null && expectedSha != Sha256.compute(pakBytes)) {
      error(
        'PAK_ARCHIVE_SHA_MISMATCH',
        'archive SHA-256 does not match sidecar manifest',
      );
    }
    final expectedBytes = sidecarManifest['archiveBytes'];
    if (expectedBytes != null && expectedBytes != pakBytes.length) {
      error(
        'PAK_ARCHIVE_SIZE_MISMATCH',
        'archive byte size does not match sidecar manifest',
      );
    }
    final entriesRaw = sidecarManifest['entries'];
    if (entriesRaw is! List) {
      error('PAK_SIDECAR_MALFORMED', 'sidecar manifest entries must be a list');
    } else {
      if (sidecarManifest['entryCount'] != null &&
          sidecarManifest['entryCount'] != decodedEntries.length) {
        error(
          'PAK_SIDECAR_COUNT_MISMATCH',
          'archive entry count ${decodedEntries.length} != sidecar entryCount ${sidecarManifest['entryCount']}',
        );
      }
      final declaredPaths = <String>{};
      for (final item in entriesRaw) {
        if (item is! Map || item['path'] is! String) {
          error('PAK_SIDECAR_MALFORMED', 'sidecar entry missing path');
          continue;
        }
        final path = VfsPath.normalize(item['path'] as String);
        declaredPaths.add(path);
        final entry = byPath[path];
        if (entry == null) {
          error(
            'PAK_SIDECAR_ENTRY_MISSING',
            'sidecar manifest entry missing from .pak: $path',
            relativePath: path,
          );
          continue;
        }
        if (item['byteLength'] != null &&
            item['byteLength'] != entry.bytes.length) {
          error(
            'PAK_SIDECAR_LENGTH_MISMATCH',
            'byteLength mismatch for $path',
            relativePath: path,
          );
        }
        if (item['sha256'] != null && item['sha256'] != entry.sha256) {
          error(
            'PAK_SIDECAR_SHA_MISMATCH',
            'sha256 mismatch for $path',
            relativePath: path,
          );
        }
      }
      for (final path in byPath.keys) {
        if (!declaredPaths.contains(path)) {
          error(
            'PAK_SIDECAR_UNDECLARED_ENTRY',
            'archive entry $path is not declared in sidecar manifest',
            relativePath: path,
          );
        }
      }
    }
  }

  return diagnostics;
}

/// Cooks `.obj` models and `.cube` LUTs under [sourceDir] and packs all
/// validated runtime assets into a deterministic `.pak` at [outputPak].
Future<AssetPackReport> packAssetDirectory({
  required Directory sourceDir,
  required File outputPak,
  Directory? cookDir,
  String prefix = '',
  bool compress = true,
  int? xorKey,
  File? sidecarManifestOut,
  bool dryRun = false,
}) async {
  if (!sourceDir.existsSync()) {
    throw FileSystemException(
      'Source asset directory not found',
      sourceDir.path,
    );
  }
  final normPrefix = VfsPath.normalize(prefix);
  String withPrefix(String relPath) =>
      normPrefix.isEmpty ? relPath : '$normPrefix/$relPath';

  final excludedAbsPaths = <String>{
    _normAbs(outputPak.absolute.path),
    if (sidecarManifestOut != null) _normAbs(sidecarManifestOut.absolute.path),
  };
  final excludedDirPrefix = cookDir == null
      ? null
      : '${_normAbs(cookDir.absolute.path)}/';
  final diskFiles = _collectRelativeFiles(sourceDir)
    ..removeWhere((_, file) {
      final abs = _normAbs(file.absolute.path);
      if (excludedAbsPaths.contains(abs)) return true;
      if (excludedDirPrefix != null && abs.startsWith(excludedDirPrefix)) {
        return true;
      }
      return false;
    });
  final sortedPaths = diskFiles.keys.toList()..sort();

  final entriesByPath = <String, AssetPackEntry>{};
  final cookedModels = <String>[];
  final cookedLuts = <String>[];
  final warnings = <String>[];

  // Track already-processed directories (pre-cooked model packages) and files.
  final consumedFiles = <String>{};

  void addEntry(String virtualPath, Uint8List bytes, String kind) {
    final full = withPrefix(VfsPath.normalize(virtualPath));
    entriesByPath[full] = AssetPackEntry(
      virtualPath: full,
      bytes: bytes,
      kind: kind,
    );
  }

  // 1. Detect pre-cooked model package directories containing manifest.json.
  for (final relPath in sortedPaths) {
    if (relPath != 'manifest.json' && !relPath.endsWith('/manifest.json')) {
      continue;
    }
    final file = diskFiles[relPath]!;
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } catch (_) {
      continue;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != 'pixeldart-model-package-v1') {
      continue;
    }
    final pkgDir = file.parent;
    final diags = validateModelPackageDirectory(pkgDir);
    if (diags.any((d) => d.severity == DiagnosticSeverity.error)) {
      throw FormatException(
        'Pre-cooked model package at $relPath failed validation: '
        '${diags.map((d) => d.message).join('; ')}',
      );
    }
    final dirRelPrefix = relPath == 'manifest.json'
        ? ''
        : relPath.substring(0, relPath.length - 'manifest.json'.length);
    for (final candidate in sortedPaths) {
      if (candidate.startsWith(dirRelPrefix)) {
        consumedFiles.add(candidate);
        addEntry(
          candidate,
          diskFiles[candidate]!.readAsBytesSync(),
          _classifyPath(candidate),
        );
      }
    }
    cookedModels.add(relPath);
  }

  // 2. Cook .obj models -> QMSH model packages.
  for (final relPath in sortedPaths) {
    if (consumedFiles.contains(relPath) ||
        !relPath.toLowerCase().endsWith('.obj')) {
      continue;
    }
    final objFile = diskFiles[relPath]!;
    final objDirRel = _parentDirOf(relPath);
    final stem = _stemOf(relPath.split('/').last);
    final packageBaseRel = objDirRel.isEmpty ? stem : '$objDirRel/$stem';

    final tempCookDir = await Directory.systemTemp.createTemp('volition_cook_');
    try {
      final cooked = await cookObjFileToDirectory(
        objFile: objFile,
        outputDir: tempCookDir,
        assetId: normalizeAssetId(stem),
        writeSidecarChecksums: false,
      );
      final manifestJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(cooked.manifest.toJson());
      final manifestBytes = Uint8List.fromList(utf8.encode('$manifestJson\n'));
      addEntry(
        '$packageBaseRel/manifest.json',
        manifestBytes,
        'model-manifest',
      );
      for (final p in cooked.payloads.entries) {
        addEntry('$packageBaseRel/${p.key}', p.value, 'qmesh');
      }
      for (final s in cooked.sidecars.entries) {
        addEntry('$packageBaseRel/${s.key}', s.value, 'texture');
      }
      cookedModels.add(relPath);
      consumedFiles.add(relPath);

      // Mark referenced .mtl sidecars as consumed so raw .mtl doesn't leak.
      final objScene = parseObj(objFile.readAsStringSync());
      for (final mtlRel in objScene.mtlLibraries) {
        final fullMtlRel = VfsPath.normalize(
          objDirRel.isEmpty ? mtlRel : '$objDirRel/$mtlRel',
        );
        consumedFiles.add(fullMtlRel);
      }
    } finally {
      if (tempCookDir.existsSync()) {
        tempCookDir.deleteSync(recursive: true);
      }
    }
  }

  // 3. Cook .cube 3D LUTs -> .qlut binary assets.
  for (final relPath in sortedPaths) {
    if (consumedFiles.contains(relPath) ||
        !relPath.toLowerCase().endsWith('.cube')) {
      continue;
    }
    final cubeFile = diskFiles[relPath]!;
    final lut = parseCubeLut(cubeFile.readAsStringSync());
    final qlutBytes = encodePackedLut(lut);
    final qlutRel = '${relPath.substring(0, relPath.length - 5)}.qlut';
    // Verify round-trip decoding into LutAsset before packing.
    loadPackedLutAsset(qlutBytes, key: withPrefix(qlutRel));
    addEntry(qlutRel, qlutBytes, 'lut');
    cookedLuts.add(relPath);
    consumedFiles.add(relPath);
  }

  // 4. Include remaining non-source runtime files.
  for (final relPath in sortedPaths) {
    if (consumedFiles.contains(relPath)) continue;
    final lower = relPath.toLowerCase();
    if (_sourceAssetExtensions.any(lower.endsWith)) {
      warnings.add('Skipped unreferenced source file: $relPath');
      continue;
    }
    addEntry(
      relPath,
      diskFiles[relPath]!.readAsBytesSync(),
      _classifyPath(relPath),
    );
  }

  final entries = entriesByPath.values.toList()
    ..sort((a, b) => a.virtualPath.compareTo(b.virtualPath));
  final validationErrors = validatePackEntries(entries);
  if (validationErrors.any((d) => d.severity == DiagnosticSeverity.error)) {
    throw FormatException(validationErrors.map((d) => d.message).join('; '));
  }

  if (dryRun) {
    return AssetPackReport(
      dryRun: true,
      sourceDir: sourceDir.path,
      outputPakPath: outputPak.path,
      entries: entries,
      cookedModels: cookedModels,
      cookedLuts: cookedLuts,
      warnings: warnings,
      sidecarManifestPath: sidecarManifestOut?.path,
    );
  }

  if (cookDir != null) {
    await cookDir.create(recursive: true);
    for (final entry in entries) {
      await _writeRelativeFile(cookDir, entry.virtualPath, entry.bytes);
    }
  }

  final pakBytes = buildDeterministicPak(
    entries,
    compress: compress,
    xorKey: xorKey,
    validate: true,
  );
  await outputPak.parent.create(recursive: true);
  await outputPak.writeAsBytes(pakBytes, flush: true);

  final archiveSha = Sha256.compute(pakBytes);
  if (sidecarManifestOut != null) {
    final doc = {
      'schema': 'volition-asset-pack-v1',
      'archiveSha256': archiveSha,
      'archiveBytes': pakBytes.length,
      'entryCount': entries.length,
      'entries': [
        for (final entry in entries)
          {
            'path': entry.virtualPath,
            'kind': entry.kind,
            'byteLength': entry.bytes.length,
            'sha256': entry.sha256,
          },
      ],
    };
    await sidecarManifestOut.parent.create(recursive: true);
    await sidecarManifestOut.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(doc)}\n',
    );
    final checkSidecar = verifyPakArchiveBytes(
      pakBytes,
      xorKey: xorKey,
      sidecarManifest: doc,
    );
    if (checkSidecar.any((d) => d.severity == DiagnosticSeverity.error)) {
      throw FormatException(checkSidecar.map((d) => d.message).join('; '));
    }
  }

  return AssetPackReport(
    dryRun: false,
    sourceDir: sourceDir.path,
    outputPakPath: outputPak.path,
    entries: entries,
    cookedModels: cookedModels,
    cookedLuts: cookedLuts,
    warnings: warnings,
    sidecarManifestPath: sidecarManifestOut?.path,
    archiveSizeBytes: pakBytes.length,
    archiveSha256: archiveSha,
  );
}

/// CLI entrypoint shared by `tool/asset_packer.dart` and `bin/volition.dart`.
Future<int> runAssetPackerCli(
  List<String> args, {
  void Function(String)? log,
  void Function(String)? onError,
}) async {
  final void Function(String) out = log ?? (String m) => stdout.writeln(m);
  final void Function(String) err = onError ?? (String m) => stderr.writeln(m);

  if (args.contains('-h') || args.contains('--help')) {
    out(_packerUsage);
    return 0;
  }

  final subcommand = args.isNotEmpty && !args.first.startsWith('-')
      ? args.first
      : 'pack';
  if (subcommand == 'obj2qmesh') {
    return _cliObj2Qmesh(args.sublist(1), out, err);
  }
  if (subcommand == 'cube2lut') {
    return _cliCube2Lut(args.sublist(1), out, err);
  }
  if (subcommand == 'validate') {
    return _cliValidate(args.sublist(1), out, err);
  }

  final packArgs = subcommand == 'pack' ? args.sublist(1) : args;
  return _cliPack(packArgs, out, err);
}

Future<void> main(List<String> args) async {
  final code = await runAssetPackerCli(args);
  if (code != 0) exit(code);
}

const String _packerUsage = '''
glVolition Asset Packer (tool/asset_packer.dart)

Usage:
  dart run tool/asset_packer.dart [pack] [--in <source-dir>] [--out <bundle.pak>] [--cook-dir <dir>] [--prefix <vfs-prefix>] [--manifest <sidecar.json>] [--no-compress] [--xor-key <int>] [--dry-run]
  dart run tool/asset_packer.dart obj2qmesh <model.obj> --out <package-dir> [--mtl <materials.mtl>] [--asset-id <id>] [--license <id>]
  dart run tool/asset_packer.dart cube2lut <grade.cube> --out <grade.qlut>
  dart run tool/asset_packer.dart validate <package-dir|bundle.pak> [--xor-key <int>] [--manifest <sidecar.json>]
''';

Future<int> _cliPack(
  List<String> args,
  void Function(String) out,
  void Function(String) err,
) async {
  String? inDir;
  String? outPak;
  String? cookDir;
  String prefix = '';
  String? sidecarManifest;
  var compress = true;
  int? xorKey;
  var dryRun = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--in' && i + 1 < args.length) {
      inDir = args[++i];
    } else if (a == '--out' && i + 1 < args.length) {
      outPak = args[++i];
    } else if (a == '--cook-dir' && i + 1 < args.length) {
      cookDir = args[++i];
    } else if (a == '--prefix' && i + 1 < args.length) {
      prefix = args[++i];
    } else if (a == '--manifest' && i + 1 < args.length) {
      sidecarManifest = args[++i];
    } else if (a == '--no-compress') {
      compress = false;
    } else if (a == '--xor-key' && i + 1 < args.length) {
      xorKey = int.tryParse(args[++i]);
      if (xorKey == null) {
        err('Invalid integer for --xor-key');
        return 64;
      }
    } else if (a == '--dry-run') {
      dryRun = true;
    } else if (a.startsWith('-')) {
      err('Unknown pack option "$a".');
      return 64;
    } else if (inDir == null) {
      inDir = a;
    } else if (outPak == null) {
      outPak = a;
    } else {
      err('Unexpected positional argument "$a".');
      return 64;
    }
  }

  inDir ??= 'assets';
  outPak ??= 'assets.pak';

  final sourceDir = Directory(inDir);
  if (!sourceDir.existsSync()) {
    err('Source asset directory not found: $inDir');
    return 66;
  }

  try {
    final report = await packAssetDirectory(
      sourceDir: sourceDir,
      outputPak: File(outPak),
      cookDir: cookDir == null ? null : Directory(cookDir),
      prefix: prefix,
      compress: compress,
      xorKey: xorKey,
      sidecarManifestOut: sidecarManifest == null
          ? null
          : File(sidecarManifest),
      dryRun: dryRun,
    );
    out(report.formatSummary());
    return 0;
  } catch (e) {
    err('Asset pack failed: $e');
    return 1;
  }
}

Future<int> _cliObj2Qmesh(
  List<String> args,
  void Function(String) out,
  void Function(String) err,
) async {
  String? objPath;
  String? outDir;
  String? mtlPath;
  String? assetId;
  String? licenseId;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--out' && i + 1 < args.length) {
      outDir = args[++i];
    } else if (a == '--mtl' && i + 1 < args.length) {
      mtlPath = args[++i];
    } else if (a == '--asset-id' && i + 1 < args.length) {
      assetId = args[++i];
    } else if (a == '--license' && i + 1 < args.length) {
      licenseId = args[++i];
    } else if (a.startsWith('-')) {
      err('Unknown obj2qmesh option "$a".');
      return 64;
    } else {
      objPath ??= a;
    }
  }

  if (objPath == null || outDir == null) {
    err(
      'Usage: obj2qmesh <model.obj> --out <package-dir> [--mtl <materials.mtl>]',
    );
    return 64;
  }
  final objFile = File(objPath);
  if (!objFile.existsSync()) {
    err('OBJ file not found: $objPath');
    return 66;
  }

  try {
    final result = await cookObjFileToDirectory(
      objFile: objFile,
      outputDir: Directory(outDir),
      mtlFile: mtlPath == null ? null : File(mtlPath),
      assetId: assetId,
      licenseId: licenseId,
    );
    out(
      'Cooked OBJ -> QMSH package "${result.manifest.assetId}" '
      '(${result.payloads.length} parts, hash=${result.manifest.packageHash}) -> $outDir',
    );
    return 0;
  } catch (e) {
    err('OBJ cook failed: $e');
    return 1;
  }
}

Future<int> _cliCube2Lut(
  List<String> args,
  void Function(String) out,
  void Function(String) err,
) async {
  String? cubePath;
  String? outPath;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--out' && i + 1 < args.length) {
      outPath = args[++i];
    } else if (a.startsWith('-')) {
      err('Unknown cube2lut option "$a".');
      return 64;
    } else {
      cubePath ??= a;
    }
  }

  if (cubePath == null || outPath == null) {
    err('Usage: cube2lut <grade.cube> --out <grade.qlut>');
    return 64;
  }
  final cubeFile = File(cubePath);
  if (!cubeFile.existsSync()) {
    err('LUT .cube file not found: $cubePath');
    return 66;
  }

  try {
    final parsed = parseCubeLut(await cubeFile.readAsString());
    final encoded = encodePackedLut(parsed);
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(encoded, flush: true);
    out(
      'Cooked .cube LUT "${parsed.title.isEmpty ? cubePath : parsed.title}" '
      '(${parsed.size}^3, ${encoded.length} B) -> $outPath',
    );
    return 0;
  } catch (e) {
    err('LUT cook failed: $e');
    return 1;
  }
}

Future<int> _cliValidate(
  List<String> args,
  void Function(String) out,
  void Function(String) err,
) async {
  String? targetPath;
  int? xorKey;
  String? manifestPath;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--xor-key' && i + 1 < args.length) {
      xorKey = int.tryParse(args[++i]);
      if (xorKey == null) {
        err('Invalid integer for --xor-key');
        return 64;
      }
    } else if (a == '--manifest' && i + 1 < args.length) {
      manifestPath = args[++i];
    } else if (a.startsWith('-')) {
      err('Unknown validate option "$a".');
      return 64;
    } else {
      targetPath ??= a;
    }
  }

  if (targetPath == null) {
    err(
      'Usage: validate <package-dir|bundle.pak> [--xor-key <int>] [--manifest <sidecar.json>]',
    );
    return 64;
  }

  final dir = Directory(targetPath);
  if (dir.existsSync()) {
    final diags = validateModelPackageDirectory(dir);
    if (diags.isEmpty) {
      out('Validation passed for model package directory: $targetPath');
      return 0;
    }
    for (final d in diags) {
      err('[${d.code}] ${d.message}');
    }
    return 1;
  }

  final file = File(targetPath);
  if (!file.existsSync()) {
    err('Validation target not found: $targetPath');
    return 66;
  }

  Map<String, dynamic>? sidecar;
  if (manifestPath != null) {
    final mf = File(manifestPath);
    if (!mf.existsSync()) {
      err('Sidecar manifest not found: $manifestPath');
      return 66;
    }
    sidecar = jsonDecode(await mf.readAsString()) as Map<String, dynamic>;
  }

  final diags = verifyPakArchiveBytes(
    await file.readAsBytes(),
    xorKey: xorKey,
    sidecarManifest: sidecar,
  );
  if (diags.isEmpty) {
    out('Validation passed for .pak archive: $targetPath');
    return 0;
  }
  for (final d in diags) {
    err('[${d.code}] ${d.message}');
  }
  return 1;
}

bool _isSafeRelPath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path.contains(':') ||
      path.contains('://')) {
    return false;
  }
  final segments = path.split('/');
  return segments.every((s) => s.isNotEmpty && s != '.' && s != '..');
}

File _resolveSafeChildFile(Directory baseDir, String relativePath) {
  if (!_isSafeRelPath(relativePath)) {
    throw FormatException('Unsafe relative asset path: $relativePath');
  }
  final sep = Platform.pathSeparator;
  return File('${baseDir.path}$sep${relativePath.replaceAll('/', sep)}');
}

File? _tryResolveTextureFile(Directory baseDir, String relativePath) {
  if (!_isSafeRelPath(relativePath)) return null;
  final candidate = _resolveSafeChildFile(baseDir, relativePath);
  return candidate.existsSync() ? candidate : null;
}

Future<void> _writeRelativeFile(
  Directory baseDir,
  String relativePath,
  Uint8List bytes,
) async {
  final file = _resolveSafeChildFile(baseDir, relativePath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

String _normAbs(String path) =>
    path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');

Map<String, File> _collectRelativeFiles(Directory root) {
  final rootNorm = _normAbs(root.absolute.path);
  final files = <String, File>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final full = _normAbs(entity.absolute.path);
    if (!full.startsWith('$rootNorm/')) continue;
    final rel = full.substring(rootNorm.length + 1);
    final name = rel.split('/').last;
    if (name == '.DS_Store' || name == 'Thumbs.db') continue;
    files[rel] = entity;
  }
  return files;
}

String _stemOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot <= 0 ? fileName : fileName.substring(0, dot);
}

String _parentDirOf(String relPath) {
  final slash = relPath.lastIndexOf('/');
  return slash < 0 ? '' : relPath.substring(0, slash);
}

String _classifyPath(String path) {
  final lower = path.toLowerCase();
  if (lower == 'manifest.json' || lower.endsWith('/manifest.json')) {
    return 'model-manifest';
  }
  if (lower.endsWith('.qmesh')) return 'qmesh';
  if (lower.endsWith('.qlut')) return 'lut';
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.svg')) {
    return 'texture';
  }
  return 'data';
}
