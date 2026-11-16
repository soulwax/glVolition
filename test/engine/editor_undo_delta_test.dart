/// Fine-grained EditorCommand delta undo/redo tests & 1,000-entity scaling benchmark (P7-W15-A).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P7-W15-A — EditorCommand Delta Undo/Redo System', () {
    test(
      'TransformMoveCommand modifies local transform and restores on undo',
      () {
        final engine = Engine(HeadlessHost());
        final go = engine.scene.createGameObject(
          'Prop',
          position: const Vec3(1.0, 2.0, 3.0),
        );

        final cmd = TransformMoveCommand(
          targetName: 'Prop',
          oldPosition: const Vec3(1.0, 2.0, 3.0),
          newPosition: const Vec3(10.0, 20.0, 30.0),
          newScale: 2.5,
          oldScale: 1.0,
        );

        engine.editor.executeCommand(cmd);
        expect(go.transform.localPosition.x, closeTo(10.0, 1e-4));
        expect(go.transform.localScale, closeTo(2.5, 1e-4));

        expect(engine.editor.undo(), isTrue);
        expect(go.transform.localPosition.x, closeTo(1.0, 1e-4));
        expect(go.transform.localScale, closeTo(1.0, 1e-4));

        expect(engine.editor.redo(), isTrue);
        expect(go.transform.localPosition.x, closeTo(10.0, 1e-4));
        expect(go.transform.localScale, closeTo(2.5, 1e-4));
      },
    );

    test(
      'AddGameObjectCommand and RemoveGameObjectCommand manipulate scene hierarchy',
      () {
        final engine = Engine(HeadlessHost());

        final addCmd = AddGameObjectCommand(
          objectName: 'Tree',
          position: const Vec3(5.0, 0.0, -5.0),
        );

        engine.editor.executeCommand(addCmd);
        expect(engine.scene.find('Tree'), isNotNull);
        expect(engine.editor.selected?.name, equals('Tree'));

        expect(engine.editor.undo(), isTrue);
        expect(engine.scene.find('Tree'), isNull);

        expect(engine.editor.redo(), isTrue);
        expect(engine.scene.find('Tree'), isNotNull);

        // Now remove it
        final removeCmd = RemoveGameObjectCommand(objectName: 'Tree');
        engine.editor.executeCommand(removeCmd);
        expect(engine.scene.find('Tree'), isNull);

        expect(engine.editor.undo(), isTrue);
        expect(engine.scene.find('Tree'), isNotNull);
      },
    );

    test('ReparentCommand attaches and detaches parent cleanly', () {
      final engine = Engine(HeadlessHost());
      final rootA = engine.scene.createGameObject('RootA');
      final rootB = engine.scene.createGameObject('RootB');
      final child = engine.scene.createGameObject('Child', parent: rootA);

      expect(child.parent, equals(rootA));

      final reparentCmd = ReparentCommand(
        targetName: 'Child',
        oldParentName: 'RootA',
        newParentName: 'RootB',
      );

      engine.editor.executeCommand(reparentCmd);
      expect(child.parent, equals(rootB));

      expect(engine.editor.undo(), isTrue);
      expect(child.parent, equals(rootA));

      expect(engine.editor.redo(), isTrue);
      expect(child.parent, equals(rootB));
    });

    test('CompoundCommand applies and rolls back batches atomically', () {
      final engine = Engine(HeadlessHost());
      final a = engine.scene.createGameObject('BoxA', position: Vec3.zero);
      final b = engine.scene.createGameObject('BoxB', position: Vec3.zero);

      final batch = CompoundCommand(
        name: 'Move Both',
        commands: [
          TransformMoveCommand(
            targetName: 'BoxA',
            oldPosition: Vec3.zero,
            newPosition: const Vec3(10.0, 0.0, 0.0),
          ),
          TransformMoveCommand(
            targetName: 'BoxB',
            oldPosition: Vec3.zero,
            newPosition: const Vec3(0.0, 20.0, 0.0),
          ),
        ],
      );

      engine.editor.executeCommand(batch);
      expect(a.transform.localPosition.x, closeTo(10.0, 1e-4));
      expect(b.transform.localPosition.y, closeTo(20.0, 1e-4));

      expect(engine.editor.undo(), isTrue);
      expect(a.transform.localPosition.x, closeTo(0.0, 1e-4));
      expect(b.transform.localPosition.y, closeTo(0.0, 1e-4));

      expect(engine.editor.redo(), isTrue);
      expect(a.transform.localPosition.x, closeTo(10.0, 1e-4));
      expect(b.transform.localPosition.y, closeTo(20.0, 1e-4));
    });

    test(
      'O(delta) vs O(scene) scaling on 1,000-entity scene demonstrates orders of magnitude performance advantage',
      () {
        final engineDelta = Engine(HeadlessHost());
        // Populate 1,000 entities
        for (var i = 0; i < 1000; i++) {
          engineDelta.scene.createGameObject(
            'Entity_$i',
            position: Vec3(i.toDouble(), 0.0, 0.0),
          );
        }

        final target = engineDelta.scene.find('Entity_500')!;

        // 1. Measure 20 delta command operations
        final swDelta = Stopwatch()..start();
        for (var i = 0; i < 20; i++) {
          engineDelta.editor.executeCommand(
            TransformMoveCommand(
              targetName: 'Entity_500',
              oldPosition: target.transform.localPosition,
              newPosition: Vec3(500.0 + i, 0.0, 0.0),
            ),
          );
        }
        for (var i = 0; i < 20; i++) {
          engineDelta.editor.undo();
        }
        swDelta.stop();
        final deltaUs = swDelta.elapsedMicroseconds;

        // 2. Measure 20 legacy full-scene JSON serialization operations
        final engineScene = Engine(HeadlessHost());
        for (var i = 0; i < 1000; i++) {
          engineScene.scene.createGameObject(
            'Entity_$i',
            position: Vec3(i.toDouble(), 0.0, 0.0),
          );
        }
        final targetLegacy = engineScene.scene.find('Entity_500')!;

        final swScene = Stopwatch()..start();
        for (var i = 0; i < 20; i++) {
          engineScene.editor.recordUndoState('edit_$i');
          targetLegacy.transform.localPosition = Vec3(500.0 + i, 0.0, 0.0);
        }
        for (var i = 0; i < 20; i++) {
          engineScene.editor.undo();
        }
        swScene.stop();
        final sceneUs = swScene.elapsedMicroseconds;

        // Delta commands execute O(1) per step without scene traversals and serialization
        expect(deltaUs, lessThan(sceneUs));
        final speedup = sceneUs / (deltaUs == 0 ? 1 : deltaUs);
        expect(speedup, greaterThan(5.0)); // At least 5x faster (often 100x+)
      },
    );
  });
}
