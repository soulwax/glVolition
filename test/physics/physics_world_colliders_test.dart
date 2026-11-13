/// 3D & 2D physics world queries, rigidbodies, colliders, raycasters, layers & joints.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../support/subsystems_test_helpers.dart';

void main() {
  group('E4 — Tilemap Circle Collision', () {
    test(
      'TilemapComponent.moveAndSlideCircle slides along solid tiles without penetrating',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final layer = TileLayer(
          columns: 8,
          rows: 8,
          tileWidth: 16,
          tileHeight: 16,
          tileset: [SpriteRegion.white, SpriteRegion.white],
        );
        // Place a solid wall at column 3, rows 0..7
        for (var r = 0; r < 8; r++) {
          layer.setTile(3, r, 1);
        }

        final tm = TilemapComponent(layer, solidTiles: {1});
        engine.scene.createGameObject('Map', components: [tm]);

        // Circle of radius 4 at (42, 32) moving (+10, +12) diagonally into wall at x = 3*16 = 48
        final next = tm.moveAndSlideCircle(
          const Vec2(42, 32),
          const Vec2(10, 12),
          4,
        );
        // X must be clamped to left edge of wall minus radius (48 - 4 = 44), while Y slides freely to 44
        expect(next.x, closeTo(44.0, 1e-4));
        expect(next.y, closeTo(44.0, 1e-4));
      },
    );
  });

  group('E9 — RigidBody Gravity & Solid Collision', () {
    test(
      'RigidBody integrates gravity, resolves solid sphere-box collision, and fires onCollisionEnter',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        Collision? recordedCollision;
        final ball = engine.scene.createGameObject(
          'Ball',
          position: const Vec3(0, 2.0, 0),
          components: [
            SphereCollider(radius: 0.5, isTrigger: false),
            RigidBody(restitution: 0.8, linearDrag: 0.0),
            CollisionSpy((c) => recordedCollision = c),
          ],
        );
        engine.scene.createGameObject(
          'Floor',
          position: const Vec3(0, -0.5, 0),
          components: [
            BoxCollider(size: const Vec3(10, 1, 10), isTrigger: false),
            RigidBody(isKinematic: true, restitution: 0.8),
          ],
        );

        for (var i = 0; i < 45; i++) {
          engine.step(1 / 60);
        }

        expect(recordedCollision, isNotNull);
        expect(recordedCollision!.other.gameObject.name, 'Floor');
        expect(recordedCollision!.contactNormal.y, closeTo(1.0, 1e-4));
        // Ball should have bounced upward and stayed above the floor surface (y = 0)
        expect(ball.transform.position.y, greaterThanOrEqualTo(0.45));
      },
    );
  });

  group('E10 — CharacterController 3D Sliding & Grounding', () {
    test(
      'CharacterController slides along solid BoxCollider and grounds on floor',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        engine.scene.createGameObject(
          'Floor',
          position: const Vec3(0, -0.5, 0),
          components: [
            BoxCollider(size: const Vec3(20, 1, 20), isTrigger: false),
          ],
        );
        engine.scene.createGameObject(
          'Wall',
          position: const Vec3(2.0, 1.0, 0),
          components: [
            BoxCollider(size: const Vec3(1, 3, 6), isTrigger: false),
          ],
        );

        final cc = CharacterController(
          radius: 0.4,
          height: 1.8,
          center: const Vec3(0, 0.9, 0),
        );
        final player = engine.scene.createGameObject(
          'Player',
          position: const Vec3(0, 0.2, 0),
          components: [cc],
        );

        // Step downward + forward into the floor and toward the wall at x=1.5
        final flags = cc.move(const Vec3(3.0, -0.5, 1.5));
        expect(cc.isGrounded, isTrue);
        expect(flags & CollisionFlags.below, isNonZero);
        expect(flags & CollisionFlags.sides, isNonZero);
        // Stopped outside the wall's -X face (wall min.x = 1.5, minus radius ~0.42)
        expect(player.transform.position.x, lessThanOrEqualTo(1.12));
        // Still slid along Z!
        expect(player.transform.position.z, closeTo(1.5, 1e-3));
      },
    );
  });

  group('E12 — Spatial Physics Queries', () {
    test(
      'PhysicsWorld overlapBox, raycastAll, and sphereCast query colliders accurately',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        engine.scene.createGameObject(
          'CrateA',
          position: const Vec3(0, 0, -4),
          components: [
            BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
          ],
        );
        engine.scene.createGameObject(
          'CrateB',
          position: const Vec3(0, 0, -9),
          components: [SphereCollider(radius: 0.8, isTrigger: true)],
        );
        engine.scene.createGameObject(
          'OffsetTarget',
          position: const Vec3(1.2, 0, -6),
          components: [SphereCollider(radius: 0.5, isTrigger: false)],
        );

        final boxHits = engine.physics
            .overlapBox(Aabb(const Vec3(-2, -2, -5), const Vec3(2, 2, -3)))
            .map((c) => c.gameObject.name)
            .toList();
        expect(boxHits, ['CrateA']);

        final ray = Ray(
          origin: const Vec3(0, 0, 0),
          direction: const Vec3(0, 0, -1),
        );
        final allHits = engine.physics.raycastAll(ray);
        expect(allHits.map((h) => h.gameObject.name).toList(), [
          'CrateA',
          'CrateB',
        ]);
        expect(allHits[0].distance, lessThan(allHits[1].distance));

        // Excluding triggers omits CrateB
        final solidHits = engine.physics.raycastAll(
          ray,
          includeTriggers: false,
        );
        expect(solidHits.map((h) => h.gameObject.name).toList(), ['CrateA']);

        // Thin ray along X=0 misses OffsetTarget at X=1.2 (radius 0.5 -> min X=0.7),
        // but sphereCast with radius 0.8 hits it!
        final sweepHit = engine.physics.sphereCast(
          Ray(origin: const Vec3(0, 0, -6), direction: const Vec3(1, 0, 0)),
          0.8,
        );
        expect(sweepHit, isNotNull);
        expect(sweepHit!.gameObject.name, 'OffsetTarget');
      },
    );
  });

  group('E13 — CapsuleCollider Intersection & Serialization', () {
    test(
      'CapsuleCollider intersects spheres/boxes/rays and round-trips via SceneSerializer',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final pillar = engine.scene.createGameObject(
          'Pillar',
          position: const Vec3(0, 1.0, -5.0),
          components: [
            CapsuleCollider(radius: 0.5, height: 2.0, isTrigger: false),
          ],
        );

        // Ray aimed at top hemisphere (y = 1.5) hits Pillar
        final hit = engine.physics.raycast(
          const Ray(origin: Vec3(0, 1.5, 0), direction: Vec3(0, 0, -1)),
        );
        expect(hit, isNotNull);
        expect(hit!.gameObject, same(pillar));

        // Overlap sphere near bottom hemisphere (y = 0.5) hits Pillar
        final overlaps = engine.physics
            .overlapSphere(const Vec3(0.4, 0.5, -5.0), 0.3)
            .toList();
        expect(overlaps.length, 1);
        expect(overlaps.first.gameObject, same(pillar));

        // Serialization round-trip preserves CapsuleCollider radius and height
        final json = SceneSerializer.toJson(
          engine.scene,
          registry: engine.registry,
        );
        final restored = SceneSerializer.fromJson(
          json,
          registry: engine.registry,
        );
        final restoredCap = restored
            .find('Pillar')
            ?.getComponent<CapsuleCollider>();
        expect(restoredCap, isNotNull);
        expect(restoredCap!.radius, closeTo(0.5, 1e-5));
        expect(restoredCap.height, closeTo(2.0, 1e-5));
      },
    );
  });

  group('E14 — Capsule Contact Manifolds', () {
    test(
      'Capsule RigidBody rests on a box floor and bounces off spheres with axis-accurate normals',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        engine.scene.createGameObject(
          'Floor',
          position: const Vec3(0, -0.5, 0),
          components: [
            BoxCollider(size: const Vec3(20, 1, 20), isTrigger: false),
          ],
        );
        final capsule = engine.scene.createGameObject(
          'Capsule',
          position: const Vec3(0, 3, 0),
          components: [
            CapsuleCollider(radius: 0.5, height: 2.0, isTrigger: false),
            RigidBody(restitution: 0.0, linearDrag: 0.0),
          ],
        );

        for (var i = 0; i < 240; i++) {
          engine.step(1 / 60);
        }
        // Capsule half-height is 1.0, so its centre settles near y == 1.
        expect(capsule.transform.position.y, closeTo(1.0, 0.15));
        expect(
          capsule.getComponent<RigidBody>()!.velocity.y.abs(),
          lessThan(1.0),
        );

        // A sphere touching the capsule's side gets a horizontal normal, not a
        // vertical AABB face normal.
        final probe = engine.scene.createGameObject(
          'Probe',
          position: Vec3(0.8, capsule.transform.position.y + 0.6, 0),
          components: [SphereCollider(radius: 0.4, isTrigger: false)],
        );
        final manifold = PhysicsWorld.debugManifold(
          capsule.getComponent<CapsuleCollider>()!,
          probe.getComponent<SphereCollider>()!,
        );
        expect(manifold, isNotNull);
        expect(manifold!.$1.x, greaterThan(0.99));
        expect(manifold.$2, greaterThan(0));
      },
    );
  });

  group('E16 — PhysicsRaycaster 3D Interaction & LayerMask', () {
    test(
      'PhysicsRaycaster dispatches enter, down, up, click, and exit to 3D Behaviour colliders',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        engine.scene.createGameObject(
          'MainCamera',
          position: const Vec3(0, 0, 5),
          components: [Camera(), PhysicsRaycaster()],
        );

        final spy = PointerSpy();
        final target = engine.scene.createGameObject(
          'InteractiveChest',
          position: const Vec3(0, 0, 0),
          components: [
            BoxCollider(size: const Vec3(2, 2, 2)),
            spy,
          ],
        );

        // Frame 1: Pointer at (640, 360) aiming straight through center at target.
        host.input.pointerX = 640;
        host.input.pointerY = 360;
        engine.step(0.016);
        expect(spy.events, ['enter']);
        expect(spy.lastHit?.gameObject, same(target));

        // Frame 2: Pointer pressed -> fires onPointerDown.
        host.input.pointerPressed = true;
        host.input.pointerDown = true;
        engine.step(0.016);
        expect(spy.events, ['enter', 'down']);

        // Frame 3: Pointer released over same target -> fires onPointerUp and onPointerClick.
        host.input.pointerPressed = false;
        host.input.pointerReleased = true;
        host.input.pointerDown = false;
        engine.step(0.016);
        expect(spy.events, ['enter', 'down', 'up', 'click']);

        // Frame 4: Pointer moves away to (50, 50) -> fires onPointerExit.
        host.input.pointerReleased = false;
        host.input.pointerX = 50;
        host.input.pointerY = 50;
        engine.step(0.016);
        expect(spy.events, ['enter', 'down', 'up', 'click', 'exit']);
      },
    );

    test('LayerMask calculates bitmasks and filters physics queries', () {
      expect(LayerMask.none.value, 0);
      expect(LayerMask.all.value, -1);
      expect(LayerMask.defaultLayer.value, 1);

      final mask = LayerMask.fromLayers([1, 3, 5]);
      expect(mask.contains(0), isFalse);
      expect(mask.contains(1), isTrue);
      expect(mask.contains(2), isFalse);
      expect(mask.contains(3), isTrue);
      expect(mask.contains(5), isTrue);

      final modified = mask.withLayer(2).withoutLayer(1);
      expect(modified.contains(1), isFalse);
      expect(modified.contains(2), isTrue);

      // Verify layer mask filtering in PhysicsWorld
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.scene.createGameObject(
        'HiddenObstacle',
        layer: 8,
        position: const Vec3(0, 0, 0),
        components: [BoxCollider(size: const Vec3(2, 2, 2))],
      );

      final ray = const Ray(origin: Vec3(0, 0, 5), direction: Vec3(0, 0, -1));

      // Query excluding layer 8 finds nothing
      final hitDefault = engine.scene.physics.raycast(
        ray,
        layerMask: LayerMask.fromLayer(0),
      );
      expect(hitDefault, isNull);

      // Query including layer 8 hits HiddenObstacle
      final hitLayer8 = engine.scene.physics.raycast(
        ray,
        layerMask: LayerMask.fromLayer(8),
      );
      expect(hitLayer8, isNotNull);
      expect(hitLayer8!.gameObject.name, 'HiddenObstacle');
    });
  });

  group('E17 — Layer Collision Matrix & Radial Explosion Impulses', () {
    test(
      'PhysicsWorld layer collision matrix selectively disables layer-pair collisions',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final physics = engine.scene.physics;

        // By default all 32x32 layers can collide
        expect(physics.getLayerCollision(2, 2), isTrue);
        expect(physics.getLayerCollision(0, 1), isTrue);

        engine.scene.createGameObject(
          'DebrisA',
          layer: 2,
          position: const Vec3(0, 0, 0),
          components: [SphereCollider(radius: 1.0, isTrigger: true)],
        );
        engine.scene.createGameObject(
          'DebrisB',
          layer: 2,
          position: const Vec3(0.5, 0, 0),
          components: [SphereCollider(radius: 1.0, isTrigger: true)],
        );

        // Disable layer 2 vs layer 2 collision
        physics.setLayerCollision(2, 2, false);
        expect(physics.getLayerCollision(2, 2), isFalse);

        engine.step(0.05);
        expect(physics.contactPairs.length, 0);

        // Re-enable layer 2 vs layer 2 collision
        physics.setLayerCollision(2, 2, true);
        expect(physics.getLayerCollision(2, 2), isTrue);

        engine.step(0.05);
        expect(physics.contactPairs.length, 1);
      },
    );

    test(
      'RigidBody and PhysicsWorld radial explosion impulse applies outward velocity and upwards loft',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final body = engine.scene
            .createGameObject(
              'Barrel',
              position: const Vec3(2, 0, 0),
              components: [
                SphereCollider(radius: 0.5),
                RigidBody(useGravity: false, linearDrag: 0.0),
              ],
            )
            .getComponent<RigidBody>()!;

        // Explosion at origin, radius 5, force 10
        // Distance is 2, factor is (1 - 2/5) = 0.6 -> impulse 6 along +X
        body.addExplosionForce(10.0, Vec3.zero, 5.0, upwardsModifier: 1.5);
        expect(body.velocity.x, greaterThan(0));
        expect(
          body.velocity.y,
          greaterThan(0),
        ); // lifted upwards by upwardsModifier

        // Multiple bodies via PhysicsWorld.addExplosionForce
        final farBody = engine.scene
            .createGameObject(
              'FarBarrel',
              position: const Vec3(10, 0, 0),
              components: [
                SphereCollider(radius: 0.5),
                RigidBody(useGravity: false, linearDrag: 0.0),
              ],
            )
            .getComponent<RigidBody>()!;

        engine.scene.physics.addExplosionForce(20.0, Vec3.zero, 6.0);
        expect(farBody.velocity.length, 0.0); // beyond radius 6.0
      },
    );
  });

  group('E26 — SpatialGrid2D Queries', () {
    test(
      'SpatialGrid2D indexes 2D entities and accelerates radius/aabb queries',
      () {
        final grid = SpatialGrid2D<String>(cellSize: 50.0);

        grid.insert('Bullet1', const Vec2(10, 10), 5.0);
        grid.insert('Bullet2', const Vec2(25, 25), 5.0);
        grid.insert('DistantEnemy', const Vec2(500, 500), 10.0);

        expect(grid.count, 3);

        // Query near (0, 0) within radius 50.0 -> should retrieve Bullet1 and Bullet2, NOT DistantEnemy
        final nearby = grid.querySphere(const Vec2(0, 0), 50.0);
        expect(nearby, containsAll(['Bullet1', 'Bullet2']));
        expect(nearby, isNot(contains('DistantEnemy')));

        // Remove Bullet1 -> query should no longer return it
        expect(grid.remove('Bullet1'), isTrue);
        expect(grid.count, 2);
        final afterRemove = grid.querySphere(const Vec2(0, 0), 50.0);
        expect(afterRemove, isNot(contains('Bullet1')));
        expect(afterRemove, contains('Bullet2'));

        // Clear grid
        grid.clear();
        expect(grid.count, 0);
        expect(grid.querySphere(const Vec2(0, 0), 1000.0), isEmpty);
      },
    );
  });

  group('E29 — Scene.raycastMeshes', () {
    test(
      'E29: Scene.raycastMeshes hits closest active MeshRenderer bounding box',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final cubeA = engine.scene.createGameObject('CubeNear');
        cubeA.transform.position = const Vec3(0, 0, 5);
        final meshA = cubeA.addComponent(MeshRenderer());

        final cubeB = engine.scene.createGameObject('CubeFar');
        cubeB.transform.position = const Vec3(0, 0, 15);
        cubeB.addComponent(MeshRenderer());

        engine.step(0.016);

        final ray = Ray3(const GeomVec3(0, 0, 0), const GeomVec3(0, 0, 1));
        final hit = engine.scene.raycastMeshes(ray);

        expect(hit, isNotNull);
        expect(hit!.gameObject, equals(cubeA));
        expect(hit.renderer, equals(meshA));
        expect(hit.distance, closeTo(4.5, 1e-3));
      },
    );
  });

  group('E32 — 2D Physics, Colliders, Triggers & DistanceJoint2D', () {
    test(
      'E32: RigidBody2D and BoxCollider2D fall under gravity and rest on ground',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.scene.physics2D.gravity = const Vec2(0.0, -10.0);

        // Static ground at (0, 0), size (10, 1) -> top is at y = 0.5
        final groundGo = engine.scene.createGameObject(
          'Ground',
          position: Vec3.zero,
        );
        groundGo.addComponent(
          BoxCollider2D(
            size: const Vec2(10.0, 1.0),
            friction: 0.5,
            restitution: 0.0,
          ),
        );

        // Dynamic crate at (0, 3), size (1, 1) -> halfHeight = 0.5
        final crateGo = engine.scene.createGameObject(
          'Crate',
          position: const Vec3(0.0, 3.0, 0.0),
        );
        final rb = crateGo.addComponent(
          RigidBody2D(bodyType: BodyType.dynamicBody),
        );
        crateGo.addComponent(
          BoxCollider2D(
            size: const Vec2(1.0, 1.0),
            friction: 0.5,
            restitution: 0.0,
          ),
        );

        // Step engine 60 frames (1.0s)
        for (var i = 0; i < 60; i++) {
          engine.step(1.0 / 60.0);
        }

        // Crate should come to rest on ground: y = 0.5 + 0.5 = 1.0
        expect(crateGo.transform.position.y, closeTo(1.0, 0.05));
        expect(rb.linearVelocity.y.abs(), lessThan(0.05));
      },
    );

    test('E32: 2D Collision and Trigger Behaviour callbacks', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.scene.physics2D.gravity = const Vec2(0.0, -10.0);

      final colSpy = CollisionSpy2D();
      final trigSpy = TriggerSpy2D();

      final groundGo = engine.scene.createGameObject(
        'Ground',
        position: Vec3.zero,
      );
      groundGo.addComponent(BoxCollider2D(size: const Vec2(10.0, 1.0)));
      groundGo.addComponent(colSpy);

      // Sensor zone at (0, 1.5)
      final sensorGo = engine.scene.createGameObject(
        'Sensor',
        position: const Vec3(0.0, 1.5, 0.0),
      );
      sensorGo.addComponent(
        BoxCollider2D(size: const Vec2(4.0, 2.0), isTrigger: true),
      );
      sensorGo.addComponent(trigSpy);

      // Dynamic crate at (0, 3)
      final crateGo = engine.scene.createGameObject(
        'Crate',
        position: const Vec3(0.0, 3.0, 0.0),
      );
      crateGo.addComponent(RigidBody2D(bodyType: BodyType.dynamicBody));
      crateGo.addComponent(CircleCollider2D(radius: 0.5));

      for (var i = 0; i < 60; i++) {
        engine.step(1.0 / 60.0);
      }

      expect(trigSpy.entered, isTrue);
      expect(colSpy.entered, isTrue);
      expect(colSpy.lastCollision, isNotNull);
      expect(colSpy.lastCollision!.otherGameObject, equals(crateGo));
    });

    test(
      'E32: DistanceJoint2D maintains distance constraint in engine scene',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.scene.physics2D.gravity = const Vec2(0.0, -10.0);

        final anchorGo = engine.scene.createGameObject(
          'Anchor',
          position: const Vec3(0.0, 5.0, 0.0),
        );
        final anchorRb = anchorGo.addComponent(
          RigidBody2D(bodyType: BodyType.staticBody),
        );

        final bobGo = engine.scene.createGameObject(
          'Bob',
          position: const Vec3(3.0, 5.0, 0.0),
        );
        bobGo.addComponent(RigidBody2D(bodyType: BodyType.dynamicBody));
        bobGo.addComponent(CircleCollider2D(radius: 0.3));

        bobGo.addComponent(
          DistanceJoint2D(connectedBody: anchorRb, length: 3.0),
        );

        for (var i = 0; i < 60; i++) {
          engine.step(1.0 / 60.0);
        }

        final dist =
            (bobGo.transform.position - anchorGo.transform.position).length;
        expect(dist, closeTo(3.0, 0.05));
      },
    );

    test('E32: Scene.raycast2D queries 2D colliders', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final targetGo = engine.scene.createGameObject(
        'Target',
        position: const Vec3(0.0, 4.0, 0.0),
      );
      targetGo.addComponent(CircleCollider2D(radius: 1.0));

      final hit = engine.scene.raycast2D(
        const Vec2(0.0, 10.0),
        const Vec2(0.0, -1.0),
      );
      expect(hit, isNotNull);
      expect(hit!.gameObject, equals(targetGo));
      expect(hit.point.y, closeTo(5.0, 1e-3));
      expect(hit.normal.y, closeTo(1.0, 1e-3));
    });
  });
}
