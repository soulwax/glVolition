/// S5-D test: Verifies 2-level nested prefab propagation, outermost-wins
/// override precedence, variant-of-variant chains, isolated Prefab Mode
/// breadcrumbs, and broken-reference detection + repair.
library;

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S5-D — Nested Prefabs, Variant Chains & Prefab Mode', () {
    test(
      '2-level nested propagation, outermost-wins overrides & Prefab Mode breadcrumbs',
      () {
        final stage = PrefabModeStage();

        // Level 0 (leaf): Turret
        stage.register(
          const NestedPrefabAsset(
            id: 'prefab_turret',
            name: 'Turret',
            properties: {'damage': 10, 'color': 'gray'},
          ),
        );
        // Level 1: Vehicle containing a Turret child with override
        stage.register(
          const NestedPrefabAsset(
            id: 'prefab_tank',
            name: 'Tank',
            properties: {'armor': 100},
            children: [
              NestedPrefabChildRef(
                instanceName: 'MainTurret',
                prefabId: 'prefab_turret',
                overrides: {'color': 'olive'},
              ),
            ],
          ),
        );
        // Level 2: Squad containing a Tank
        stage.register(
          const NestedPrefabAsset(
            id: 'prefab_squad',
            name: 'Squad',
            children: [
              NestedPrefabChildRef(
                instanceName: 'LeadTank',
                prefabId: 'prefab_tank',
              ),
            ],
          ),
        );

        // Edit leaf Turret inside isolated Prefab Mode
        stage.openPrefab('prefab_turret');
        expect(stage.isInPrefabMode, isTrue);
        expect(stage.breadcrumbs, equals(['prefab_turret']));
        stage.setWorkingProperty('damage', 25);
        stage.saveAndExit();
        expect(stage.isInPrefabMode, isFalse);

        // Verify 2-level propagation to Squad -> LeadTank -> MainTurret
        final squad = stage.resolve('prefab_squad');
        final turret = squad.children.single.children.single;
        expect(turret.properties['damage'], equals(25));
        // Outermost override ('olive') beats leaf default ('gray')
        expect(turret.properties['color'], equals('olive'));
      },
    );

    test('variant-of-variant chain and broken-reference repair', () {
      final stage = PrefabModeStage();
      stage.register(
        const NestedPrefabAsset(
          id: 'enemy_base',
          name: 'EnemyBase',
          properties: {'hp': 50, 'speed': 3.0},
        ),
      );
      stage.register(
        const NestedPrefabAsset(
          id: 'enemy_elite',
          name: 'EnemyElite',
          basePrefabId: 'enemy_base',
          properties: {'hp': 120},
        ),
      );
      stage.register(
        const NestedPrefabAsset(
          id: 'enemy_boss',
          name: 'EnemyBoss',
          basePrefabId: 'enemy_elite',
          properties: {'scale': 2.0},
          children: [
            NestedPrefabChildRef(
              instanceName: 'Weapon',
              prefabId: 'missing_sword_guid',
            ),
          ],
        ),
      );

      final boss = stage.resolve('enemy_boss');
      expect(boss.properties['hp'], equals(120));
      expect(boss.properties['speed'], equals(3.0));
      expect(boss.properties['scale'], equals(2.0));

      // Detect and repair broken reference
      final broken = stage.findBrokenReferences();
      expect(broken, hasLength(1));
      expect(broken.single.missingPrefabId, equals('missing_sword_guid'));

      stage.register(
        const NestedPrefabAsset(
          id: 'sword_v2',
          name: 'SwordV2',
          properties: {'atk': 40},
        ),
      );
      expect(
        stage.repairBrokenReference('missing_sword_guid', 'sword_v2'),
        equals(1),
      );
      expect(stage.findBrokenReferences(), isEmpty);
      expect(
        stage.resolve('enemy_boss').children.single.properties['atk'],
        equals(40),
      );
    });
  });
}
