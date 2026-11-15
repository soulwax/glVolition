/// Rotational dynamics, sequential impulse contact solver, 3D physics joints,
/// sleeping transitions, and swept Continuous Collision Detection (CCD) (Wave 13 / P5-W13-C).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

final class CollisionSpy extends Behaviour {
  final void Function(Collision) onCollision;
  CollisionSpy(this.onCollision);

  @override
  void onCollisionEnter(Collision collision) => onCollision(collision);
}

Engine _createEngine() {
  final host = HeadlessHost();
  final engine = Engine(host);
  engine.time.fixedDeltaTime = 1.0 / 60.0;
  return engine;
}

void main() {
  group('P5-W13-C — Multi-Box Stack Stability', () {
    test(
      'Multi-box stack settles calmly on solid floor without jitter, toppling or collapse',
      () {
        final engine = _createEngine();

        // Ground floor at y = -0.5, top surface at y = 0
        engine.scene.createGameObject(
          'Floor',
          position: const Vec3(0, -0.5, 0),
          components: [
            BoxCollider(size: const Vec3(20, 1, 20), isTrigger: false),
            RigidBody(isKinematic: true, restitution: 0.0),
          ],
        );

        // Three 1x1x1 boxes stacked vertically
        final box1 = engine.scene.createGameObject(
          'Box1',
          position: const Vec3(0, 0.5, 0),
          components: [
            BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
            RigidBody(
              mass: 1.0,
              restitution: 0.0,
              linearDrag: 0.05,
              angularDrag: 0.05,
            ),
          ],
        );
        final box2 = engine.scene.createGameObject(
          'Box2',
          position: const Vec3(0, 1.5, 0),
          components: [
            BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
            RigidBody(
              mass: 1.0,
              restitution: 0.0,
              linearDrag: 0.05,
              angularDrag: 0.05,
            ),
          ],
        );
        final box3 = engine.scene.createGameObject(
          'Box3',
          position: const Vec3(0, 2.5, 0),
          components: [
            BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
            RigidBody(
              mass: 1.0,
              restitution: 0.0,
              linearDrag: 0.05,
              angularDrag: 0.05,
            ),
          ],
        );

        // Step simulation for 120 fixed steps (2 seconds)
        for (var i = 0; i < 120; i++) {
          engine.step(1.0 / 60.0);
        }

        // Box 1 should settle at y ≈ 0.5
        expect(box1.transform.position.y, closeTo(0.5, 0.08));
        expect(box1.transform.position.x, closeTo(0.0, 0.1));
        expect(box1.transform.position.z, closeTo(0.0, 0.1));

        // Box 2 should settle on Box 1 at y ≈ 1.5
        expect(box2.transform.position.y, closeTo(1.5, 0.08));
        expect(box2.transform.position.x, closeTo(0.0, 0.1));
        expect(box2.transform.position.z, closeTo(0.0, 0.1));

        // Box 3 should settle on Box 2 at y ≈ 2.5
        expect(box3.transform.position.y, closeTo(2.5, 0.08));
        expect(box3.transform.position.x, closeTo(0.0, 0.1));
        expect(box3.transform.position.z, closeTo(0.0, 0.1));

        // Velocities must be calm / near zero
        final rb1 = box1.getComponent<RigidBody>()!;
        final rb2 = box2.getComponent<RigidBody>()!;
        final rb3 = box3.getComponent<RigidBody>()!;
        expect(rb1.velocity.length, lessThan(0.2));
        expect(rb2.velocity.length, lessThan(0.2));
        expect(rb3.velocity.length, lessThan(0.2));
      },
    );
  });

  group('P5-W13-C — Swept TOI Continuous Collision Detection (CCD)', () {
    test(
      'High-speed projectile (>500 units/sec) hits thin wall cleanly without tunneling',
      () {
        final engine = _createEngine();

        // Thin wall at x = 8.0 with thickness 0.2 (spans x: 7.9 to 8.1)
        engine.scene.createGameObject(
          'ThinWall',
          position: const Vec3(8.0, 1.0, 0),
          components: [
            BoxCollider(size: const Vec3(0.2, 10, 10), isTrigger: false),
            RigidBody(isKinematic: true),
          ],
        );

        // Projectile at x = 0 moving at 750 units/sec along +X
        // In a single 1/60s frame, displacement is 12.5 units!
        // Without CCD, it would jump to x = 12.5 and completely tunnel through the wall.
        Collision? wallCollision;
        final projectile = engine.scene.createGameObject(
          'FastBullet',
          position: const Vec3(0, 1.0, 0),
          components: [
            SphereCollider(radius: 0.2, isTrigger: false),
            RigidBody(
              mass: 0.5,
              velocity: const Vec3(750, 0, 0),
              useContinuousCollision: true,
              useGravity: false,
              restitution: 0.5,
            ),
            CollisionSpy((c) => wallCollision = c),
          ],
        );

        // Step 1 frame (1/60 s)
        engine.step(1.0 / 60.0);

        // Projectile MUST NOT have tunneled past x = 8.0!
        expect(projectile.transform.position.x, lessThanOrEqualTo(8.0));
        expect(projectile.transform.position.x, closeTo(7.7, 0.3));

        // Collision callback must have fired
        expect(wallCollision, isNotNull);
        expect(wallCollision!.other.gameObject.name, 'ThinWall');

        // Velocity must have bounced backwards or stopped
        final rb = projectile.getComponent<RigidBody>()!;
        expect(rb.velocity.x, lessThanOrEqualTo(0.0));
      },
    );
  });

  group(
    'P5-W13-C — Rotational Dynamics, Torque, Off-Center Force & Friction',
    () {
      test(
        'addTorque applies angular acceleration unless freezeRotation is set',
        () {
          final engine = _createEngine();

          final freeBox = engine.scene.createGameObject(
            'FreeBox',
            position: const Vec3(0, 5, 0),
            components: [
              BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
              RigidBody(useGravity: false),
            ],
          );
          final freezeBox = engine.scene.createGameObject(
            'FreezeBox',
            position: const Vec3(5, 5, 0),
            components: [
              BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
              RigidBody(useGravity: false, freezeRotation: true),
            ],
          );

          final rbFree = freeBox.getComponent<RigidBody>()!;
          final rbFreeze = freezeBox.getComponent<RigidBody>()!;

          rbFree.addTorque(const Vec3(0, 15, 0));
          rbFreeze.addTorque(const Vec3(0, 15, 0));

          engine.step(1.0 / 60.0);

          // Free box develops positive angular velocity around Y
          expect(rbFree.angularVelocity.y, greaterThan(0.5));
          expect(freeBox.transform.rotation.y.abs(), greaterThan(0.001));

          // Freeze box suppresses all angular velocity and stays upright
          expect(rbFreeze.angularVelocity, equals(Vec3.zero));
          expect(freezeBox.transform.rotation.x, equals(0.0));
          expect(freezeBox.transform.rotation.y, equals(0.0));
          expect(freezeBox.transform.rotation.z, equals(0.0));
          expect(freezeBox.transform.rotation.w, equals(1.0));
        },
      );

      test(
        'addForceAtPosition produces linear acceleration and toppling torque',
        () {
          final engine = _createEngine();

          final box = engine.scene.createGameObject(
            'LeverBox',
            position: const Vec3(0, 2, 0),
            components: [
              BoxCollider(size: const Vec3(1, 2, 1), isTrigger: false),
              RigidBody(useGravity: false),
            ],
          );
          final rb = box.getComponent<RigidBody>()!;

          // Apply horizontal force at top edge (y = 3, so r = (0, 1, 0))
          // r x F = (0, 1, 0) x (20, 0, 0) = (0, 0, -20)
          rb.addForceAtPosition(const Vec3(20, 0, 0), const Vec3(0, 3, 0));

          engine.step(1.0 / 60.0);

          expect(rb.velocity.x, greaterThan(0.1));
          expect(rb.angularVelocity.z, lessThan(-0.5));
        },
      );

      test(
        'Coulomb friction decelerates a sliding body on a solid surface',
        () {
          final engine = _createEngine();

          engine.scene.createGameObject(
            'Floor',
            position: const Vec3(0, -0.5, 0),
            components: [
              BoxCollider(size: const Vec3(40, 1, 40), isTrigger: false),
              RigidBody(isKinematic: true),
            ],
          );

          final slidingBox = engine.scene.createGameObject(
            'Slider',
            position: const Vec3(0, 0.5, 0),
            components: [
              BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
              RigidBody(
                mass: 1.0,
                velocity: const Vec3(3, 0, 0),
                staticFriction: 0.6,
                dynamicFriction: 0.4,
                useGravity: true,
              ),
            ],
          );
          final rb = slidingBox.getComponent<RigidBody>()!;

          for (var i = 0; i < 60; i++) {
            engine.step(1.0 / 60.0);
          }

          // Dynamic friction should have decelerated the box to near zero
          expect(rb.velocity.x, lessThan(1.0));
        },
      );
    },
  );

  group('P5-W13-C — 3D Physics Joints (FixedJoint, BallJoint, HingeJoint)', () {
    test(
      'FixedJoint locks relative position and orientation to connected body',
      () {
        final engine = _createEngine();

        final anchorGo = engine.scene.createGameObject(
          'Anchor',
          position: const Vec3(0, 5, 0),
          components: [RigidBody(isKinematic: true)],
        );
        final childGo = engine.scene.createGameObject(
          'FixedChild',
          position: const Vec3(0, 5, 2),
          components: [
            RigidBody(mass: 1.0, useGravity: true),
            FixedJoint(
              connectedBody: anchorGo.getComponent<RigidBody>(),
              anchor: Vec3.zero,
              connectedAnchor: const Vec3(0, 0, 2),
            ),
          ],
        );

        for (var i = 0; i < 60; i++) {
          engine.step(1.0 / 60.0);
        }

        // Fixed child should remain held at (0, 5, 2) against gravity
        expect(childGo.transform.position.y, closeTo(5.0, 0.08));
        expect(childGo.transform.position.z, closeTo(2.0, 0.08));
        expect(childGo.transform.rotation.x.abs(), lessThan(0.08));
      },
    );

    test('BallJoint pins world anchor while allowing spherical rotation', () {
      final engine = _createEngine();

      final anchorGo = engine.scene.createGameObject(
        'Pivot',
        position: const Vec3(0, 5, 0),
        components: [RigidBody(isKinematic: true)],
      );
      final bobGo = engine.scene.createGameObject(
        'PendulumBob',
        position: const Vec3(0, 3, 0),
        components: [
          RigidBody(mass: 1.0, useGravity: true),
          BallJoint(
            connectedBody: anchorGo.getComponent<RigidBody>(),
            anchor: const Vec3(0, 2, 0),
            connectedAnchor: Vec3.zero,
          ),
        ],
      );

      final joint = bobGo.getComponent<BallJoint>()!;

      for (var i = 0; i < 60; i++) {
        engine.step(1.0 / 60.0);
      }

      // The top anchor of the pendulum bob must coincide with pivot (0, 5, 0)
      final worldAnchor = joint.worldAnchor;
      expect((worldAnchor - const Vec3(0, 5, 0)).length, lessThan(0.08));
    });

    test(
      'HingeJoint permits rotation about hinge axis while locking translation',
      () {
        final engine = _createEngine();

        final frameGo = engine.scene.createGameObject(
          'DoorFrame',
          position: const Vec3(0, 2, 0),
          components: [RigidBody(isKinematic: true)],
        );
        final doorGo = engine.scene.createGameObject(
          'Door',
          position: const Vec3(1, 2, 0),
          components: [
            BoxCollider(size: const Vec3(2, 2, 0.2), isTrigger: false),
            RigidBody(mass: 1.0, useGravity: false),
            HingeJoint(
              connectedBody: frameGo.getComponent<RigidBody>(),
              anchor: const Vec3(-1, 0, 0),
              connectedAnchor: Vec3.zero,
              axis: Vec3.unitY,
            ),
          ],
        );

        final doorRb = doorGo.getComponent<RigidBody>()!;
        doorRb.addTorque(const Vec3(0, 25, 0));

        for (var i = 0; i < 30; i++) {
          engine.step(1.0 / 60.0);
        }

        // Door should have spun around Y
        expect(doorRb.angularVelocity.y.abs(), greaterThan(0.1));
        // Out-of-plane angular velocities should remain constrained
        expect(doorRb.angularVelocity.x.abs(), lessThan(0.1));
        expect(doorRb.angularVelocity.z.abs(), lessThan(0.1));

        // Hinge anchor position on frame (0, 2, 0) must remain pinned
        final hingeJoint = doorGo.getComponent<HingeJoint>()!;
        expect(
          (hingeJoint.worldAnchor - const Vec3(0, 2, 0)).length,
          lessThan(0.08),
        );
      },
    );
  });

  group('P5-W13-C — RigidBody Sleeping & Wake Transitions', () {
    test('Resting body enters sleep state and ceases integration', () {
      final engine = _createEngine();

      engine.scene.createGameObject(
        'Floor',
        position: const Vec3(0, -0.5, 0),
        components: [
          BoxCollider(size: const Vec3(10, 1, 10), isTrigger: false),
          RigidBody(isKinematic: true),
        ],
      );

      final boxGo = engine.scene.createGameObject(
        'Box',
        position: const Vec3(0, 0.52, 0),
        components: [
          BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
          RigidBody(mass: 1.0, restitution: 0.0),
        ],
      );
      final rb = boxGo.getComponent<RigidBody>()!;

      // Step for 60 frames (1 second, well beyond 0.3s low-motion timer)
      for (var i = 0; i < 60; i++) {
        engine.step(1.0 / 60.0);
      }

      expect(rb.isSleeping, isTrue);
      expect(rb.velocity, equals(Vec3.zero));
      expect(rb.angularVelocity, equals(Vec3.zero));
    });

    test('Sleeping body wakes on external impulse', () {
      final engine = _createEngine();

      final boxGo = engine.scene.createGameObject(
        'SleepBox',
        position: const Vec3(0, 5, 0),
        components: [RigidBody(useGravity: false)],
      );
      final rb = boxGo.getComponent<RigidBody>()!;
      rb.sleep();
      expect(rb.isSleeping, isTrue);

      // Applying impulse should wake it up
      rb.addImpulse(const Vec3(0, 10, 0));
      expect(rb.isSleeping, isFalse);
      expect(rb.velocity.y, greaterThan(8.0));
    });

    test('Awake colliding body wakes up sleeping body upon impact', () {
      final engine = _createEngine();

      engine.scene.createGameObject(
        'Floor',
        position: const Vec3(0, -0.5, 0),
        components: [
          BoxCollider(size: const Vec3(10, 1, 10), isTrigger: false),
          RigidBody(isKinematic: true),
        ],
      );

      final sleeper = engine.scene.createGameObject(
        'Sleeper',
        position: const Vec3(0, 0.5, 0),
        components: [
          BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
          RigidBody(mass: 1.0, restitution: 0.0),
        ],
      );
      final sleeperRb = sleeper.getComponent<RigidBody>()!;
      sleeperRb.sleep();
      expect(sleeperRb.isSleeping, isTrue);

      // Drop an awake ball directly on top of the sleeping box
      engine.scene.createGameObject(
        'Dropper',
        position: const Vec3(0, 3.0, 0),
        components: [
          SphereCollider(radius: 0.5, isTrigger: false),
          RigidBody(mass: 1.0),
        ],
      );

      // Step until impact occurs
      for (var i = 0; i < 45; i++) {
        engine.step(1.0 / 60.0);
      }

      // Sleeping body must have woken up on collision
      expect(sleeperRb.isSleeping, isFalse);
    });
  });
}
