/// Volition Studio State-Preserving Hot-Reload Snapshot (`[S5-B]`):
/// Serializes and restores scene state (including unsaved changes), selection,
/// scene camera pose, active tool, and dock layout across web/native reloads.
library;

import 'dart:convert';

import 'package:pixeldart/rendering/math/vec.dart';

import '../../engine.dart';
import '../shell/dock_layout.dart';
import '../viewport/scene_viewport_model.dart';

/// Serializable editor snapshot preserved across hot-reload cycles (`[S5-B]`).
final class StudioReloadSnapshot {
  final int schemaVersion;
  final Map<String, Object?> sceneJson;
  final List<int> selectedIds;
  final Vec3 cameraTarget;
  final double cameraYaw;
  final double cameraPitch;
  final double cameraDistance;
  final String activeTool;
  final Map<String, Object?> dockLayoutJson;

  const StudioReloadSnapshot({
    this.schemaVersion = 1,
    required this.sceneJson,
    required this.selectedIds,
    required this.cameraTarget,
    required this.cameraYaw,
    required this.cameraPitch,
    required this.cameraDistance,
    required this.activeTool,
    required this.dockLayoutJson,
  });

  /// Captures a complete snapshot of the live Studio session prior to reload.
  factory StudioReloadSnapshot.capture({
    required Scene scene,
    required List<int> selectedIds,
    required EditorCameraController camera,
    required StudioDockLayout dockLayout,
    required String activeTool,
    ComponentRegistry? registry,
  }) => StudioReloadSnapshot(
    sceneJson: SceneSerializer.toJson(scene, registry: registry),
    selectedIds: List<int>.unmodifiable(selectedIds),
    cameraTarget: camera.target,
    cameraYaw: camera.yawRadians,
    cameraPitch: camera.pitchRadians,
    cameraDistance: camera.distance,
    activeTool: activeTool,
    dockLayoutJson: dockLayout.toJson(),
  );

  /// Restores the camera pose and dock layout from this snapshot.
  StudioDockLayout restoreInto({required EditorCameraController camera}) {
    camera.target = cameraTarget;
    camera.yawRadians = cameraYaw;
    camera.pitchRadians = cameraPitch;
    camera.distance = cameraDistance;
    return StudioDockLayout.fromJson(dockLayoutJson);
  }

  /// Restores the serialized [Scene] from [sceneJson].
  Scene restoreScene({ComponentRegistry? registry}) =>
      SceneSerializer.fromJson(sceneJson, registry: registry);

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'scene': sceneJson,
    'selectedIds': selectedIds,
    'camera': {
      'target': [cameraTarget.x, cameraTarget.y, cameraTarget.z],
      'yaw': cameraYaw,
      'pitch': cameraPitch,
      'distance': cameraDistance,
    },
    'activeTool': activeTool,
    'dockLayout': dockLayoutJson,
  };

  String toCanonicalJson() => jsonEncode(toJson());

  factory StudioReloadSnapshot.fromJson(Map<String, Object?> json) {
    final cam = (json['camera'] as Map?) ?? const {};
    final t = (cam['target'] as List?) ?? const [0, 0, 0];
    return StudioReloadSnapshot(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      sceneJson: (json['scene'] as Map).map((k, v) => MapEntry('$k', v)),
      selectedIds: [
        for (final id in (json['selectedIds'] as List?) ?? const [])
          (id as num).toInt(),
      ],
      cameraTarget: Vec3(
        (t[0] as num).toDouble(),
        (t[1] as num).toDouble(),
        (t[2] as num).toDouble(),
      ),
      cameraYaw: (cam['yaw'] as num?)?.toDouble() ?? 0.0,
      cameraPitch: (cam['pitch'] as num?)?.toDouble() ?? 0.0,
      cameraDistance: (cam['distance'] as num?)?.toDouble() ?? 10.0,
      activeTool: json['activeTool'] as String? ?? 'translate',
      dockLayoutJson: (json['dockLayout'] as Map).map(
        (k, v) => MapEntry('$k', v),
      ),
    );
  }
}
