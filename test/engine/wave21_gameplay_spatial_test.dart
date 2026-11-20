/// Wave 21 gameplay & spatial tests: CharacterController coyote/buffer/platform
/// carry, exact SpatialGrid2D queries & DDA raycast, and Camera batch frustum
/// culling (P13-W21-A..C).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group(
    'P13-W21-A — CharacterController Coyote Time, Jump Buffer & Moving Platform',
    () {
      test(
        'supports coyote jump after stepping off ledge, jump buffering, and moving platform carry',
        () {
          final engine = Engine(HeadlessHost());
          final platform = engine.scene.createGameObject(
            'MovingPlatform',
            position: const Vec3(0, -0.5, 0),
          );
          platform.addComponent(
            BoxCollider(size: const Vec3(4, 1, 4), isTrigger: false),
          );

          final player = engine.scene.createGameObject(
            'Player',
            position: const Vec3(0, 0.05, 0),
          );
          final cc = player.addComponent(
            CharacterController(
              radius: 0.4,
              height: 1.8,
              center: const Vec3(0, 0.9, 0),
              coyoteTime: 0.15,
              jumpBufferTime: 0.15,
            ),
          );

          // Step down onto platform -> grounded on MovingPlatform
          for (var i = 0; i < 6; i++) {
            engine.step(0.02);
            cc.simpleMove(Vec3.zero);
          }
          expect(cc.isGrounded, isTrue);
          expect(cc.groundObject, same(platform));

          // Move platform +2.0 on X -> character carries with platform automatically
          final startX = player.transform.position.x;
          platform.transform.position = const Vec3(2.0, -0.5, 0);
          engine.step(0.02);
          cc.simpleMove(Vec3.zero);
          expect(player.transform.position.x, closeTo(startX + 2.0, 0.05));

          // Step off the edge of the platform -> no longer grounded, but coyote jump succeeds
          player.transform.position = const Vec3(20.0, 5.0, 0);
          engine.step(0.02);
          cc.move(const Vec3(0, -0.05, 0));
          expect(cc.isGrounded, isFalse);
          expect(cc.canCoyoteJump, isTrue);

          cc.queueJump();
          expect(cc.hasBufferedJump, isTrue);
          expect(cc.consumeBufferedJump(8.0), isTrue);
          expect(cc.verticalSpeed, closeTo(8.0, 1e-4));
          expect(cc.canCoyoteJump, isFalse);
        },
      );
    },
  );

  group('P13-W21-B — SpatialGrid2D Exact Circle, Nearest & DDA Ray Queries', () {
    test(
      'performs cell-coherent update, exact circle filtering, nearest lookup, and DDA raycast',
      () {
        final grid = SpatialGrid2D<String>(cellSize: 10.0);
        grid.insert('near', const Vec2(2, 2), 1.0);
        grid.insert('corner', const Vec2(9.5, 9.5), 0.5);
        grid.insert('far', const Vec2(45, 5), 1.0);

        // Exact circle at (0,0) radius 4 includes 'near' (~2.83) but excludes 'corner' (~13.4)
        final exact = grid.queryCircleExact(const Vec2(0, 0), 4.0);
        expect(exact, equals(['near']));

        // Nearest neighbor respects filter and maxRadius
        expect(grid.findNearest(const Vec2(1, 1)), equals('near'));
        expect(
          grid.findNearest(const Vec2(1, 1), where: (id) => id != 'near'),
          equals('corner'),
        );

        // Fast cell-coherent update moves 'corner' into another cell cleanly
        grid.update('corner', const Vec2(25, 5), 0.5);
        expect(grid.findNearest(const Vec2(24, 5), maxRadius: 3.0), 'corner');

        // DDA ray from (0,5) to (50,5) traverses cells holding 'near', 'corner', and 'far'
        final rayHits = grid.queryRay(const Vec2(0, 5), const Vec2(50, 5));
        expect(rayHits, containsAll(['near', 'corner', 'far']));
      },
    );
  });

  group('P13-W21-C — Camera Batch Frustum Culling & Visibility Helpers', () {
    test(
      'collectVisibleMeshes filters by frustum and cullingMask in a single pass',
      () {
        final engine = Engine(HeadlessHost());
        final camGo = engine.scene.createGameObject(
          'MainCam',
          position: const Vec3(0, 0, 10),
        );
        final cam = camGo.addComponent(
          Camera(near: 0.1, far: 50.0, cullingMask: LayerMask.fromLayer(0)),
        );

        // Directly in front of camera (-Z) on layer 0 -> visible
        final front = engine.scene.createPrimitive(
          PrimitiveType.cube,
          name: 'FrontCube',
          position: const Vec3(0, 0, 0),
        );
        // Behind camera (+Z) -> outside frustum
        final behind = engine.scene.createPrimitive(
          PrimitiveType.cube,
          name: 'BehindCube',
          position: const Vec3(0, 0, 25),
        );
        // In front of camera but on culled layer 3 -> excluded by cullingMask
        final hiddenLayer = engine.scene.createPrimitive(
          PrimitiveType.cube,
          name: 'HiddenLayerCube',
          position: const Vec3(1, 0, 0),
        );
        hiddenLayer.layer = 3;

        engine.step(0.016);

        expect(cam.isPointVisible(const Vec3(0, 0, 0)), isTrue);
        expect(cam.isPointVisible(const Vec3(0, 0, 25)), isFalse);
        expect(
          cam.isAabbVisible(Aabb(const Vec3(-1, -1, -1), const Vec3(1, 1, 1))),
          isTrue,
        );

        final visible = cam.collectVisibleMeshes();
        expect(visible.map((r) => r.gameObject), equals([front]));
        expect(visible.map((r) => r.gameObject), isNot(contains(behind)));
        expect(visible.map((r) => r.gameObject), isNot(contains(hiddenLayer)));
      },
    );
  });
}
