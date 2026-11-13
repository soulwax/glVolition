part of '../../engine.dart';

/// 2D collision payload passed to [Behaviour.onCollisionEnter2D],
/// [Behaviour.onCollisionStay2D], and [Behaviour.onCollisionExit2D].
class Collision2D {
  final Collider2D otherCollider;
  final GameObject otherGameObject;
  final Vec2 relativeVelocity;
  final Vec2 normal;
  final List<Vec2> contacts;

  Collision2D({
    required this.otherCollider,
    required this.otherGameObject,
    required this.relativeVelocity,
    required this.normal,
    required this.contacts,
  });
}

/// Raycast hit information returned by [Physics2DWorld.raycast] and [Scene.raycast2D].
class RaycastHit2D {
  final Collider2D collider;
  final Vec2 point;
  final Vec2 normal;
  final double fraction;
  final double distance;

  RaycastHit2D({
    required this.collider,
    required this.point,
    required this.normal,
    required this.fraction,
    required this.distance,
  });

  GameObject get gameObject => collider.gameObject;
  TransformComponent get transform => collider.transform;
  RigidBody2D? get rigidBody => collider.rigidBody;
}

/// 2D rigid body dynamics component backed by `package:voxphys` (E32).
class RigidBody2D extends Component {
  phys.BodyType bodyType;
  Vec2 _initialLinearVelocity;
  double _initialAngularVelocity;
  double linearDamping;
  double angularDamping;
  double gravityScale;
  bool fixedRotation;
  bool bullet;

  phys.RigidBody? _rawBody;

  RigidBody2D({
    this.bodyType = phys.BodyType.dynamicBody,
    Vec2 linearVelocity = Vec2.zero,
    double angularVelocity = 0.0,
    this.linearDamping = 0.0,
    this.angularDamping = 0.0,
    this.gravityScale = 1.0,
    this.fixedRotation = false,
    this.bullet = false,
  }) : _initialLinearVelocity = linearVelocity,
       _initialAngularVelocity = angularVelocity;

  phys.RigidBody? get rawBody => _rawBody;

  Vec2 get linearVelocity {
    final b = _rawBody;
    if (b == null) return _initialLinearVelocity;
    return Vec2(b.linearVelocity.x, b.linearVelocity.y);
  }

  set linearVelocity(Vec2 v) {
    _initialLinearVelocity = v;
    _rawBody?.linearVelocity = phys.PhysVec2(v.x, v.y);
  }

  double get angularVelocity =>
      _rawBody?.angularVelocity ?? _initialAngularVelocity;
  set angularVelocity(double w) {
    _initialAngularVelocity = w;
    _rawBody?.angularVelocity = w;
  }

  double get mass => _rawBody?.mass ?? 0.0;
  double get inertia => _rawBody?.inertia ?? 0.0;

  void applyForce(Vec2 force, [Vec2? worldPoint]) {
    final b = _rawBody;
    if (b == null) return;
    if (worldPoint != null) {
      b.applyForce(
        phys.PhysVec2(force.x, force.y),
        phys.PhysVec2(worldPoint.x, worldPoint.y),
      );
    } else {
      b.applyForceToCenter(phys.PhysVec2(force.x, force.y));
    }
  }

  void applyImpulse(Vec2 impulse, [Vec2? worldPoint]) {
    final b = _rawBody;
    if (b == null) return;
    if (worldPoint != null) {
      b.applyLinearImpulse(
        phys.PhysVec2(impulse.x, impulse.y),
        phys.PhysVec2(worldPoint.x, worldPoint.y),
      );
    } else {
      b.applyLinearImpulseToCenter(phys.PhysVec2(impulse.x, impulse.y));
    }
  }

  void applyTorque(double torque) {
    _rawBody?.applyTorque(torque);
  }

  Vec2 getVelocityAtPoint(Vec2 worldPoint) {
    final b = _rawBody;
    if (b == null) return Vec2.zero;
    final v = b.getVelocityAtWorldPoint(
      phys.PhysVec2(worldPoint.x, worldPoint.y),
    );
    return Vec2(v.x, v.y);
  }

  @override
  void _onEnableInternal() {
    scene.physics2D._registerBody(this);
  }

  @override
  void _onDisableInternal() {
    scene.physics2D._unregisterBody(this);
  }
}

/// Abstract base class for 2D colliders backed by `package:voxphys` (E32).
abstract class Collider2D extends Component {
  Vec2 offset;
  double density;
  double friction;
  double restitution;
  bool isTrigger;
  int categoryBits;
  int maskBits;

  phys.Fixture? _fixture;

  Collider2D({
    this.offset = Vec2.zero,
    this.density = 1.0,
    this.friction = 0.2,
    this.restitution = 0.0,
    this.isTrigger = false,
    this.categoryBits = 0x0001,
    this.maskBits = 0xFFFF,
  });

  RigidBody2D? get rigidBody => gameObject.getComponent<RigidBody2D>();

  phys.PhysShape _createShape();

  @override
  void _onEnableInternal() {
    scene.physics2D._registerCollider(this);
  }

  @override
  void _onDisableInternal() {
    scene.physics2D._unregisterCollider(this);
  }
}

/// 2D box collider component (E32).
class BoxCollider2D extends Collider2D {
  Vec2 size;

  BoxCollider2D({
    this.size = const Vec2(1.0, 1.0),
    super.offset,
    super.density,
    super.friction,
    super.restitution,
    super.isTrigger,
    super.categoryBits,
    super.maskBits,
  });

  @override
  phys.PhysShape _createShape() {
    return phys.PolygonShape.box(
      size.x * 0.5,
      size.y * 0.5,
      phys.PhysVec2(offset.x, offset.y),
    );
  }
}

/// 2D circular collider component (E32).
class CircleCollider2D extends Collider2D {
  double radius;

  CircleCollider2D({
    this.radius = 0.5,
    super.offset,
    super.density,
    super.friction,
    super.restitution,
    super.isTrigger,
    super.categoryBits,
    super.maskBits,
  });

  @override
  phys.PhysShape _createShape() {
    return phys.CircleShape(
      radius: radius,
      center: phys.PhysVec2(offset.x, offset.y),
    );
  }
}

/// 2D convex polygon collider component (E32).
class PolygonCollider2D extends Collider2D {
  List<Vec2> points;

  PolygonCollider2D({
    required this.points,
    super.offset,
    super.density,
    super.friction,
    super.restitution,
    super.isTrigger,
    super.categoryBits,
    super.maskBits,
  });

  @override
  phys.PhysShape _createShape() {
    return phys.PolygonShape(
      points.map((p) => phys.PhysVec2(p.x + offset.x, p.y + offset.y)).toList(),
    );
  }
}

/// 2D Distance Joint maintaining fixed or spring distance between two bodies (E32).
class DistanceJoint2D extends Component {
  RigidBody2D? connectedBody;
  Vec2 anchor;
  Vec2 connectedAnchor;
  double? length;
  double frequencyHz;
  double dampingRatio;
  bool collideConnected;

  phys.DistanceJoint? _rawJoint;

  DistanceJoint2D({
    this.connectedBody,
    this.anchor = Vec2.zero,
    this.connectedAnchor = Vec2.zero,
    this.length,
    this.frequencyHz = 0.0,
    this.dampingRatio = 0.0,
    this.collideConnected = false,
  });

  @override
  void _onEnableInternal() {
    scene.physics2D._registerJoint(this);
  }

  @override
  void _onDisableInternal() {
    scene.physics2D._unregisterJoint(this);
  }
}

/// 2D Revolute Joint (pin / hinge) constraint (E32).
class RevoluteJoint2D extends Component {
  RigidBody2D? connectedBody;
  Vec2 anchor;
  Vec2 connectedAnchor;
  bool enableMotor;
  double motorSpeed;
  double maxMotorTorque;
  bool enableLimit;
  double lowerAngle;
  double upperAngle;
  bool collideConnected;

  phys.RevoluteJoint? _rawJoint;

  RevoluteJoint2D({
    this.connectedBody,
    this.anchor = Vec2.zero,
    this.connectedAnchor = Vec2.zero,
    this.enableMotor = false,
    this.motorSpeed = 0.0,
    this.maxMotorTorque = 0.0,
    this.enableLimit = false,
    this.lowerAngle = 0.0,
    this.upperAngle = 0.0,
    this.collideConnected = false,
  });

  double get jointAngle => _rawJoint?.jointAngle ?? 0.0;
  double get jointSpeed => _rawJoint?.jointSpeed ?? 0.0;

  @override
  void _onEnableInternal() {
    scene.physics2D._registerJoint(this);
  }

  @override
  void _onDisableInternal() {
    scene.physics2D._unregisterJoint(this);
  }
}

/// 2D Prismatic Joint (slider) constraint (E32).
class PrismaticJoint2D extends Component {
  RigidBody2D? connectedBody;
  Vec2 anchor;
  Vec2 connectedAnchor;
  Vec2 axis;
  bool enableMotor;
  double motorSpeed;
  double maxMotorForce;
  bool enableLimit;
  double lowerTranslation;
  double upperTranslation;
  bool collideConnected;

  phys.PrismaticJoint? _rawJoint;

  PrismaticJoint2D({
    this.connectedBody,
    this.anchor = Vec2.zero,
    this.connectedAnchor = Vec2.zero,
    this.axis = const Vec2(1.0, 0.0),
    this.enableMotor = false,
    this.motorSpeed = 0.0,
    this.maxMotorForce = 0.0,
    this.enableLimit = false,
    this.lowerTranslation = 0.0,
    this.upperTranslation = 0.0,
    this.collideConnected = false,
  });

  double get jointTranslation => _rawJoint?.jointTranslation ?? 0.0;
  double get jointSpeed => _rawJoint?.jointSpeed ?? 0.0;

  @override
  void _onEnableInternal() {
    scene.physics2D._registerJoint(this);
  }

  @override
  void _onDisableInternal() {
    scene.physics2D._unregisterJoint(this);
  }
}

/// 2D Physics World subsystem owned by [Scene] (E32).
class Physics2DWorld {
  final Scene scene;
  late final phys.PhysWorld2D _world;

  final List<RigidBody2D> _bodies = [];
  final List<Collider2D> _colliders = [];
  final List<Component> _joints = [];

  final Map<phys.Fixture, Collider2D> _fixtureToCollider = {};
  final Set<phys.Contact> _currentTouchingContacts = {};

  Physics2DWorld._(this.scene) {
    _world = phys.PhysWorld2D(
      gravity: const phys.PhysVec2(0.0, -9.8),
      onBeginContact: _onBeginContact,
      onEndContact: _onEndContact,
    );
  }

  Vec2 get gravity => Vec2(_world.gravity.x, _world.gravity.y);
  set gravity(Vec2 g) => _world.gravity = phys.PhysVec2(g.x, g.y);

  void _registerBody(RigidBody2D body) {
    if (_bodies.contains(body)) return;
    _bodies.add(body);

    final pos = body.transform.position;
    final q = body.transform.rotation;
    final angle = 2.0 * math.atan2(q.z, q.w);

    final raw = _world.createBody(
      phys.RigidBodyDef(
        type: body.bodyType,
        position: phys.PhysVec2(pos.x, pos.y),
        angle: angle,
        linearVelocity: phys.PhysVec2(
          body._initialLinearVelocity.x,
          body._initialLinearVelocity.y,
        ),
        angularVelocity: body._initialAngularVelocity,
        linearDamping: body.linearDamping,
        angularDamping: body.angularDamping,
        gravityScale: body.gravityScale,
        fixedRotation: body.fixedRotation,
        bullet: body.bullet,
        userData: body,
      ),
    );
    body._rawBody = raw;

    // Attach any colliders already on this GameObject
    for (final col in body.gameObject.getComponents<Collider2D>()) {
      _attachColliderToBody(col, raw);
    }
  }

  void _unregisterBody(RigidBody2D body) {
    _bodies.remove(body);
    final raw = body._rawBody;
    if (raw != null) {
      for (final f in List.of(raw.fixtures)) {
        _fixtureToCollider.remove(f);
      }
      _world.destroyBody(raw);
      body._rawBody = null;
    }
  }

  void _registerCollider(Collider2D collider) {
    if (_colliders.contains(collider)) return;
    _colliders.add(collider);

    final rb =
        collider.rigidBody ??
        collider.gameObject.addComponent<RigidBody2D>(
          RigidBody2D(bodyType: phys.BodyType.staticBody),
        );

    final raw = rb.rawBody;
    if (raw != null) {
      _attachColliderToBody(collider, raw);
    }
  }

  void _attachColliderToBody(Collider2D collider, phys.RigidBody rawBody) {
    if (collider._fixture != null) return;
    final shape = collider._createShape();
    final fixture = rawBody.createFixture(
      phys.FixtureDef(
        shape: shape,
        density: collider.density,
        friction: collider.friction,
        restitution: collider.restitution,
        isSensor: collider.isTrigger,
        categoryBits: collider.categoryBits,
        maskBits: collider.maskBits,
        userData: collider,
      ),
    );
    collider._fixture = fixture;
    _fixtureToCollider[fixture] = collider;
  }

  void _unregisterCollider(Collider2D collider) {
    _colliders.remove(collider);
    final fixture = collider._fixture;
    if (fixture != null) {
      _fixtureToCollider.remove(fixture);
      fixture.body.destroyFixture(fixture);
      collider._fixture = null;
    }
  }

  void _registerJoint(Component joint) {
    if (_joints.contains(joint)) return;
    _joints.add(joint);

    if (joint is DistanceJoint2D) {
      final rbA = joint.gameObject.getComponent<RigidBody2D>();
      final rbB = joint.connectedBody;
      if (rbA?.rawBody != null && rbB?.rawBody != null) {
        joint._rawJoint = _world.createJoint(
          phys.DistanceJoint(
            bodyA: rbA!.rawBody!,
            bodyB: rbB!.rawBody!,
            localAnchorA: phys.PhysVec2(joint.anchor.x, joint.anchor.y),
            localAnchorB: phys.PhysVec2(
              joint.connectedAnchor.x,
              joint.connectedAnchor.y,
            ),
            length: joint.length,
            frequencyHz: joint.frequencyHz,
            dampingRatio: joint.dampingRatio,
            collideConnected: joint.collideConnected,
            userData: joint,
          ),
        );
      }
    } else if (joint is RevoluteJoint2D) {
      final rbA = joint.gameObject.getComponent<RigidBody2D>();
      final rbB = joint.connectedBody;
      if (rbA?.rawBody != null && rbB?.rawBody != null) {
        joint._rawJoint = _world.createJoint(
          phys.RevoluteJoint(
            bodyA: rbA!.rawBody!,
            bodyB: rbB!.rawBody!,
            localAnchorA: phys.PhysVec2(joint.anchor.x, joint.anchor.y),
            localAnchorB: phys.PhysVec2(
              joint.connectedAnchor.x,
              joint.connectedAnchor.y,
            ),
            enableMotor: joint.enableMotor,
            motorSpeed: joint.motorSpeed,
            maxMotorTorque: joint.maxMotorTorque,
            enableLimit: joint.enableLimit,
            lowerAngle: joint.lowerAngle,
            upperAngle: joint.upperAngle,
            collideConnected: joint.collideConnected,
            userData: joint,
          ),
        );
      }
    } else if (joint is PrismaticJoint2D) {
      final rbA = joint.gameObject.getComponent<RigidBody2D>();
      final rbB = joint.connectedBody;
      if (rbA?.rawBody != null && rbB?.rawBody != null) {
        joint._rawJoint = _world.createJoint(
          phys.PrismaticJoint(
            bodyA: rbA!.rawBody!,
            bodyB: rbB!.rawBody!,
            localAnchorA: phys.PhysVec2(joint.anchor.x, joint.anchor.y),
            localAnchorB: phys.PhysVec2(
              joint.connectedAnchor.x,
              joint.connectedAnchor.y,
            ),
            localAxisA: phys.PhysVec2(joint.axis.x, joint.axis.y),
            enableMotor: joint.enableMotor,
            motorSpeed: joint.motorSpeed,
            maxMotorForce: joint.maxMotorForce,
            enableLimit: joint.enableLimit,
            lowerTranslation: joint.lowerTranslation,
            upperTranslation: joint.upperTranslation,
            collideConnected: joint.collideConnected,
            userData: joint,
          ),
        );
      }
    }
  }

  void _unregisterJoint(Component joint) {
    _joints.remove(joint);
    if (joint is DistanceJoint2D && joint._rawJoint != null) {
      _world.destroyJoint(joint._rawJoint!);
      joint._rawJoint = null;
    } else if (joint is RevoluteJoint2D && joint._rawJoint != null) {
      _world.destroyJoint(joint._rawJoint!);
      joint._rawJoint = null;
    } else if (joint is PrismaticJoint2D && joint._rawJoint != null) {
      _world.destroyJoint(joint._rawJoint!);
      joint._rawJoint = null;
    }
  }

  void _step(double dt) {
    // 1. Sync kinematic bodies positions from transforms
    for (final rb in _bodies) {
      final raw = rb._rawBody;
      if (raw != null && raw.isKinematic) {
        final pos = rb.transform.position;
        final q = rb.transform.rotation;
        raw.position = phys.PhysVec2(pos.x, pos.y);
        raw.angle = 2.0 * math.atan2(q.z, q.w);
      }
    }

    // 2. Step physics simulation
    _world.step(dt);

    // 3. Write dynamic and kinematic body positions back to GameObjects
    for (final rb in _bodies) {
      final raw = rb._rawBody;
      if (raw != null && !raw.isStatic) {
        final cur = rb.transform.position;
        rb.transform.position = Vec3(raw.position.x, raw.position.y, cur.z);
        rb.transform.rotation = Quat.axisAngle(const Vec3(0, 0, 1), raw.angle);
      }
    }

    // 4. Dispatch stay callbacks for contacts that persist
    for (final contact in _currentTouchingContacts) {
      if (!contact.isTouching) continue;
      final colA = _fixtureToCollider[contact.fixtureA];
      final colB = _fixtureToCollider[contact.fixtureB];
      if (colA == null || colB == null) continue;

      if (contact.isSensor) {
        for (final b in colA.gameObject.getComponents<Behaviour>()) {
          b.onTriggerStay2D(colB);
        }
        for (final b in colB.gameObject.getComponents<Behaviour>()) {
          b.onTriggerStay2D(colA);
        }
      } else {
        final m = contact.manifold;
        final normal = m != null ? Vec2(m.normal.x, m.normal.y) : Vec2.zero;
        final pts = m != null
            ? m.points.map((p) => Vec2(p.position.x, p.position.y)).toList()
            : <Vec2>[];
        final relVel = colB.rigidBody != null && colA.rigidBody != null
            ? colB.rigidBody!.linearVelocity - colA.rigidBody!.linearVelocity
            : Vec2.zero;

        final cA = Collision2D(
          otherCollider: colB,
          otherGameObject: colB.gameObject,
          relativeVelocity: relVel,
          normal: normal,
          contacts: pts,
        );
        for (final b in colA.gameObject.getComponents<Behaviour>()) {
          b.onCollisionStay2D(cA);
        }

        final cB = Collision2D(
          otherCollider: colA,
          otherGameObject: colA.gameObject,
          relativeVelocity: Vec2(-relVel.x, -relVel.y),
          normal: Vec2(-normal.x, -normal.y),
          contacts: pts,
        );
        for (final b in colB.gameObject.getComponents<Behaviour>()) {
          b.onCollisionStay2D(cB);
        }
      }
    }
  }

  void _onBeginContact(phys.Contact contact) {
    _currentTouchingContacts.add(contact);
    final colA = _fixtureToCollider[contact.fixtureA];
    final colB = _fixtureToCollider[contact.fixtureB];
    if (colA == null || colB == null) return;

    if (contact.isSensor) {
      for (final b in colA.gameObject.getComponents<Behaviour>()) {
        b.onTriggerEnter2D(colB);
      }
      for (final b in colB.gameObject.getComponents<Behaviour>()) {
        b.onTriggerEnter2D(colA);
      }
    } else {
      final m = contact.manifold;
      final normal = m != null ? Vec2(m.normal.x, m.normal.y) : Vec2.zero;
      final pts = m != null
          ? m.points.map((p) => Vec2(p.position.x, p.position.y)).toList()
          : <Vec2>[];
      final relVel = colB.rigidBody != null && colA.rigidBody != null
          ? colB.rigidBody!.linearVelocity - colA.rigidBody!.linearVelocity
          : Vec2.zero;

      final cA = Collision2D(
        otherCollider: colB,
        otherGameObject: colB.gameObject,
        relativeVelocity: relVel,
        normal: normal,
        contacts: pts,
      );
      for (final b in colA.gameObject.getComponents<Behaviour>()) {
        b.onCollisionEnter2D(cA);
      }

      final cB = Collision2D(
        otherCollider: colA,
        otherGameObject: colA.gameObject,
        relativeVelocity: Vec2(-relVel.x, -relVel.y),
        normal: Vec2(-normal.x, -normal.y),
        contacts: pts,
      );
      for (final b in colB.gameObject.getComponents<Behaviour>()) {
        b.onCollisionEnter2D(cB);
      }
    }
  }

  void _onEndContact(phys.Contact contact) {
    _currentTouchingContacts.remove(contact);
    final colA = _fixtureToCollider[contact.fixtureA];
    final colB = _fixtureToCollider[contact.fixtureB];
    if (colA == null || colB == null) return;

    if (contact.isSensor) {
      for (final b in colA.gameObject.getComponents<Behaviour>()) {
        b.onTriggerExit2D(colB);
      }
      for (final b in colB.gameObject.getComponents<Behaviour>()) {
        b.onTriggerExit2D(colA);
      }
    } else {
      final m = contact.manifold;
      final normal = m != null ? Vec2(m.normal.x, m.normal.y) : Vec2.zero;
      final pts = m != null
          ? m.points.map((p) => Vec2(p.position.x, p.position.y)).toList()
          : <Vec2>[];
      final relVel = colB.rigidBody != null && colA.rigidBody != null
          ? colB.rigidBody!.linearVelocity - colA.rigidBody!.linearVelocity
          : Vec2.zero;

      final cA = Collision2D(
        otherCollider: colB,
        otherGameObject: colB.gameObject,
        relativeVelocity: relVel,
        normal: normal,
        contacts: pts,
      );
      for (final b in colA.gameObject.getComponents<Behaviour>()) {
        b.onCollisionExit2D(cA);
      }

      final cB = Collision2D(
        otherCollider: colA,
        otherGameObject: colA.gameObject,
        relativeVelocity: Vec2(-relVel.x, -relVel.y),
        normal: Vec2(-normal.x, -normal.y),
        contacts: pts,
      );
      for (final b in colB.gameObject.getComponents<Behaviour>()) {
        b.onCollisionExit2D(cB);
      }
    }
  }

  RaycastHit2D? raycast(
    Vec2 origin,
    Vec2 direction, {
    double maxDistance = 1000.0,
    int mask = 0xFFFF,
  }) {
    final len = direction.length;
    if (len < 1e-12) return null;
    final dir = Vec2(direction.x / len, direction.y / len);
    final p1 = phys.PhysVec2(origin.x, origin.y);
    final p2 = phys.PhysVec2(
      origin.x + dir.x * maxDistance,
      origin.y + dir.y * maxDistance,
    );

    final rawHit = _world.raycastClosest(p1, p2, mask: mask);
    if (rawHit == null) return null;

    final collider = _fixtureToCollider[rawHit.fixture];
    if (collider == null) return null;

    return RaycastHit2D(
      collider: collider,
      point: Vec2(rawHit.point.x, rawHit.point.y),
      normal: Vec2(rawHit.normal.x, rawHit.normal.y),
      fraction: rawHit.fraction,
      distance: rawHit.fraction * maxDistance,
    );
  }
}
