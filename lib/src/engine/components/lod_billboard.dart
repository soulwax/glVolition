part of '../../engine.dart';

/// One distance tier in a [LodGroup] (E11-2).
final class LodLevel {
  final double maxDistance;
  final GameObject target;

  const LodLevel({required this.maxDistance, required this.target});
}

/// Switches active child [GameObject] representations by distance to the active
/// [Camera] (or editor free-look camera), and optionally culls all levels
/// beyond [cullDistance] (E11-2).
final class LodGroup extends Behaviour {
  final List<LodLevel> levels;
  double? cullDistance;

  int _activeLevelIndex = -1;

  LodGroup({List<LodLevel> levels = const [], this.cullDistance})
    : levels = List.of(levels);

  static final spec = ComponentSpec<LodGroup>(
    'LodGroup',
    LodGroup.new,
    const [],
  );

  /// Index of the currently active [LodLevel], or `-1` when culled.
  int get activeLevelIndex => _activeLevelIndex;

  @override
  void lateUpdate() {
    if (levels.isEmpty) return;
    final camPos = _resolveCameraPosition();
    final dist = (transform.position - camPos).length;

    if (cullDistance != null && dist > cullDistance!) {
      _activateLevel(-1);
      return;
    }

    var chosen = levels.length - 1;
    for (var i = 0; i < levels.length; i++) {
      if (dist <= levels[i].maxDistance) {
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
