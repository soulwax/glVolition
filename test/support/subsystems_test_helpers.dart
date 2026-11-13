/// Shared test fixtures and spy components for sharded subsystem suites.
library;

import 'package:gl_volition/gl_volition.dart';

/// Minimal serialized [Behaviour] fixture shared across subsystem test suites.
final class HealthBehaviour extends Behaviour {
  int hp;
  String faction;
  double speed;

  HealthBehaviour({this.hp = 100, this.faction = 'neutral', this.speed = 5.0});

  static final spec =
      ComponentSpec<HealthBehaviour>('HealthBehaviour', HealthBehaviour.new, [
        Field.integer('hp', (b) => b.hp, (b, v) => b.hp = v),
        Field.text('faction', (b) => b.faction, (b, v) => b.faction = v),
        Field.number('speed', (b) => b.speed, (b, v) => b.speed = v),
      ]);
}

/// Counts `fixedUpdate` and `update` invocations for stepping diagnostics.
final class FixedCounter extends Behaviour {
  int fixedCount = 0;
  int updateCount = 0;

  @override
  void fixedUpdate() => fixedCount++;

  @override
  void update() => updateCount++;
}

/// Tracks [Poolable] spawn and despawn lifecycle counts for `ObjectPool` tests.
final class PoolTracker extends Behaviour with Poolable {
  int spawnCount = 0;
  int despawnCount = 0;

  @override
  void onSpawned() => spawnCount++;

  @override
  void onDespawned() => despawnCount++;
}

/// Records pointer raycast lifecycle events dispatched by `PhysicsRaycaster`.
final class PointerSpy extends Behaviour {
  final List<String> events = [];
  PointerRaycastHit? lastHit;

  @override
  void onPointerEnter(PointerRaycastHit hit) {
    events.add('enter');
    lastHit = hit;
  }

  @override
  void onPointerExit(PointerRaycastHit hit) {
    events.add('exit');
    lastHit = hit;
  }

  @override
  void onPointerDown(PointerRaycastHit hit) {
    events.add('down');
    lastHit = hit;
  }

  @override
  void onPointerUp(PointerRaycastHit hit) {
    events.add('up');
    lastHit = hit;
  }

  @override
  void onPointerClick(PointerRaycastHit hit) {
    events.add('click');
    lastHit = hit;
  }
}

/// Minimal [ResourceLibrary] adapter forwarding mesh and material allocation to [HeadlessGraphics].
final class HeadlessResources implements ResourceLibrary {
  final HeadlessGraphics graphics;
  HeadlessResources(this.graphics);

  @override
  MeshHandle registerMesh(MeshData data, {String? debugLabel}) =>
      graphics.createMesh(data, debugLabel: debugLabel);

  @override
  MaterialHandle registerMaterial(MaterialDefinition definition) =>
      graphics.createMaterial(definition);

  // `Invocation` is shadowed by the engine's invoke handle, so widen the
  // parameter to Object (a valid override) and forward dynamically.
  @override
  dynamic noSuchMethod(Object invocation) =>
      super.noSuchMethod(invocation as dynamic);
}

/// Forwards 3D `onCollisionEnter` callbacks in rigidbody tests.
final class CollisionSpy extends Behaviour {
  final void Function(Collision) onHit;
  CollisionSpy(this.onHit);

  @override
  void onCollisionEnter(Collision collision) => onHit(collision);
}

/// Captures 2D `onCollisionEnter2D` events for physics2D tests.
final class CollisionSpy2D extends Behaviour {
  bool entered = false;
  Collision2D? lastCollision;

  @override
  void onCollisionEnter2D(Collision2D collision) {
    entered = true;
    lastCollision = collision;
  }
}

/// Captures 2D `onTriggerEnter2D` events for physics2D tests.
final class TriggerSpy2D extends Behaviour {
  bool entered = false;
  Collider2D? lastTrigger;

  @override
  void onTriggerEnter2D(Collider2D other) {
    entered = true;
    lastTrigger = other;
  }
}
