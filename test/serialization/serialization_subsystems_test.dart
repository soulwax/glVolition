/// Serialization, save slots, scene cloning, prefab variants & registry coverage tests.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../support/subsystems_test_helpers.dart';

void main() {
  group('E3 — SceneSerializer Round-Trip & Prefab Overrides', () {
    test(
      'SceneSerializer round-trips hierarchy, lights, cameras, colliders, and prefab overrides',
      () {
        final reg = ComponentRegistry.defaults()
          ..register(HealthBehaviour.spec);
        final enemyPrefab = Prefab(
          'Enemy',
          (go) => go.addComponent(
            HealthBehaviour(hp: 50, faction: 'raiders', speed: 4.0),
          ),
        );

        final s1 = Scene('Level1');
        s1.renderSettings
          ..fogEnabled = true
          ..fogStart = 25
          ..fogEnd = 120;

        final camGo = s1.createGameObject(
          'MainCamera',
          position: const Vec3(0, 10, 20),
          components: [Camera.ortho(orthoHeight: 16)],
        );
        s1.createGameObject(
          'Sun',
          parent: camGo,
          components: [Light.directional(intensity: 1.8)],
        );
        s1.createGameObject(
          'TriggerZone',
          position: const Vec3(1, 2, 3),
          components: [SphereCollider(radius: 3.5, isTrigger: true)],
        );

        final jsonStr = SceneSerializer.toJsonString(s1, registry: reg);
        final map = SceneSerializer.toJson(s1, registry: reg);
        // Inject a prefab instance with an hp override into the JSON object list
        (map['objects'] as List<Object?>).add(<String, Object?>{
          'prefab': 'Enemy',
          'name': 'BossEnemy',
          'transform': {
            'p': [10.0, 0.0, -5.0],
          },
          'components': [
            {'type': 'HealthBehaviour', 'hp': 250},
          ],
        });

        final s2 = SceneSerializer.fromJson(
          map,
          registry: reg,
          prefabs: {'Enemy': enemyPrefab},
        );
        expect(s2.name, 'Level1');
        expect(s2.renderSettings.fogEnabled, isTrue);
        expect(s2.renderSettings.fogStart, 25);
        expect(
          s2.find('MainCamera')?.getComponent<Camera>()?.orthographic,
          isTrue,
        );
        expect(s2.find('MainCamera')?.getComponent<Camera>()?.orthoHeight, 16);
        expect(s2.find('Sun')?.parent?.name, 'MainCamera');
        expect(s2.find('Sun')?.getComponent<Light>()?.intensity, 1.8);
        expect(
          s2.find('TriggerZone')?.getComponent<SphereCollider>()?.radius,
          3.5,
        );

        final boss = s2.find('BossEnemy');
        expect(boss, isNotNull);
        expect(boss!.transform.localPosition, const Vec3(10, 0, -5));
        final bossHealth = boss.getComponent<HealthBehaviour>()!;
        expect(bossHealth.hp, 250);
        expect(bossHealth.faction, 'raiders'); // preserved from prefab default

        // Also verify string round-trip
        final s3 = SceneSerializer.fromJsonString(jsonStr, registry: reg);
        expect(s3.find('MainCamera'), isNotNull);
      },
    );
  });

  group('E12 — SaveSystem & EditorSession.duplicate', () {
    test(
      'SaveSystem persists named data slots and full checkpoints, and EditorSession.duplicate clones subtrees',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final beacon = engine.scene.createGameObject(
          'Beacon',
          position: const Vec3(3, 4, 5),
          tag: 'Landmark',
          components: [
            Light.point(
              color: const LinearColor(0.2, 0.8, 1.0),
              intensity: 3.5,
            ),
          ],
        );
        engine.scene.createGameObject(
          'ChildOrb',
          parent: beacon,
          position: const Vec3(0, 1, 0),
        );

        // Duplicate Beacon via EditorSession.duplicate
        final copy = engine.editor.duplicate(beacon);
        expect(copy, isNotNull);
        expect(copy!.name, 'Beacon_Copy');
        expect(copy.tag, 'Landmark');
        expect(copy.transform.localPosition.x, closeTo(3.0, 1e-4));
        expect(copy.getComponent<Light>()?.intensity, closeTo(3.5, 1e-4));
        expect(copy.find('ChildOrb'), isNotNull);

        // Save data + checkpoint into slot 'slot_1'
        engine.saves.saveData('slot_1', {
          'coins': 42,
          'chapter': 'harbour',
        }, summary: 'Harbour Dock');
        engine.saves.saveCheckpoint('slot_1', summary: 'Harbour Dock');

        final slots = engine.saves.listSlots();
        expect(slots.length, 1);
        expect(slots.first.slot, 'slot_1');
        expect(slots.first.hasCheckpoint, isTrue);
        expect(engine.saves.loadData('slot_1')?['coins'], 42);

        // Mutate scene, then restore checkpoint
        beacon.destroy();
        copy.destroy();
        engine.step(0.016);
        expect(engine.scene.find('Beacon'), isNull);

        expect(engine.saves.loadCheckpoint('slot_1'), isTrue);
        expect(engine.scene.find('Beacon'), isNotNull);
        expect(engine.scene.find('Beacon_Copy'), isNotNull);

        engine.saves.deleteSlot('slot_1');
        expect(engine.saves.listSlots(), isEmpty);
      },
    );
  });

  group('E25 — Scene.clone', () {
    test(
      'Scene.clone duplicates GameObjects, components, and hierarchies independently',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final original = engine.scene.createGameObject(
          'Hero',
          tag: 'Player',
          layer: 3,
          position: const Vec3(1, 2, 3),
          components: [
            MeshRenderer(
              meshData: Primitives.cube(),
              tintColor: LinearColor(1, 0, 0),
            ),
            BoxCollider(size: const Vec3(1, 1, 1)),
          ],
        );

        final sword = engine.scene.createGameObject('Sword', parent: original);
        sword.addComponent(
          Light.point(color: LinearColor(1, 1, 0), intensity: 5.0),
        );

        // Clone original to a new position
        final clone = original.clone(
          name: 'HeroClone',
          position: const Vec3(10, 20, 30),
        );

        expect(clone.name, 'HeroClone');
        expect(clone.tag, 'Player');
        expect(clone.layer, 3);
        expect(clone.transform.position, const Vec3(10, 20, 30));

        // Must have own independent MeshRenderer and BoxCollider
        final mr = clone.getComponent<MeshRenderer>();
        expect(mr, isNotNull);
        expect(mr!.tintColor?.r, closeTo(1.0, 1e-4));
        expect(clone.getComponent<BoxCollider>(), isNotNull);

        // Must have duplicated child hierarchy
        expect(clone.children.length, 1);
        final clonedSword = clone.children.first;
        expect(clonedSword.name, 'Sword');
        final light = clonedSword.getComponent<Light>();
        expect(light, isNotNull);
        expect(light!.intensity, 5.0);

        // Modifying clone does not mutate original
        clone.layer = 7;
        mr.tintColor = LinearColor(0, 1, 0);
        expect(original.layer, 3);
        expect(
          original.getComponent<MeshRenderer>()!.tintColor?.r,
          closeTo(1.0, 1e-4),
        );
      },
    );
  });

  group('E98 — PrefabVariants, PrefabRegistry & SceneStreamZone', () {
    test(
      'PrefabRegistry & PrefabVariant apply hierarchical field overrides with cycle protection',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final basePrefab = Prefab('TurretPrefab', (root) {
          root.addComponent(
            Light(type: LightType.point, intensity: 1.0, range: 8.0),
          );
          engine.scene.createGameObject('Barrel', parent: root);
        });

        final registry = PrefabRegistry()
          ..register('turret_base', basePrefab)
          ..registerVariant(
            'turret_heavy',
            const PrefabVariant(
              name: 'HeavyTurret',
              basePrefabId: 'turret_base',
              overrides: [
                PrefabNodeOverride(
                  componentFieldOverrides: {
                    'Light': {'intensity': 3.5, 'range': 16.0},
                  },
                ),
                PrefabNodeOverride(
                  nodePath: 'Barrel',
                  localPosition: Vec3(0.0, 1.0, 2.0),
                  localScale: 1.5,
                ),
              ],
            ),
          );

        final spawned = registry.instantiate(
          engine.scene,
          'turret_heavy',
          position: const Vec3(10.0, 0.0, -5.0),
        );
        expect(spawned.transform.localPosition.x, closeTo(10.0, 1e-6));
        expect(spawned.getComponent<Light>()!.intensity, closeTo(3.5, 1e-6));
        expect(spawned.getComponent<Light>()!.range, closeTo(16.0, 1e-6));
        final barrel = spawned.children.firstWhere((c) => c.name == 'Barrel');
        expect(barrel.transform.localPosition.z, closeTo(2.0, 1e-6));
        expect(barrel.transform.localScale, closeTo(1.5, 1e-6));
        expect(
          registry.exportManifestJson()['registeredIds'],
          contains('turret_heavy'),
        );
      },
    );

    test(
      'SceneStreamZone streams additive chunk objects with distance hysteresis & SceneStreamZoneInspectorUI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final player = engine.scene.createGameObject(
          'PlayerHero',
          tag: 'Player',
          position: const Vec3(50.0, 0.0, 0.0),
        );

        final zoneGo = engine.scene.createGameObject('SectorA');
        final zone = zoneGo.addComponent(
          SceneStreamZone(
              zoneId: 'Sector_A',
              loadRadius: 12.0,
              unloadRadius: 20.0,
              targetTag: 'Player',
            )
            ..zoneBuilder = (scene, owner) => [
              scene.createGameObject('StreamedCrate', parent: owner.gameObject),
              scene.createGameObject('StreamedTorch', parent: owner.gameObject),
            ],
        );

        // Far away -> stays unloaded
        engine.step(0.016);
        expect(zone.state, StreamZoneState.unloaded);
        expect(zone.loadedObjectCount, 0);

        // Move player inside loadRadius (10 <= 12) -> loads chunk
        player.transform.position = const Vec3(10.0, 0.0, 0.0);
        engine.step(0.016);
        expect(zone.state, StreamZoneState.loaded);
        expect(zone.loadedObjectCount, 2);

        // Hysteresis band (16m: >12m but <20m) -> stays loaded
        player.transform.position = const Vec3(16.0, 0.0, 0.0);
        engine.step(0.016);
        expect(zone.state, StreamZoneState.loaded);

        // Move beyond unloadRadius (25m >= 20m) -> unloads cleanly
        player.transform.position = const Vec3(25.0, 0.0, 0.0);
        engine.step(0.016);
        engine.step(0.016);
        expect(zone.state, StreamZoneState.unloaded);

        // Test SceneStreamZoneInspectorUI: click Load button at (148.0, 159.0)
        zone.autoStream = false;
        final ui = VoxUiContext();
        final uiState = SceneStreamZoneUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 148.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        SceneStreamZoneInspectorUI.render(ui, zone, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 148.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        SceneStreamZoneInspectorUI.render(ui, zone, state: uiState);
        final dl = ui.endFrame();
        expect(zone.state, StreamZoneState.loaded);
        expect(zone.loadedObjectCount, 2);
        expect(dl.commands.any((c) => c.text == 'Scene Stream Zone'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('SceneStreamZone'), isNotNull);
      },
    );
  });

  group('E103 — Full ComponentSpec Registry Coverage', () {
    test(
      'E103: ComponentRegistry.defaults instantiates and round-trips every registered ComponentSpec (142+ specs)',
      () {
        final reg = ComponentRegistry.defaults();
        final specs = reg.registeredSpecs.toList();
        // 93 baseline + E94-E98 (5) + E102 (1) + E103 extended (48) = 147 specs.
        expect(specs.length, greaterThanOrEqualTo(142));

        final engine = Engine(HeadlessHost());
        final go = engine.scene.createGameObject('Target');
        for (final spec in specs) {
          final comp = spec.create();
          final json = spec.toJson(comp);
          final restored = spec.create();
          spec.applyJson(restored, json);
          expect(
            restored.runtimeType,
            comp.runtimeType,
            reason: 'Type mismatch on ${spec.typeName}',
          );
          expect(json['type'], spec.typeName);
          if (spec.typeName == 'RigidBody2D' ||
              spec.typeName == 'BoxCollider2D' ||
              spec.typeName == 'AudioLowPassFilterComponent') {
            go.addComponent(restored);
          }
        }
        expect(go.components.length, greaterThanOrEqualTo(4));
      },
    );
  });
}
