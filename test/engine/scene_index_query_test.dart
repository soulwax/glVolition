/// Indexed Scene tag/node lookups, component archetype queries, and indexed renderer sync tests (P9-W17-A).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P9-W17-A — Indexed Scene Tag & Node Lookups', () {
    test(
      'tag index tracks creation, live tag mutation, inactive toggle, and destruction',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final a = scene.createGameObject('Alpha', tag: 'Enemy');
        final b = scene.createGameObject('Beta', tag: 'Enemy');
        final c = scene.createGameObject('Gamma', tag: 'Friendly');

        expect(
          scene.findGameObjectsWithTag('Enemy').map((g) => g.name).toList(),
          equals(['Alpha', 'Beta']),
        );
        expect(scene.findWithTag('Friendly'), same(c));

        // Live tag mutation re-indexes immediately.
        b.tag = 'Friendly';
        expect(
          scene.findGameObjectsWithTag('Enemy').map((g) => g.name).toList(),
          equals(['Alpha']),
        );
        expect(
          scene.findGameObjectsWithTag('Friendly').map((g) => g.name).toList(),
          equals(['Gamma', 'Beta']),
        );

        // Inactive objects are excluded from active tag queries.
        a.setActive(false);
        expect(scene.findGameObjectsWithTag('Enemy'), isEmpty);
        a.setActive(true);
        expect(scene.findWithTag('Enemy'), same(a));

        // Destruction removes from index cleanly.
        b.destroy();
        expect(
          scene.findGameObjectsWithTag('Friendly').map((g) => g.name).toList(),
          equals(['Gamma']),
        );
        engine.step(0.016);
        expect(
          scene.findGameObjectsWithTag('Friendly').map((g) => g.name).toList(),
          equals(['Gamma']),
        );
      },
    );

    test(
      'raycastVisuals resolves owner via indexed node map across create and destroy',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final cube = scene.createPrimitive(
          PrimitiveType.cube,
          name: 'TargetCube',
          position: Vec3.zero,
        );
        engine.step(0.016);

        final hit = scene.raycastVisuals(
          Ray(origin: const Vec3(0, 0, 5), direction: const Vec3(0, 0, -1)),
        );
        expect(hit, isNotNull);
        expect(hit!.$1, same(cube));

        cube.destroy();
        engine.step(0.016);

        final afterDestroy = scene.raycastVisuals(
          Ray(origin: const Vec3(0, 0, 5), direction: const Vec3(0, 0, -1)),
        );
        expect(afterDestroy, isNull);
      },
    );
  });

  group('P9-W17-A — Component Archetype Queries', () {
    test(
      'query, query2, and query3 filter by components, tag, layerMask, and active state',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final e1 = scene.createGameObject('E1', tag: 'Unit', layer: 1);
        e1.addComponent(RigidBody());
        e1.addComponent(BoxCollider(size: const Vec3(1, 1, 1)));
        e1.addComponent(Light.point());

        final e2 = scene.createGameObject('E2', tag: 'Unit', layer: 2);
        e2.addComponent(RigidBody());
        e2.addComponent(BoxCollider(size: const Vec3(1, 1, 1)));

        final e3 = scene.createGameObject('E3', tag: 'Prop', layer: 1);
        e3.addComponent(RigidBody());
        e3.addComponent(BoxCollider(size: const Vec3(1, 1, 1)));

        final inactiveObj = scene.createGameObject(
          'Inactive',
          tag: 'Unit',
          layer: 1,
          active: false,
        );
        inactiveObj.addComponent(RigidBody());
        inactiveObj.addComponent(BoxCollider(size: const Vec3(1, 1, 1)));

        expect(
          scene.query<RigidBody>().map((r) => r.$1.name).toList(),
          equals(['E1', 'E2', 'E3']),
        );
        expect(
          scene.query<RigidBody>(tag: 'Unit').map((r) => r.$1.name).toList(),
          equals(['E1', 'E2']),
        );
        expect(
          scene
              .query<RigidBody>(tag: 'Unit', includeInactive: true)
              .map((r) => r.$1.name)
              .toList(),
          equals(['E1', 'E2', 'Inactive']),
        );
        expect(
          scene
              .query2<RigidBody, BoxCollider>(
                tag: 'Unit',
                layerMask: LayerMask.fromLayer(1),
              )
              .map((r) => r.$1.name)
              .toList(),
          equals(['E1']),
        );
        expect(
          scene
              .query3<RigidBody, BoxCollider, Light>()
              .map((r) => (r.$1.name, r.$2, r.$3, r.$4))
              .single
              .$1,
          equals('E1'),
        );
      },
    );
  });
}
