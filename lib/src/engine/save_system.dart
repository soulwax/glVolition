part of '../engine.dart';

/// Metadata describing a persisted slot in [SaveSystem] (E12-3).
final class SaveSlotMeta {
  final String slot;
  final String savedAtIso;
  final String sceneName;
  final String? summary;
  final bool hasCheckpoint;

  const SaveSlotMeta({
    required this.slot,
    required this.savedAtIso,
    required this.sceneName,
    this.summary,
    this.hasCheckpoint = false,
  });

  Map<String, Object?> toJson() => {
    'slot': slot,
    'savedAtIso': savedAtIso,
    'sceneName': sceneName,
    if (summary != null) 'summary': summary,
    'hasCheckpoint': hasCheckpoint,
  };

  factory SaveSlotMeta.fromJson(Map<String, Object?> json) => SaveSlotMeta(
    slot: (json['slot'] as String?) ?? 'default',
    savedAtIso: (json['savedAtIso'] as String?) ?? '',
    sceneName: (json['sceneName'] as String?) ?? 'Scene',
    summary: json['summary'] as String?,
    hasCheckpoint: (json['hasCheckpoint'] as bool?) ?? false,
  );
}

/// Manages named save-game slots and full scene/session checkpoints on top of
/// [EngineHost.storage] (E12-3).
final class SaveSystem {
  static const String _indexKey = 'volition.saves.index';
  static const String _dataPrefix = 'volition.save.data.';
  static const String _checkpointPrefix = 'volition.save.checkpoint.';

  final Engine _engine;

  SaveSystem._(this._engine);

  KeyValueStore get _store => _engine.host.storage;

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

  bool hasSlot(String slot) => listSlots().any((m) => m.slot == slot);

  /// Saves arbitrary JSON-compatible progress [data] into [slot].
  void saveData(String slot, Map<String, Object?> data, {String? summary}) {
    _store.write('$_dataPrefix$slot', jsonEncode(data));
    _upsertMeta(
      SaveSlotMeta(
        slot: slot,
        savedAtIso: DateTime.now().toUtc().toIso8601String(),
        sceneName: _engine.scene.name,
        summary: summary,
        hasCheckpoint: _store.read('$_checkpointPrefix$slot') != null,
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

  /// Captures a full engine & scene checkpoint (`captureSessionSnapshot`) into
  /// [slot].
  void saveCheckpoint(String slot, {String? summary}) {
    final snap = _engine.captureSessionSnapshot();
    _store.write('$_checkpointPrefix$slot', jsonEncode(snap));
    _upsertMeta(
      SaveSlotMeta(
        slot: slot,
        savedAtIso: DateTime.now().toUtc().toIso8601String(),
        sceneName: _engine.scene.name,
        summary: summary,
        hasCheckpoint: true,
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
