/// Multi-selection editor session, hierarchy search, camera framing, and batch
/// EditorCommand undo/redo tests (P9-W17-C).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P9-W17-C — EditorSession Multi-Selection, Framing & Search', () {
    test(
      'supports legacy single selection, additive/toggle selection, bounds, and camera framing',
      () {
        final engine = Engine(HeadlessHost());
        final editor = engine.editor;

        final a = engine.scene.createGameObject(
          'Cube_A',
          position: const Vec3(-4, 0, 0),
        );
        a.addComponent(BoxCollider(size: const Vec3(2, 2, 2)));

        final b = engine.scene.createGameObject(
          'Cube_B',
          position: const Vec3(4, 2, 0),
        );
        b.addComponent(BoxCollider(size: const Vec3(2, 2, 2)));

        final c = engine.scene.createGameObject(
          'Sphere_C',
          position: const Vec3(0, 0, 6),
        );

        // Legacy single-selection setter still works as expected.
        editor.selected = a;
        expect(editor.selected, same(a));
        expect(editor.selectionCount, equals(1));
        expect(editor.isSelected(a), isTrue);

        // Additive selection adds without dropping prior items.
        editor.select(b, additive: true);
        expect(editor.selectionCount, equals(2));
        expect(editor.selectedObjects, equals([a, b]));
        expect(editor.selected, same(b));

        // Toggle removes an already-selected item or adds a missing one.
        editor.select(a, toggle: true);
        expect(editor.selectedObjects, equals([b]));
        editor.select(c, toggle: true);
        expect(editor.selectedObjects, equals([b, c]));

        // selectAll computes centroid, bounds, and frames freeLookCamera.
        editor.selectAll([a, b]);
        final centroid = editor.selectionCentroid!;
        expect(centroid.x, closeTo(0.0, 1e-6));
        expect(centroid.y, closeTo(1.0, 1e-6));

        final bounds = editor.selectionWorldBounds!;
        expect(bounds.min.x, closeTo(-5.0, 1e-4));
        expect(bounds.max.x, closeTo(5.0, 1e-4));
        expect(bounds.min.y, closeTo(-1.0, 1e-4));
        expect(bounds.max.y, closeTo(3.0, 1e-4));

        expect(editor.focusSelection(), isTrue);
        expect(editor.freeLookCamera.target.x, closeTo(0.0, 1e-4));
        expect(editor.freeLookCamera.target.y, closeTo(1.0, 1e-4));
        expect(editor.freeLookCamera.distance, greaterThan(5.0));

        // Destroyed objects are automatically pruned from selection.
        b.destroy();
        engine.step(0.016);
        expect(editor.selectedObjects, equals([a]));
      },
    );

    test(
      'searchHierarchy filters objects by nameQuery, tag, layer, and componentType',
      () {
        final engine = Engine(HeadlessHost());
        final editor = engine.editor;

        final hero = engine.scene.createGameObject(
          'Hero_Robot',
          tag: 'Player',
          layer: 1,
        );
        hero.addComponent(RigidBody());

        final turret = engine.scene.createGameObject(
          'Sentry_Robot',
          tag: 'Enemy',
          layer: 2,
        );
        turret.addComponent(RigidBody());
        turret.addComponent(Light.spot());

        final crate = engine.scene.createGameObject(
          'SupplyCrate',
          tag: 'Enemy',
          layer: 2,
          active: false,
        );
        crate.addComponent(BoxCollider(size: const Vec3(1, 1, 1)));

        expect(
          editor
              .searchHierarchy(nameQuery: 'robot')
              .map((g) => g.name)
              .toList(),
          equals(['Hero_Robot', 'Sentry_Robot']),
        );
        expect(
          editor
              .searchHierarchy(tag: 'Enemy', includeInactive: false)
              .map((g) => g.name)
              .toList(),
          equals(['Sentry_Robot']),
        );
        expect(
          editor.searchHierarchy(layer: 2).map((g) => g.name).toList(),
          equals(['Sentry_Robot', 'SupplyCrate']),
        );
        expect(
          editor
              .searchHierarchy(componentType: Light)
              .map((g) => g.name)
              .toList(),
          equals(['Sentry_Robot']),
        );
      },
    );
  });

  group('P9-W17-C — Batch Editor Commands', () {
    test('BatchTransformDeltaCommand executes, undoes, and redoes cleanly', () {
      final engine = Engine(HeadlessHost());
      final editor = engine.editor;

      final a = engine.scene.createGameObject(
        'BatchA',
        position: const Vec3(1, 0, 0),
        scale: 1.0,
      );
      final b = engine.scene.createGameObject(
        'BatchB',
        position: const Vec3(2, 3, 4),
        scale: 2.0,
      );

      editor.executeCommand(
        BatchTransformDeltaCommand(
          targetNames: const ['BatchA', 'BatchB'],
          positionDelta: const Vec3(10, 0, -2),
          scaleFactor: 2.0,
        ),
      );

      expect(a.transform.localPosition.x, closeTo(11.0, 1e-5));
      expect(a.transform.localScale, closeTo(2.0, 1e-5));
      expect(b.transform.localPosition.x, closeTo(12.0, 1e-5));
      expect(b.transform.localPosition.z, closeTo(2.0, 1e-5));
      expect(b.transform.localScale, closeTo(4.0, 1e-5));

      expect(editor.undo(), isTrue);
      expect(a.transform.localPosition.x, closeTo(1.0, 1e-5));
      expect(a.transform.localScale, closeTo(1.0, 1e-5));
      expect(b.transform.localPosition.x, closeTo(2.0, 1e-5));
      expect(b.transform.localPosition.z, closeTo(4.0, 1e-5));
      expect(b.transform.localScale, closeTo(2.0, 1e-5));

      expect(editor.redo(), isTrue);
      expect(a.transform.localPosition.x, closeTo(11.0, 1e-5));
      expect(b.transform.localScale, closeTo(4.0, 1e-5));
    });

    test(
      'BatchSetActiveCommand preserves heterogeneous per-object active states on undo',
      () {
        final engine = Engine(HeadlessHost());
        final editor = engine.editor;

        final a = engine.scene.createGameObject('ToggleA', active: true);
        final b = engine.scene.createGameObject('ToggleB', active: false);

        editor.executeCommand(
          BatchSetActiveCommand(
            targetNames: const ['ToggleA', 'ToggleB'],
            active: false,
          ),
        );
        expect(a.activeSelf, isFalse);
        expect(b.activeSelf, isFalse);

        expect(editor.undo(), isTrue);
        expect(a.activeSelf, isTrue);
        expect(b.activeSelf, isFalse);

        expect(editor.redo(), isTrue);
        expect(a.activeSelf, isFalse);
        expect(b.activeSelf, isFalse);
      },
    );

    test('BatchDeleteCommand removes and restores multi-object selection', () {
      final engine = Engine(HeadlessHost());
      final editor = engine.editor;

      final a = engine.scene.createGameObject(
        'DelA',
        position: const Vec3(3, 4, 5),
      );
      final b = engine.scene.createGameObject(
        'DelB',
        position: const Vec3(-1, 2, 0),
      );
      editor.selectAll([a, b]);

      editor.executeCommand(
        BatchDeleteCommand(targetNames: const ['DelA', 'DelB']),
      );
      expect(engine.scene.find('DelA'), isNull);
      expect(engine.scene.find('DelB'), isNull);
      expect(editor.selectionCount, equals(0));

      expect(editor.undo(), isTrue);
      final restoredA = engine.scene.find('DelA');
      final restoredB = engine.scene.find('DelB');
      expect(restoredA, isNotNull);
      expect(restoredB, isNotNull);
      expect(restoredA!.transform.localPosition.x, closeTo(3.0, 1e-5));
      expect(restoredB!.transform.localPosition.y, closeTo(2.0, 1e-5));
      expect(editor.selectedObjects, equals([restoredA, restoredB]));
    });
  });
}
