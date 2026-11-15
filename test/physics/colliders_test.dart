/// Unit tests for SAT OBB BoxCollider, BVH MeshCollider, and HeightfieldCollider.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('True 15-Axis SAT OBB BoxCollider', () {
    test(
      '45-deg rotated boxes separate at corners where enclosing AABBs overlap',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // Box A at origin, size 2x2x2 (half-extents 1, 1, 1), rotated 45 deg around Y.
        // Its enclosing AABB extends to ±sqrt(2) ≈ ±1.4142 on X and Z.
        final boxObjA = engine.scene.createGameObject(
          'BoxA',
          position: Vec3.zero,
          rotation: Quat.axisAngle(const Vec3(0, 1, 0), math.pi / 4),
          components: [BoxCollider(size: const Vec3(2, 2, 2))],
        );
        final boxA = boxObjA.getComponent<BoxCollider>()!;

        // Box B at (1.2, 0, 1.2), size 0.3x0.3x0.3, axis-aligned.
        // In AABB space, (1.2, 1.2) is inside [-1.414, 1.414] x [-1.414, 1.414]!
        final boxObjB = engine.scene.createGameObject(
          'BoxB',
          position: const Vec3(1.2, 0, 1.2),
          components: [BoxCollider(size: const Vec3(0.3, 0.3, 0.3))],
        );
        final boxB = boxObjB.getComponent<BoxCollider>()!;

        // 1. Enclosing AABBs DO overlap (would cause false positive in old implementation)
        expect(
          PhysicsNarrowphase.aabbIntersects(boxA.worldBounds, boxB.worldBounds),
          isTrue,
          reason: 'Enclosing AABBs overlap in the diagonal corner region',
        );

        // 2. True SAT OBB detects that the rotated boxes do NOT collide!
        expect(
          PhysicsNarrowphase.intersects(boxA, boxB),
          isFalse,
          reason: 'SAT separates rotated box from corner region',
        );
        expect(
          boxA.intersectsAabb(boxB.worldBounds),
          isFalse,
          reason: 'BoxCollider.intersectsAabb exact rotated OBB test separates',
        );
        expect(
          PhysicsNarrowphase.computeManifold(boxA, boxB),
          isNull,
          reason: 'Separated boxes produce null contact manifold',
        );
      },
    );

    test(
      'SAT OBB-vs-OBB manifold computes penetration normal, depth, and symmetry',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final boxObjA = engine.scene.createGameObject(
          'BoxA',
          position: Vec3.zero,
          rotation: Quat.axisAngle(const Vec3(0, 1, 0), math.pi / 4),
          components: [BoxCollider(size: const Vec3(2, 2, 2))],
        );
        final boxA = boxObjA.getComponent<BoxCollider>()!;

        // Box B placed at (1.1, 0, 0), size 1x1x1.
        // Tip of Box A along +X reaches x = sqrt(2) ≈ 1.4142.
        // Box B left edge is at x = 1.1 - 0.5 = 0.6. They collide!
        final boxObjB = engine.scene.createGameObject(
          'BoxB',
          position: const Vec3(1.1, 0, 0),
          components: [BoxCollider(size: const Vec3(1, 1, 1))],
        );
        final boxB = boxObjB.getComponent<BoxCollider>()!;

        expect(PhysicsNarrowphase.intersects(boxA, boxB), isTrue);

        final manifoldAB = PhysicsNarrowphase.computeManifold(boxA, boxB);
        expect(manifoldAB, isNotNull);
        final (normalAB, depthAB) = manifoldAB!;
        // Normal points from A to B (along +X direction)
        expect(normalAB.x, greaterThan(0.8));
        expect(depthAB, greaterThan(0.0));

        // Test symmetric swapped call (B, A): normal must point from B toward A (-normal)
        final manifoldBA = PhysicsNarrowphase.computeManifold(boxB, boxA);
        expect(manifoldBA, isNotNull);
        final (normalBA, depthBA) = manifoldBA!;
        expect(normalBA.x, closeTo(-normalAB.x, 1e-4));
        expect(normalBA.y, closeTo(-normalAB.y, 1e-4));
        expect(normalBA.z, closeTo(-normalAB.z, 1e-4));
        expect(depthBA, closeTo(depthAB, 1e-4));
      },
    );

    test(
      'Rotated BoxCollider raycast misses empty corners of enclosing AABB and hits rotated face',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final boxObj = engine.scene.createGameObject(
          'RotatedBox',
          position: Vec3.zero,
          rotation: Quat.axisAngle(const Vec3(0, 1, 0), math.pi / 4),
          components: [BoxCollider(size: const Vec3(2, 2, 2))],
        );
        final box = boxObj.getComponent<BoxCollider>()!;

        // Ray passing through (1.3, y, 1.3) along Y: inside enclosing AABB, but misses rotated OBB!
        final rayMiss = Ray(
          origin: const Vec3(1.3, 5, 1.3),
          direction: const Vec3(0, -1, 0),
        );
        expect(
          box.worldBounds.min.x <= 1.3 && 1.3 <= box.worldBounds.max.x,
          isTrue,
        );
        expect(engine.scene.physics.raycast(rayMiss), isNull);

        // Ray aimed straight at rotated corner tip from (0, 0, 4) pointing along -Z:
        // Rotated corner is at z = sqrt(2) ≈ 1.4142. Hit distance = 4 - 1.4142 = 2.5858.
        final rayHit = Ray(
          origin: const Vec3(0, 0, 4),
          direction: const Vec3(0, 0, -1),
        );
        final hit = engine.scene.physics.raycast(rayHit);
        expect(hit, isNotNull);
        expect(hit!.collider, box);
        expect(hit.distance, closeTo(4.0 - math.sqrt(2.0), 1e-3));
        expect(hit.point.z, closeTo(math.sqrt(2.0), 1e-3));
      },
    );

    test(
      'OBB-vs-Sphere separates at AABB corner and penetrates at rotated surface',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final boxObj = engine.scene.createGameObject(
          'Box',
          position: Vec3.zero,
          rotation: Quat.axisAngle(const Vec3(0, 1, 0), math.pi / 4),
          components: [BoxCollider(size: const Vec3(2, 2, 2))],
        );
        final box = boxObj.getComponent<BoxCollider>()!;

        final sphereObjMiss = engine.scene.createGameObject(
          'SphereMiss',
          position: const Vec3(1.2, 0, 1.2),
          components: [SphereCollider(radius: 0.2)],
        );
        final sphereMiss = sphereObjMiss.getComponent<SphereCollider>()!;

        // Misses rotated box despite being inside enclosing AABB
        expect(PhysicsNarrowphase.intersects(box, sphereMiss), isFalse);
        expect(PhysicsNarrowphase.computeManifold(box, sphereMiss), isNull);

        // Hits tip of rotated box at x = 1.3
        final sphereObjHit = engine.scene.createGameObject(
          'SphereHit',
          position: const Vec3(1.3, 0, 0),
          components: [SphereCollider(radius: 0.3)],
        );
        final sphereHit = sphereObjHit.getComponent<SphereCollider>()!;

        expect(PhysicsNarrowphase.intersects(box, sphereHit), isTrue);
        final m = PhysicsNarrowphase.computeManifold(box, sphereHit);
        expect(m, isNotNull);
        // Face normal of 45-deg rotated box has x == sqrt(0.5) ≈ 0.7071
        expect(m!.$1.x, closeTo(math.sqrt(0.5), 1e-3));
        expect(m.$2, greaterThan(0.0));
      },
    );

    test(
      'OBB-vs-Capsule separates at AABB corner and penetrates at rotated surface',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final boxObj = engine.scene.createGameObject(
          'Box',
          position: Vec3.zero,
          rotation: Quat.axisAngle(const Vec3(0, 1, 0), math.pi / 4),
          components: [BoxCollider(size: const Vec3(2, 2, 2))],
        );
        final box = boxObj.getComponent<BoxCollider>()!;

        final capObjMiss = engine.scene.createGameObject(
          'CapMiss',
          position: const Vec3(1.2, 0, 1.2),
          components: [CapsuleCollider(radius: 0.2, height: 2.0)],
        );
        final capMiss = capObjMiss.getComponent<CapsuleCollider>()!;
        expect(PhysicsNarrowphase.intersects(box, capMiss), isFalse);

        final capObjHit = engine.scene.createGameObject(
          'CapHit',
          position: const Vec3(1.3, 0, 0),
          components: [CapsuleCollider(radius: 0.3, height: 2.0)],
        );
        final capHit = capObjHit.getComponent<CapsuleCollider>()!;
        expect(PhysicsNarrowphase.intersects(box, capHit), isTrue);
        final m = PhysicsNarrowphase.computeManifold(box, capHit);
        expect(m, isNotNull);
        // Face normal of 45-deg rotated box has x == sqrt(0.5) ≈ 0.7071
        expect(m!.$1.x, closeTo(math.sqrt(0.5), 1e-3));
        expect(m.$2, greaterThan(0.0));
      },
    );
  });

  group('BVH-Accelerated Static Concave MeshCollider', () {
    test('MeshCollider constructs from vertex/index lists and MeshData', () {
      final verts = [
        const Vec3(0, 0, 0),
        const Vec3(1, 0, 0),
        const Vec3(0, 1, 0),
      ];
      final indices = [0, 1, 2];
      final mesh1 = MeshCollider(vertices: verts, indices: indices);
      expect(mesh1.triangleCount, 1);
      expect(mesh1.worldBounds.min, const Vec3(0, 0, 0));
      expect(mesh1.worldBounds.max, const Vec3(1, 1, 0));

      final meshData = MeshData(
        layout: VertexLayoutDescriptor.compatibility14,
        vertices: Float32List(14 * 3)
          ..[0] = 0
          ..[1] = 0
          ..[2] = 0
          ..[14] = 2
          ..[15] = 0
          ..[16] = 0
          ..[28] = 0
          ..[29] = 2
          ..[30] = 0,
        indices: Uint16List.fromList([0, 1, 2]),
        localBounds: const Aabb(Vec3(0, 0, 0), Vec3(2, 2, 0)),
      );
      final mesh2 = MeshCollider.fromMeshData(meshData);
      expect(mesh2.triangleCount, 1);
      expect(mesh2.vertices.length, 3);
      expect(mesh2.vertices[1].x, 2.0);
    });

    test(
      'Concave MeshCollider raycast misses hollow interior and hits triangle surface',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // Build a concave U-channel mesh:
        // Floor from x = -2..2, z = -2..2 at y = 0
        // Left wall at x = -2, from y = 0..2, z = -2..2
        // Right wall at x = 2, from y = 0..2, z = -2..2
        final verts = <Vec3>[
          // Floor (0..3)
          const Vec3(-2, 0, -2), // 0
          const Vec3(2, 0, -2), // 1
          const Vec3(2, 0, 2), // 2
          const Vec3(-2, 0, 2), // 3
          // Left wall top (4..5)
          const Vec3(-2, 2, -2), // 4
          const Vec3(-2, 2, 2), // 5
          // Right wall top (6..7)
          const Vec3(2, 2, -2), // 6
          const Vec3(2, 2, 2), // 7
        ];
        final indices = <int>[
          // Floor
          0, 1, 2, 0, 2, 3,
          // Left wall
          0, 3, 5, 0, 5, 4,
          // Right wall
          1, 6, 7, 1, 7, 2,
        ];

        final meshObj = engine.scene.createGameObject(
          'UChannel',
          position: Vec3.zero,
          components: [MeshCollider(vertices: verts, indices: indices)],
        );
        final mesh = meshObj.getComponent<MeshCollider>()!;
        expect(mesh.triangleCount, 6);

        // 1. Ray aiming down through the open top hits the concave floor at y = 0
        final rayDown = Ray(
          origin: const Vec3(0, 5, 0),
          direction: const Vec3(0, -1, 0),
        );
        final hitFloor = engine.scene.physics.raycast(rayDown);
        expect(hitFloor, isNotNull);
        expect(hitFloor!.distance, closeTo(5.0, 1e-4));
        expect(hitFloor.point.y, closeTo(0.0, 1e-4));

        // 2. Ray passing horizontally through the hollow channel (y = 1, z = 0, along Z)
        final rayHollow = Ray(
          origin: const Vec3(0, 1, -5),
          direction: const Vec3(0, 0, 1),
        );
        final hitHollow = engine.scene.physics.raycast(rayHollow);
        expect(
          hitHollow,
          isNull,
          reason: 'Ray passes through open hollow interior',
        );

        // 3. Ray aiming horizontally at the left wall
        final rayWall = Ray(
          origin: const Vec3(-5, 1, 0),
          direction: const Vec3(1, 0, 0),
        );
        final hitWall = engine.scene.physics.raycast(rayWall);
        expect(hitWall, isNotNull);
        expect(hitWall!.distance, closeTo(3.0, 1e-4));
        expect(hitWall.point.x, closeTo(-2.0, 1e-4));
      },
    );

    test(
      'Concave MeshCollider sphere contact produces exact normal pointing out from mesh',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // Quad floor at y = 0
        final verts = <Vec3>[
          const Vec3(-5, 0, -5),
          const Vec3(5, 0, -5),
          const Vec3(5, 0, 5),
          const Vec3(-5, 0, 5),
        ];
        final indices = <int>[0, 1, 2, 0, 2, 3];

        final meshObj = engine.scene.createGameObject(
          'FloorMesh',
          position: Vec3.zero,
          components: [MeshCollider(vertices: verts, indices: indices)],
        );
        final mesh = meshObj.getComponent<MeshCollider>()!;

        // Sphere placed at (0, 0.4, 0), radius 0.5: penetrates floor by 0.1
        final sphereObj = engine.scene.createGameObject(
          'Sphere',
          position: const Vec3(0, 0.4, 0),
          components: [SphereCollider(radius: 0.5)],
        );
        final sphere = sphereObj.getComponent<SphereCollider>()!;

        expect(PhysicsNarrowphase.intersects(mesh, sphere), isTrue);

        final manifold = PhysicsNarrowphase.computeManifold(mesh, sphere);
        expect(manifold, isNotNull);
        final (normal, depth) = manifold!;
        // Normal points upward (+Y) out of the mesh floor toward the sphere
        expect(normal.y, closeTo(1.0, 1e-3));
        expect(normal.x.abs(), lessThan(1e-3));
        expect(normal.z.abs(), lessThan(1e-3));
        expect(depth, closeTo(0.1, 1e-3));

        // Separated sphere
        sphereObj.transform.position = const Vec3(0, 1.0, 0);
        expect(PhysicsNarrowphase.intersects(mesh, sphere), isFalse);
        expect(PhysicsNarrowphase.computeManifold(mesh, sphere), isNull);
      },
    );
  });

  group('Grid HeightfieldCollider', () {
    test(
      'HeightfieldCollider computes exact bounds and samples interpolated heights',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // 3x3 grid with heights:
        // row 0: [0, 1, 2]
        // row 1: [1, 2, 3]
        // row 2: [2, 3, 4]
        final heights = <double>[0, 1, 2, 1, 2, 3, 2, 3, 4];
        final hfObj = engine.scene.createGameObject(
          'Terrain',
          position: Vec3.zero,
          components: [
            HeightfieldCollider(
              columns: 3,
              rows: 3,
              heights: heights,
              cellSize: 2.0,
              heightScale: 1.0,
            ),
          ],
        );
        final hf = hfObj.getComponent<HeightfieldCollider>()!;

        // Bounds: (columns - 1) * cellSize = 2 * 2 = 4
        expect(hf.worldBounds.min, const Vec3(0, 0, 0));
        expect(hf.worldBounds.max, const Vec3(4, 4, 4));

        // Height sampling at exact grid vertices:
        expect(hf.sampleHeightAt(0, 0), closeTo(0.0, 1e-4));
        expect(hf.sampleHeightAt(2, 2), closeTo(2.0, 1e-4));
        expect(hf.sampleHeightAt(4, 4), closeTo(4.0, 1e-4));

        // Bilinear interpolation between vertices:
        expect(hf.sampleHeightAt(1.0, 1.0), closeTo(1.0, 1e-4));
        expect(hf.sampleHeightAt(3.0, 3.0), closeTo(3.0, 1e-4));
      },
    );

    test('HeightfieldCollider terrain raycasts hit surface accurately', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      // Flat 4x4 terrain at height = 2.0
      final heights = List.filled(16, 2.0);
      final hfObj = engine.scene.createGameObject(
        'Terrain',
        position: Vec3.zero,
        components: [
          HeightfieldCollider(
            columns: 4,
            rows: 4,
            heights: heights,
            cellSize: 1.0,
          ),
        ],
      );
      final hf = hfObj.getComponent<HeightfieldCollider>()!;

      // Ray cast straight down at (1.5, 10, 1.5)
      final ray = Ray(
        origin: const Vec3(1.5, 10, 1.5),
        direction: const Vec3(0, -1, 0),
      );
      final hit = engine.scene.physics.raycast(ray);
      expect(hit, isNotNull);
      expect(hit!.collider, hf);
      expect(hit.point.y, closeTo(2.0, 1e-4));
      expect(hit.distance, closeTo(8.0, 1e-4));

      // Ray cast outside grid misses
      final rayOutside = Ray(
        origin: const Vec3(10, 10, 10),
        direction: const Vec3(0, -1, 0),
      );
      expect(engine.scene.physics.raycast(rayOutside), isNull);
    });

    test('Rolling sphere and capsule terrain contact manifolds', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      // Sloped terrain: heights increase along X (slope)
      // row 0: [0, 1, 2]
      // row 1: [0, 1, 2]
      // row 2: [0, 1, 2]
      final heights = <double>[0, 1, 2, 0, 1, 2, 0, 1, 2];
      final hfObj = engine.scene.createGameObject(
        'Terrain',
        position: Vec3.zero,
        components: [
          HeightfieldCollider(
            columns: 3,
            rows: 3,
            heights: heights,
            cellSize: 1.0,
          ),
        ],
      );
      final hf = hfObj.getComponent<HeightfieldCollider>()!;

      // At x = 1.0, height is 1.0. Place sphere of radius 0.5 at y = 1.4 (penetrating by 0.1)
      final sphereObj = engine.scene.createGameObject(
        'Sphere',
        position: const Vec3(1.0, 1.4, 1.0),
        components: [SphereCollider(radius: 0.5)],
      );
      final sphere = sphereObj.getComponent<SphereCollider>()!;

      expect(PhysicsNarrowphase.intersects(hf, sphere), isTrue);
      final mSphere = PhysicsNarrowphase.computeManifold(hf, sphere);
      expect(mSphere, isNotNull);
      // Upward normal supporting the sphere
      expect(mSphere!.$1.y, greaterThan(0.5));
      // On 45-degree slope (y = x), plane perpendicular distance = 0.4 / sqrt(2)
      expect(mSphere.$2, closeTo(0.5 - (0.4 / math.sqrt(2.0)), 1e-3));

      // Capsule on terrain
      final capObj = engine.scene.createGameObject(
        'Capsule',
        position: const Vec3(1.0, 1.9, 1.0),
        components: [CapsuleCollider(radius: 0.4, height: 1.8)],
      );
      final cap = capObj.getComponent<CapsuleCollider>()!;
      expect(PhysicsNarrowphase.intersects(hf, cap), isTrue);
      final mCap = PhysicsNarrowphase.computeManifold(hf, cap);
      expect(mCap, isNotNull);
      expect(mCap!.$1.y, greaterThan(0.5));
    });
  });

  group('PhysicsWorld End-to-End Dynamic Integration', () {
    test(
      'RigidBody sphere falls under gravity and rests on HeightfieldCollider terrain',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // Terrain with height 1.0
        final heights = List.filled(16, 1.0);
        engine.scene.createGameObject(
          'Terrain',
          position: Vec3.zero,
          components: [
            HeightfieldCollider(
              columns: 4,
              rows: 4,
              heights: heights,
              cellSize: 2.0,
              isTrigger: false,
            ),
          ],
        );

        // Sphere with radius 0.5 falling from y = 3.0
        final ball = engine.scene.createGameObject(
          'Ball',
          position: const Vec3(3.0, 3.0, 3.0),
          components: [
            SphereCollider(radius: 0.5, isTrigger: false),
            RigidBody(restitution: 0.0, linearDrag: 0.1),
          ],
        );

        for (var i = 0; i < 60; i++) {
          engine.step(1 / 60);
        }

        // Ball rests on terrain at surface y = 1.0 + radius 0.5 = 1.5
        expect(ball.transform.position.y, closeTo(1.5, 0.15));
        expect(ball.getComponent<RigidBody>()!.velocity.y.abs(), lessThan(1.0));
      },
    );

    test(
      'RigidBody sphere falls onto concave MeshCollider floor and rests',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final verts = <Vec3>[
          const Vec3(-5, 0, -5),
          const Vec3(5, 0, -5),
          const Vec3(5, 0, 5),
          const Vec3(-5, 0, 5),
        ];
        final indices = <int>[0, 1, 2, 0, 2, 3];

        engine.scene.createGameObject(
          'MeshFloor',
          position: Vec3.zero,
          components: [
            MeshCollider(vertices: verts, indices: indices, isTrigger: false),
          ],
        );

        final ball = engine.scene.createGameObject(
          'Ball',
          position: const Vec3(0, 3.0, 0),
          components: [
            SphereCollider(radius: 0.5, isTrigger: false),
            RigidBody(restitution: 0.0, linearDrag: 0.1),
          ],
        );

        for (var i = 0; i < 60; i++) {
          engine.step(1 / 60);
        }

        // Ball rests on mesh floor at y = 0.0 + radius 0.5 = 0.5
        expect(ball.transform.position.y, closeTo(0.5, 0.15));
        expect(ball.getComponent<RigidBody>()!.velocity.y.abs(), lessThan(1.0));
      },
    );
  });
}
