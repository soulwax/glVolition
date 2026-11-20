/// Scene & prefab schema migration, envelope validation, and failure tests.
library;

import 'dart:convert';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../support/subsystems_test_helpers.dart';

final class _RenameLegacyFieldV1ToV2 implements SceneMigrationStep {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  Map<String, Object?> migrate(Map<String, Object?> data) {
    final objects = data['objects'] as List<Object?>;
    final first = objects.first as Map<String, Object?>;
    first['tag'] = 'MigratedV2';
    final transform = first['transform'] as Map<String, Object?>;
    final p = transform['p'] as List<Object?>;
    p[0] = (p[0] as num).toDouble() + 10.0;
    return data;
  }
}

final class _UpgradeTagAndAddChildV2ToV3 implements SceneMigrationStep {
  @override
  int get fromVersion => 2;

  @override
  int get toVersion => 3;

  @override
  Map<String, Object?> migrate(Map<String, Object?> data) {
    final objects = data['objects'] as List<Object?>;
    final first = objects.first as Map<String, Object?>;
    first['tag'] = '${first['tag']}_V3';
    final children = first['children'] as List<Object?>;
    children.add(<String, Object?>{
      'name': 'InjectedBeacon',
      'components': <Object?>[
        <String, Object?>{'type': 'Light', 'intensity': 2.5},
      ],
    });
    return data;
  }
}

final class _SelfLoopStep implements SceneMigrationStep {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 1;

  @override
  Map<String, Object?> migrate(Map<String, Object?> data) => data;
}

final class _OvershootStep implements SceneMigrationStep {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 4;

  @override
  Map<String, Object?> migrate(Map<String, Object?> data) => data;
}

void main() {
  group('SceneMigration — Recorded v1 Scene Fixture', () {
    test(
      'migrates recorded v1 scene fixture cleanly with hierarchy, components, and prefab overrides intact',
      () {
        final reg = ComponentRegistry.defaults()
          ..register(HealthBehaviour.spec);
        final sentryPrefab = Prefab('Sentry', (go) {
          go.tag = 'Enemy';
          go.layer = 5;
          go.transform.localScale = 2.0;
          go.addComponent(
            HealthBehaviour(hp: 80, faction: 'drones', speed: 6.5),
          );
        });

        // Recorded v1 fixture intentionally omits newer v2 defaults such as
        // transform.stretch, default tag/layer/active on standard nodes, and
        // newer renderSettings/post subfields.
        final v1SceneFixture = <String, Object?>{
          'schemaVersion': 1,
          'name': 'LegacyDock',
          'renderSettings': <String, Object?>{
            'fogEnabled': true,
            'fogStart': 15.0,
            'fogEnd': 95.0,
            'post': <String, Object?>{'exposure': 1.25, 'toneMapping': 'aces'},
          },
          'objects': <Object?>[
            <String, Object?>{
              'name': 'MainCamera',
              'transform': <String, Object?>{
                'position': <Object?>[0.0, 6.0, 14.0],
                'scale': 1.0,
              },
              'components': <Object?>[
                <String, Object?>{
                  'type': 'Camera',
                  'fovYRadians': 1.0472,
                  'near': 0.2,
                  'far': 500.0,
                },
              ],
              'children': <Object?>[
                <String, Object?>{
                  'name': 'KeyLight',
                  'layer': 2,
                  'transform': <String, Object?>{
                    'p': <Object?>[1.0, 3.0, -2.0],
                  },
                  'components': <Object?>[
                    <String, Object?>{
                      'type': 'Light',
                      'lightType': 'directional',
                      'intensity': 2.2,
                    },
                  ],
                },
                <String, Object?>{
                  'name': 'DisabledTrigger',
                  'active': false,
                  'components': <Object?>[
                    <String, Object?>{
                      'type': 'SphereCollider',
                      'radius': 4.5,
                      'isTrigger': true,
                    },
                  ],
                },
              ],
            },
            <String, Object?>{
              'prefab': 'Sentry',
              'name': 'BossSentry',
              'transform': <String, Object?>{
                'p': <Object?>[12.0, 0.0, -8.0],
              },
              'components': <Object?>[
                <String, Object?>{
                  'type': 'HealthBehaviour',
                  'hp': 300,
                  'enabled': false,
                },
              ],
            },
          ],
        };

        final snapshotBefore = jsonEncode(v1SceneFixture);

        final migrator = SceneMigrator();
        final migrationResult = migrator.migrate(v1SceneFixture);
        expect(migrationResult.fromVersion, 1);
        expect(migrationResult.toVersion, SceneSerializer.schemaVersion);
        expect(migrationResult.didMigrate, isTrue);
        expect(migrationResult.appliedSteps, ['v1->v2', 'v2->v3']);
        expect(
          migrationResult.data['schemaVersion'],
          SceneSerializer.schemaVersion,
        );
        expect(jsonEncode(v1SceneFixture), snapshotBefore);

        final migratedObjects =
            migrationResult.data['objects']! as List<Object?>;
        final camJson = migratedObjects[0]! as Map<String, Object?>;
        final camTransform = camJson['transform']! as Map<String, Object?>;
        expect(camTransform['p'], [0.0, 6.0, 14.0]);
        expect(camTransform['stretch'], [1.0, 1.0, 1.0]);
        expect(camJson['tag'], 'Untagged');

        // Load through SceneSerializer.fromJson and SceneSerializer.fromJsonString.
        final scene = SceneSerializer.fromJson(
          v1SceneFixture,
          registry: reg,
          prefabs: {'Sentry': sentryPrefab},
        );
        expect(jsonEncode(v1SceneFixture), snapshotBefore);

        final sceneFromString = SceneSerializer.fromJsonString(
          snapshotBefore,
          registry: reg,
          prefabs: {'Sentry': sentryPrefab},
        );

        for (final loaded in [scene, sceneFromString]) {
          expect(loaded.name, 'LegacyDock');
          expect(loaded.renderSettings.fogEnabled, isTrue);
          expect(loaded.renderSettings.fogStart, closeTo(15.0, 1e-6));
          expect(loaded.renderSettings.fogEnd, closeTo(95.0, 1e-6));
          expect(loaded.renderSettings.post.exposure, closeTo(1.25, 1e-6));
          expect(loaded.renderSettings.post.toneMapping, ToneMappingMode.aces);

          final cam = loaded.find('MainCamera');
          expect(cam, isNotNull);
          expect(cam!.transform.localPosition, const Vec3(0, 6, 14));
          expect(cam.transform.localStretch, const Vec3(1, 1, 1));
          expect(cam.getComponent<Camera>()?.far, closeTo(500.0, 1e-6));

          final keyLight = loaded.find('KeyLight');
          expect(keyLight, isNotNull);
          expect(keyLight!.parent, same(cam));
          expect(keyLight.layer, 2);
          expect(keyLight.getComponent<Light>()?.intensity, closeTo(2.2, 1e-6));

          final disabledTrigger = loaded.find('DisabledTrigger');
          expect(disabledTrigger, isNotNull);
          expect(disabledTrigger!.activeSelf, isFalse);
          expect(
            disabledTrigger.getComponent<SphereCollider>()?.radius,
            closeTo(4.5, 1e-6),
          );

          final boss = loaded.find('BossSentry');
          expect(boss, isNotNull);
          expect(boss!.tag, 'Enemy');
          expect(boss.layer, 5);
          expect(boss.transform.localScale, closeTo(2.0, 1e-6));
          expect(boss.transform.localPosition, const Vec3(12, 0, -8));
          final health = boss.getComponent<HealthBehaviour>()!;
          expect(health.hp, 300);
          expect(health.faction, 'drones');
          expect(health.enabled, isFalse);
        }

        // Re-serializing produces current schemaVersion and reports no-op migration.
        final v2Json = SceneSerializer.toJson(scene, registry: reg);
        expect(v2Json['schemaVersion'], SceneSerializer.schemaVersion);
        final noopResult = migrator.migrate(v2Json);
        expect(noopResult.didMigrate, isFalse);
        expect(noopResult.appliedSteps, isEmpty);
      },
    );

    test('migrates minimal v1 scene omitting renderSettings', () {
      final minimalV1 = <String, Object?>{
        'schemaVersion': 1,
        'objects': <Object?>[
          <String, Object?>{'name': 'Marker'},
        ],
      };

      final scene = SceneSerializer.fromJson(minimalV1);
      expect(scene.name, 'Scene');
      final marker = scene.find('Marker');
      expect(marker, isNotNull);
      expect(marker!.tag, 'Untagged');
      expect(marker.layer, 0);
      expect(marker.activeSelf, isTrue);
      expect(marker.transform.localStretch, const Vec3(1, 1, 1));
    });
  });

  group('SceneMigration — Recorded v1 Prefab Fixture', () {
    test(
      'migrates recorded v1 prefab JSON fixture and instantiates hierarchy & components cleanly',
      () {
        final reg = ComponentRegistry.defaults()
          ..register(HealthBehaviour.spec);
        final v1PrefabFixture = <String, Object?>{
          'schemaVersion': 1,
          'name': 'LegacyTurret',
          'tag': 'Defense',
          'layer': 3,
          'transform': <String, Object?>{
            'position': <Object?>[4.0, 1.5, -6.0],
            'scale': 1.5,
          },
          'components': <Object?>[
            <String, Object?>{
              'type': 'BoxCollider',
              'size': <Object?>[2.0, 2.0, 2.0],
            },
            <String, Object?>{
              'type': 'HealthBehaviour',
              'hp': 150,
              'faction': 'automated',
            },
          ],
          'children': <Object?>[
            <String, Object?>{
              'name': 'Muzzle',
              'transform': <String, Object?>{
                'p': <Object?>[0.0, 0.75, -1.2],
              },
              'components': <Object?>[
                <String, Object?>{
                  'type': 'Light',
                  'lightType': 'point',
                  'intensity': 3.2,
                },
              ],
            },
            <String, Object?>{'name': 'ReserveCell', 'active': false},
          ],
        };

        final snapshotBefore = jsonEncode(v1PrefabFixture);

        final prefab = Prefab.fromJson(v1PrefabFixture, registry: reg);
        final prefabFromStr = Prefab.fromJsonString(
          snapshotBefore,
          registry: reg,
        );
        expect(jsonEncode(v1PrefabFixture), snapshotBefore);

        final scene = Scene('PrefabArena');
        final spawned = prefab.instantiate(scene);
        expect(spawned.name, 'LegacyTurret');
        expect(spawned.tag, 'Defense');
        expect(spawned.layer, 3);
        expect(spawned.transform.localPosition, const Vec3(4.0, 1.5, -6.0));
        expect(spawned.transform.localScale, closeTo(1.5, 1e-6));
        expect(spawned.transform.localStretch, const Vec3(1, 1, 1));
        expect(
          spawned.getComponent<BoxCollider>()?.size,
          const Vec3(2.0, 2.0, 2.0),
        );
        final health = spawned.getComponent<HealthBehaviour>()!;
        expect(health.hp, 150);
        expect(health.faction, 'automated');

        final muzzle = spawned.find('Muzzle');
        expect(muzzle, isNotNull);
        expect(muzzle!.transform.localPosition, const Vec3(0.0, 0.75, -1.2));
        expect(muzzle.getComponent<Light>()?.intensity, closeTo(3.2, 1e-6));

        final reserve = spawned.find('ReserveCell');
        expect(reserve, isNotNull);
        expect(reserve!.activeSelf, isFalse);

        // Verify spawn overrides preserve explicit name & position on migrated prefab.
        final overridden = prefabFromStr.instantiate(
          scene,
          name: 'TurretWest',
          position: const Vec3(-10, 0, 5),
        );
        expect(overridden.name, 'TurretWest');
        expect(overridden.transform.localPosition, const Vec3(-10, 0, 5));
        expect(overridden.find('Muzzle')?.getComponent<Light>(), isNotNull);
      },
    );
  });

  group('SceneMigration — Multi-Step Custom Migration Chains', () {
    test(
      'executes v1 -> v2 -> v3 steps sequentially without mutating original input fixture',
      () {
        final inputFixture = <String, Object?>{
          'schemaVersion': 1,
          'name': 'CustomChainScene',
          'objects': <Object?>[
            <String, Object?>{
              'name': 'RootNode',
              'tag': 'OldTag',
              'transform': <String, Object?>{
                'p': <Object?>[1.0, 2.0, 3.0],
              },
              'children': <Object?>[],
            },
          ],
        };
        final snapshotBefore = jsonEncode(inputFixture);

        final migrator = SceneMigrator(
          currentVersion: 3,
          steps: [_RenameLegacyFieldV1ToV2(), _UpgradeTagAndAddChildV2ToV3()],
        );

        final result = migrator.migrate(inputFixture);
        expect(result.fromVersion, 1);
        expect(result.toVersion, 3);
        expect(result.didMigrate, isTrue);
        expect(result.appliedSteps, ['v1->v2', 'v2->v3']);
        expect(result.data['schemaVersion'], 3);

        final objects = result.data['objects']! as List<Object?>;
        final root = objects.first! as Map<String, Object?>;
        expect(root['tag'], 'MigratedV2_V3');
        final transform = root['transform']! as Map<String, Object?>;
        expect(transform['p'], [11.0, 2.0, 3.0]);
        final children = root['children']! as List<Object?>;
        expect(children.length, 1);
        expect(
          (children.first! as Map<String, Object?>)['name'],
          'InjectedBeacon',
        );

        // Input fixture (including nested lists/maps) must remain completely untouched.
        expect(jsonEncode(inputFixture), snapshotBefore);
        final origRoot =
            (inputFixture['objects']! as List<Object?>).first!
                as Map<String, Object?>;
        expect(origRoot['tag'], 'OldTag');
        expect((origRoot['children']! as List<Object?>), isEmpty);
        expect(
          ((origRoot['transform']! as Map<String, Object?>)['p']!
              as List<Object?>)[0],
          1.0,
        );

        // Also verify custom migrator plugs cleanly into SceneSerializer.fromJson.
        final scene = SceneSerializer.fromJson(
          inputFixture,
          migrator: migrator,
        );
        expect(scene.find('RootNode')?.tag, 'MigratedV2_V3');
        expect(
          scene.find('RootNode')?.transform.localPosition.x,
          closeTo(11.0, 1e-6),
        );
        expect(
          scene.find('InjectedBeacon')?.getComponent<Light>()?.intensity,
          closeTo(2.5, 1e-6),
        );
        expect(jsonEncode(inputFixture), snapshotBefore);
      },
    );
  });

  group('SceneMigration — Corrupted Payloads & Future Schemas', () {
    test('rejects non-map inputs with FormatException', () {
      final migrator = SceneMigrator();
      expect(() => migrator.migrate('not a map'), throwsFormatException);
      expect(() => migrator.migrate([1, 2, 3]), throwsFormatException);
      expect(() => migrator.migrate(42), throwsFormatException);
      expect(() => migrator.migrate(null), throwsFormatException);
      expect(
        () => SceneSerializer.fromJsonString('[1, 2, 3]'),
        throwsFormatException,
      );
      expect(
        () => SceneSerializer.fromJsonString('"hello"'),
        throwsFormatException,
      );
      expect(() => Prefab.fromJsonString('[1, 2, 3]'), throwsFormatException);
    });

    test(
      'rejects missing, non-int, negative, and unsupported v0 schemaVersion',
      () {
        final migrator = SceneMigrator();
        final missing = <String, Object?>{'name': 'NoVersion', 'objects': []};
        final nullVer = <String, Object?>{'schemaVersion': null, 'objects': []};
        final stringVer = <String, Object?>{
          'schemaVersion': '1',
          'objects': [],
        };
        final doubleVer = <String, Object?>{
          'schemaVersion': 1.5,
          'objects': [],
        };
        final boolVer = <String, Object?>{'schemaVersion': true, 'objects': []};
        final negativeVer = <String, Object?>{
          'schemaVersion': -1,
          'objects': [],
        };
        final zeroVer = <String, Object?>{'schemaVersion': 0, 'objects': []};

        for (final bad in [
          missing,
          nullVer,
          stringVer,
          doubleVer,
          boolVer,
          negativeVer,
          zeroVer,
        ]) {
          expect(() => migrator.migrate(bad), throwsFormatException);
          expect(() => SceneSerializer.fromJson(bad), throwsFormatException);
        }

        for (final badPrefab in [
          <String, Object?>{'name': 'NoVersion'},
          <String, Object?>{'schemaVersion': '1', 'name': 'BadStr'},
          <String, Object?>{'schemaVersion': 1.5, 'name': 'BadFloat'},
          <String, Object?>{'schemaVersion': -2, 'name': 'Neg'},
        ]) {
          expect(() => Prefab.fromJson(badPrefab), throwsFormatException);
        }
      },
    );

    test('rejects future-unsupported schemaVersion > currentVersion', () {
      final futureScene = <String, Object?>{
        'schemaVersion': 999,
        'name': 'Future',
        'objects': <Object?>[],
      };
      final futurePrefab = <String, Object?>{
        'schemaVersion': 999,
        'name': 'FuturePrefab',
      };

      expect(() => SceneMigrator().migrate(futureScene), throwsFormatException);
      expect(
        () => SceneSerializer.fromJson(futureScene),
        throwsFormatException,
      );
      expect(
        () => SceneSerializer.fromJsonString(jsonEncode(futureScene)),
        throwsFormatException,
      );
      expect(() => Prefab.fromJson(futurePrefab), throwsFormatException);
      expect(
        () => Prefab.fromJsonString(jsonEncode(futurePrefab)),
        throwsFormatException,
      );
    });

    test(
      'rejects missing required structural fields and mismatched payload kinds',
      () {
        final migrator = SceneMigrator();

        // Empty envelope with only schemaVersion.
        expect(
          () => migrator.migrate(<String, Object?>{'schemaVersion': 1}),
          throwsFormatException,
        );
        expect(
          () => SceneSerializer.fromJson(<String, Object?>{'schemaVersion': 1}),
          throwsFormatException,
        );
        expect(
          () => Prefab.fromJson(<String, Object?>{'schemaVersion': 1}),
          throwsFormatException,
        );

        // Scene missing required objects list.
        expect(
          () => SceneSerializer.fromJson(<String, Object?>{
            'schemaVersion': 2,
            'name': 'MissingObjects',
          }),
          throwsFormatException,
        );

        // Prefab missing required name.
        expect(
          () => Prefab.fromJson(<String, Object?>{
            'schemaVersion': 2,
            'components': <Object?>[],
          }),
          throwsFormatException,
        );

        // Scene payload passed to Prefab.fromJson & Prefab payload passed to SceneSerializer.
        expect(
          () => Prefab.fromJson(<String, Object?>{
            'schemaVersion': 1,
            'name': 'ActuallyAScene',
            'objects': <Object?>[],
          }),
          throwsFormatException,
        );
        expect(
          () => SceneSerializer.fromJson(<String, Object?>{
            'schemaVersion': 1,
            'name': 'ActuallyAPrefab',
            'components': <Object?>[],
          }),
          throwsFormatException,
        );
      },
    );

    test(
      'rejects invalid node, transform, component, and renderSettings structures',
      () {
        final badPayloads = <Map<String, Object?>>[
          {
            'schemaVersion': 1,
            'name': 'BadObjectsType',
            'objects': 'not-a-list',
          },
          {
            'schemaVersion': 2,
            'name': 'BadNodeEntry',
            'objects': [42],
          },
          {
            'schemaVersion': 2,
            'name': 'EmptyNode',
            'objects': [<String, Object?>{}],
          },
          {
            'schemaVersion': 2,
            'name': 'OutOfRangeLayer',
            'objects': [
              <String, Object?>{'name': 'Obj', 'layer': 32},
            ],
          },
          {
            'schemaVersion': 1,
            'name': 'BadTransformType',
            'objects': [
              <String, Object?>{'name': 'Obj', 'transform': 'bad'},
            ],
          },
          {
            'schemaVersion': 2,
            'name': 'BadTransformVec3',
            'objects': [
              <String, Object?>{
                'name': 'Obj',
                'transform': <String, Object?>{
                  'p': [1.0, 2.0],
                },
              },
            ],
          },
          {
            'schemaVersion': 2,
            'name': 'BadTransformQuat',
            'objects': [
              <String, Object?>{
                'name': 'Obj',
                'transform': <String, Object?>{
                  'r': [0.0, 0.0, 'bad', 1.0],
                },
              },
            ],
          },
          {
            'schemaVersion': 2,
            'name': 'ComponentMissingType',
            'objects': [
              <String, Object?>{
                'name': 'Obj',
                'components': [
                  <String, Object?>{'intensity': 1.0},
                ],
              },
            ],
          },
          {
            'schemaVersion': 1,
            'name': 'BadChildrenType',
            'objects': [
              <String, Object?>{'name': 'Obj', 'children': 'bad'},
            ],
          },
          {
            'schemaVersion': 2,
            'name': 'BadNestedChild',
            'objects': [
              <String, Object?>{
                'name': 'Obj',
                'children': ['invalid-child'],
              },
            ],
          },
          {
            'schemaVersion': 2,
            'name': 'BadRenderSettings',
            'renderSettings': 'invalid',
            'objects': <Object?>[],
          },
          {
            'schemaVersion': 2,
            'name': 'BadRenderSettingsColor',
            'renderSettings': <String, Object?>{
              'clearColor': [1.0, 2.0],
            },
            'objects': <Object?>[],
          },
        ];

        for (final payload in badPayloads) {
          expect(
            () => SceneSerializer.fromJson(payload),
            throwsFormatException,
            reason: 'Expected FormatException for ${payload['name']}',
          );
        }

        // Also validate bad prefab node structure.
        expect(
          () => Prefab.fromJson(<String, Object?>{
            'schemaVersion': 1,
            'name': 'BadPrefabChild',
            'children': [
              <String, Object?>{'components': 'bad'},
            ],
          }),
          throwsFormatException,
        );
      },
    );

    test('rejects broken migration step chains', () {
      final v1Input = <String, Object?>{
        'schemaVersion': 1,
        'name': 'Chain',
        'objects': <Object?>[
          <String, Object?>{
            'name': 'Root',
            'transform': <String, Object?>{
              'p': <Object?>[0.0, 0.0, 0.0],
            },
            'children': <Object?>[],
          },
        ],
      };

      // Missing v2 -> v3 step.
      final incompleteTail = SceneMigrator(
        currentVersion: 3,
        steps: [_RenameLegacyFieldV1ToV2()],
      );
      expect(() => incompleteTail.migrate(v1Input), throwsFormatException);

      // Missing v1 -> v2 step.
      final incompleteHead = SceneMigrator(
        currentVersion: 3,
        steps: [_UpgradeTagAndAddChildV2ToV3()],
      );
      expect(() => incompleteHead.migrate(v1Input), throwsFormatException);

      // Empty steps list when migration is needed.
      final noSteps = SceneMigrator(currentVersion: 2, steps: const []);
      expect(() => noSteps.migrate(v1Input), throwsFormatException);

      // Self-loop step v1 -> v1.
      final selfLoop = SceneMigrator(
        currentVersion: 2,
        steps: [_SelfLoopStep()],
      );
      expect(() => selfLoop.migrate(v1Input), throwsFormatException);

      // Step overshooting target currentVersion (v1 -> v4 when target is v3).
      final overshoot = SceneMigrator(
        currentVersion: 3,
        steps: [_OvershootStep()],
      );
      expect(() => overshoot.migrate(v1Input), throwsFormatException);
    });
  });
}
