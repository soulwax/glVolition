part of '../engine.dart';

/// Metadata describing a persisted slot in [SaveSystem] (E12-3, P10-W18-B).
final class SaveSlotMeta {
  final String slot;
  final String savedAtIso;
  final String sceneName;
  final String? summary;
  final bool hasCheckpoint;
  final int schemaVersion;
  final int? crc32;
  final int? dataCrc32;
  final int? checkpointCrc32;

  const SaveSlotMeta({
    required this.slot,
    required this.savedAtIso,
    required this.sceneName,
    this.summary,
    this.hasCheckpoint = false,
    this.schemaVersion = 1,
    this.crc32,
    this.dataCrc32,
    this.checkpointCrc32,
  });

  Map<String, Object?> toJson() => {
    'slot': slot,
    'savedAtIso': savedAtIso,
    'sceneName': sceneName,
    if (summary != null) 'summary': summary,
    'hasCheckpoint': hasCheckpoint,
    'schemaVersion': schemaVersion,
    if (crc32 != null) 'crc32': crc32,
    if (dataCrc32 != null) 'dataCrc32': dataCrc32,
    if (checkpointCrc32 != null) 'checkpointCrc32': checkpointCrc32,
  };

  factory SaveSlotMeta.fromJson(Map<String, Object?> json) => SaveSlotMeta(
    slot: (json['slot'] as String?) ?? 'default',
    savedAtIso: (json['savedAtIso'] as String?) ?? '',
    sceneName: (json['sceneName'] as String?) ?? 'Scene',
    summary: json['summary'] as String?,
    hasCheckpoint: (json['hasCheckpoint'] as bool?) ?? false,
    schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
    crc32: (json['crc32'] as num?)?.toInt(),
    dataCrc32: (json['dataCrc32'] as num?)?.toInt(),
    checkpointCrc32: (json['checkpointCrc32'] as num?)?.toInt(),
  );
}

/// Manages named save-game slots, CRC32 integrity verification, schema
/// migrations, portable bundles, and full scene/session checkpoints on top of
/// [EngineHost.storage] (E12-3, P10-W18-B).
final class SaveSystem {
  static const String _indexKey = 'volition.saves.index';
  static const String _dataPrefix = 'volition.save.data.';
  static const String _checkpointPrefix = 'volition.save.checkpoint.';

  final Engine _engine;

  SaveSystem._(this._engine);

  KeyValueStore get _store => _engine.host.storage;

  static int _computeCrc32(String payload) =>
      pack.Crc32.compute(Uint8List.fromList(utf8.encode(payload)));

  /// Lists all saved slot metadata entries in storage order.
  List<SaveSlotMeta> listSlots() {
    final raw = _store.read(_indexKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map<String, Object?>) SaveSlotMeta.fromJson(item),
    ];
  }

  SaveSlotMeta? _findMeta(String slot) {
    for (final m in listSlots()) {
      if (m.slot == slot) return m;
    }
    return null;
  }

  bool hasSlot(String slot) => listSlots().any((m) => m.slot == slot);

  /// Saves arbitrary JSON-compatible progress [data] into [slot] with CRC32
  /// integrity tracking.
  void saveData(
    String slot,
    Map<String, Object?> data, {
    String? summary,
    int schemaVersion = 1,
  }) {
    final encoded = jsonEncode(data);
    final crc = _computeCrc32(encoded);
    final existing = _findMeta(slot);
    _store.write('$_dataPrefix$slot', encoded);
    _upsertMeta(
      SaveSlotMeta(
        slot: slot,
        savedAtIso: DateTime.now().toUtc().toIso8601String(),
        sceneName: _engine.scene.name,
        summary: summary ?? existing?.summary,
        hasCheckpoint: _store.read('$_checkpointPrefix$slot') != null,
        schemaVersion: schemaVersion,
        crc32: crc,
        dataCrc32: crc,
        checkpointCrc32: existing?.checkpointCrc32,
      ),
    );
  }

  /// Reads the custom progress dictionary previously saved in [slot], or `null`
  /// if none exists.
  Map<String, Object?>? loadData(String slot) {
    final raw = _store.read('$_dataPrefix$slot');
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  /// Reads custom progress data from [slot], runs [migrator] to upgrade older
  /// schemas, and optionally persists the upgraded payload back to storage.
  Map<String, Object?>? loadDataMigrated(
    String slot, {
    required pack.SaveMigrator migrator,
    int defaultInitialVersion = 0,
    bool persistUpgraded = true,
  }) {
    final data = loadData(slot);
    if (data == null) return null;
    final result = migrator.migrate(
      data,
      defaultInitialVersion: defaultInitialVersion,
    );
    if (result.didMigrate && persistUpgraded) {
      saveData(slot, result.data, schemaVersion: migrator.targetVersion);
    }
    return result.data;
  }

  /// Captures a full engine & scene checkpoint (`captureSessionSnapshot`) into
  /// [slot] with CRC32 integrity tracking.
  void saveCheckpoint(String slot, {String? summary, int schemaVersion = 1}) {
    final snap = _engine.captureSessionSnapshot();
    final encoded = jsonEncode(snap);
    final crc = _computeCrc32(encoded);
    final existing = _findMeta(slot);
    _store.write('$_checkpointPrefix$slot', encoded);
    _upsertMeta(
      SaveSlotMeta(
        slot: slot,
        savedAtIso: DateTime.now().toUtc().toIso8601String(),
        sceneName: _engine.scene.name,
        summary: summary ?? existing?.summary,
        hasCheckpoint: true,
        schemaVersion: schemaVersion,
        crc32: crc,
        dataCrc32: existing?.dataCrc32,
        checkpointCrc32: crc,
      ),
    );
  }

  /// Restores the scene & session checkpoint stored in [slot]. Returns `true`
  /// when a checkpoint existed and was restored.
  bool loadCheckpoint(String slot) {
    final raw = _store.read('$_checkpointPrefix$slot');
    if (raw == null || raw.isEmpty) return false;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return false;
    _engine.restoreSessionSnapshot(decoded);
    return true;
  }

  /// Verifies CRC32 checksums and JSON integrity of all payloads stored in [slot].
  bool verifySlotIntegrity(String slot) {
    final meta = _findMeta(slot);
    if (meta == null) return false;

    final rawData = _store.read('$_dataPrefix$slot');
    final rawCheckpoint = _store.read('$_checkpointPrefix$slot');
    if (rawData == null && rawCheckpoint == null) return false;

    try {
      if (rawData != null) {
        final expectedDataCrc =
            meta.dataCrc32 ?? (rawCheckpoint == null ? meta.crc32 : null);
        if (expectedDataCrc != null &&
            _computeCrc32(rawData) != expectedDataCrc) {
          return false;
        }
        if (jsonDecode(rawData) is! Map) return false;
      }
      if (rawCheckpoint != null) {
        final expectedCpCrc =
            meta.checkpointCrc32 ?? (rawData == null ? meta.crc32 : null);
        if (expectedCpCrc != null &&
            _computeCrc32(rawCheckpoint) != expectedCpCrc) {
          return false;
        }
        if (jsonDecode(rawCheckpoint) is! Map) return false;
      }
    } catch (_) {
      return false;
    }
    return true;
  }

  /// Packages [slot] (metadata, progress data, and checkpoint) into a
  /// portable CRC32-signed JSON bundle string.
  String exportSlotBundle(String slot) {
    final meta = _findMeta(slot);
    if (meta == null) {
      throw StateError('No save slot "$slot" exists to export');
    }
    final rawData = _store.read('$_dataPrefix$slot');
    final rawCheckpoint = _store.read('$_checkpointPrefix$slot');
    final payload = <String, Object?>{
      'meta': meta.toJson(),
      if (rawData != null) 'data': rawData,
      if (rawCheckpoint != null) 'checkpoint': rawCheckpoint,
    };
    final bundleCrc = _computeCrc32(jsonEncode(payload));
    return jsonEncode({...payload, 'bundleCrc32': bundleCrc});
  }

  /// Verifies and imports a portable save bundle produced by [exportSlotBundle].
  SaveSlotMeta importSlotBundle(String bundleJson, {String? overrideSlotName}) {
    final decoded = jsonDecode(bundleJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected top-level JSON object for bundle');
    }
    final expectedCrc = (decoded['bundleCrc32'] as num?)?.toInt();
    final metaRaw = decoded['meta'];
    if (expectedCrc == null || metaRaw is! Map<String, Object?>) {
      throw const FormatException('Save bundle missing meta or bundleCrc32');
    }
    final rawData = decoded['data'] as String?;
    final rawCheckpoint = decoded['checkpoint'] as String?;
    final canonicalPayload = <String, Object?>{
      'meta': metaRaw,
      if (rawData != null) 'data': rawData,
      if (rawCheckpoint != null) 'checkpoint': rawCheckpoint,
    };
    if (_computeCrc32(jsonEncode(canonicalPayload)) != expectedCrc) {
      throw const FormatException('Save bundle CRC32 integrity check failed');
    }

    final parsedMeta = SaveSlotMeta.fromJson(metaRaw);
    final targetSlot = overrideSlotName ?? parsedMeta.slot;

    int? dataCrc;
    if (rawData != null) {
      dataCrc = _computeCrc32(rawData);
      _store.write('$_dataPrefix$targetSlot', rawData);
    } else {
      _store.remove('$_dataPrefix$targetSlot');
    }

    int? checkpointCrc;
    if (rawCheckpoint != null) {
      checkpointCrc = _computeCrc32(rawCheckpoint);
      _store.write('$_checkpointPrefix$targetSlot', rawCheckpoint);
    } else {
      _store.remove('$_checkpointPrefix$targetSlot');
    }

    final importedMeta = SaveSlotMeta(
      slot: targetSlot,
      savedAtIso: parsedMeta.savedAtIso,
      sceneName: parsedMeta.sceneName,
      summary: parsedMeta.summary,
      hasCheckpoint: rawCheckpoint != null,
      schemaVersion: parsedMeta.schemaVersion,
      crc32: checkpointCrc ?? dataCrc ?? parsedMeta.crc32,
      dataCrc32: dataCrc,
      checkpointCrc32: checkpointCrc,
    );
    _upsertMeta(importedMeta);
    return importedMeta;
  }

  /// Deletes both custom progress data and checkpoint data for [slot].
  void deleteSlot(String slot) {
    _store.remove('$_dataPrefix$slot');
    _store.remove('$_checkpointPrefix$slot');
    final next = listSlots().where((m) => m.slot != slot).toList();
    _store.write(_indexKey, jsonEncode([for (final m in next) m.toJson()]));
  }

  void _upsertMeta(SaveSlotMeta meta) {
    final slots = listSlots().toList();
    final idx = slots.indexWhere((m) => m.slot == meta.slot);
    if (idx >= 0) {
      slots[idx] = meta;
    } else {
      slots.add(meta);
    }
    _store.write(_indexKey, jsonEncode([for (final m in slots) m.toJson()]));
  }
}
