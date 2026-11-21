part of '../engine.dart';

/// Base class for GUID-referenced `.vasset` data containers (ScriptableObject
/// equivalent, `[S5-0]`).
abstract class DataAsset {
  String guid;
  String name;

  DataAsset({this.guid = '', this.name = 'DataAsset'});

  /// Unique type identifier written into `.vasset` JSON (`"assetType"`).
  String get assetType;

  /// Serializes subclass fields into a JSON-compatible map.
  Map<String, Object?> serializeFields();

  /// Restores subclass fields from a JSON-compatible map.
  void deserializeFields(Map<String, Object?> data);

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'assetType': assetType,
    'guid': guid,
    'name': name,
    'data': serializeFields(),
  };

  void loadFromJson(Map<String, Object?> json) {
    guid = json['guid'] as String? ?? guid;
    name = json['name'] as String? ?? name;
    final raw = json['data'];
    if (raw is Map<String, Object?>) {
      deserializeFields(raw);
    } else if (raw is Map) {
      deserializeFields(raw.map((k, v) => MapEntry('$k', v)));
    }
  }
}

/// Registry mapping `assetType` strings to [DataAsset] factories (`[S5-0]`).
final class DataAssetRegistry {
  final Map<String, DataAsset Function()> _factories = {};

  void register(String assetType, DataAsset Function() factory) {
    _factories[assetType] = factory;
  }

  bool isRegistered(String assetType) => _factories.containsKey(assetType);

  List<String> get registeredTypes => _factories.keys.toList()..sort();

  DataAsset? deserialize(Map<String, Object?> json) {
    final type = json['assetType'] as String?;
    if (type == null) return null;
    final factory = _factories[type];
    if (factory == null) return null;
    final asset = factory();
    asset.loadFromJson(json);
    return asset;
  }
}
