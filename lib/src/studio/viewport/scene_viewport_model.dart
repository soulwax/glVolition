/// Pure-Dart Scene View & Game View models (S2-B):
/// - Independent [EditorCameraController] (orbit, pan, zoom, WASD+RMB fly,
///   frame-selected `F`, 2D/ortho toggle) decoupled from game [Camera]s.
/// - [SceneViewportModel] producing [EditorOverlayState] (infinite grid,
///   gizmo lines, component icons, selection IDs) and RGBA8 ID-buffer / ray
///   picking.
/// - [GameViewportModel] managing aspect-ratio presets & resolution scaling.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pixeldart/rendering/api/editor_overlay.dart';

import '../../../gl_volition.dart';
import '../bridge/editor_host_bridge.dart';
import '../shell/dock_layout.dart';

/// RGBA8 24-bit object-ID encoder/decoder for on-demand ID-buffer picking.
abstract final class EditorPickIdCodec {
  static const int maxObjectId = 0xFFFFFF;

  static (int r, int g, int b, int a) encode(int objectId) {
    final id = objectId.clamp(0, maxObjectId);
    return (id & 0xFF, (id >> 8) & 0xFF, (id >> 16) & 0xFF, 255);
  }

  static int decode(int r, int g, int b) =>
      (r & 0xFF) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16);

  /// Reads the object ID at pixel `(px, py)` (top-left origin) from an RGBA8
  /// pixel buffer of dimensions `width x height`.
  static int readPixel(Uint8List rgba, int width, int height, int px, int py) {
    if (px < 0 || py < 0 || px >= width || py >= height) return 0;
    final idx = (py * width + px) * 4;
    if (idx + 2 >= rgba.length) return 0;
    return decode(rgba[idx], rgba[idx + 1], rgba[idx + 2]);
  }
}

/// Independent Scene-view editor camera supporting orbit, pan, zoom, WASD fly,
/// frame-selected (`F`), and 2D orthographic toggle.
final class EditorCameraController {
  Vec3 target;
  double distance;
  double yawRadians;
  double pitchRadians;
  double fovYRadians;
  double nearPlane;
  double farPlane;
  bool isOrthographic2D;
  double orthoHeight;
  double flySpeed;

  double _savedYaw = 0.6;
  double _savedPitch = 0.4;

  EditorCameraController({
    this.target = Vec3.zero,
    this.distance = 12.0,
    this.yawRadians = 0.6,
    this.pitchRadians = 0.4,
    this.fovYRadians = 1.04719755, // 60 deg
    this.nearPlane = 0.05,
    this.farPlane = 1000.0,
    this.isOrthographic2D = false,
    this.orthoHeight = 10.0,
    this.flySpeed = 8.0,
  });

  Vec3 get position {
    final cosP = math.cos(pitchRadians);
    final sinP = math.sin(pitchRadians);
    final sinY = math.sin(yawRadians);
    final cosY = math.cos(yawRadians);
    final offset = Vec3(sinY * cosP, sinP, cosY * cosP) * distance;
    return target + offset;
  }

  Vec3 get forward => (target - position).normalized;

  Vec3 get right {
    final fwd = forward;
    final upRef = fwd.y.abs() > 0.99
        ? const Vec3(0, 0, -1)
        : const Vec3(0, 1, 0);
    return fwd.cross(upRef).normalized;
  }

  Vec3 get up => right.cross(forward).normalized;

  void orbit(double deltaYaw, double deltaPitch) {
    if (isOrthographic2D) return;
    yawRadians += deltaYaw;
    pitchRadians = (pitchRadians + deltaPitch).clamp(-1.52, 1.52);
  }

  void pan(double deltaRight, double deltaUp) {
    final scale = isOrthographic2D ? orthoHeight * 0.01 : distance * 0.002;
    target =
        target + (right * (-deltaRight * scale)) + (up * (deltaUp * scale));
  }

  void zoom(double delta) {
    final factor = math.exp(-delta * 0.12);
    if (isOrthographic2D) {
      orthoHeight = (orthoHeight * factor).clamp(0.5, 500.0);
    } else {
      distance = (distance * factor).clamp(0.5, 500.0);
    }
  }

  /// First-person WASD + Q/E fly movement while holding RMB in Scene view.
  void flyWasd({
    double forwardInput = 0.0,
    double rightInput = 0.0,
    double upInput = 0.0,
    required double dt,
    bool boost = false,
  }) {
    if (dt <= 0) return;
    final speed = flySpeed * (boost ? 2.5 : 1.0) * dt;
    final move =
        (forward * forwardInput +
            right * rightInput +
            const Vec3(0, 1, 0) * upInput) *
        speed;
    target = target + move;
  }

  /// Frames the current [EditorSession] selection (`F` shortcut).
  bool frameSelection(EditorSession session, {double padding = 1.6}) {
    final bounds = session.selectionWorldBounds;
    if (bounds == null) return false;
    target = (bounds.min + bounds.max) * 0.5;
    final radius = math.max(0.5, (bounds.max - bounds.min).length * 0.5);
    distance = math.max(2.0, radius * padding * 2.0);
    orthoHeight = math.max(2.0, radius * padding * 2.0);
    return true;
  }

  /// Toggles between 3D perspective and 2D XY orthographic view.
  void toggle2DMode() {
    isOrthographic2D = !isOrthographic2D;
    if (isOrthographic2D) {
      _savedYaw = yawRadians;
      _savedPitch = pitchRadians;
      yawRadians = 0.0;
      pitchRadians = 0.0;
    } else {
      yawRadians = _savedYaw;
      pitchRadians = _savedPitch;
    }
  }

  Mat4 viewMatrix() => Mat4.lookAt(eye: position, forward: forward, up: up);

  Mat4 projectionMatrix(double aspect) {
    final safeAspect = aspect <= 0 ? 16.0 / 9.0 : aspect;
    if (isOrthographic2D) {
      final halfH = orthoHeight * 0.5;
      final halfW = halfH * safeAspect;
      return Mat4.orthographic(
        left: -halfW,
        right: halfW,
        bottom: -halfH,
        top: halfH,
        near: nearPlane,
        far: farPlane,
      );
    }
    return Mat4.perspective(
      fovYRadians: fovYRadians,
      aspect: safeAspect,
      near: nearPlane,
      far: farPlane,
    );
  }

  /// Unprojects normalized viewport coordinates `(nx, ny)` in `[0, 1]`
  /// (top-left origin) into a world-space [Ray].
  Ray screenPointToRay(double nx, double ny, double aspect) {
    final ndcX = nx * 2.0 - 1.0;
    final ndcY = 1.0 - ny * 2.0;
    final safeAspect = aspect <= 0 ? 16.0 / 9.0 : aspect;
    if (isOrthographic2D) {
      final halfH = orthoHeight * 0.5;
      final halfW = halfH * safeAspect;
      final origin = position + right * (ndcX * halfW) + up * (ndcY * halfH);
      return Ray(origin: origin, direction: forward);
    }
    final tanHalfFov = math.tan(fovYRadians * 0.5);
    final dir =
        (forward +
                right * (ndcX * safeAspect * tanHalfFov) +
                up * (ndcY * tanHalfFov))
            .normalized;
    return Ray(origin: position, direction: dir);
  }
}

/// Pure-Dart Scene View panel model producing [EditorOverlayState] and
/// handling viewport picking + shading modes.
final class SceneViewportModel implements StudioPanel {
  final EditorHostBridge bridge;
  final EditorCameraController editorCamera;
  final ViewportGizmos gizmos;
  EditorGridSpec grid;
  bool showGizmos;
  bool showIcons;

  SceneViewportModel(
    this.bridge, {
    EditorCameraController? editorCamera,
    ViewportGizmos? gizmos,
    this.grid = const EditorGridSpec(),
    this.showGizmos = true,
    this.showIcons = true,
  }) : editorCamera = editorCamera ?? EditorCameraController(),
       gizmos = gizmos ?? ViewportGizmos(bridge.session.engine.scene);

  @override
  String get id => 'scene';

  @override
  String get title => 'Scene';

  static int objectPickId(GameObject go) => go.transform.instanceId;

  static Iterable<GameObject> _walkScene(Scene scene) sync* {
    Iterable<GameObject> visit(GameObject go) sync* {
      if (go.isDestroyed) return;
      yield go;
      for (final child in go.children) {
        yield* visit(child);
      }
    }

    for (final root in scene.rootGameObjects) {
      yield* visit(root);
    }
  }

  /// Builds the per-frame [EditorOverlayState] for `[S2-B]` renderer passes.
  EditorOverlayState buildOverlayState({EditorPickRequest? pickRequest}) {
    final session = bridge.session;
    final selected = session.selectedObjects;
    final selectedIds = <int>{for (final go in selected) objectPickId(go)};

    final lines = <EditorGizmoLine>[];
    if (showGizmos && selected.isNotEmpty) {
      final pivot =
          session.selectionCentroid ?? selected.first.transform.position;
      const axisLen = 1.5;
      lines.addAll([
        EditorGizmoLine(
          start: pivot,
          end: pivot + const Vec3(1, 0, 0) * axisLen,
          color: const LinearColor(0.95, 0.25, 0.25),
        ),
        EditorGizmoLine(
          start: pivot,
          end: pivot + const Vec3(0, 1, 0) * axisLen,
          color: const LinearColor(0.25, 0.90, 0.35),
        ),
        EditorGizmoLine(
          start: pivot,
          end: pivot + const Vec3(0, 0, 1) * axisLen,
          color: const LinearColor(0.25, 0.55, 0.98),
        ),
      ]);
    }

    final icons = <EditorGizmoIcon>[];
    if (showIcons) {
      for (final go in _walkScene(session.engine.scene)) {
        if (go.getComponent<Camera>() != null) {
          icons.add(
            EditorGizmoIcon(
              worldPosition: go.transform.position,
              iconId: 'camera',
              objectId: objectPickId(go),
            ),
          );
        } else if (go.getComponent<Light>() != null) {
          icons.add(
            EditorGizmoIcon(
              worldPosition: go.transform.position,
              iconId: 'light',
              tint: go.getComponent<Light>()!.color,
              objectId: objectPickId(go),
            ),
          );
        }
      }
    }

    return EditorOverlayState(
      grid: EditorGridSpec(
        enabled: grid.enabled,
        plane: editorCamera.isOrthographic2D ? EditorGridPlane.xy : grid.plane,
        cellSize: grid.cellSize,
        majorEvery: grid.majorEvery,
        fadeDistance: grid.fadeDistance,
        minorColor: grid.minorColor,
        majorColor: grid.majorColor,
      ),
      lines: lines,
      icons: icons,
      selectedObjectIds: selectedIds,
      pickRequest: pickRequest,
    );
  }

  /// Resolves a picked object ID from an RGBA8 ID buffer back to its live
  /// [GameObject] in the active scene.
  EditorPickResult? pickFromIdBuffer(
    Uint8List rgbaPixels,
    int width,
    int height,
    int px,
    int py,
  ) {
    final id = EditorPickIdCodec.readPixel(rgbaPixels, width, height, px, py);
    if (id == 0) return null;
    for (final go in _walkScene(bridge.session.engine.scene)) {
      if (objectPickId(go) == id) {
        return EditorPickResult(
          objectId: id,
          gameObject: go,
          worldPoint: go.transform.position,
        );
      }
    }
    return EditorPickResult(objectId: id);
  }

  /// Fallback ray-sphere pick against scene objects when no GPU ID buffer is
  /// attached (e.g. headless mode).
  EditorPickResult? pickByRay(
    double nx,
    double ny,
    double aspect, {
    double hitRadius = 0.75,
  }) {
    final ray = editorCamera.screenPointToRay(nx, ny, aspect);
    GameObject? best;
    var bestDist = double.infinity;
    Vec3? bestPoint;

    for (final go in _walkScene(bridge.session.engine.scene)) {
      if (!go.activeInHierarchy) continue;
      final center = go.transform.position;
      final oc = center - ray.origin;
      final proj = oc.dot(ray.direction);
      if (proj < 0) continue;
      final closest = ray.origin + ray.direction * proj;
      final distSq = (center - closest).lengthSquared;
      if (distSq <= hitRadius * hitRadius && proj < bestDist) {
        bestDist = proj;
        best = go;
        bestPoint = closest;
      }
    }
    if (best == null) return null;
    return EditorPickResult(
      objectId: objectPickId(best),
      gameObject: best,
      worldPoint: bestPoint,
      distance: bestDist,
    );
  }

  @override
  Map<String, Object?> saveState() => {
    'target': [
      editorCamera.target.x,
      editorCamera.target.y,
      editorCamera.target.z,
    ],
    'distance': editorCamera.distance,
    'yaw': editorCamera.yawRadians,
    'pitch': editorCamera.pitchRadians,
    'is2D': editorCamera.isOrthographic2D,
    'showGizmos': showGizmos,
    'showIcons': showIcons,
  };

  @override
  void restoreState(Map<String, Object?> state) {
    final t = state['target'];
    if (t is List && t.length == 3) {
      editorCamera.target = Vec3(
        (t[0] as num).toDouble(),
        (t[1] as num).toDouble(),
        (t[2] as num).toDouble(),
      );
    }
    editorCamera.distance = (state['distance'] as num?)?.toDouble() ?? 12.0;
    editorCamera.yawRadians = (state['yaw'] as num?)?.toDouble() ?? 0.6;
    editorCamera.pitchRadians = (state['pitch'] as num?)?.toDouble() ?? 0.4;
    editorCamera.isOrthographic2D = state['is2D'] == true;
    showGizmos = state['showGizmos'] as bool? ?? true;
    showIcons = state['showIcons'] as bool? ?? true;
  }
}

/// Game View aspect-ratio preset (`[S2-B]`).
enum GameViewAspectPreset {
  freeAspect(null, 'Free Aspect'),
  hd16x9(16.0 / 9.0, '16:9'),
  classic4x3(4.0 / 3.0, '4:3'),
  ultrawide21x9(21.0 / 9.0, '21:9'),
  portrait9x16(9.0 / 16.0, '9:16');

  final double? ratio;
  final String label;
  const GameViewAspectPreset(this.ratio, this.label);
}

/// Pure-Dart Game View panel model managing aspect presets & scale.
final class GameViewportModel implements StudioPanel {
  GameViewAspectPreset aspectPreset;
  double resolutionScale;
  bool muteAudio;
  bool showStats;

  GameViewportModel({
    this.aspectPreset = GameViewAspectPreset.hd16x9,
    this.resolutionScale = 1.0,
    this.muteAudio = false,
    this.showStats = false,
  });

  @override
  String get id => 'game';

  @override
  String get title => 'Game';

  /// Computes the centered letterboxed viewport rectangle inside
  /// `availableWidth x availableHeight`.
  ({double x, double y, double width, double height}) computeViewportRect(
    double availableWidth,
    double availableHeight,
  ) {
    final targetRatio = aspectPreset.ratio;
    if (targetRatio == null || availableWidth <= 0 || availableHeight <= 0) {
      return (x: 0, y: 0, width: availableWidth, height: availableHeight);
    }
    final availRatio = availableWidth / availableHeight;
    if (availRatio > targetRatio) {
      final w = availableHeight * targetRatio;
      return (
        x: (availableWidth - w) * 0.5,
        y: 0,
        width: w,
        height: availableHeight,
      );
    }
    final h = availableWidth / targetRatio;
    return (
      x: 0,
      y: (availableHeight - h) * 0.5,
      width: availableWidth,
      height: h,
    );
  }

  @override
  Map<String, Object?> saveState() => {
    'aspectPreset': aspectPreset.name,
    'resolutionScale': resolutionScale,
    'muteAudio': muteAudio,
    'showStats': showStats,
  };

  @override
  void restoreState(Map<String, Object?> state) {
    final name = state['aspectPreset'] as String?;
    if (name != null) {
      aspectPreset = GameViewAspectPreset.values.firstWhere(
        (p) => p.name == name,
        orElse: () => GameViewAspectPreset.hd16x9,
      );
    }
    resolutionScale = ((state['resolutionScale'] as num?)?.toDouble() ?? 1.0)
        .clamp(0.25, 2.0);
    muteAudio = state['muteAudio'] == true;
    showStats = state['showStats'] == true;
  }
}
