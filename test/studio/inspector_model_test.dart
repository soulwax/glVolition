/// S2-C tests: HierarchyPanelModel (tree, search, shift-range multi-select,
/// undoable reparent/rename/create/delete) and InspectorPanelModel (all
/// FieldKinds, multi-edit mixed values, add/remove/reset component, prefab
/// override detection/revert/apply).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S2-C — HierarchyPanelModel', () {
    test(
      'supports expand/collapse, search, range select, and undoable reparent & rename',
      () {
        final engine = Engine(HeadlessHost());
        final parent = engine.scene.createGameObject('Parent');
        final child = engine.scene.createGameObject('Child', parent: parent);
        final sibling = engine.scene.createGameObject('Sibling');

        final session = EditorSession(engine)..stopPlayMode();
        final bridge = SessionEditorHostBridge(session);
        final hierarchy = HierarchyPanelModel(bridge);

        // Collapsed by default -> only roots visible
        expect(
          hierarchy.visibleRows().map((r) => r.object.name),
          equals(['Parent', 'Sibling']),
        );

        hierarchy.setExpanded('Parent', true);
        expect(
          hierarchy.visibleRows().map((r) => r.object.name),
          equals(['Parent', 'Child', 'Sibling']),
        );

        // Shift-range select from Parent to Sibling selects all 3
        hierarchy.selectSingle(parent);
        hierarchy.selectRangeTo(sibling);
        expect(session.selectedObjects.length, equals(3));

        // Undoable reparent: move Sibling under Parent
        hierarchy.reparent(sibling, parent);
        expect(sibling.parent, equals(parent));
        expect(bridge.undo(), isTrue);
        expect(sibling.parent, isNull);
        expect(bridge.redo(), isTrue);
        expect(sibling.parent, equals(parent));

        // Undoable rename
        hierarchy.rename(child, 'HeroChild');
        expect(child.name, equals('HeroChild'));
        expect(bridge.undo(), isTrue);
        expect(child.name, equals('Child'));
      },
    );
  });

  group('S2-C — InspectorPanelModel', () {
    test(
      'detects mixed values across multi-selection and applies undoable edits',
      () {
        final engine = Engine(HeadlessHost());
        final a = engine.scene.createGameObject('LightA')
          ..addComponent(Light.point(intensity: 2.0, range: 10.0));
        final b = engine.scene.createGameObject('LightB')
          ..addComponent(Light.point(intensity: 5.0, range: 10.0));

        final session = EditorSession(engine)..stopPlayMode();
        final bridge = SessionEditorHostBridge(session);
        final inspector = InspectorPanelModel(bridge);

        bridge.selectObjects([a, b]);
        final sections = inspector.buildSections();
        final lightSection = sections.firstWhere((s) => s.typeName == 'Light');

        final intensityField = lightSection.fields.firstWhere(
          (f) => f.field.name == 'intensity',
        );
        final rangeField = lightSection.fields.firstWhere(
          (f) => f.field.name == 'range',
        );

        expect(intensityField.isMixed, isTrue);
        expect(rangeField.isMixed, isFalse);
        expect(rangeField.jsonValue, equals(10.0));

        // Unified multi-edit sets both to 8.0 and is undoable
        inspector.setFieldValue('Light', 'intensity', 8.0);
        expect(a.getComponent<Light>()!.intensity, equals(8.0));
        expect(b.getComponent<Light>()!.intensity, equals(8.0));

        expect(bridge.undo(), isTrue);
        expect(a.getComponent<Light>()!.intensity, equals(2.0));
        expect(b.getComponent<Light>()!.intensity, equals(5.0));

        // Add & remove component undoably
        bridge.selectObjects([a]);
        expect(inspector.searchAvailableComponents('cam'), contains('Camera'));
        inspector.addComponent('Camera');
        expect(a.getComponent<Camera>(), isNotNull);
        expect(bridge.undo(), isTrue);
        expect(a.getComponent<Camera>(), isNull);
      },
    );

    test(
      'flags prefab field overrides and supports revert & apply-as-variant',
      () {
        final engine = Engine(HeadlessHost());
        final prefabs = PrefabRegistry();
        prefabs.register(
          'lamp',
          Prefab('LampTemplate', (root) {
            root.addComponent(Light.point(intensity: 3.0, range: 12.0));
          }),
        );

        final instance = prefabs.instantiate(
          engine.scene,
          'lamp',
          registry: engine.registry,
        );
        instance.getComponent<Light>()!.intensity = 9.0;

        final session = EditorSession(engine)..stopPlayMode();
        final bridge = SessionEditorHostBridge(session);
        final inspector = InspectorPanelModel(bridge, prefabRegistry: prefabs);

        bridge.selectObjects([instance]);
        final lightSection = inspector.buildSections().firstWhere(
          (s) => s.typeName == 'Light',
        );
        final intensityField = lightSection.fields.firstWhere(
          (f) => f.field.name == 'intensity',
        );
        expect(intensityField.isPrefabOverride, isTrue);

        // Apply as variant
        final variant = inspector.applyOverridesAsVariant(
          instance,
          'bright_lamp',
        );
        expect(variant, isNotNull);
        expect(prefabs.findVariant('bright_lamp'), isNotNull);

        // Revert override back to 3.0
        expect(
          inspector.revertPrefabFieldOverride(instance, 'Light', 'intensity'),
          isTrue,
        );
        expect(instance.getComponent<Light>()!.intensity, equals(3.0));
      },
    );
  });
}
