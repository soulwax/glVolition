part of '../../engine.dart';

/// Collision bitmask returned by [CharacterController.move] (E10-2).
abstract final class CollisionFlags {
  static const int none = 0;
  static const int sides = 1 << 0;
  static const int above = 1 << 1;
  static const int below = 1 << 2;
}

/// Kinematic 3D character controller with capsule/sphere depenetration,
/// wall sliding, slope clamping, coyote time, jump buffering, moving platform
/// carry, and automatic [TerrainComponent] grounding (E10-2, P13-W21-A).
final class CharacterController extends Component {
  double radius;
  double height;
  Vec3 center;
  double stepOffset;
  double slopeLimitDegrees;
  double skinWidth;
  bool useGravity;
  Vec3 gravity;
  double coyoteTime;
  double jumpBufferTime;

  bool _isGrounded = false;
  Vec3 _velocity = Vec3.zero;
  double _verticalSpeed = 0.0;
  int _collisionFlags = CollisionFlags.none;
  Vec3 _groundNormal = Vec3.unitY;
  GameObject? _groundObject;
  Vec3? _lastGroundPos;
  double _coyoteTimer = 0.0;
  double _jumpBufferTimer = 0.0;

  CharacterController({
    this.radius = 0.4,
    this.height = 1.8,
    this.center = const Vec3(0, 0.9, 0),
    this.stepOffset = 0.35,
    this.slopeLimitDegrees = 45.0,
    this.skinWidth = 0.02,
    this.useGravity = true,
    this.gravity = const Vec3(0, -9.81, 0),
    this.coyoteTime = 0.12,
    this.jumpBufferTime = 0.12,
  });

  bool get isGrounded => _isGrounded;
  Vec3 get velocity => _velocity;
  double get verticalSpeed => _verticalSpeed;
  int get collisionFlags => _collisionFlags;
  Vec3 get groundNormal => _groundNormal;
  GameObject? get groundObject =>
      (_groundObject != null && !_groundObject!.isDestroyed)
      ? _groundObject
      : null;
  bool get canCoyoteJump => _isGrounded || _coyoteTimer > 0.0;
  bool get hasBufferedJump => _jumpBufferTimer > 0.0;

  /// Buffers a jump request for [jumpBufferTime] seconds so slightly-early jump
  /// presses execute automatically on landing (P13-W21-A).
  void queueJump() {
    _jumpBufferTimer = math.max(0.0, jumpBufferTime);
  }

  /// Executes a buffered (or immediate when [requireBuffer] is `false`) jump
  /// with upward [jumpSpeed] if grounded or within [coyoteTime].
  bool consumeBufferedJump(double jumpSpeed, {bool requireBuffer = true}) {
    if (requireBuffer && _jumpBufferTimer <= 0.0) return false;
    if (!canCoyoteJump) return false;
    _verticalSpeed = jumpSpeed;
    _isGrounded = false;
    _coyoteTimer = 0.0;
    _jumpBufferTimer = 0.0;
    _groundObject = null;
    _lastGroundPos = null;
    return true;
  }

  /// Moves the character by [motion] in world space, sliding along static solid
  /// colliders in [PhysicsWorld] and clamping against any active
  /// [TerrainComponent] in the scene. Returns a [CollisionFlags] bitmask.
  int move(Vec3 motion) {
    final dt = scene.isLoaded ? engine.time.deltaTime : 0.0;

    // Carry character along with moving ground platform if still standing on it.
    var effectiveMotion = motion;
    if (_isGrounded &&
        _groundObject != null &&
        !_groundObject!.isDestroyed &&
        _lastGroundPos != null) {
      final platformDelta = _groundObject!.transform.position - _lastGroundPos!;
      effectiveMotion = effectiveMotion + platformDelta;
    }

    final startPos = transform.position;
    var flags = CollisionFlags.none;
    var grounded = false;
    var bestGroundNormal = Vec3.unitY;
    GameObject? hitGroundObject;
    final minSlopeY = math.cos(slopeLimitDegrees * math.pi / 180.0);
    final r = math.max(0.05, radius) + skinWidth;
    final halfSeg = math.max(0.0, height * 0.5 - radius);
    final offsets = halfSeg > 1e-4
        ? <Vec3>[Vec3(0, -halfSeg, 0), Vec3(0, halfSeg, 0)]
        : const <Vec3>[Vec3.zero];

    final maxStep = math.max(0.05, radius * 0.5);
    final subSteps = math.max(1, (effectiveMotion.length / maxStep).ceil());
    final stepDelta = effectiveMotion * (1.0 / subSteps);
    var pos = startPos;

    for (var s = 0; s < subSteps; s++) {
      pos = pos + stepDelta;
      for (var pass = 0; pass < 3; pass++) {
        for (final other in scene.physics._colliders) {
          if (!other._active ||
              other.isTrigger ||
              other.gameObject == gameObject) {
            continue;
          }
          if ((other.collidesWithMask & (1 << gameObject.layer)) == 0) continue;

          for (final offset in offsets) {
            final sphereCenter = pos + center + offset;
            final resolved = _depenetrateSphere(sphereCenter, r, other);
            if (resolved == null) continue;
            final (:normal, :depth) = resolved;
            pos = pos + normal * depth;
            if (normal.y >= minSlopeY) {
              grounded = true;
              bestGroundNormal = normal;
              hitGroundObject = other.gameObject;
              flags |= CollisionFlags.below;
            } else if (normal.y < -0.5) {
              flags |= CollisionFlags.above;
            } else {
              flags |= CollisionFlags.sides;
            }
          }
        }
      }
    }

    // Clamp to active TerrainComponent height if present.
    for (final terrain in scene.findObjectsOfType<TerrainComponent>()) {
      final groundY = terrain.sampleHeight(pos.x, pos.z);
      final bottomY = pos.y + center.y - math.max(radius, height * 0.5);
      if (bottomY <= groundY + skinWidth) {
        final lift =
            (groundY + math.max(radius, height * 0.5) - center.y) - pos.y;
        if (lift >= -skinWidth) {
          pos = Vec3(pos.x, pos.y + lift, pos.z);
          grounded = true;
          bestGroundNormal = Vec3.unitY;
          hitGroundObject = terrain.gameObject;
          flags |= CollisionFlags.below;
        }
      }
    }

    transform.position = pos;
    _isGrounded = grounded;
    _groundNormal = bestGroundNormal;
    _groundObject = hitGroundObject;
    _lastGroundPos = hitGroundObject?.transform.position;
    _collisionFlags = flags;

    if (grounded) {
      _coyoteTimer = coyoteTime;
    } else if (dt > 0) {
      _coyoteTimer = math.max(0.0, _coyoteTimer - dt);
    }
    if (_jumpBufferTimer > 0 && dt > 0) {
      _jumpBufferTimer = math.max(0.0, _jumpBufferTimer - dt);
    }

    if (dt > 1e-6) {
      _velocity = (pos - startPos) * (1.0 / dt);
    } else {
      _velocity = pos - startPos;
    }
    return flags;
  }

  /// Moves the character using a horizontal/planar [speed] (units/second) and
  /// integrates [gravity] automatically across `time.deltaTime`.
  bool simpleMove(Vec3 speed) {
    final dt = scene.isLoaded ? engine.time.deltaTime : (1.0 / 60.0);
    if (_isGrounded && _verticalSpeed < 0) {
      _verticalSpeed = -0.5;
    }
    if (useGravity) {
      _verticalSpeed += gravity.y * dt;
    }
    final motion = Vec3(
      speed.x * dt,
      (speed.y + _verticalSpeed) * dt,
      speed.z * dt,
    );
    move(motion);
    if (_isGrounded && _verticalSpeed < 0) {
      _verticalSpeed = 0.0;
    }
    return _isGrounded;
  }

  ({Vec3 normal, double depth})? _depenetrateSphere(
    Vec3 sphereCenter,
    double sphereRadius,
    Collider other,
  ) {
    if (other is SphereCollider) {
      final otherCenter = other.worldCenter;
      final otherRadius = other.worldRadius;
      final delta = sphereCenter - otherCenter;
      final dist = delta.length;
      final minDist = sphereRadius + otherRadius;
      if (dist >= minDist) return null;
      final normal = dist > 1e-6 ? delta * (1.0 / dist) : Vec3.unitY;
      return (normal: normal, depth: minDist - dist);
    }
    final box = other.worldBounds;
    final closest = Vec3(
      sphereCenter.x.clamp(box.min.x, box.max.x),
      sphereCenter.y.clamp(box.min.y, box.max.y),
      sphereCenter.z.clamp(box.min.z, box.max.z),
    );
    final delta = sphereCenter - closest;
    final distSq = delta.lengthSquared;
    if (distSq >= sphereRadius * sphereRadius) return null;
    if (distSq > 1e-9) {
      final dist = math.sqrt(distSq);
      return (normal: delta * (1.0 / dist), depth: sphereRadius - dist);
    }
    // Center is inside the AABB: push out along the shallowest axis.
    final dxMin = (sphereCenter.x - box.min.x).abs();
    final dxMax = (box.max.x - sphereCenter.x).abs();
    final dyMin = (sphereCenter.y - box.min.y).abs();
    final dyMax = (box.max.y - sphereCenter.y).abs();
    final dzMin = (sphereCenter.z - box.min.z).abs();
    final dzMax = (box.max.z - sphereCenter.z).abs();
    var best = dyMax;
    var normal = Vec3.unitY;
    if (dyMin < best) {
      best = dyMin;
      normal = const Vec3(0, -1, 0);
    }
    if (dxMin < best) {
      best = dxMin;
      normal = const Vec3(-1, 0, 0);
    }
    if (dxMax < best) {
      best = dxMax;
      normal = Vec3.unitX;
    }
    if (dzMin < best) {
      best = dzMin;
      normal = const Vec3(0, 0, -1);
    }
    if (dzMax < best) {
      best = dzMax;
      normal = Vec3.unitZ;
    }
    return (normal: normal, depth: best + sphereRadius);
  }
}
