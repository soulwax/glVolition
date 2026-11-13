/// Cameras, input actions/rebinding, transforms, math/curves, tweens, blendspaces & IK.
library;

import 'dart:math' as math;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../support/subsystems_test_helpers.dart';

void main() {
  group('E4 — Camera.ortho & SpriteAnimator', () {
    test(
      'Camera.ortho and screenToGroundPlane project rays onto y == groundHeight',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final camGo = engine.scene.createGameObject(
          'IsoCam',
          position: const Vec3(0, 20, 20),
          rotation: lookRotation(const Vec3(0, -20, -20)),
          components: [Camera.ortho(orthoHeight: 20)],
        );
        final cam = camGo.getComponent<Camera>()!;
        engine.step(0.016);

        // Center of 1280x720 viewport should hit near (0, 0, 0) on ground plane y=0
        final hit = cam.screenToGroundPlane(640, 360, 0);
        expect(hit, isNotNull);
        expect(hit!.x.abs(), lessThan(1e-3));
        expect(hit.y, closeTo(0, 1e-5));
        expect(hit.z.abs(), lessThan(1e-3));
      },
    );

    test(
      'SpriteAnimator steps through clips and updates sibling SpriteRenderer',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.scene.createGameObject(
          'Cam2D',
          components: [Camera2DComponent()],
        );

        final f0 = SpriteRegion(
          texture: null,
          width: 16,
          height: 16,
          u0: 0,
          v0: 0,
          u1: 0.5,
          v1: 1,
        );
        final f1 = SpriteRegion(
          texture: null,
          width: 16,
          height: 16,
          u0: 0.5,
          v0: 0,
          u1: 1.0,
          v1: 1,
        );

        final sr = SpriteRenderer(region: f0);
        final anim = SpriteAnimator(
          clips: {
            'run': [f0, f1],
          },
          fps: 10,
          initialClip: 'run',
        );
        engine.scene.createGameObject('Runner', components: [sr, anim]);

        engine.step(0.01);
        expect(sr.region, same(f0));

        engine.step(0.12); // total > 0.1s -> frame 1
        expect(sr.region, same(f1));
      },
    );
  });

  group('E5 — 3D Animator', () {
    test(
      'Animator plays keyframe AnimationClip and respects time.timeScale',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final go = engine.scene.createGameObject('Platform');
        final clip = AnimationClip(
          name: 'slide',
          duration: 1.0,
          loopMode: LoopMode.once,
          tracks: [
            Vector3Track(
              target: go.node,
              keyframes: const [
                Keyframe(0.0, Vec3(0, 0, 0)),
                Keyframe(1.0, Vec3(10, 0, 0)),
              ],
            ),
          ],
        );
        go.addComponent(Animator(initialClips: [clip], defaultClip: 'slide'));

        for (var i = 0; i < 10; i++) {
          engine.step(0.05);
        }
        expect(go.node.localTransform.translation.x, closeTo(5.0, 1e-2));
      },
    );
  });

  group('E9 — BehaviourTweenExt', () {
    test(
      'BehaviourTweenExt tweens localPosition and localScale with Curves and pingPong',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final go = engine.scene.createGameObject(
          'Box',
          components: [HealthBehaviour()],
        );
        final beh = go.getComponent<HealthBehaviour>()!;

        var completed = false;
        beh.tweenPosition(
          const Vec3(10, 4, -2),
          duration: 0.2,
          curve: Curves.easeOutCubic,
          onComplete: () => completed = true,
        );
        beh.tweenScale(2.5, duration: 0.2, curve: Curves.linear);

        engine.step(0.1);
        expect(
          go.transform.localPosition.x,
          greaterThan(5.0),
        ); // easeOutCubic > 0.5 at t=0.5
        expect(go.transform.localScale, closeTo(1.75, 1e-4));
        expect(completed, isFalse);

        engine.step(0.1);
        expect(go.transform.localPosition.x, closeTo(10.0, 1e-4));
        expect(go.transform.localPosition.y, closeTo(4.0, 1e-4));
        expect(go.transform.localScale, closeTo(2.5, 1e-4));
        expect(completed, isTrue);
      },
    );
  });

  group('E11 — Camera.worldToScreenPoint & UIWorldAnchor', () {
    test(
      'Camera.worldToScreenPoint and UIWorldAnchor project 3D target onto UICanvas',
      () {
        final host = HeadlessHost();
        host.graphics
          ..viewportWidth = 640
          ..viewportHeight = 360;
        final engine = Engine(host);

        final cam = Camera(fovYRadians: 1.0);
        engine.scene.createGameObject(
          'MainCam',
          position: const Vec3(0, 0, 5),
          components: [cam],
        );
        final unit = engine.scene.createGameObject('Unit', position: Vec3.zero);

        final bar = UIProgressBar(width: 40, height: 6, value: 0.75);
        final anchor = UIWorldAnchor(target: unit, child: bar);
        final canvas = UICanvas(designWidth: 640, designHeight: 360)
          ..add(anchor);
        engine.scene.createGameObject('HUD', components: [canvas]);

        engine.step(0.016);
        expect(anchor.isInFrontOfCamera, isTrue);
        // Unit at origin dead-center in front of camera -> bar centered at (320 - 20, 180 - 3)
        expect(bar.x, closeTo(300.0, 1.0));
        expect(bar.y, closeTo(177.0, 1.0));

        // Move unit behind camera (z = 10 > cam.z = 5)
        unit.transform.position = const Vec3(0, 0, 10);
        engine.step(0.016);
        expect(anchor.isInFrontOfCamera, isFalse);
      },
    );
  });

  group('E12 — SmoothFollowCamera, CinematicTourCamera & Camera.shake', () {
    test(
      'SmoothFollowCamera tracks target, CinematicTourCamera completes tour, and Camera.shake perturbs view',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final hero = engine.scene.createGameObject(
          'Hero',
          position: const Vec3(10, 0, -5),
        );
        final follow = SmoothFollowCamera(
          target: hero,
          distance: 6.0,
          height: 2.0,
        );
        final cam = Camera();
        final camGo = engine.scene.createGameObject(
          'FollowCam',
          components: [cam, follow],
        );

        engine.step(0.1);
        expect(
          (camGo.transform.position - hero.transform.position).length,
          lessThan(12.0),
        );

        // Trigger trauma shake and verify shakeEngine perturbs the view after stepping
        final unshakenEye = cam.toCameraView(16 / 9).eye;
        cam.shake(trauma: 0.8);
        engine.step(0.05);
        final shakenEye = cam.toCameraView(16 / 9).eye;
        expect((shakenEye - unshakenEye).length, greaterThan(1e-4));

        // CinematicTourCamera non-looping tour fires onCompleted
        var tourFinished = false;
        final tour = CinematicTourCamera(
          waypoints: const [
            CameraWaypoint(eye: Vec3(0, 2, 10), target: Vec3.zero),
            CameraWaypoint(eye: Vec3(5, 4, 5), target: Vec3.zero),
          ],
          duration: 0.2,
          loop: false,
          onCompleted: () => tourFinished = true,
        );
        engine.scene.createGameObject('TourCam', components: [Camera(), tour]);
        engine.step(0.1);
        expect(tour.progress, closeTo(0.5, 1e-2));
        expect(tourFinished, isFalse);

        engine.step(0.15);
        expect(tour.progress, closeTo(1.0, 1e-4));
        expect(tourFinished, isTrue);
      },
    );
  });

  group('E17 — Spatial Camera Shake & Scene.explode Camera Integration', () {
    test(
      'Camera.shakeAt, Scene.shakeCamerasAt, and Scene.explode shake nearby cameras and query input metadata',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final nearCam = engine.scene
            .createGameObject(
              'NearCam',
              position: const Vec3(0, 0, 5),
              components: [Camera()],
            )
            .getComponent<Camera>()!;

        final farCam = engine.scene
            .createGameObject(
              'FarCam',
              position: const Vec3(0, 0, 50),
              components: [Camera()],
            )
            .getComponent<Camera>()!;

        // Unified scene.explode shakes nearCam but leaves farCam untouched
        engine.scene.explode(
          Vec3.zero,
          force: 15.0,
          radius: 6.0,
          cameraTrauma: 0.8,
          cameraMaxDistance: 20.0,
        );

        expect(nearCam.shakeEngine.trauma, greaterThan(0.0));
        expect(farCam.shakeEngine.trauma, closeTo(0.0, 1e-6));

        // InputActions queries
        expect(engine.input.hasButton('Submit'), isTrue);
        expect(engine.input.hasButton('UnknownButton'), isFalse);
        expect(engine.input.hasAxis('Horizontal'), isTrue);
        expect(engine.input.hasAxis('UnknownAxis'), isFalse);
        expect(engine.input.buttonNames, contains('Submit'));
        expect(engine.input.axisNames, contains('Vertical'));
        expect(engine.input.getAxisRaw('Horizontal'), closeTo(0.0, 1e-6));
      },
    );
  });

  group('E18 — TransformComponent Ergonomics', () {
    test('TransformComponent directional properties and rotation helpers', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final go = engine.scene.createGameObject('Target');
      final t = go.transform;

      // Identity orientation: forward = (0, 0, 1), up = (0, 1, 0), right = (1, 0, 0)
      expect(t.back, equals(-t.forward));
      expect(t.left, equals(-t.right));
      expect(t.down, equals(-t.up));

      // Rotate 90 deg around Y
      t.rotateY(math.pi * 0.5);
      expect(t.right.x, closeTo(0, 1e-5));
      expect(t.right.z, closeTo(-1, 1e-5));

      // Reset
      t.resetLocal();
      expect(t.localPosition, Vec3.zero);
      expect(t.localRotation, Quat.identity);
      expect(t.localScale, 1.0);
    });
  });

  group('E19 — Camera2D Follow & Clamp', () {
    test(
      'Camera2DComponent smoothFollow and clampToBounds constrain ortho camera view',
      () {
        final cam = Camera2DComponent(
          designWidth: 400,
          designHeight: 225,
          followTransform: false,
        );
        cam.x = 0;
        cam.y = 0;

        // Smooth follow towards (100, 50)
        cam.smoothFollow(const Vec2(100, 50), smoothing: 10.0, dt: 0.1);
        expect(cam.x, greaterThan(0.0));
        expect(cam.x, lessThan(100.0));
        expect(cam.y, greaterThan(0.0));
        expect(cam.y, lessThan(50.0));

        // Repeated follow converges
        for (var i = 0; i < 60; i++) {
          cam.smoothFollow(const Vec2(100, 50), smoothing: 10.0, dt: 0.1);
        }
        expect(cam.x, closeTo(100.0, 1e-2));
        expect(cam.y, closeTo(50.0, 1e-2));

        // Clamping to bounds [10..80, 5..30]
        cam.clampToBounds(minX: 10, maxX: 80, minY: 5, maxY: 30);
        expect(cam.x, closeTo(80.0, 1e-5));
        expect(cam.y, closeTo(30.0, 1e-5));
      },
    );
  });

  group('E20 — Camera Viewport Projections & CullingMask', () {
    test(
      'Camera worldToViewportPoint, viewportToWorldPoint, and cullingMask serialization',
      () {
        final host = HeadlessHost();
        host.graphics
          ..viewportWidth = 800
          ..viewportHeight = 600;
        final engine = Engine(host);

        final camObj = engine.scene.createGameObject(
          'MainCamera',
          position: const Vec3(0, 0, 5),
          components: [Camera(cullingMask: 0x05)],
        );
        final cam = camObj.getComponent<Camera>()!;
        expect(cam.cullingMask, 0x05);

        // Point right at the center of the camera's view (0, 0, 0)
        final vpCenter = cam.worldToViewportPoint(const Vec3(0, 0, 0));
        expect(vpCenter, isNotNull);
        expect(vpCenter!.x, closeTo(0.5, 1e-3));
        expect(vpCenter.y, closeTo(0.5, 1e-3));
        expect(vpCenter.depth, greaterThan(0));

        // Reconstruct world ray at distance = 5.0
        final reconstructed = cam.viewportToWorldPoint(Vec3(0.5, 0.5, 5.0));
        expect(reconstructed, isNotNull);
        expect(reconstructed!.x, closeTo(0.0, 1e-3));
        expect(reconstructed.y, closeTo(0.0, 1e-3));
        expect(reconstructed.z, closeTo(0.0, 1e-3));

        // Round-trip Camera via SceneSerializer to ensure cullingMask is preserved
        final json = SceneSerializer.toJson(
          engine.scene,
          registry: engine.registry,
        );
        final restored = SceneSerializer.fromJson(
          json,
          registry: engine.registry,
        );
        final restoredCam = restored.find('MainCamera')?.getComponent<Camera>();
        expect(restoredCam, isNotNull);
        expect(restoredCam!.cullingMask, 0x05);
      },
    );
  });

  group('E21 — Time.smoothDamp', () {
    test(
      'Time.smoothDamp and smoothDampVec3 converge critically to target without oscillation',
      () {
        final time = Time();

        // Smooth damp scalar from 0 to 100 with smoothTime = 0.2s
        var current = 0.0;
        var velocity = 0.0;
        const target = 100.0;

        for (var i = 0; i < 30; i++) {
          final res = time.smoothDamp(
            current,
            target,
            velocity,
            smoothTime: 0.2,
            dt: 0.016,
          );
          current = res.current;
          velocity = res.velocity;
        }

        expect(current, greaterThan(80.0));
        expect(current, lessThanOrEqualTo(100.0));

        // After 60 more steps (total ~1.44s), converges to target
        for (var i = 0; i < 60; i++) {
          final res = time.smoothDamp(
            current,
            target,
            velocity,
            smoothTime: 0.2,
            dt: 0.016,
          );
          current = res.current;
          velocity = res.velocity;
        }
        expect(current, closeTo(100.0, 1e-2));
        expect(velocity, closeTo(0.0, 1e-2));

        // Smooth damp Vec3
        var vCurrent = Vec3.zero;
        var vVelocity = Vec3.zero;
        const vTarget = Vec3(10, 20, 30);

        for (var i = 0; i < 90; i++) {
          final res = time.smoothDampVec3(
            vCurrent,
            vTarget,
            vVelocity,
            smoothTime: 0.2,
            dt: 0.016,
          );
          vCurrent = res.current;
          vVelocity = res.velocity;
        }
        expect(vCurrent.x, closeTo(10.0, 1e-3));
        expect(vCurrent.y, closeTo(20.0, 1e-3));
        expect(vCurrent.z, closeTo(30.0, 1e-3));
      },
    );
  });

  group('E22 — Multi-Camera Split-Screen Viewports', () {
    test(
      'Camera multi-viewport split-screen and depth ordering round-trip via SceneSerializer',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // Player 1 Camera (left half: x: 0, y: 0, w: 0.5, h: 1)
        final cam1Obj = engine.scene.createGameObject(
          'Player1Camera',
          position: const Vec3(0, 1.5, 5),
          components: [
            Camera(
              normalizedViewportRect: const Vec4(0, 0, 0.5, 1.0),
              depth: 0,
            ),
          ],
        );

        // Player 2 Camera (right half: x: 0.5, y: 0, w: 0.5, h: 1)
        final cam2Obj = engine.scene.createGameObject(
          'Player2Camera',
          position: const Vec3(10, 1.5, 5),
          components: [
            Camera(
              normalizedViewportRect: const Vec4(0.5, 0, 0.5, 1.0),
              depth: 1,
            ),
          ],
        );

        final c1 = cam1Obj.getComponent<Camera>()!;
        final c2 = cam2Obj.getComponent<Camera>()!;
        expect(c1.normalizedViewportRect.z, closeTo(0.5, 1e-4));
        expect(c2.normalizedViewportRect.x, closeTo(0.5, 1e-4));
        expect(c2.depth, 1);

        // Verify serialization round-trip of depth and properties
        final json = SceneSerializer.toJson(
          engine.scene,
          registry: engine.registry,
        );
        final restored = SceneSerializer.fromJson(
          json,
          registry: engine.registry,
        );
        final restoredC2 = restored
            .find('Player2Camera')
            ?.getComponent<Camera>();
        expect(restoredC2, isNotNull);
        expect(restoredC2!.depth, 1);
      },
    );
  });

  group('E23 — InputActions.getVector2', () {
    test(
      'InputActions.getVector2 evaluates clamped/normalized composite 2D input',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // Only Right held -> (1.0, 0.0)
        host.input.press('KeyD');
        expect(engine.input.getVector2().x, closeTo(1.0, 1e-4));
        expect(engine.input.getVector2().y, closeTo(0.0, 1e-4));

        // Both Right + Up held -> (1.0, 1.0) normalized to ~ (0.7071, 0.7071)
        host.input.press('KeyW');
        final diag = engine.input.getVector2(normalize: true);
        expect(diag.x, closeTo(math.sqrt(0.5), 1e-4));
        expect(diag.y, closeTo(math.sqrt(0.5), 1e-4));
        expect(diag.length, closeTo(1.0, 1e-4));

        // Without normalization -> (1.0, 1.0)
        final unnorm = engine.input.getVector2(normalize: false);
        expect(unnorm.x, closeTo(1.0, 1e-4));
        expect(unnorm.y, closeTo(1.0, 1e-4));
      },
    );
  });

  group('E24 — Mathfx Utilities & ParallaxBackground2D', () {
    test(
      'Mathfx evaluates inverseLerp, pingPong, repeat, deltaAngle, moveTowards, and damp',
      () {
        // inverseLerp
        expect(Mathfx.inverseLerp(10, 20, 15), closeTo(0.5, 1e-5));
        expect(Mathfx.inverseLerp(10, 20, 5), closeTo(0.0, 1e-5));
        expect(Mathfx.inverseLerp(10, 20, 25), closeTo(1.0, 1e-5));

        // pingPong
        expect(Mathfx.pingPong(0.0, 5.0), closeTo(0.0, 1e-5));
        expect(Mathfx.pingPong(3.0, 5.0), closeTo(3.0, 1e-5));
        expect(Mathfx.pingPong(7.0, 5.0), closeTo(3.0, 1e-5));
        expect(Mathfx.pingPong(10.0, 5.0), closeTo(0.0, 1e-5));

        // repeat
        expect(Mathfx.repeat(2.5, 5.0), closeTo(2.5, 1e-5));
        expect(Mathfx.repeat(7.5, 5.0), closeTo(2.5, 1e-5));

        // deltaAngle & deltaAngleDeg
        expect(
          Mathfx.deltaAngle(0, math.pi * 0.5),
          closeTo(math.pi * 0.5, 1e-5),
        );
        expect(
          Mathfx.deltaAngle(math.pi * 0.9, -math.pi * 0.9),
          closeTo(math.pi * 0.2, 1e-4),
        );
        expect(Mathfx.deltaAngleDeg(10, 350), closeTo(-20.0, 1e-4));

        // moveTowards
        expect(Mathfx.moveTowards(0.0, 10.0, 2.5), closeTo(2.5, 1e-5));
        expect(Mathfx.moveTowards(9.0, 10.0, 2.5), closeTo(10.0, 1e-5));

        // moveTowardsVec3
        final v1 = Mathfx.moveTowardsVec3(Vec3.zero, const Vec3(10, 0, 0), 3.0);
        expect(v1.x, closeTo(3.0, 1e-4));
        expect(v1.y, closeTo(0.0, 1e-4));

        // damp & dampVec3
        final d = Mathfx.damp(0.0, 10.0, 5.0, 0.1);
        expect(d, greaterThan(0.0));
        expect(d, lessThan(10.0));

        final dv = Mathfx.dampVec3(Vec3.zero, const Vec3(10, 20, 0), 5.0, 0.1);
        expect(dv.x, greaterThan(0.0));
        expect(dv.y, greaterThan(0.0));
      },
    );

    test(
      'ParallaxBackground2D advances parallax layers with camera delta and autoScroll',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final camGo = engine.scene.createGameObject(
          'Cam2D',
          position: Vec3.zero,
        );
        camGo.addComponent(
          Camera2DComponent(designWidth: 640, designHeight: 360),
        );

        final bg = ParallaxBackground2D(
          layers: [
            ParallaxLayer(
              factor: const Vec2(0.2, 0.0),
              autoScroll: const Vec2(10.0, 0.0),
              width: 640.0,
              repeatX: true,
            ),
            ParallaxLayer(
              factor: const Vec2(0.8, 0.0),
              autoScroll: Vec2.zero,
              width: 640.0,
              repeatX: true,
            ),
          ],
        );
        engine.scene.createGameObject('Background', components: [bg]);

        // Initial frame establishes baseline position
        engine.step(0.1);
        expect(
          bg.layers[0].offset.x,
          closeTo(1.0, 1e-4),
        ); // 10.0 * 0.1s autoScroll = 1.0

        // Move camera 100 units right over 0.1s
        camGo.transform.position = const Vec3(100.0, 0, 0);
        engine.step(0.1);

        // Layer 0: prev offset (1.0) + autoScroll (10 * 0.1 = 1.0) + camera delta (100 * 0.2 = 20) = 22.0
        expect(bg.layers[0].offset.x, closeTo(22.0, 1e-3));

        // Layer 1: camera delta (100 * 0.8 = 80)
        expect(bg.layers[1].offset.x, closeTo(80.0, 1e-3));
      },
    );
  });

  group('E25 — LookAtConstraint & FollowConstraint', () {
    test(
      'LookAtConstraint and FollowConstraint update orientation and spatial position',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final target = engine.scene.createGameObject(
          'Target',
          position: const Vec3(10.0, 0, 0),
        );
        final turret = engine.scene.createGameObject(
          'Turret',
          position: Vec3.zero,
        );
        turret.addComponent(
          LookAtConstraint(target: target.transform, weight: 1.0),
        );

        engine.step(0.016);
        // Turret's forward (-Z) should now point towards Target (+X), so forward.x is ~ 1.0
        expect(turret.transform.forward.x, closeTo(1.0, 1e-3));
        expect(turret.transform.forward.y, closeTo(0.0, 1e-3));

        // Follower follows target with offset (0, 2, 0) and lockY: true
        final follower = engine.scene.createGameObject(
          'Follower',
          position: Vec3.zero,
        );
        follower.addComponent(
          FollowConstraint(
            target: target.transform,
            offset: const Vec3(0, 2, 0),
            smoothing: 0.0,
            lockY: true,
          ),
        );

        engine.step(0.016);
        expect(follower.transform.position.x, closeTo(10.0, 1e-4));
        expect(
          follower.transform.position.y,
          closeTo(0.0, 1e-4),
        ); // Y locked to 0
      },
    );
  });

  group('E29 — Transform & GameObject Tweening (voxtween)', () {
    test('E29: Transform and GameObject tweening with voxtween', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.time.maximumDeltaTime = 10.0;

      final go = engine.scene.createGameObject('Hero');
      go.transform.position = Vec3.zero;
      go.transform.localScale = 1.0;

      var posCompleted = false;
      var scaleCompleted = false;

      go.transform
          .tweenPosition(const Vec3(10, 0, 0), 1.0, ease: Ease.linear)
          .onComplete(() => posCompleted = true);

      go
          .tweenScale(2.0, 1.0, ease: Ease.linear)
          .onComplete(() => scaleCompleted = true);

      // Step half second (0.5s)
      engine.step(0.5);
      expect(go.transform.position.x, closeTo(5.0, 1e-3));
      expect(go.transform.localScale, closeTo(1.5, 1e-3));
      expect(posCompleted, isFalse);
      expect(scaleCompleted, isFalse);

      // Step remaining half second
      engine.step(0.5);
      expect(go.transform.position.x, closeTo(10.0, 1e-3));
      expect(go.transform.localScale, closeTo(2.0, 1e-3));
      expect(posCompleted, isTrue);
      expect(scaleCompleted, isTrue);

      // Destroying GameObject cleans up active tweens
      go.transform.tweenPosition(const Vec3(100, 0, 0), 1.0);
      go.destroy();
      engine.step(0.016);
      expect(TweenManager.instance.activeCount, equals(0));
    });
  });

  group('E34 — TwoBoneIk, AimIk & BlendTree', () {
    test(
      'E34: TwoBoneIkComponent solves limb kinematics towards target position',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final upperLeg = engine.scene.createGameObject(
          'UpperLeg',
          position: const Vec3(0.0, 2.0, 0.0),
        );
        final lowerLeg = engine.scene.createGameObject(
          'LowerLeg',
          position: const Vec3(0.0, -1.0, 0.0),
          parent: upperLeg,
        );
        final foot = engine.scene.createGameObject(
          'Foot',
          position: const Vec3(0.0, -1.0, 0.0),
          parent: lowerLeg,
        );

        const targetPos = Vec3(0.4, 0.2, 0.0);
        const polePos = Vec3(0.0, 1.0, 1.0);

        upperLeg.addComponent(
          TwoBoneIkComponent(
            rootBone: upperLeg,
            midBone: lowerLeg,
            endEffector: foot,
            targetPosition: targetPos,
            polePosition: polePos,
          ),
        );

        engine.step(0.05);

        // Foot world position should reach target
        expect((foot.transform.position - targetPos).length, lessThan(0.05));
        // Knee bent forward towards pole (+Z)
        expect(lowerLeg.transform.position.z, greaterThan(0.0));
      },
    );

    test('E34: AimIkComponent directs forward vector towards 3D target', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final head = engine.scene.createGameObject(
        'Head',
        position: const Vec3(0.0, 1.5, 0.0),
      );
      const targetPos = Vec3(
        10.0,
        1.5,
        -10.0,
      ); // 45 deg right/forward in -Z space

      head.addComponent(AimIkComponent(bone: head, targetPosition: targetPos));

      engine.step(0.05);

      final toTarget = (targetPos - head.transform.position).normalized;
      final aimDot = head.transform.forward.dot(toTarget);
      expect(aimDot, closeTo(1.0, 0.05));
    });

    test(
      'E34: BlendTreeComponent evaluates 1D blend tree and updates bone transforms',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final character = engine.scene.createGameObject('Character');
        final arm = engine.scene.createGameObject('Arm', parent: character);

        final idlePose = Pose({
          'Arm': BoneTransform(position: const AnimVec3(0.0, 1.0, 0.0)),
        });
        final runPose = Pose({
          'Arm': BoneTransform(position: const AnimVec3(0.0, 1.0, 4.0)),
        });

        final blendTree = Blend1DNode(
          parameterName: 'speed',
          entries: [
            Blend1DEntry(
              threshold: 0.0,
              node: ClipNode(
                name: 'Idle',
                duration: 1.0,
                sampler: (_) => idlePose,
              ),
            ),
            Blend1DEntry(
              threshold: 10.0,
              node: ClipNode(
                name: 'Run',
                duration: 1.0,
                sampler: (_) => runPose,
              ),
            ),
          ],
        );

        character.addComponent(
          BlendTreeComponent(
            rootNode: blendTree,
            initialParameters: {'speed': 5.0}, // 50% blend
          ),
        );

        engine.step(0.05);

        // Arm Z position should be halfway between 0.0 and 4.0 -> 2.0
        expect(arm.transform.localPosition.z, closeTo(2.0, 1e-4));
        expect(arm.transform.localPosition.y, closeTo(1.0, 1e-4));
      },
    );
  });

  group('E40 — InputManagerComponent & VirtualGamepad', () {
    test(
      'E40: InputManagerComponent processes WASD Vector2, chord combos, and ActionMap priorities',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final im = InputManagerComponent();
        final gameplay = im.actions.addMap('Gameplay', priority: 0);
        gameplay.addVector2('Move', [Vector2Binding.wasd]);
        gameplay.addButton('Jump', [const KeyBinding('Space')]);
        gameplay.addButton('QuickSave', [
          const ChordBinding(['ControlLeft', 'KeyS']),
        ]);

        final pauseMenu = im.actions.addMap(
          'Menu',
          priority: 10,
          enabled: false,
          blocksLowerMaps: true,
        );
        pauseMenu.addButton('Confirm', [const KeyBinding('Space')]);

        engine.scene.createGameObject('InputSystem', components: [im]);

        // Press W + D for diagonal normalized movement
        host.input.press('KeyW');
        host.input.press('KeyD');
        engine.step(0.016);
        host.input.endFrame();

        final move = im.getVector2('Move');
        expect(move.length, closeTo(1.0, 1e-3));
        expect(move.x, closeTo(0.7071, 1e-3));
        expect(move.y, closeTo(0.7071, 1e-3));

        // QuickSave chord Ctrl+S
        host.input.press('ControlLeft');
        engine.step(0.016);
        expect(im.isPressed('QuickSave'), isFalse);

        host.input.press('KeyS');
        engine.step(0.016);
        expect(im.wasPressed('QuickSave'), isTrue);

        // Pause Menu active -> Space is consumed by Menu and blocked from Gameplay Jump
        pauseMenu.enabled = true;
        host.input.press('Space');
        engine.step(0.016);
        expect(im.isPressed('Menu/Confirm'), isTrue);
        expect(im.isPressed('Gameplay/Jump'), isFalse);
      },
    );

    test(
      'E40: InputManagerComponent interactive rebinding + storage profile persistence',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final im = InputManagerComponent();
        final gameplay = im.actions.addMap('Gameplay');
        final jump = gameplay.addButton('Jump', [const KeyBinding('Space')]);
        engine.scene.createGameObject('InputSystem', components: [im]);

        // Start rebinding Jump
        String? boundControl;
        im.rebinder.startListening(
          map: gameplay,
          action: jump,
          onCompleted: (ctrl) => boundControl = ctrl,
        );

        // Step frame where player presses KeyF
        host.input.press('KeyF');
        engine.step(0.016);
        host.input.endFrame();

        expect(boundControl, equals('KeyF'));
        expect(im.isPressed('Jump'), isTrue);

        // Save profile to host.storage
        im.saveProfile('player_controls');

        // Reload into a fresh engine & InputManagerComponent sharing host storage
        final engine2 = Engine(host);
        final im2 = InputManagerComponent();
        final gameplay2 = im2.actions.addMap('Gameplay');
        gameplay2.addButton('Jump', [const KeyBinding('Space')]);
        engine2.scene.createGameObject('InputSystem2', components: [im2]);

        expect(im2.loadProfile('player_controls'), isTrue);
        final loadedBinding = im2.action('Jump')!.bindings.first as KeyBinding;
        expect(loadedBinding.control, equals('KeyF'));
      },
    );

    test(
      'E40: VirtualGamepad drives InputManagerComponent actions and renders via VirtualGamepadUI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final vpad = VirtualGamepad(
          sticks: [
            VirtualStick(
              centerX: 80,
              centerY: 280,
              radius: 40,
              axisXName: 'VirtualLeftX',
              axisYName: 'VirtualLeftY',
            ),
          ],
          buttons: [
            VirtualButton(
              centerX: 520,
              centerY: 280,
              radius: 30,
              controlName: 'GamepadA',
              label: 'A',
            ),
          ],
        );

        final im = InputManagerComponent(virtualGamepad: vpad);
        final mobile = im.actions.addMap('Mobile');
        mobile.addVector2('Move', [
          const Vector2Binding(
            analogX: 'VirtualLeftX',
            analogY: 'VirtualLeftY',
          ),
        ]);
        mobile.addButton('Fire', [const KeyBinding('GamepadA')]);
        engine.scene.createGameObject('MobileInput', components: [im]);

        // Multi-touch: finger 1 pulls stick left-up, finger 2 holds Fire button
        im.feedVirtualPointers([
          const VirtualTouchPointer(id: 1, x: 80, y: 280, isDown: true),
          const VirtualTouchPointer(id: 2, x: 520, y: 280, isDown: true),
        ]);
        engine.step(0.016);
        expect(im.isPressed('Fire'), isTrue);

        // Move finger 1 right to edge (+40px -> +1.0 X)
        im.feedVirtualPointers([
          const VirtualTouchPointer(id: 1, x: 120, y: 280, isDown: true),
        ]);
        engine.step(0.016);
        expect(im.getVector2('Move').x, closeTo(1.0, 1e-4));
        expect(im.isPressed('Fire'), isFalse);

        // Verify VirtualGamepadUI renders circles and button label
        final ui = VoxUiContext();
        ui.beginFrame(VoxInput());
        VirtualGamepadUI.render(ui, vpad);
        final dl = ui.endFrame();
        expect(
          dl.commands.any((c) => c.type == DrawCmdType.circleFilled),
          isTrue,
        );
        expect(
          dl.commands.any((c) => c.type == DrawCmdType.text && c.text == 'A'),
          isTrue,
        );
      },
    );
  });

  group('E50 — CameraBrainComponent & VirtualCameras', () {
    test(
      'E50: CameraBrainComponent blends VirtualCameraComponents, pulls in on obstacles & renders CameraDirectorUI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final hero = engine.scene.createGameObject(
          'Hero',
          position: const Vec3(0, 0, 0),
          components: [CapsuleCollider(radius: 0.4, height: 1.8)],
        );

        // Trigger zone in front of the wall must be ignored; solid wall at z=5 intercepts the 10m orbit arm.
        engine.scene.createGameObject(
          'AmbientTrigger',
          position: const Vec3(0, 1.2, 2.5),
          components: [
            BoxCollider(size: const Vec3(4.0, 4.0, 1.0), isTrigger: true),
          ],
        );
        engine.scene.createGameObject(
          'Wall',
          position: const Vec3(0, 1.2, 5.0),
          components: [
            BoxCollider(size: const Vec3(6.0, 4.0, 1.0), isTrigger: false),
          ],
        );

        final orbitVcam = VirtualCameraComponent(
          cameraId: 'orbit',
          priority: 10,
          fovYDegrees: 60.0,
          followTarget: hero,
          orbitRig: CameraOrbitRig(
            yawRadians: 0.0,
            pitchRadians: 0.0,
            distance: 10.0,
            targetOffset: const CamVec3(0, 1.2, 0),
            wallPullInPadding: 0.3,
          ),
        );
        engine.scene.createGameObject('OrbitCam', components: [orbitVcam]);

        final cutVcam = VirtualCameraComponent(
          cameraId: 'cutscene',
          priority: 5,
          fovYDegrees: 38.0,
          lookAtTarget: hero,
        );
        engine.scene.createGameObject(
          'CutsceneCam',
          position: const Vec3(8, 4, 8),
          components: [cutVcam],
        );

        final camComp = Camera();
        final brainComp = CameraBrainComponent(
          defaultTransition: const CameraTransitionSpec(
            durationSeconds: 0.5,
            curve: CameraBlendCurve.linear,
          ),
        );
        final camGo = engine.scene.createGameObject(
          'MainCamera',
          components: [camComp, brainComp],
        );

        // First step initializes active camera ('orbit') and evaluates obstacle pull-in.
        engine.step(0.05);
        expect(brainComp.activeCamera?.id, 'orbit');
        expect(camGo.transform.position.z, closeTo(4.2, 0.05));
        expect(camComp.fovYRadians, closeTo(60.0 * math.pi / 180.0, 1e-4));

        // Boost CutsceneCam priority -> blends FOV and position smoothly over 0.5s.
        cutVcam.priority = 30;
        for (int i = 0; i < 5; i++) {
          engine.step(0.05);
        }
        expect(brainComp.activeCamera?.id, 'cutscene');
        expect(brainComp.isBlending, isTrue);
        expect(brainComp.blendProgress, closeTo(0.5, 0.05));
        expect(camComp.fovYRadians, lessThan(60.0 * math.pi / 180.0));
        expect(camComp.fovYRadians, greaterThan(38.0 * math.pi / 180.0));

        for (int i = 0; i < 6; i++) {
          engine.step(0.05);
        }
        expect(brainComp.isBlending, isFalse);
        expect(camComp.fovYRadians, closeTo(38.0 * math.pi / 180.0, 1e-4));

        // Render CameraDirectorUI and trigger shake via button press+release.
        final ui = VoxUiContext();
        final uiState = CameraDirectorUiState();
        // 'Impulse!' button lies cleanly inside toolbar at x+pad+90+8 = 128, barY = 20+24+8+68 = 120.
        const btnX = 160.0;
        const btnY = 134.0;
        ui.beginFrame(
          VoxInput(
            mouseX: btnX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        CameraDirectorUI.render(ui, brainComp.brain, state: uiState);
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: btnX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        CameraDirectorUI.render(ui, brainComp.brain, state: uiState);
        final drawList = ui.endFrame();

        expect(
          drawList.commands.any(
            (c) => c.text != null && c.text!.contains('[LIVE] cutscene'),
          ),
          isTrue,
        );
        expect(brainComp.brain.impulseSources.first.trauma, greaterThan(0.5));
      },
    );
  });

  group('E77 — Procedural Foot-Stepping IK & Slope Adaptation (voxgait)', () {
    test(
      'ProceduralGaitComponent drives foot IK targets, terrain slope tilt, pelvis bob & GaitDebuggerUI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final walkerGo = engine.scene.createGameObject(
          'Walker',
          position: const Vec3(0.0, 0.0, 0.0),
        );
        final pelvisGo = engine.scene.createGameObject(
          'Pelvis',
          position: const Vec3(0.0, 1.0, 0.0),
        );
        pelvisGo.transform.setParent(walkerGo.transform);

        final leftFootTarget = engine.scene.createGameObject('LeftFootTarget');
        final hipGo = engine.scene.createGameObject(
          'LeftHip',
          position: const Vec3(-0.17, 1.0, 0.0),
        );
        final kneeGo = engine.scene.createGameObject(
          'LeftKnee',
          position: const Vec3(-0.17, 0.5, 0.1),
        );
        final ankleGo = engine.scene.createGameObject(
          'LeftAnkle',
          position: const Vec3(-0.17, 0.0, 0.0),
        );
        final ik = walkerGo.addComponent(
          TwoBoneIkComponent(
            rootBone: hipGo,
            midBone: kneeGo,
            endEffector: ankleGo,
          ),
        );

        // Sloped terrain y = 0.25 * z
        const slopeTan = 0.25;
        final gaitComp = walkerGo.addComponent(
          ProceduralGaitComponent(
            preset: GaitPreset.biped,
            pelvisTarget: pelvisGo,
            pelvisBobAmplitude: 0.06,
            autoApplySlopeTilt: true,
            explicitVelocity: const Vec3(0.0, 0.0, 2.0),
            terrainSampler: (x, z) => GaitTerrainSample(
              groundY: z * slopeTan,
              normal: GaitVec3(0.0, 1.0, -slopeTan).normalized,
            ),
          ),
        );
        gaitComp.bindFootTarget('left', leftFootTarget);
        gaitComp.bindTwoBoneIk('left', ik);

        var maxLeftLift = 0.0;
        for (var i = 0; i < 36; i++) {
          walkerGo.transform.position = Vec3(
            0.0,
            walkerGo.transform.position.z * slopeTan,
            walkerGo.transform.position.z + 2.0 * 0.025,
          );
          engine.step(0.025);
          final lf = gaitComp.footTarget('left')!;
          if (lf.stepArcLift > maxLeftLift) maxLeftLift = lf.stepArcLift;
          expect(gaitComp.groundedFootCount, greaterThanOrEqualTo(1));
        }

        expect(maxLeftLift, greaterThan(0.10));
        expect(leftFootTarget.transform.position.z, greaterThan(0.5));
        expect(leftFootTarget.transform.position.y, greaterThan(0.1));
        expect(ik.targetPosition, isNotNull);
        expect(gaitComp.lastSnapshot!.bodyPitchRad.abs(), greaterThan(0.10));
        expect(walkerGo.transform.localRotation.x.abs(), greaterThan(0.05));

        // Test GaitDebuggerUI interaction: Pause (x=66, y=159) -> Next Gait (x=235, y=159)
        final ui = VoxUiContext();
        final uiState = GaitDebuggerUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 66.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        GaitDebuggerUI.render(ui, gaitComp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 66.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        GaitDebuggerUI.render(ui, gaitComp, state: uiState);
        ui.endFrame();
        expect(gaitComp.paused, isTrue);

        ui.beginFrame(
          VoxInput(
            mouseX: 235.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        GaitDebuggerUI.render(ui, gaitComp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 235.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        GaitDebuggerUI.render(ui, gaitComp, state: uiState);
        final dl = ui.endFrame();
        expect(gaitComp.preset, GaitPreset.quadrupedTrot);
        expect(
          dl.commands.any((c) => c.text == 'Procedural Gait Solver'),
          isTrue,
        );

        // Verify ComponentRegistry serialization
        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('ProceduralGaitComponent'), isNotNull);
        final json = reg.specFor(gaitComp)!.toJson(gaitComp);
        expect(json['preset'], 'quadrupedTrot');
        expect(json['paused'], isTrue);
      },
    );
  });

  group('E79 — Camera Spline Rails, Trauma Shake & Lens Transitions (voxlens)', () {
    test(
      'CameraLensRigComponent drives Camera along dolly rail, applies trauma shake, transitions FOV/exposure & LensRigInspectorUI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final targetGo = engine.scene.createGameObject(
          'Hero',
          position: const Vec3(0.0, 1.0, 0.0),
        );
        final cam = Camera(fovYRadians: 60.0 * 3.141592653589793 / 180.0);
        final pp = PostProcessVolume(exposure: 1.0, vignette: 0.15);
        final rig = CameraLensRigComponent(
          railSpeed: 0.5,
          loopRail: false,
          lookAtTarget: targetGo,
          waypoints: const [
            Vec3(0.0, 2.0, 10.0),
            Vec3(6.0, 3.0, 6.0),
            Vec3(12.0, 4.0, 0.0),
          ],
        );
        final camGo = engine.scene.createGameObject(
          'CineCam',
          components: [cam, pp, rig],
        );

        rig.addTrauma(0.6);
        rig.startTransition(
          effect: LensTransitionEffect.zoomPulse,
          durationSeconds: 0.8,
          fovBoostDeg: 18.0,
          exposureShift: -0.3,
        );

        for (var i = 0; i < 8; i++) {
          engine.step(0.05);
        }

        expect(rig.progress, closeTo(0.2, 0.02));
        expect(camGo.transform.position.x, greaterThan(1.5));
        expect(cam.fovYRadians * 180.0 / 3.141592653589793, greaterThan(72.0));
        expect(pp.exposure, lessThan(0.9));
        expect(pp.vignette, greaterThan(0.4));

        // Test LensRigInspectorUI: Pause (x=65, y=159) & Shake +0.5 (x=152, y=159)
        final ui = VoxUiContext();
        final uiState = LensRigInspectorUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 65.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        LensRigInspectorUI.render(ui, rig, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 65.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        LensRigInspectorUI.render(ui, rig, state: uiState);
        ui.endFrame();
        expect(rig.playing, isFalse);

        final prevTrauma = rig.trauma;
        ui.beginFrame(
          VoxInput(
            mouseX: 152.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        LensRigInspectorUI.render(ui, rig, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 152.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        LensRigInspectorUI.render(ui, rig, state: uiState);
        final dl = ui.endFrame();
        expect(rig.trauma, greaterThan(prevTrauma));
        expect(dl.commands.any((c) => c.text == 'Camera Lens Rig'), isTrue);

        // Verify ComponentRegistry serialization
        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('CameraLensRigComponent'), isNotNull);
        final json = reg.specFor(rig)!.toJson(rig);
        expect(json['playing'], isFalse);
        expect(json['railSpeed'], closeTo(0.5, 1e-6));
      },
    );
  });

  group(
    'E84 — Blendspaces, Motion Clips & Root-Motion State Machines (voxblend)',
    () {
      test(
        'BlendTreeControllerComponent transitions via parameter, applies root motion & drives BlendTreeInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final hero = engine.scene.createGameObject('LocomotionHero');
          final ctrl = hero.addComponent(
            BlendTreeControllerComponent(
              parameterY: 3.5,
              applyRootMotion: true,
            ),
          );

          for (var i = 0; i < 6; i++) {
            engine.step(0.05);
          }

          expect(ctrl.activeStateName, 'Run');
          expect(hero.transform.position.z, greaterThan(0.5));
          expect(ctrl.lastBlendResult?.dominantClipName, 'run');

          // Test BlendTreeInspectorUI: click Pause (x=66, y=159) -> click Jump (x=146, y=159)
          final ui = VoxUiContext();
          final uiState = BlendTreeInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 66.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          BlendTreeInspectorUI.render(ui, ctrl, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 66.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          BlendTreeInspectorUI.render(ui, ctrl, state: uiState);
          ui.endFrame();
          expect(ctrl.paused, isTrue);

          ui.beginFrame(
            VoxInput(
              mouseX: 146.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          BlendTreeInspectorUI.render(ui, ctrl, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 146.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          BlendTreeInspectorUI.render(ui, ctrl, state: uiState);
          final dl = ui.endFrame();

          ctrl.stepController(0.05);
          expect(ctrl.activeStateName, 'Jump');
          expect(dl.commands.any((c) => c.text == 'Blend Tree FSM'), isTrue);

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('BlendTreeControllerComponent'), isNotNull);
          final json = reg.specFor(ctrl)!.toJson(ctrl);
          expect(json['parameterY'], closeTo(3.5, 1e-6));
          expect(json['paused'], isTrue);
        },
      );
    },
  );

  group(
    'E89 — Analytic Two-Bone IK, FABRIK & Spring-Bone Secondary Motion (voxik2d)',
    () {
      test(
        'CharacterIk2DComponent solves 2-bone & FABRIK limbs, steps spring tail & drives IkSolverInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final charGo = engine.scene.createGameObject(
            'HeroRig',
            position: const Vec3(1.0, 2.0, 0.0),
          );
          final ik = charGo.addComponent(
            CharacterIk2DComponent(
              mode: IkSolver2DMode.twoBone,
              upperBoneLength: 1.0,
              lowerBoneLength: 1.0,
              targetX: 2.2,
              targetY: 2.0,
            ),
          );

          engine.step(0.02);
          expect(ik.solvedJoints.length, 3);
          expect(
            (ik.solvedJoints.last - const IkVec2(2.2, 2.0)).length,
            lessThan(1e-3),
          );
          expect(ik.springChain.nodes.last.position.y, lessThan(2.0));

          // Test IkSolverInspectorUI: click Mode (x=74, y=159) -> click Flip Bend (x=172, y=159)
          final ui = VoxUiContext();
          final uiState = IkSolverInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 74.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          IkSolverInspectorUI.render(ui, ik, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 74.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          IkSolverInspectorUI.render(ui, ik, state: uiState);
          ui.endFrame();
          expect(ik.mode, IkSolver2DMode.fabrik);
          expect(ik.solvedJoints.length, 4);

          ui.beginFrame(
            VoxInput(
              mouseX: 172.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          IkSolverInspectorUI.render(ui, ik, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 172.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          IkSolverInspectorUI.render(ui, ik, state: uiState);
          final dl = ui.endFrame();
          expect(ik.bendSign, closeTo(-1.0, 1e-6));
          expect(
            dl.commands.any((c) => c.text == '2D IK & Spring Rig'),
            isTrue,
          );

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('CharacterIk2DComponent'), isNotNull);
          final json = reg.specFor(ik)!.toJson(ik);
          expect(json['mode'], 'fabrik');
          expect(json['bendSign'], closeTo(-1.0, 1e-6));
        },
      );
    },
  );

  group(
    'E90 — Piecewise Animation Curves, ADSR Envelopes & Critical Springs (voxcurve)',
    () {
      test(
        'CurveEnvelopeComponent steps Hermite curve, ADSR envelope & spring damper & drives CurveEditorInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final envGo = engine.scene.createGameObject('CurveHost');
          final env = envGo.addComponent(
            CurveEnvelopeComponent(
              springTarget: 2.0,
              springSmoothTime: 0.1,
              timeScale: 1.0,
            ),
          );

          env.triggerEnvelope(velocity: 1.0);
          for (var i = 0; i < 10; i++) {
            engine.step(0.05);
          }
          expect(env.currentCurveValue, greaterThan(0.0));
          expect(env.currentSpringValue, greaterThan(1.0));
          expect(env.adsrPhase, isNot(AdsrPhase.idle));

          // Test CurveEditorInspectorUI: click Trigger (x=150, y=159) -> click Release (x=240, y=159)
          final ui = VoxUiContext();
          final uiState = CurveEditorInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 150.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          CurveEditorInspectorUI.render(ui, env, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 150.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          CurveEditorInspectorUI.render(ui, env, state: uiState);
          ui.endFrame();
          expect(env.adsrPhase, AdsrPhase.attack);

          ui.beginFrame(
            VoxInput(
              mouseX: 240.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          CurveEditorInspectorUI.render(ui, env, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 240.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          CurveEditorInspectorUI.render(ui, env, state: uiState);
          final dl = ui.endFrame();
          expect(env.adsrPhase, AdsrPhase.release);
          expect(dl.commands.any((c) => c.text == 'Curve & ADSR'), isTrue);

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('CurveEnvelopeComponent'), isNotNull);
          final json = reg.specFor(env)!.toJson(env);
          expect(json['wrapMode'], 'loop');
          expect(json['springTarget'], closeTo(2.0, 1e-6));
        },
      );
    },
  );
}
