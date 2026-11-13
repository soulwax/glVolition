part of '../../engine.dart';

/// Attaches a pixeldart [ParticleEmitter] to a [GameObject]. When
/// [followTransform] is true the emitter's spawn transform tracks the
/// object's world transform each frame.
final class ParticleSystem extends Component {
  final ParticleEmitter emitter;
  bool followTransform;

  ParticleSystem(this.emitter, {this.followTransform = true});

  /// Creates a campfire particle preset emitter (E18-1).
  factory ParticleSystem.campfire({
    required MeshHandle mesh,
    required MaterialHandle material,
    List<MaterialHandle>? materialRamp,
    Vec3 origin = Vec3.zero,
    double scale = 1.0,
    int? seed,
    bool followTransform = true,
  }) => ParticleSystem(
    ParticlePresets.campfire(
      mesh: mesh,
      material: material,
      materialRamp: materialRamp,
      origin: origin,
      scale: scale,
      seed: seed,
    ),
    followTransform: followTransform,
  );

  /// Creates an explosion particle preset emitter (E18-1).
  factory ParticleSystem.explosion({
    required MeshHandle mesh,
    required MaterialHandle material,
    Vec3 origin = Vec3.zero,
    double radius = 1.5,
    int particleCount = 120,
    double explosionSpeed = 12.0,
    int? seed,
    bool followTransform = true,
  }) => ParticleSystem(
    ParticlePresets.explosion(
      mesh: mesh,
      material: material,
      origin: origin,
      radius: radius,
      particleCount: particleCount,
      explosionSpeed: explosionSpeed,
      seed: seed,
    ),
    followTransform: followTransform,
  );

  /// Creates a smoke plume particle preset emitter (E18-1).
  factory ParticleSystem.smokePlume({
    required MeshHandle mesh,
    required MaterialHandle material,
    Vec3 origin = Vec3.zero,
    double scale = 1.0,
    int? seed,
    bool followTransform = true,
  }) => ParticleSystem(
    ParticlePresets.smokePlume(
      mesh: mesh,
      material: material,
      origin: origin,
      scale: scale,
      seed: seed,
    ),
    followTransform: followTransform,
  );

  /// Creates bouncing sparks particle preset emitter (E18-1).
  factory ParticleSystem.bouncingSparks({
    required MeshHandle mesh,
    required MaterialHandle material,
    Vec3 origin = const Vec3(0, 1.5, 0),
    Vec3 sprayDirection = const Vec3(0.8, -0.5, 0),
    double groundHeight = 0.0,
    int? seed,
    bool followTransform = true,
  }) => ParticleSystem(
    ParticlePresets.bouncingSparks(
      mesh: mesh,
      material: material,
      origin: origin,
      sprayDirection: sprayDirection,
      groundHeight: groundHeight,
      seed: seed,
    ),
    followTransform: followTransform,
  );

  /// Creates fireflies particle preset emitter (E18-1).
  factory ParticleSystem.fireflies({
    required MeshHandle mesh,
    required MaterialHandle material,
    Vec3 origin = Vec3.zero,
    Vec3 boundsHalfExtents = const Vec3(5, 2, 5),
    int particleCount = 40,
    int? seed,
    bool followTransform = true,
  }) => ParticleSystem(
    ParticlePresets.fireflies(
      mesh: mesh,
      material: material,
      origin: origin,
      boundsHalfExtents: boundsHalfExtents,
      particleCount: particleCount,
      seed: seed,
    ),
    followTransform: followTransform,
  );

  /// Creates celebratory confetti particle preset emitter (E18-1).
  factory ParticleSystem.confetti({
    required MeshHandle mesh,
    required MaterialHandle material,
    Vec3 origin = const Vec3(0, 6, 0),
    Vec3 areaHalfExtents = const Vec3(4, 0.5, 4),
    int? seed,
    bool followTransform = true,
  }) => ParticleSystem(
    ParticlePresets.confetti(
      mesh: mesh,
      material: material,
      origin: origin,
      areaHalfExtents: areaHalfExtents,
      seed: seed,
    ),
    followTransform: followTransform,
  );

  int get activeParticleCount => emitter.activeCount;

  void reset() => emitter.reset();
  void clear() => emitter.reset();

  int burst(int count, {Vec3? position, Vec3? inheritedVelocity}) =>
      emitter.burst(
        count,
        position: position ?? (followTransform ? transform.position : null),
        inheritedVelocity: inheritedVelocity,
      );

  void _syncTransform() {
    if (followTransform) emitter.transform = transform.world;
  }

  @override
  void _onEnableInternal() {
    _syncTransform();
    scene._particles.add(this);
    engine.graphics.addEmitter(emitter);
  }

  @override
  void _onDisableInternal() {
    scene._particles.remove(this);
    engine.graphics.removeEmitter(emitter);
  }
}
