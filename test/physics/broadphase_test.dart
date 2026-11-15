/// Broadphase spatial acceleration unit, integration & benchmark tests.
library;

import 'dart:math' as math;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P5-W13-A: Spatial Broadphase Hit Parity vs Linear Reference', () {
    test(
      'Exact hit parity across queryAabb, querySphere, queryRay, querySweptSphere and queryCandidatePairs',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final rnd = math.Random(1337);
        final colliders = <Collider>[];

        // 1. Giant floor plane (loose/global bucket test)
        final floorGo = engine.scene.createGameObject(
          'GiantFloor',
          position: const Vec3(0, -5, 0),
          components: [
            BoxCollider(size: const Vec3(200, 2, 200), isTrigger: false),
          ],
        );
        colliders.add(floorGo.getComponent<BoxCollider>()!);

        // 2. Large boundary wall
        final wallGo = engine.scene.createGameObject(
          'HugeWall',
          position: const Vec3(50, 10, 0),
          components: [
            BoxCollider(size: const Vec3(2, 30, 100), isTrigger: false),
          ],
        );
        colliders.add(wallGo.getComponent<BoxCollider>()!);

        // 3. 120 randomized mixed colliders (boxes, spheres, capsules)
        for (var i = 0; i < 120; i++) {
          final x = (rnd.nextDouble() - 0.5) * 80.0;
          final y = rnd.nextDouble() * 20.0;
          final z = (rnd.nextDouble() - 0.5) * 80.0;

          Collider col;
          switch (i % 3) {
            case 0:
              final sx = 0.5 + rnd.nextDouble() * 4.0;
              final sy = 0.5 + rnd.nextDouble() * 4.0;
              final sz = 0.5 + rnd.nextDouble() * 4.0;
              col = BoxCollider(size: Vec3(sx, sy, sz));
            case 1:
              final r = 0.4 + rnd.nextDouble() * 2.5;
              col = SphereCollider(radius: r);
            case 2:
            default:
              final r = 0.3 + rnd.nextDouble() * 1.5;
              final h = 1.0 + rnd.nextDouble() * 3.0;
              col = CapsuleCollider(radius: r, height: h);
          }

          final go = engine.scene.createGameObject(
            'Col_$i',
            position: Vec3(x, y, z),
            components: [col],
          );
          colliders.add(go.getComponent<Collider>()!);
        }

        final linear = LinearPhysicsBroadphase();
        final spatial = SpatialPhysicsBroadphase(cellSize: 4.0);
        final bvh = BvhPhysicsBroadphase();

        linear.sync(colliders);
        spatial.sync(colliders);
        bvh.sync(colliders);

        expect(spatial.trackedCount, colliders.length);
        expect(spatial.largeColliderCount, greaterThanOrEqualTo(2));
        expect(spatial.occupiedCellCount, greaterThan(0));

        // --- A. queryAabb parity ---
        for (var q = 0; q < 25; q++) {
          final cx = (rnd.nextDouble() - 0.5) * 60.0;
          final cy = rnd.nextDouble() * 15.0;
          final cz = (rnd.nextDouble() - 0.5) * 60.0;
          final ext = 1.0 + rnd.nextDouble() * 8.0;
          final box = Aabb(
            Vec3(cx - ext, cy - ext, cz - ext),
            Vec3(cx + ext, cy + ext, cz + ext),
          );

          final linearHits = linear.queryAabb(box);
          final spatialHits = spatial.queryAabb(box);
          final bvhHits = bvh.queryAabb(box);

          expect(
            spatialHits.map((c) => c.instanceId).toList(),
            equals(linearHits.map((c) => c.instanceId).toList()),
            reason: 'queryAabb mismatch at iteration $q',
          );
          expect(
            bvhHits.map((c) => c.instanceId).toList(),
            equals(linearHits.map((c) => c.instanceId).toList()),
            reason: 'BVH queryAabb mismatch at iteration $q',
          );
        }

        // --- B. querySphere parity ---
        for (var q = 0; q < 25; q++) {
          final cx = (rnd.nextDouble() - 0.5) * 60.0;
          final cy = rnd.nextDouble() * 15.0;
          final cz = (rnd.nextDouble() - 0.5) * 60.0;
          final radius = 0.5 + rnd.nextDouble() * 10.0;
          final center = Vec3(cx, cy, cz);

          final linearHits = linear.querySphere(center, radius);
          final spatialHits = spatial.querySphere(center, radius);
          final bvhHits = bvh.querySphere(center, radius);

          expect(
            spatialHits.map((c) => c.instanceId).toList(),
            equals(linearHits.map((c) => c.instanceId).toList()),
            reason: 'querySphere mismatch at iteration $q',
          );
          expect(
            bvhHits.map((c) => c.instanceId).toList(),
            equals(linearHits.map((c) => c.instanceId).toList()),
            reason: 'BVH querySphere mismatch at iteration $q',
          );
        }

        // --- C. queryRay parity ---
        for (var q = 0; q < 30; q++) {
          final ox = (rnd.nextDouble() - 0.5) * 80.0;
          final oy = rnd.nextDouble() * 25.0;
          final oz = (rnd.nextDouble() - 0.5) * 80.0;
          final dx = (rnd.nextDouble() - 0.5) * 2.0;
          final dy = (rnd.nextDouble() - 0.5) * 2.0;
          final dz = (rnd.nextDouble() - 0.5) * 2.0;
          final dirLen = math.sqrt(dx * dx + dy * dy + dz * dz);
          final dir = dirLen > 1e-4
              ? Vec3(dx / dirLen, dy / dirLen, dz / dirLen)
              : kForward;
          final ray = Ray(origin: Vec3(ox, oy, oz), direction: dir);
          final maxD = q % 3 == 0
              ? double.infinity
              : (5.0 + rnd.nextDouble() * 60.0);

          final linearHits = linear.queryRay(ray, maxDistance: maxD);
          final spatialHits = spatial.queryRay(ray, maxDistance: maxD);
          final bvhHits = bvh.queryRay(ray, maxDistance: maxD);

          expect(
            spatialHits.map((c) => c.instanceId).toList(),
            equals(linearHits.map((c) => c.instanceId).toList()),
            reason: 'queryRay mismatch at iteration $q (maxD: $maxD)',
          );
          expect(
            bvhHits.map((c) => c.instanceId).toList(),
            equals(linearHits.map((c) => c.instanceId).toList()),
            reason: 'BVH queryRay mismatch at iteration $q (maxD: $maxD)',
          );
        }

        // --- D. querySweptSphere parity ---
        for (var q = 0; q < 25; q++) {
          final ox = (rnd.nextDouble() - 0.5) * 60.0;
          final oy = rnd.nextDouble() * 15.0;
          final oz = (rnd.nextDouble() - 0.5) * 60.0;
          final dx = (rnd.nextDouble() - 0.5) * 2.0;
          final dy = (rnd.nextDouble() - 0.5) * 2.0;
          final dz = (rnd.nextDouble() - 0.5) * 2.0;
          final dirLen = math.sqrt(dx * dx + dy * dy + dz * dz);
          final dir = dirLen > 1e-4
              ? Vec3(dx / dirLen, dy / dirLen, dz / dirLen)
              : kForward;
          final ray = Ray(origin: Vec3(ox, oy, oz), direction: dir);
          final radius = 0.5 + rnd.nextDouble() * 3.0;
          final maxD = 10.0 + rnd.nextDouble() * 40.0;

          final linearHits = linear.querySweptSphere(
            ray,
            radius,
            maxDistance: maxD,
          );
          final spatialHits = spatial.querySweptSphere(
            ray,
            radius,
            maxDistance: maxD,
          );
          final bvhHits = bvh.querySweptSphere(ray, radius, maxDistance: maxD);

          expect(
            spatialHits.map((c) => c.instanceId).toList(),
            equals(linearHits.map((c) => c.instanceId).toList()),
            reason: 'querySweptSphere mismatch at iteration $q',
          );
          expect(
            bvhHits.map((c) => c.instanceId).toList(),
            equals(linearHits.map((c) => c.instanceId).toList()),
            reason: 'BVH querySweptSphere mismatch at iteration $q',
          );
        }

        // --- E. queryCandidatePairs parity ---
        final active = colliders.toList();
        final linearPairs = linear.queryCandidatePairs(active);
        final spatialPairs = spatial.queryCandidatePairs(active);
        final bvhPairs = bvh.queryCandidatePairs(active);

        expect(
          spatialPairs.map((p) => (p.$1.instanceId, p.$2.instanceId)).toList(),
          equals(
            linearPairs.map((p) => (p.$1.instanceId, p.$2.instanceId)).toList(),
          ),
          reason: 'queryCandidatePairs mismatch against linear brute-force',
        );
        expect(
          bvhPairs.map((p) => (p.$1.instanceId, p.$2.instanceId)).toList(),
          equals(
            linearPairs.map((p) => (p.$1.instanceId, p.$2.instanceId)).toList(),
          ),
          reason: 'BVH queryCandidatePairs mismatch against linear brute-force',
        );
      },
    );

    test(
      'PhysicsWorld queries and collision step with SpatialPhysicsBroadphase match Linear reference 100%',
      () {
        final host1 = HeadlessHost();
        final engineLinear = Engine(host1);

        final host2 = HeadlessHost();
        final engineSpatial = Engine(host2);
        engineSpatial.scene.physics.broadphase = SpatialPhysicsBroadphase(
          cellSize: 3.5,
        );

        // Populate identical test geometry into both scenes
        void populate(Scene scene) {
          // Giant ground plane
          scene.createGameObject(
            'Floor',
            position: const Vec3(0, -1, 0),
            components: [
              BoxCollider(size: const Vec3(100, 2, 100), isTrigger: false),
              RigidBody(isKinematic: true),
            ],
          );

          // Walls
          scene.createGameObject(
            'WallLeft',
            position: const Vec3(-10, 3, 0),
            components: [BoxCollider(size: const Vec3(2, 6, 20))],
          );
          scene.createGameObject(
            'WallRight',
            position: const Vec3(10, 3, 0),
            components: [BoxCollider(size: const Vec3(2, 6, 20))],
          );

          // Clusters of overlapping & non-overlapping boxes & spheres
          for (var i = 0; i < 25; i++) {
            final x = (i % 5 - 2) * 3.5;
            final z = (i ~/ 5 - 2) * 3.5;
            scene.createGameObject(
              'Box_$i',
              position: Vec3(x, 1.0 + (i % 3) * 0.5, z),
              components: [
                BoxCollider(size: const Vec3(1.5, 1.5, 1.5)),
                RigidBody(mass: 1.0),
              ],
            );
            scene.createGameObject(
              'Sphere_$i',
              position: Vec3(x + 0.6, 2.5, z + 0.6),
              components: [SphereCollider(radius: 0.8), RigidBody(mass: 0.5)],
            );
          }
        }

        populate(engineLinear.scene);
        populate(engineSpatial.scene);

        // 1. Compare overlapBox
        final testBox = Aabb(const Vec3(-5, 0, -5), const Vec3(5, 5, 5));
        final linearOverlap = engineLinear.scene.physics
            .overlapBox(testBox)
            .map((c) => c.gameObject.name)
            .toSet();
        final spatialOverlap = engineSpatial.scene.physics
            .overlapBox(testBox)
            .map((c) => c.gameObject.name)
            .toSet();
        expect(spatialOverlap, equals(linearOverlap));
        expect(spatialOverlap, isNotEmpty);

        // 2. Compare overlapSphere
        final sphereCenter = const Vec3(0, 2, 0);
        const sphereRadius = 6.0;
        final linearSphere = engineLinear.scene.physics
            .overlapSphere(sphereCenter, sphereRadius)
            .map((c) => c.gameObject.name)
            .toSet();
        final spatialSphere = engineSpatial.scene.physics
            .overlapSphere(sphereCenter, sphereRadius)
            .map((c) => c.gameObject.name)
            .toSet();
        expect(spatialSphere, equals(linearSphere));
        expect(spatialSphere, isNotEmpty);

        // 3. Compare raycast closest hit
        final ray = const Ray(
          origin: Vec3(0, 15, 0),
          direction: Vec3(0, -1, 0),
        );
        final linearRay = engineLinear.scene.physics.raycast(ray);
        final spatialRay = engineSpatial.scene.physics.raycast(ray);
        expect(linearRay, isNotNull);
        expect(spatialRay, isNotNull);
        expect(
          spatialRay!.collider.gameObject.name,
          equals(linearRay!.collider.gameObject.name),
        );
        expect(spatialRay.distance, closeTo(linearRay.distance, 1e-4));
        expect(spatialRay.point.x, closeTo(linearRay.point.x, 1e-4));
        expect(spatialRay.point.y, closeTo(linearRay.point.y, 1e-4));
        expect(spatialRay.point.z, closeTo(linearRay.point.z, 1e-4));

        // 4. Compare raycastAll hits
        final angledRay = const Ray(
          origin: Vec3(-15, 2, 0),
          direction: Vec3(1, 0, 0),
        );
        final linearAll = engineLinear.scene.physics.raycastAll(angledRay);
        final spatialAll = engineSpatial.scene.physics.raycastAll(angledRay);
        expect(spatialAll.length, equals(linearAll.length));
        for (var i = 0; i < linearAll.length; i++) {
          expect(
            spatialAll[i].collider.gameObject.name,
            equals(linearAll[i].collider.gameObject.name),
          );
          expect(spatialAll[i].distance, closeTo(linearAll[i].distance, 1e-4));
        }

        // 5. Compare sphereCast
        final sweepRay = const Ray(
          origin: Vec3(0, 10, -15),
          direction: Vec3(0, -0.3, 1),
        );
        final linearSweep = engineLinear.scene.physics.sphereCast(
          sweepRay,
          0.5,
        );
        final spatialSweep = engineSpatial.scene.physics.sphereCast(
          sweepRay,
          0.5,
        );
        expect(spatialSweep, isNotNull);
        expect(linearSweep, isNotNull);
        expect(
          spatialSweep!.collider.gameObject.name,
          equals(linearSweep!.collider.gameObject.name),
        );
        expect(spatialSweep.distance, closeTo(linearSweep.distance, 1e-4));

        // 6. Step both engines over multiple frames and verify bit-identical contact pairs
        for (var frame = 0; frame < 15; frame++) {
          engineLinear.step(1 / 60);
          engineSpatial.step(1 / 60);

          final linearContacts = engineLinear.scene.physics.contactPairs
              .map((p) => (p.$1.gameObject.name, p.$2.gameObject.name))
              .toSet();
          final spatialContacts = engineSpatial.scene.physics.contactPairs
              .map((p) => (p.$1.gameObject.name, p.$2.gameObject.name))
              .toSet();

          expect(
            spatialContacts,
            equals(linearContacts),
            reason: 'Contact pairs differed at frame $frame',
          );
        }
      },
    );
  });

  group('P5-W13-A: Edge Cases & Dynamic Movements', () {
    test('Deduplication of multi-cell colliders and dynamic repositioning', () {
      final bp = SpatialPhysicsBroadphase(cellSize: 2.0);

      final host = HeadlessHost();
      final engine = Engine(host);

      // Box of size 3x3x3 at (1, 1, 1) spans multiple cells (0,0,0) through (1,1,1)
      final go = engine.scene.createGameObject(
        'SpanningBox',
        position: const Vec3(1, 1, 1),
        components: [BoxCollider(size: const Vec3(3, 3, 3))],
      );
      final col = go.getComponent<BoxCollider>()!;

      bp.upsert(col);
      expect(bp.trackedCount, 1);
      expect(bp.largeColliderCount, 0);
      expect(bp.occupiedCellCount, greaterThan(1));

      // Query broad AABB overlapping all its cells -> must return col exactly once
      final hits = bp.queryAabb(
        Aabb(const Vec3(-5, -5, -5), const Vec3(5, 5, 5)),
      );
      expect(hits.length, 1);
      expect(hits.single, equals(col));

      // Move collider far away to (50, 50, 50)
      go.transform.position = const Vec3(50, 50, 50);
      bp.upsert(col);

      // Old area should return empty, new area returns single hit
      expect(
        bp.queryAabb(Aabb(const Vec3(-5, -5, -5), const Vec3(5, 5, 5))),
        isEmpty,
      );
      expect(
        bp.queryAabb(Aabb(const Vec3(45, 45, 45), const Vec3(55, 55, 55))),
        [col],
      );

      // Remove collider
      bp.remove(col);
      expect(bp.trackedCount, 0);
      expect(bp.occupiedCellCount, 0);
      expect(
        bp.queryAabb(Aabb(const Vec3(45, 45, 45), const Vec3(55, 55, 55))),
        isEmpty,
      );
    });

    test(
      'Unbounded / huge colliders are stored in loose bucket and queried correctly',
      () {
        final bp = SpatialPhysicsBroadphase(
          cellSize: 4.0,
          maxCellsPerAxis: 10,
          maxCellsPerCollider: 64,
        );

        final host = HeadlessHost();
        final engine = Engine(host);

        // Huge floor spanning 500x2x500 (125x1x125 = 15,625 cells!)
        final floorGo = engine.scene.createGameObject(
          'HugeFloor',
          position: const Vec3(0, -1, 0),
          components: [BoxCollider(size: const Vec3(500, 2, 500))],
        );
        final floorCol = floorGo.getComponent<BoxCollider>()!;

        // Normal cube at (10, 0, 10) resting on/in the floor (y in [-2, 0])
        final cubeGo = engine.scene.createGameObject(
          'NormalCube',
          position: const Vec3(10, 0, 10),
          components: [BoxCollider(size: const Vec3(2, 2, 2))],
        );
        final cubeCol = cubeGo.getComponent<BoxCollider>()!;

        bp.sync([floorCol, cubeCol]);

        expect(bp.trackedCount, 2);
        expect(bp.largeColliderCount, 1); // Floor is in loose bucket!
        // Grid cells are only occupied by the single normal cube (at most 8 cells, not 15,000!)
        expect(bp.occupiedCellCount, lessThanOrEqualTo(8));

        // Overlap queries intersecting floor
        final floorHit = bp.queryAabb(
          Aabb(const Vec3(-200, -2, -200), const Vec3(-190, 0, -190)),
        );
        expect(floorHit, contains(floorCol));
        expect(floorHit, isNot(contains(cubeCol)));

        // Query intersecting both
        final bothHit = bp.queryAabb(
          Aabb(const Vec3(9, -2, 9), const Vec3(11, 4, 11)),
        );
        expect(bothHit, containsAll([floorCol, cubeCol]));

        // Raycast hitting floor far away
        final ray = const Ray(
          origin: Vec3(-100, 50, -100),
          direction: Vec3(0, -1, 0),
        );
        expect(bp.queryRay(ray), contains(floorCol));

        // Candidate pairs between loose bucket and normal colliders
        final pairs = bp.queryCandidatePairs([floorCol, cubeCol]);
        expect(pairs.length, 1);
        expect({pairs.single.$1, pairs.single.$2}, equals({floorCol, cubeCol}));
      },
    );

    test(
      'BroadphaseWorldComponent exposes broadphase adaptor and keeps E80 stats in sync',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final bpGo = engine.scene.createGameObject('Broadphase');
        final bpComp = bpGo.addComponent(
          BroadphaseWorldComponent(cellSize: 3.0),
        );

        final boxA = engine.scene.createGameObject(
          'BoxA',
          position: const Vec3(0, 0, 0),
          components: [BoxCollider(size: const Vec3(2, 2, 2))],
        );
        final boxB = engine.scene.createGameObject(
          'BoxB',
          position: const Vec3(1.5, 0, 0),
          components: [BoxCollider(size: const Vec3(2, 2, 2))],
        );

        // Wire broadphase to PhysicsWorld
        engine.scene.physics.broadphase = bpComp.broadphase;
        engine.step(0.02);

        expect(bpComp.trackedCount, 2);
        expect(bpComp.overlapPairCount, 1);
        expect(bpComp.broadphase.trackedCount, 2);

        // Test adaptor queryAabb
        final hits = bpComp.broadphase.queryAabb(
          Aabb(const Vec3(-1, -1, -1), const Vec3(0.4, 1, 1)),
        );
        expect(hits, contains(boxA.getComponent<BoxCollider>()!));
        expect(hits, isNot(contains(boxB.getComponent<BoxCollider>()!)));

        // Update cell size
        bpComp.setCellSize(5.0);
        expect(bpComp.cellSize, 5.0);
        expect(bpComp.broadphase.cellSize, 5.0);
      },
    );
  });

  group('P5-W13-A: Benchmark Speedup Proof on 1,500+ Colliders', () {
    test(
      'SpatialPhysicsBroadphase achieves massive sub-linear speedup on 1,500+ colliders vs Linear brute-force',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        const countX = 40;
        const countZ = 40;
        // 40 x 40 = 1,600 small colliders + 1 giant ground plane = 1,601 colliders total!
        final totalExpected = countX * countZ + 1;
        expect(totalExpected, greaterThanOrEqualTo(1500));

        final colliders = <Collider>[];

        // 1. Giant ground plane (200m x 1m x 200m)
        final floorGo = engine.scene.createGameObject(
          'Floor',
          position: const Vec3(0, -0.5, 0),
          components: [
            BoxCollider(size: const Vec3(200, 1, 200), isTrigger: false),
            RigidBody(isKinematic: true),
          ],
        );
        colliders.add(floorGo.getComponent<BoxCollider>()!);

        // 2. 1,600 small cubes placed in a 40x40 grid spanning (-50..50, -50..50)
        for (var x = 0; x < countX; x++) {
          for (var z = 0; z < countZ; z++) {
            final px = -50.0 + x * 2.5;
            final pz = -50.0 + z * 2.5;
            final go = engine.scene.createGameObject(
              'Box_${x}_$z',
              position: Vec3(px, 0.5, pz),
              components: [BoxCollider(size: const Vec3(1.0, 1.0, 1.0))],
            );
            colliders.add(go.getComponent<BoxCollider>()!);
          }
        }

        expect(colliders.length, totalExpected);

        final linear = LinearPhysicsBroadphase();
        final spatial = SpatialPhysicsBroadphase(cellSize: 4.0);

        // Sync both
        linear.sync(colliders);
        spatial.sync(colliders);

        expect(spatial.trackedCount, totalExpected);
        expect(spatial.largeColliderCount, 1);

        // --- Benchmark 1: queryCandidatePairs ---
        // Brute-force N*(N-1)/2 = 1,601 * 1,600 / 2 = 1,280,800 pairwise tests!
        final swLinear = Stopwatch()..start();
        final linearPairs = linear.queryCandidatePairs(colliders);
        swLinear.stop();
        final linearPairUs = swLinear.elapsedMicroseconds;

        final swSpatial = Stopwatch()..start();
        final spatialPairs = spatial.queryCandidatePairs(colliders);
        swSpatial.stop();
        final spatialPairUs = swSpatial.elapsedMicroseconds;

        // Verify exact hit parity on candidate pairs
        expect(
          spatialPairs.length,
          equals(linearPairs.length),
          reason: 'Spatial candidate pair count must match Linear exactly',
        );
        expect(
          spatialPairs.map((p) => (p.$1.instanceId, p.$2.instanceId)).toList(),
          equals(
            linearPairs.map((p) => (p.$1.instanceId, p.$2.instanceId)).toList(),
          ),
          reason: 'Candidate pairs must match in identical sorted order',
        );

        // --- Benchmark 2: 100 Raycasts ---
        final rays = <Ray>[];
        for (var i = 0; i < 100; i++) {
          final t = (i / 100.0) * math.pi * 2.0;
          rays.add(
            Ray(
              origin: Vec3(math.cos(t) * 40.0, 5.0, math.sin(t) * 40.0),
              direction: Vec3(-math.cos(t), -0.1, -math.sin(t)),
            ),
          );
        }

        final swRayLinear = Stopwatch()..start();
        for (final ray in rays) {
          linear.queryRay(ray, maxDistance: 30.0);
        }
        swRayLinear.stop();
        final linearRayUs = swRayLinear.elapsedMicroseconds;

        final swRaySpatial = Stopwatch()..start();
        for (final ray in rays) {
          spatial.queryRay(ray, maxDistance: 30.0);
        }
        swRaySpatial.stop();
        final spatialRayUs = swRaySpatial.elapsedMicroseconds;

        // --- Benchmark 3: 100 Overlap Spheres ---
        final swSphereLinear = Stopwatch()..start();
        for (var i = 0; i < 100; i++) {
          final px = -40.0 + (i % 10) * 8.0;
          final pz = -40.0 + (i ~/ 10) * 8.0;
          linear.querySphere(Vec3(px, 0.5, pz), 2.5);
        }
        swSphereLinear.stop();
        final linearSphereUs = swSphereLinear.elapsedMicroseconds;

        final swSphereSpatial = Stopwatch()..start();
        for (var i = 0; i < 100; i++) {
          final px = -40.0 + (i % 10) * 8.0;
          final pz = -40.0 + (i ~/ 10) * 8.0;
          spatial.querySphere(Vec3(px, 0.5, pz), 2.5);
        }
        swSphereSpatial.stop();
        final spatialSphereUs = swSphereSpatial.elapsedMicroseconds;

        final pairSpeedup = linearPairUs / math.max(1, spatialPairUs);
        final raySpeedup = linearRayUs / math.max(1, spatialRayUs);
        final sphereSpeedup = linearSphereUs / math.max(1, spatialSphereUs);

        // Print benchmark telemetry for verification
        // ignore: avoid_print
        print(
          '\n=== Broadphase Benchmark on $totalExpected colliders ===\n'
          '  Candidate Pairs (1.28M pairs):\n'
          '    Linear:  ${(linearPairUs / 1000).toStringAsFixed(2)} ms\n'
          '    Spatial: ${(spatialPairUs / 1000).toStringAsFixed(2)} ms -> ${pairSpeedup.toStringAsFixed(1)}x speedup\n'
          '  100 Raycasts (maxD=30):\n'
          '    Linear:  ${(linearRayUs / 1000).toStringAsFixed(2)} ms\n'
          '    Spatial: ${(spatialRayUs / 1000).toStringAsFixed(2)} ms -> ${raySpeedup.toStringAsFixed(1)}x speedup\n'
          '  100 OverlapSpheres (r=2.5):\n'
          '    Linear:  ${(linearSphereUs / 1000).toStringAsFixed(2)} ms\n'
          '    Spatial: ${(spatialSphereUs / 1000).toStringAsFixed(2)} ms -> ${sphereSpeedup.toStringAsFixed(1)}x speedup\n',
        );

        // Speedup assertions:
        // Pairwise check must be substantially faster than the 1.28M brute-force loop
        expect(
          spatialPairUs,
          lessThan(linearPairUs),
          reason:
              'Spatial candidate pair search must be faster than linear brute-force',
        );
        expect(
          pairSpeedup,
          greaterThan(2.0),
          reason:
              'Spatial broadphase must achieve at least 2x (typically >20x) speedup on 1,500+ colliders',
        );

        // Raycast and Sphere queries must also be faster
        expect(spatialRayUs, lessThan(linearRayUs));
        expect(spatialSphereUs, lessThan(linearSphereUs));
      },
    );
  });
}
