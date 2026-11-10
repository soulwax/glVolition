import 'dart:math' as math;

import 'package:gl_volition/gl_volition.dart';
import 'package:test/test.dart';

final class _Recorder extends Behaviour {
  final List<String> log;
  final String label;
  @override
  final int executionOrder;

  _Recorder(this.log, [this.label = 'R', this.executionOrder = 0]);

  @override
  void awake() => log.add('$label.awake');
  @override
  void onEnable() => log.add('$label.onEnable');
  @override
  void start() => log.add('$label.start');
  @override
  void fixedUpdate() => log.add('$label.fixedUpdate(${time.deltaTime.toStringAsFixed(3)})');
  @override
  void update() => log.add('$label.update');
  @override
  void lateUpdate() => log.add('$label.lateUpdate');
  @override
  void onDisable() => log.add('$label.onDisable');
  @override
  void onDestroy() => log.add('$label.onDestroy');

  @override
  void onTriggerEnter(Collider other) => log.add('$label.enter:${other.gameObject.name}');
  @override
  void onTriggerStay(Collider other) => log.add('$label.stay:${other.gameObject.name}');
  @override
  void onTriggerExit(Collider other) => log.add('$label.exit:${other.gameObject.name}');
}

void main() {
  group('Lifecycle & execution order', () {
    test('runs awake -> onEnable -> start -> fixedUpdate -> update -> lateUpdate -> onDisable -> onDestroy', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.time.fixedDeltaTime = 0.02;
      final log = <String>[];

      final go = engine.scene.createGameObject('Actor');
      final rec = go.addComponent(_Recorder(log));
      expect(log, ['R.awake', 'R.onEnable']);

      log.clear();
      engine.step(0.025);
      expect(log, [
        'R.start',
        'R.fixedUpdate(0.020)',
        'R.update',
        'R.lateUpdate',
      ]);

      log.clear();
      rec.enabled = false;
      expect(log, ['R.onDisable']);

      log.clear();
      engine.step(0.025);
      expect(log, isEmpty);

      rec.enabled = true;
      expect(log, ['R.onEnable']);

      log.clear();
      go.destroy();
      expect(log, isEmpty, reason: 'destroy is deferred to end of frame');
      engine.step(0.005);
      expect(log, ['R.onDisable', 'R.onDestroy']);
      expect(go.isDestroyed, isTrue);
      expect(engine.scene.find('Actor'), isNull);
    });

    test('inactive GameObjects defer awake until first activated', () {
      final engine = Engine(HeadlessHost());
      final log = <String>[];
      final go = engine.scene.createGameObject('Sleeping', active: false);
      go.addComponent(_Recorder(log));
      expect(log, isEmpty);

      engine.step(0.02);
      expect(log, isEmpty);

      go.setActive(true);
      expect(log, ['R.awake', 'R.onEnable']);
    });

    test('executionOrder sorts start, fixedUpdate, update, lateUpdate', () {
      final engine = Engine(HeadlessHost());
      final log = <String>[];
      engine.scene.createGameObject('Late', components: [_Recorder(log, 'B', 10)]);
      engine.scene.createGameObject('Early', components: [_Recorder(log, 'A', -5)]);
      log.clear();

      engine.step(0.001);
      expect(log, ['A.start', 'B.start', 'A.update', 'B.update', 'A.lateUpdate', 'B.lateUpdate']);
    });
  });

  group('Transform & hierarchy', () {
    test('world position/rotation and reparenting with worldPositionStays', () {
      final engine = Engine(HeadlessHost());
      final parent = engine.scene.createGameObject(
        'Parent',
        position: const Vec3(10, 0, 0),
        rotation: Quat.axisAngle(kUp, math.pi / 2),
      );
      final child = engine.scene.createGameObject(
        'Child',
        parent: parent,
        position: const Vec3(0, 0, -2),
      );

      // Local -2Z rotated +90 deg around Y lands at +X = 10 - 2 = 8.
      expect(child.transform.position.x, closeTo(8, 1e-5));
      expect(child.transform.position.z, closeTo(0, 1e-5));

      child.setParent(null, worldPositionStays: true);
      expect(child.transform.position.x, closeTo(8, 1e-5));
      expect(child.transform.forward.x, closeTo(-1, 1e-5));

      child.setParent(parent, worldPositionStays: true);
      expect(child.transform.localPosition.z, closeTo(-2, 1e-5));
    });

    test('lookAt aligns transform.forward (-Z) toward target', () {
      final engine = Engine(HeadlessHost());
      final go = engine.scene.createGameObject('Turret', position: const Vec3(0, 0, 0));
      go.transform.lookAt(const Vec3(3, 0, -4));
      final expected = const Vec3(3, 0, -4).normalized;
      expect((go.transform.forward - expected).length, lessThan(1e-5));
    });
  });

  group('Time, fixed step & invoke', () {
    test('clamps huge deltas and scales time via timeScale', () {
      final engine = Engine(HeadlessHost());
      engine.time.fixedDeltaTime = 0.02;
      engine.time.timeScale = 0.5;

      engine.step(0.04);
      expect(engine.time.unscaledDeltaTime, closeTo(0.04, 1e-9));
      expect(engine.time.deltaTime, closeTo(0.02, 1e-9));
      expect(engine.time.fixedTime, closeTo(0.02, 1e-9));
    });

    test('invoke fires on scaled game time and cancels with owning Behaviour', () {
      final engine = Engine(HeadlessHost());
      var hits = 0;
      final go = engine.scene.createGameObject('Timer');
      final b = go.addComponent(_Recorder([]));
      b.invoke(0.05, () => hits++, repeatEvery: 0.05);

      engine.step(0.06);
      expect(hits, 1);
      engine.step(0.05);
      expect(hits, 2);

      go.destroy();
      engine.step(0.01);
      engine.step(0.10);
      expect(hits, 2);
    });
  });

  group('InputActions', () {
    test('combines multiple keys into axes and buttons', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.input.button('Boost', ['ShiftLeft', 'ShiftRight']);

      expect(engine.input.getAxis('Horizontal'), 0);
      host.input.press('KeyD');
      expect(engine.input.getAxis('Horizontal'), 1);
      host.input.press('ArrowLeft');
      expect(engine.input.getAxis('Horizontal'), 0);
      host.input.release('KeyD');
      expect(engine.input.getAxis('Horizontal'), -1);

      host.input.press('ShiftLeft');
      expect(engine.input.wasPressed('Boost'), isTrue);
      host.input.endFrame();
      expect(engine.input.wasPressed('Boost'), isFalse);
      expect(engine.input.isDown('Boost'), isTrue);
    });
  });

  group('Trigger physics & queries', () {
    test('fires onTriggerEnter, Stay, and Exit across fixed steps and respects layers', () {
      final engine = Engine(HeadlessHost());
      engine.time.fixedDeltaTime = 0.02;
      final log = <String>[];

      final ship = engine.scene.createGameObject('Ship', layer: 1)
        ..addComponent(SphereCollider(radius: 1.0, collidesWithMask: 1 << 2))
        ..addComponent(_Recorder(log, 'Ship'));

      final rock = engine.scene.createGameObject('Rock', layer: 2, position: const Vec3(5, 0, 0))
        ..addComponent(SphereCollider(radius: 1.0));

      final ignored = engine.scene.createGameObject('Ignored', layer: 3)
        ..addComponent(SphereCollider(radius: 10.0));
      expect(ignored.layer, 3);
      log.clear();

      // Move rock into overlap.
      rock.transform.position = const Vec3(1.5, 0, 0);
      engine.step(0.02);
      expect(log, contains('Ship.enter:Rock'));

      log.clear();
      engine.step(0.02);
      expect(log, contains('Ship.stay:Rock'));

      // Move rock away.
      log.clear();
      rock.transform.position = const Vec3(5, 0, 0);
      engine.step(0.02);
      expect(log, contains('Ship.exit:Rock'));

      // Raycast from -Z toward the ship at the origin.
      final hit = engine.physics.raycast(const Ray(origin: Vec3(0, 0, -5), direction: Vec3(0, 0, 1)));
      expect(hit?.gameObject, same(ship));
      expect(hit?.distance, closeTo(4.0, 1e-5));
    });
  });

  group('Render sync', () {
    test('collects Camera, DirectionalLight, PointLight and RenderSettings into Graphics', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.renderSettings
        ..fogEnabled = true
        ..fogStart = 50
        ..fogEnd = 150;

      engine.scene.createGameObject(
        'Cam',
        position: const Vec3(0, 2, 8),
        components: [Camera(fovYRadians: 1.1)],
      );
      engine.scene.createGameObject(
        'Sun',
        components: [Light.directional(intensity: 2.5)],
      );
      engine.scene.createGameObject(
        'Torch',
        position: const Vec3(1, 2, 3),
        components: [Light.point(intensity: 3.0, range: 9.0)],
      );

      engine.step(0.016);

      expect(host.graphics.camera, isNotNull);
      expect(host.graphics.camera!.eye, const Vec3(0, 2, 8));
      expect(host.graphics.environment.directionalLight?.intensity, 2.5);
      expect(host.graphics.environment.pointLights, hasLength(1));
      expect(host.graphics.environment.pointLights.first.position, const Vec3(1, 2, 3));
      expect(host.graphics.environment.fogStart, 50);
    });
  });
}
