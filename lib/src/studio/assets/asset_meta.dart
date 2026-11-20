/// GUID generator and `.vmeta` sidecar model (S1-C).
///
/// Pure-Dart implementation with injectable [Random] for deterministic GUIDs
/// in tests and reproducible builds.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const String kAssetMetaExtension = '.vmeta';

/// Generates 128-bit RFC-4122-style lowercase hex GUIDs (32 hex characters).
final class AssetGuidGenerator {
  final Random _rng;

  AssetGuidGenerator([Random? random]) : _rng = random ?? Random.secure();

  String nextGuid() {
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    // Version 4 + RFC-4122 variant bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// Deterministic 64-bit FNV-1a hex content hash (pure Dart, zero deps).
String computeContentHashHex(Uint8List bytes) {
  var hashHi = 0xcbf29ce4;
  var hashLo = 0x84222325;
  // Use two independent 32-bit FNV-1a lanes for JS-safe 64-bit hex digest.
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    hashLo = ((hashLo ^ b) * 0x01000193) & 0xffffffff;
    hashHi = ((hashHi ^ (b ^ (i & 0xff))) * 0x01000193) & 0xffffffff;
  }
  return '${hashHi.toRadixString(16).padLeft(8, '0')}'
      '${hashLo.toRadixString(16).padLeft(8, '0')}';
}

/// Computes a deterministic hash of a JSON-compatible settings map.
String computeSettingsHashHex(Map<String, Object?> settings) {
  final canonical = _canonicalJson(settings);
  return computeContentHashHex(Uint8List.fromList(utf8.encode(canonical)));
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    final entries = keys
        .map((k) => '${jsonEncode(k)}:${_canonicalJson(value[k])}')
        .join(',');
    return '{$entries}';
  }
  if (value is List) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}

/// Sub-asset identifier inside a compound asset (e.g. GLB mesh, material, clip).
final class AssetSubId {
  final String localId;
  final String kind;
  final String name;

  const AssetSubId({
    required this.localId,
    required this.kind,
    required this.name,
  });

  Map<String, Object?> toJson() => {
    'localId': localId,
    'kind': kind,
    'name': name,
  };

  factory AssetSubId.fromJson(Map<String, Object?> json) => AssetSubId(
    localId: json['localId'] as String? ?? '',
    kind: json['kind'] as String? ?? 'unknown',
    name: json['name'] as String? ?? '',
  );
}

/// Sidecar `.vmeta` metadata committed next to each project asset.
final class AssetMeta {
  final String guid;
  final String importerId;
  final int importerVersion;
  final Map<String, Object?> importSettings;
  final String contentHash;
  final List<AssetSubId> subAssets;
  final List<String> dependencyGuids;

  const AssetMeta({
    required this.guid,
    required this.importerId,
    required this.importerVersion,
    this.importSettings = const {},
    required this.contentHash,
    this.subAssets = const [],
    this.dependencyGuids = const [],
  });

  String get settingsHash => computeSettingsHashHex(importSettings);

  String get cacheKey => '$contentHash:$importerVersion:$settingsHash';

  AssetMeta copyWith({
    String? guid,
    String? importerId,
    int? importerVersion,
    Map<String, Object?>? importSettings,
    String? contentHash,
    List<AssetSubId>? subAssets,
    List<String>? dependencyGuids,
  }) => AssetMeta(
    guid: guid ?? this.guid,
    importerId: importerId ?? this.importerId,
    importerVersion: importerVersion ?? this.importerVersion,
    importSettings: importSettings ?? this.importSettings,
    contentHash: contentHash ?? this.contentHash,
    subAssets: subAssets ?? this.subAssets,
    dependencyGuids: dependencyGuids ?? this.dependencyGuids,
  );

  Map<String, Object?> toJson() => {
    'guid': guid,
    'importerId': importerId,
    'importerVersion': importerVersion,
    'importSettings': importSettings,
    'contentHash': contentHash,
    'subAssets': subAssets.map((s) => s.toJson()).toList(),
    'dependencyGuids': dependencyGuids,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory AssetMeta.fromJson(Map<String, Object?> json) {
    final guid = json['guid'] as String? ?? '';
    if (guid.isEmpty) {
      throw const FormatException('.vmeta missing guid');
    }
    final rawSettings = json['importSettings'];
    final rawSubs = json['subAssets'];
    final rawDeps = json['dependencyGuids'];
    return AssetMeta(
      guid: guid,
      importerId: json['importerId'] as String? ?? 'generic',
      importerVersion: (json['importerVersion'] as num?)?.toInt() ?? 1,
      importSettings: rawSettings is Map
          ? rawSettings.cast<String, Object?>()
          : const {},
      contentHash: json['contentHash'] as String? ?? '',
      subAssets: rawSubs is List
          ? rawSubs
                .whereType<Map>()
                .map((m) => AssetSubId.fromJson(m.cast<String, Object?>()))
                .toList()
          : const [],
      dependencyGuids: rawDeps is List
          ? rawDeps.map((e) => e.toString()).toList()
          : const [],
    );
  }
}
