/// S2-M tests: Play Mode snapshot/pause/step/restore, daemon GUID scene
/// save/autosave/reload byte-equality, and 1,000-object scene open + inspector
/// edit round-trip latency measurements.
library;

import 'dart:convert';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

import '../../tool/studio/studio_daemon.dart';

void main() {
  group('S2-M — Play Mode, Daemon Save/Autosave & Performance Gates', () {
    test('play/pause/step/stop restores pre-play scene state exactly', () {
      final engine = Engine(HeadlessHost());
      final player = engine.scene.createGameObject(
        'Player',
        position: const Vec3(1, 2, 3),
      )..addComponent(Light.point(intensity: 4.0, range: 10.0));

      final session = EditorSession(engine)..stopPlayMode();
      final bridge = SessionEditorHostBridge(session);
      bridge.selectObjects([player]);

      bridge.enterPlayMode();
      expect(bridge.playState, equals(StudioPlayState.playing));

      // Runtime mutation during play mode
      player.transform.position = const Vec3(99, 88, 77);
      player.getComponent<Light>()!.intensity = 12.0;
      engine.scene.createGameObject('RuntimeBullet');

      bridge.pausePlayMode();
      expect(bridge.playState, equals(StudioPlayState.paused));
      bridge.stepPlayMode(1 / 60);
      expect(bridge.playState, equals(StudioPlayState.paused));

      // Exit play mode restores exact pre-play snapshot
      bridge.exitPlayMode();
      expect(bridge.playState, equals(StudioPlayState.editing));
      final restoredPlayer = engine.scene.find('Player')!;
      expect(restoredPlayer.transform.position, equals(const Vec3(1, 2, 3)));
      expect(restoredPlayer.getComponent<Light>()!.intensity, equals(4.0));
      expect(engine.scene.find('RuntimeBullet'), isNull);
    });

    test(
      'StudioDaemon saves GUID scene + autosave and reloads byte-equally',
      () async {
        final fs = MemoryProjectFileSystem();
        final daemon = StudioDaemon(fs: fs);

        final engine = Engine(HeadlessHost());
        engine.scene
            .createGameObject('Camera', position: const Vec3(0, 2, 8))
            .addComponent(Camera());
        engine.scene
            .createGameObject('Sun', position: const Vec3(0, 10, 0))
            .addComponent(Light.directional(intensity: 2.5));

        final sceneJson = SceneSerializer.toJson(
          engine.scene,
          registry: engine.registry,
        );

        final saveRes = await daemon.dispatch(
          StudioRequest(
            id: 's1',
            method: 'scene.save',
            params: {
              'path': 'assets/scenes/main.scene.json',
              'scene': sceneJson,
            },
          ),
        );
        expect(saveRes.ok, isTrue);

        final loadRes = await daemon.dispatch(
          const StudioRequest(
            id: 's2',
            method: 'scene.load',
            params: {'path': 'assets/scenes/main.scene.json'},
          ),
        );
        expect(loadRes.ok, isTrue);
        expect(
          jsonEncode(loadRes.result!['scene']),
          equals(jsonEncode(sceneJson)),
        );

        // Autosave crash recovery file is also byte-equal
        final autosaveRes = await daemon.dispatch(
          const StudioRequest(
            id: 's3',
            method: 'scene.load',
            params: {
              'path': 'assets/scenes/main.scene.json',
              'useAutosave': true,
            },
          ),
        );
        expect(autosaveRes.ok, isTrue);
        expect(
          jsonEncode(autosaveRes.result!['scene']),
          equals(jsonEncode(sceneJson)),
        );
        await fs.close();
      },
    );

    test(
      '1,000-object scene open < 2s and inspector edit round-trip < 16ms',
      () {
        final engine = Engine(HeadlessHost());
        final openSw = Stopwatch()..start();
        for (var i = 0; i < 1000; i++) {
          final go = engine.scene.createGameObject(
            'Entity_$i',
            position: Vec3((i % 32).toDouble(), 0, -(i ~/ 32).toDouble()),
          );
          if (i % 10 == 0) {
            go.addComponent(Light.point(intensity: 1.5, range: 8.0));
          }
        }
        final session = EditorSession(engine)..stopPlayMode();
        final bridge = SessionEditorHostBridge(session);
        final hierarchy = HierarchyPanelModel(bridge);
        final inspector = InspectorPanelModel(bridge);
        final rows = hierarchy.visibleRows();
        openSw.stop();

        expect(rows.length, equals(1000));
        expect(
          openSw.elapsedMilliseconds,
          lessThan(2000),
          reason:
              '1,000-object scene open took ${openSw.elapsedMilliseconds}ms',
        );

        // Measure inspector field edit round-trip
        bridge.selectObjects([engine.scene.find('Entity_0')!]);
        final editSw = Stopwatch()..start();
        inspector.setFieldValue('Light', 'intensity', 6.5);
        final sections = inspector.buildSections();
        editSw.stop();

        final lightSec = sections.firstWhere((s) => s.typeName == 'Light');
        final val = lightSec.fields
            .firstWhere((f) => f.field.name == 'intensity')
            .jsonValue;
        expect(val, equals(6.5));
        expect(
          editSw.elapsedMilliseconds,
          lessThan(16),
          reason:
              'Inspector edit round-trip took ${editSw.elapsedMilliseconds}ms',
        );
      },
    );
  });
}
