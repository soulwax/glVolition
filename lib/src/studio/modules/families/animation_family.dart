/// S6-C: Animation & Motion Family Studio Integration (9 packages):
/// `voxanim`, `voxblend`, `voxik2d`, `voxgait`, `voxtween`, `voxcurve`,
/// `voxseq`, `voxspline3d`, `voxextrude`.
library;

import '../../../engine.dart';
import '../../commands/menu_registry.dart';

/// Editable keyframe on a 1D animation/envelope curve (`[S6-C]` / `[S7-A]`).
final class StudioCurveKeyframe {
  final double time;
  final double value;
  final double inTangent;
  final double outTangent;

  const StudioCurveKeyframe({
    required this.time,
    required this.value,
    this.inTangent = 0.0,
    this.outTangent = 0.0,
  });
}

/// Reusable curve field editor model for the generic inspector & Animation
/// window (`[S6-C]` / `[S7-A]`).
final class CurveFieldEditorModel {
  final List<StudioCurveKeyframe> _keys = [];

  CurveFieldEditorModel([Iterable<StudioCurveKeyframe> initial = const []]) {
    _keys.addAll(initial);
    _sort();
  }

  List<StudioCurveKeyframe> get keys => List.unmodifiable(_keys);

  void addOrUpdateKey(StudioCurveKeyframe key) {
    _keys.removeWhere((k) => (k.time - key.time).abs() < 1e-4);
    _keys.add(key);
    _sort();
  }

  bool removeKeyAt(int index) {
    if (index < 0 || index >= _keys.length) return false;
    _keys.removeAt(index);
    return true;
  }

  /// Evaluates the cubic Hermite curve at [time].
  double evaluate(double time) {
    if (_keys.isEmpty) return 0.0;
    if (time <= _keys.first.time) return _keys.first.value;
    if (time >= _keys.last.time) return _keys.last.value;
    for (var i = 0; i < _keys.length - 1; i++) {
      final a = _keys[i];
      final b = _keys[i + 1];
      if (time >= a.time && time <= b.time) {
        final dt = b.time - a.time;
        if (dt <= 1e-6) return a.value;
        final t = (time - a.time) / dt;
        final t2 = t * t;
        final t3 = t2 * t;
        final h00 = 2 * t3 - 3 * t2 + 1;
        final h10 = t3 - 2 * t2 + t;
        final h01 = -2 * t3 + 3 * t2;
        final h11 = t3 - t2;
        return h00 * a.value +
            h10 * dt * a.outTangent +
            h01 * b.value +
            h11 * dt * b.inTangent;
      }
    }
    return _keys.last.value;
  }

  void _sort() => _keys.sort((a, b) => a.time.compareTo(b.time));
}

abstract final class AnimationFamilyModule {
  static const List<String> packages = [
    'voxanim',
    'voxblend',
    'voxik2d',
    'voxgait',
    'voxtween',
    'voxcurve',
    'voxseq',
    'voxspline3d',
    'voxextrude',
  ];

  static const List<String> createMenus = [
    'GameObject/Create/Animation/Animator',
    'GameObject/Create/Animation/Spline Track',
  ];

  static void registerMenus(StudioMenuRegistry menus, Scene Function() scene) {
    menus.register(
      StudioMenuItem(
        id: 'create.animation.animator',
        menuPath: 'GameObject/Create/Animation/Animator',
        action: () =>
            scene().createGameObject('Animator')..addComponent(Animator()),
      ),
    );
    menus.register(
      StudioMenuItem(
        id: 'create.animation.spline',
        menuPath: 'GameObject/Create/Animation/Spline Track',
        action: () =>
            scene().createGameObject('Spline Track')
              ..addComponent(SplineTrackLoftComponent()),
      ),
    );
  }

  static Scene buildSampleScene() {
    final scene = Scene('AnimationSample');
    scene.createGameObject('Character').addComponent(Animator());
    scene.createGameObject('Track').addComponent(SplineTrackLoftComponent());
    return scene;
  }
}
