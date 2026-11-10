part of '../engine.dart';

/// Platform-neutral state for the in-engine scene editor & live inspector
/// (E7-1..E7-3).
///
/// Manages:
/// - **Play / Stop** mode with full JSON scene snapshot & restore
/// - **Free-look editor camera** ([OrbitCameraController]) when inspecting
/// - **3D axis gizmo drag** math ([computeAxisDragDelta]) for translating
///   selected [GameObject]s along world X/Y/Z axes from pointer rays.
final class EditorSession {
  final Engine engine;
  final Map<String, Prefab> prefabs;

  GameObject? selected;
  Map<String, Object?>? _playModeSnapshot;
  bool _inPlayMode = true;
  bool _freeLookEnabled = false;
  CameraController? _savedSceneCamera;

  final OrbitCameraController freeLookCamera = OrbitCameraController(
    target: Vec3.zero,
    distance: 18,
    azimuthRadians: 0.4,
    elevationRadians: 0.35,
  );

  EditorSession(this.engine, {this.prefabs = const {}});

  bool get isPlaying => _inPlayMode;
  bool get isFreeLookEnabled => _freeLookEnabled;
  bool get hasSnapshot => _playModeSnapshot != null;

  /// Captures the current scene as the baseline snapshot that [stopPlayMode]
  /// will restore to.
  void captureBaselineSnapshot() {
    _playModeSnapshot = SceneSerializer.toJson(
      engine.scene,
      registry: engine.registry,
    );
  }

  /// Enters Play mode, taking a snapshot of the current scene first so any
  /// runtime mutations or destroyed objects can be reverted via [stopPlayMode].
  void enterPlayMode() {
    captureBaselineSnapshot();
    _inPlayMode = true;
    if (_freeLookEnabled) {
      setFreeLook(false);
    }
    engine.time.timeScale = 1.0;
  }

  /// Stops Play mode and restores the scene to the snapshot captured when
  /// [enterPlayMode] (or [captureBaselineSnapshot]) was called.
  void stopPlayMode() {
    final snap = _playModeSnapshot;
    _inPlayMode = false;
    engine.time.timeScale = 0.0;
    if (snap != null) {
      final restored = SceneSerializer.fromJson(
        snap,
        registry: engine.registry,
        prefabs: prefabs,
      );
      final prevName = selected?.name;
      engine.loadScene(restored);
      selected = prevName != null ? engine.scene.find(prevName) : null;
    }
  }

  /// Toggles between the scene's gameplay camera and the editor's
  /// [freeLookCamera].
  void setFreeLook(bool enabled) {
    if (_freeLookEnabled == enabled) return;
    _freeLookEnabled = enabled;
    if (enabled) {
      _savedSceneCamera = engine.graphics.camera;
      final sel = selected;
      if (sel != null) {
        freeLookCamera.target = sel.transform.position;
      }
      engine.graphics.camera = freeLookCamera;
    } else {
      engine.graphics.camera = _savedSceneCamera;
      _savedSceneCamera = null;
    }
  }

  /// Computes the signed scalar parameter `s` along the line passing through
  /// [axisOrigin] in direction [axisDir] (unit vector) that is closest to
  /// [ray]. Used by 3D translation gizmos to drag an object along X, Y, or Z.
  static double projectRayOntoAxis(Ray ray, Vec3 axisOrigin, Vec3 axisDir) {
    final d1 = ray.direction.normalized;
    final d2 = axisDir.normalized;
    final r = ray.origin - axisOrigin;
    final b = d1.dot(d2);
    final denom = 1.0 - b * b;
    if (denom.abs() < 1e-6) return 0.0;
    final c = d1.dot(r);
    final f = d2.dot(r);
    return (f - b * c) / denom;
  }

  /// Translates [target] along world [axisDir] by the delta between [startRay]
  /// and [currentRay] relative to [initialWorldPosition].
  static Vec3 computeAxisDragPosition({
    required Vec3 initialWorldPosition,
    required Vec3 axisDir,
    required Ray startRay,
    required Ray currentRay,
  }) {
    final unitAxis = axisDir.normalized;
    final s0 = projectRayOntoAxis(startRay, initialWorldPosition, unitAxis);
    final s1 = projectRayOntoAxis(currentRay, initialWorldPosition, unitAxis);
    return initialWorldPosition + unitAxis * (s1 - s0);
  }
}
