part of '../../engine.dart';

/// Scheduled burst definition for [ParticleSystem] (P14-W22-C).
final class ParticleBurstSchedule {
  final double time;
  final int count;
  final int cycles;
  final double interval;

  const ParticleBurstSchedule({
    required this.time,
    required this.count,
    this.cycles = 1,
    this.interval = 0.0,
  });
}

/// Attaches a pixeldart [ParticleEmitter] to a [GameObject]. When
/// [followTransform] is true the emitter's spawn transform tracks the
/// object's world transform each frame.
final class ParticleSystem extends Component {
  final ParticleEmitter emitter;
  bool followTransform;
  final List<ParticleBurstSchedule> bursts;
  final List<int> _burstCyclesFired = [];
  bool _isPlaying = true;
  double _playbackTime = 0.0;
  int _totalBurstParticlesEmitted = 0;

  ParticleSystem(
    this.emitter, {
    this.followTransform = true,
    List<ParticleBurstSchedule> bursts = const [],
  }) : bursts = List<ParticleBurstSchedule>.of(bursts) {
    _burstCyclesFired.addAll(List<int>.filled(this.bursts.length, 0));
  }

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
  bool get isPlaying => _isPlaying;
  double get playbackTime => _playbackTime;
  int get totalBurstParticlesEmitted => _totalBurstParticlesEmitted;

  void addBurst(ParticleBurstSchedule b) {
    bursts.add(b);
    _burstCyclesFired.add(0);
  }

  void play() {
    _isPlaying = true;
    emitter.isEmitting = true;
  }

  void pause() {
    _isPlaying = false;
    emitter.isEmitting = false;
  }

  void stop({bool clearParticles = false}) {
    _isPlaying = false;
    _playbackTime = 0.0;
    for (var i = 0; i < _burstCyclesFired.length; i++) {
      _burstCyclesFired[i] = 0;
    }
    emitter.isEmitting = false;
    if (clearParticles) {
      emitter.reset();
    }
  }

  void reset() {
    _playbackTime = 0.0;
    _totalBurstParticlesEmitted = 0;
    for (var i = 0; i < _burstCyclesFired.length; i++) {
      _burstCyclesFired[i] = 0;
    }
    emitter.reset();
  }

  void clear() => reset();

  int burst(int count, {Vec3? position, Vec3? inheritedVelocity}) {
    final spawned = emitter.burst(
      count,
      position: position ?? (followTransform ? transform.position : null),
      inheritedVelocity: inheritedVelocity,
    );
    _totalBurstParticlesEmitted += spawned;
    return spawned;
  }

  void _stepBursts(double dt) {
    if (!_isPlaying || dt <= 0 || bursts.isEmpty) return;
    _playbackTime += dt;
    while (_burstCyclesFired.length < bursts.length) {
      _burstCyclesFired.add(0);
    }
    for (var i = 0; i < bursts.length; i++) {
      final b = bursts[i];
      var fired = _burstCyclesFired[i];
      while (fired < b.cycles) {
        final triggerTime = b.time + fired * b.interval;
        if (_playbackTime + 1e-9 >= triggerTime) {
          burst(b.count);
          fired++;
          _burstCyclesFired[i] = fired;
        } else {
          break;
        }
      }
    }
  }

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
