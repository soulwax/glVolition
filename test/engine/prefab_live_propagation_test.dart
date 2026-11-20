/// Live PrefabRegistry instance tagging, structural diffing, variant extraction,
/// and hot-propagation tests (P10-W18-C).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P10-W18-C — PrefabRegistry Live Diff, Extraction & Hot-Propagation', () {
    test(
      'instantiate attaches PrefabInstanceComponent and extracts variant overrides accurately',
      () {
        final engine = Engine(HeadlessHost());
        final registry = PrefabRegistry();

        registry.register(
          'turret_base',
          Prefab('Turret', (root) {
            root.addComponent(BoxCollider(size: const Vec3(1, 1, 1)));
            final barrel = root.scene.createGameObject(
              'Barrel',
              parent: root,
              position: const Vec3(0, 1, 0),
            );
            barrel.addComponent(Light.point(intensity: 1.0, range: 5.0));
          }),
        );

        final inst = registry.instantiate(engine.scene, 'turret_base');
        final instComp = inst.getComponent<PrefabInstanceComponent>();
        expect(instComp, isNotNull);
        expect(instComp!.prefabName, equals('turret_base'));

        // Mutate root collider and child barrel transform + light
        inst.getComponent<BoxCollider>()!.size = const Vec3(2, 2, 2);
        final barrel = inst.find('Barrel')!;
        barrel.transform.localPosition = const Vec3(0, 2.5, -1);
        barrel.getComponent<Light>()!.intensity = 4.5;

        final overrides = registry.computeInstanceOverrides(inst);
        expect(overrides.length, equals(2));

        final variant = registry.extractVariantFromInstance(
          'HeavyTurret',
          inst,
        );
        registry.registerVariant('turret_heavy', variant);

        // Instantiating the extracted variant reproduces all mutations
        final cloned = registry.instantiate(engine.scene, 'turret_heavy');
        expect(cloned.getComponent<BoxCollider>()!.size.x, closeTo(2.0, 1e-4));
        final clonedBarrel = cloned.find('Barrel')!;
        expect(clonedBarrel.transform.localPosition.y, closeTo(2.5, 1e-4));
        expect(
          clonedBarrel.getComponent<Light>()!.intensity,
          closeTo(4.5, 1e-4),
        );
      },
    );

    test(
      'propagatePrefabChanges updates live instances while preserving placement and overrides',
      () {
        final engine = Engine(HeadlessHost());
        final registry = PrefabRegistry();

        registry.register(
          'lamp',
          Prefab('Lamp', (root) {
            root.addComponent(Light.point(intensity: 1.0, range: 6.0));
          }),
        );

        final lampA = registry.instantiate(
          engine.scene,
          'lamp',
          name: 'Lamp_A',
          position: const Vec3(5, 0, 0),
        );
        lampA.getComponent<Light>()!.intensity = 3.5;

        final lampB = registry.instantiate(
          engine.scene,
          'lamp',
          name: 'Lamp_B',
          position: const Vec3(-5, 0, 0),
        );

        // Capture Lamp_A's overrides before modifying base prefab
        final lampAOverrides = registry.computeInstanceOverrides(lampA);

        // Update base prefab definition: add a Shield child and change default range
        registry.register(
          'lamp',
          Prefab('Lamp', (root) {
            root.addComponent(Light.point(intensity: 1.0, range: 14.0));
            root.scene.createGameObject(
              'Shield',
              parent: root,
              position: const Vec3(0, 1.5, 0),
            );
          }),
        );

        final updatedCount = registry.propagatePrefabChanges(
          engine.scene,
          'lamp',
          preservedOverridesByObjectName: {'Lamp_A': lampAOverrides},
        );
        expect(updatedCount, equals(2));
        expect(lampA.isDestroyed, isTrue);
        expect(lampB.isDestroyed, isTrue);

        final newA = engine.scene.find('Lamp_A')!;
        final newB = engine.scene.find('Lamp_B')!;

        // Both instances receive the new child & updated default range
        expect(newA.find('Shield'), isNotNull);
        expect(newB.find('Shield'), isNotNull);
        expect(newB.getComponent<Light>()!.range, closeTo(14.0, 1e-4));

        // Both preserve their world/local positions, and Lamp_A preserves intensity override
        expect(newA.transform.localPosition.x, closeTo(5.0, 1e-4));
        expect(newB.transform.localPosition.x, closeTo(-5.0, 1e-4));
        expect(newA.getComponent<Light>()!.intensity, closeTo(3.5, 1e-4));
      },
    );
  });
}
