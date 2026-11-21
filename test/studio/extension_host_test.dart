/// S5-C test: Verifies [StudioExtensionHost] custom inspector precedence,
/// gizmo drawer collection, menu item registration, and `@ExecuteInEditMode`
/// tick execution with `isPlaying` guard.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:pixeldart/rendering/api/editor_overlay.dart';
import 'package:test/test.dart';

@executeInEditMode
final class _EditModeSpinner extends Behaviour implements EditModeTickable {
  int editTicks = 0;
  bool lastIsPlaying = true;

  @override
  void onEditModeUpdate(double dt, {required bool isPlaying}) {
    editTicks++;
    lastIsPlaying = isPlaying;
  }
}

final class _LowPriorityInspector extends CustomInspector<Light> {
  @override
  int get priority => 1;

  @override
  List<Map<String, Object?>> buildRows(Light component) => [
    {'label': 'low'},
  ];
}

final class _HighPriorityInspector extends CustomInspector<Light> {
  @override
  int get priority => 10;

  @override
  List<Map<String, Object?>> buildRows(Light component) => [
    {'label': 'high', 'intensity': component.intensity},
  ];
}

final class _LightTestGizmoDrawer extends GizmoDrawer<Light> {
  @override
  List<EditorGizmoLine> drawGizmos(
    Light component, {
    required bool isSelected,
  }) => [
    EditorGizmoLine(
      start: Vec3.zero,
      end: const Vec3(0, 1, 0),
      color: LinearColor.white,
    ),
  ];
}

void main() {
  group('S5-C — Extension Host & Edit-Mode Execution', () {
    test(
      'resolves highest-priority CustomInspector, collects gizmos & registers menu items',
      () {
        final host = StudioExtensionHost();
        final menus = StudioMenuRegistry();

        host.registerInspector<Light>(_LowPriorityInspector());
        host.registerInspector<Light>(_HighPriorityInspector());
        host.registerGizmoDrawer<Light>(_LightTestGizmoDrawer());

        var executed = false;
        host.registerMenuItem(
          StudioMenuItemExtension(
            id: 'ext.demo',
            menuPath: 'Tools/Extension Demo',
            onExecute: () => executed = true,
          ),
          menuRegistry: menus,
        );

        final light = Light(intensity: 3.5);
        final resolved = host.resolveInspector(light);
        expect(resolved, isA<_HighPriorityInspector>());
        expect(resolved!.buildRows(light).single['label'], equals('high'));

        expect(host.collectGizmos(light, isSelected: true), hasLength(1));
        expect(menus.trigger('ext.demo'), isTrue);
        expect(executed, isTrue);
      },
    );

    test('ticks EditModeTickable behaviours only when isPlaying is false', () {
      final scene = Scene('edit_mode');
      final go = scene.createGameObject('Spinner');
      final spinner = go.addComponent(_EditModeSpinner());

      final host = StudioExtensionHost();
      expect(host.tickEditMode(scene, 0.016, isPlaying: true), equals(0));
      expect(spinner.editTicks, equals(0));

      expect(host.tickEditMode(scene, 0.016, isPlaying: false), equals(1));
      expect(spinner.editTicks, equals(1));
      expect(spinner.lastIsPlaying, isFalse);
    });
  });
}
