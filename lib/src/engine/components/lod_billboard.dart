part of '../../engine.dart';

/// One distance tier in a [LodGroup] (E11-2).
final class LodLevel {
  final double maxDistance;
  final GameObject target;

  const LodLevel({required this.maxDistance, required this.target});
}

/// Switches active child [GameObject] representations by distance to the active
/// [Camera] (or editor free-look camera), supporting anti-popping [hysteresis],
/// quality [lodBias], optional [forcedLevelIndex] overrides, and distance
/// culling beyond [cullDistance] (E11-2, P14-W22-B).
final class LodGroup extends Behaviour {
  final List<LodLevel> levels;
  double? cullDistance;
  double hysteresis;
  double lodBias;
  int? forcedLevelIndex;

  int _activeLevelIndex = -1;

  LodGroup({
    List<LodLevel> levels = const [],
    this.cullDistance,
    this.hysteresis = 0.0,
    this.lodBias = 1.0,
    this.forcedLevelIndex,
  }) : levels = List.of(levels);

  static final spec = ComponentSpec<LodGroup>('LodGroup', LodGroup.new, [
    Field.number(
      'hysteresis',
      (l) => l.hysteresis,
      (l, v) => l.hysteresis = math.max(0.0, v),
    ),
    Field.number(
      'lodBias',
      (l) => l.lodBias,
      (l, v) => l.lodBias = math.max(0.05, v),
    ),
  ]);

  /// Index of the currently active [LodLevel], or `-1` when culled.
  int get activeLevelIndex => _activeLevelIndex;

  @override
  void lateUpdate() {
    if (levels.isEmpty) return;

    final forced = forcedLevelIndex;
    if (forced != null) {
      final clamped = forced < 0
          ? -1
          : forced.clamp(0, levels.length - 1).toInt();
      _activateLevel(clamped);
      return;
    }

    final camPos = _resolveCameraPosition();
    final bias = math.max(0.05, lodBias);
    final dist = (transform.position - camPos).length / bias;
    final h = math.max(0.0, hysteresis);

    if (cullDistance != null) {
      final cullThreshold = _activeLevelIndex == -1
          ? math.max(0.0, cullDistance! - h)
          : cullDistance! + h;
      if (dist > cullThreshold) {
        _activateLevel(-1);
        return;
      }
    }

    var chosen = levels.length - 1;
    for (var i = 0; i < levels.length; i++) {
      var threshold = levels[i].maxDistance;
      if (_activeLevelIndex >= 0) {
        if (i == _activeLevelIndex) {
          threshold += h;
        } else if (i < _activeLevelIndex) {
          threshold = math.max(0.0, threshold - h);
        }
      }
      if (dist <= threshold) {
        chosen = i;
        break;
      }
    }
    _activateLevel(chosen);
  }

  Vec3 _resolveCameraPosition() {
    if (scene.isLoaded && engine.editor.isFreeLookEnabled) {
      return engine.editor.freeLookCamera.eye;
    }
    final cam = Camera.of(scene);
    if (cam != null) {
      cam._sync();
      return cam.controller.eye;
    }
    return Vec3.zero;
  }

  void _activateLevel(int index) {
    _activeLevelIndex = index;
    for (var i = 0; i < levels.length; i++) {
      levels[i].target.setActive(i == index);
    }
  }
}

/// Rotates its [GameObject] in `lateUpdate` so its `-Z` (`forward`) axis faces
/// the active 3D [Camera] — either full spherical billboarding or Y-axis-locked
/// cylindrical billboarding (E11-2).
final class Billboard extends Behaviour {
  bool cylindrical;

  Billboard({this.cylindrical = false});

  static final spec = ComponentSpec<Billboard>('Billboard', Billboard.new, [
    Field.boolean(
      'cylindrical',
      (b) => b.cylindrical,
      (b, v) => b.cylindrical = v,
    ),
  ]);

  @override
  void lateUpdate() {
    final Vec3 camEye;
    if (scene.isLoaded && engine.editor.isFreeLookEnabled) {
      camEye = engine.editor.freeLookCamera.eye;
    } else {
      final cam = Camera.of(scene);
      if (cam == null) return;
      cam._sync();
      camEye = cam.controller.eye;
    }

    final pos = transform.position;
    if (cylindrical) {
      final flatTarget = Vec3(camEye.x, pos.y, camEye.z);
      if ((flatTarget - pos).lengthSquared > 1e-6) {
        transform.lookAt(flatTarget);
      }
    } else {
      if ((camEye - pos).lengthSquared > 1e-6) {
        transform.lookAt(camEye);
      }
    }
  }
}
