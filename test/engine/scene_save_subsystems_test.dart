/// Additive multi-scene composition (SceneManager) and CRC32 integrity,
/// migration, and portable bundle tests for SaveSystem (P10-W18-B).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P10-W18-B — SceneManager Additive Multi-Scene Composition', () {
    test(
      'loadAdditive, isAdditiveLoaded, unloadAdditive, and primary swap lifecycle',
      () {
        final engine = Engine(HeadlessHost());
        engine.scenes.register('MainWorld', () {
          final s = Scene('MainWorld');
          s.createGameObject('Terrain', position: Vec3.zero);
          return s;
        });
        engine.scenes.register('ZoneA', () {
          final s = Scene('ZoneA');
          final room = s.createGameObject(
            'ZoneA_Room',
            tag: 'Zone',
            position: const Vec3(10, 0, 0),
          );
          room.addComponent(BoxCollider(size: const Vec3(4, 4, 4)));
          return s;
        });
        engine.scenes.register('HudOverlay', () {
          final s = Scene('HudOverlay');
          s.createGameObject('HUD_Root');
          return s;
        });

        engine.scenes.load('MainWorld');
        expect(engine.scene.find('Terrain'), isNotNull);
        expect(engine.scenes.isAdditiveLoaded('ZoneA'), isFalse);

        final zoneRoots = engine.scenes.loadAdditive('ZoneA');
        expect(zoneRoots.length, equals(1));
        expect(engine.scenes.isAdditiveLoaded('ZoneA'), isTrue);
        expect(engine.scenes.loadedAdditiveScenes, contains('ZoneA'));
        expect(engine.scene.find('ZoneA_Room'), isNotNull);
        expect(
          engine.scene.find('ZoneA_Room')!.getComponent<BoxCollider>(),
          isNotNull,
        );

        engine.scenes.loadAdditive('HudOverlay');
        expect(
          engine.scenes.loadedAdditiveScenes,
          containsAll(['ZoneA', 'HudOverlay']),
        );
        expect(engine.scene.find('HUD_Root'), isNotNull);

        // Unload ZoneA while preserving MainWorld and HudOverlay
        expect(engine.scenes.unloadAdditive('ZoneA'), isTrue);
        expect(engine.scenes.isAdditiveLoaded('ZoneA'), isFalse);
        engine.step(0.016);
        expect(engine.scene.find('ZoneA_Room'), isNull);
        expect(engine.scene.find('Terrain'), isNotNull);
        expect(engine.scene.find('HUD_Root'), isNotNull);

        // Unloading non-loaded scene returns false
        expect(engine.scenes.unloadAdditive('ZoneA'), isFalse);

        // Full scene load clears additive tracking
        engine.scenes.load('MainWorld');
        expect(engine.scenes.loadedAdditiveScenes, isEmpty);
        expect(engine.scene.find('HUD_Root'), isNull);
      },
    );
  });

  group('P10-W18-B — SaveSystem Integrity, Migration & Portable Bundles', () {
    test(
      'verifies CRC32 integrity and detects tampered save storage payloads',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.saves.saveData('slot_1', {'gold': 250, 'level': 3});

        expect(engine.saves.verifySlotIntegrity('slot_1'), isTrue);
        expect(engine.saves.verifySlotIntegrity('missing_slot'), isFalse);

        // Tamper directly with underlying storage payload
        host.storage.write(
          'volition.save.data.slot_1',
          '{"gold":999999,"level":99}',
        );
        expect(engine.saves.verifySlotIntegrity('slot_1'), isFalse);
      },
    );

    test(
      'loadDataMigrated upgrades legacy slot schema and persists upgraded CRC32',
      () {
        final engine = Engine(HeadlessHost());
        engine.saves.saveData('legacy_slot', {'schemaVersion': 1, 'hp': 50});

        final migrator = SaveMigrator(targetVersion: 2)
          ..addStep(1, 2, (data) => {...data, 'maxHp': 100});

        final upgraded = engine.saves.loadDataMigrated(
          'legacy_slot',
          migrator: migrator,
        );
        expect(upgraded, isNotNull);
        expect(upgraded!['schemaVersion'], equals(2));
        expect(upgraded['maxHp'], equals(100));
        expect(engine.saves.verifySlotIntegrity('legacy_slot'), isTrue);

        // Persisted payload now carries schemaVersion 2
        final reloaded = engine.saves.loadData('legacy_slot');
        expect(reloaded!['maxHp'], equals(100));
      },
    );

    test(
      'exportSlotBundle and importSlotBundle round-trip across engines and reject corruption',
      () {
        final srcEngine = Engine(HeadlessHost());
        srcEngine.scene.createGameObject(
          'Hero',
          position: const Vec3(7, 2, -4),
        );
        srcEngine.saves.saveData('campaign', {
          'chapter': 4,
        }, summary: 'Chapter 4');
        srcEngine.saves.saveCheckpoint('campaign');

        final bundle = srcEngine.saves.exportSlotBundle('campaign');

        final dstEngine = Engine(HeadlessHost());
        final meta = dstEngine.saves.importSlotBundle(
          bundle,
          overrideSlotName: 'imported_slot',
        );
        expect(meta.slot, equals('imported_slot'));
        expect(meta.hasCheckpoint, isTrue);
        expect(dstEngine.saves.verifySlotIntegrity('imported_slot'), isTrue);
        expect(
          dstEngine.saves.loadData('imported_slot')!['chapter'],
          equals(4),
        );

        expect(dstEngine.saves.loadCheckpoint('imported_slot'), isTrue);
        final hero = dstEngine.scene.find('Hero');
        expect(hero, isNotNull);
        expect(hero!.transform.localPosition.x, closeTo(7.0, 1e-4));

        // Corrupting the bundle JSON triggers FormatException
        final tampered = bundle.replaceFirst('Chapter 4', 'Chapter 9');
        expect(tampered, isNot(equals(bundle)));
        expect(
          () => dstEngine.saves.importSlotBundle(tampered),
          throwsFormatException,
        );
      },
    );
  });
}
