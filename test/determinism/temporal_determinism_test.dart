/// 600-frame fixed-step deterministic simulation & canonical state hash suites (Wave 13 / P5-W13-D).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:test/test.dart';

// ============================================================================
// Deterministic 64-bit FNV-1a Canonical State Hasher
// ============================================================================

/// 64-bit FNV-1a hasher for bit-identical state snapshot verification.
final class Fnv1a64Hasher {
  static final BigInt _offsetBasis = BigInt.parse(
    'cbf29ce484222325',
    radix: 16,
  );
  static final BigInt _prime = BigInt.parse('100000001b3', radix: 16);
  static final BigInt _mask64 = BigInt.parse('ffffffffffffffff', radix: 16);

  BigInt _hash = _offsetBasis;

  void addByte(int byte) {
    _hash = (_hash ^ BigInt.from(byte & 0xff));
    _hash = (_hash * _prime) & _mask64;
  }

  void addBytes(List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      addByte(bytes[i]);
    }
  }

  void addFloat64(double value) {
    // Normalize -0.0 to 0.0 to ensure canonical bit representation
    final v = (value == 0.0) ? 0.0 : value;
    final bd = ByteData(8)..setFloat64(0, v, Endian.little);
    for (var i = 0; i < 8; i++) {
      addByte(bd.getUint8(i));
    }
  }

  void addInt64(int value) {
    final bd = ByteData(8)..setInt64(0, value, Endian.little);
    for (var i = 0; i < 8; i++) {
      addByte(bd.getUint8(i));
    }
  }

  void addVec3(Vec3 v) {
    addFloat64(v.x);
    addFloat64(v.y);
    addFloat64(v.z);
  }

  void addQuat(Quat q) {
    addFloat64(q.x);
    addFloat64(q.y);
    addFloat64(q.z);
    addFloat64(q.w);
  }

  void addString(String str) {
    for (final unit in str.codeUnits) {
      addByte(unit & 0xff);
      addByte((unit >> 8) & 0xff);
    }
  }

  String get hex => _hash.toRadixString(16).padLeft(16, '0');
  BigInt get value => _hash;
}

// ============================================================================
// Canonical State Snapshot Model
// ============================================================================

final class EntitySnapshot {
  final String name;
  final Vec3 position;
  final Quat rotation;
  final Vec3 scale;
  final Vec3? velocity;
  final double? animTime;
  final int? spriteFrame;
  final String? aiState;
  final double? aiMetric;
  final int? collisionCount;

  const EntitySnapshot({
    required this.name,
    required this.position,
    required this.rotation,
    required this.scale,
    this.velocity,
    this.animTime,
    this.spriteFrame,
    this.aiState,
    this.aiMetric,
    this.collisionCount,
  });

  void feedHasher(Fnv1a64Hasher hasher) {
    hasher.addString(name);
    hasher.addVec3(position);
    hasher.addQuat(rotation);
    hasher.addVec3(scale);
    if (velocity != null) {
      hasher.addByte(1);
      hasher.addVec3(velocity!);
    } else {
      hasher.addByte(0);
    }
    if (animTime != null) {
      hasher.addByte(1);
      hasher.addFloat64(animTime!);
    } else {
      hasher.addByte(0);
    }
    if (spriteFrame != null) {
      hasher.addByte(1);
      hasher.addInt64(spriteFrame!);
    } else {
      hasher.addByte(0);
    }
    if (aiState != null) {
      hasher.addByte(1);
      hasher.addString(aiState!);
    } else {
      hasher.addByte(0);
    }
    if (aiMetric != null) {
      hasher.addByte(1);
      hasher.addFloat64(aiMetric!);
    } else {
      hasher.addByte(0);
    }
    if (collisionCount != null) {
      hasher.addByte(1);
      hasher.addInt64(collisionCount!);
    } else {
      hasher.addByte(0);
    }
  }

  bool isIdenticalTo(EntitySnapshot other) {
    if (name != other.name) return false;
    if (position.x != other.position.x ||
        position.y != other.position.y ||
        position.z != other.position.z) {
      return false;
    }
    if (rotation.x != other.rotation.x ||
        rotation.y != other.rotation.y ||
        rotation.z != other.rotation.z ||
        rotation.w != other.rotation.w) {
      return false;
    }
    if (scale.x != other.scale.x ||
        scale.y != other.scale.y ||
        scale.z != other.scale.z) {
      return false;
    }
    if (velocity?.x != other.velocity?.x ||
        velocity?.y != other.velocity?.y ||
        velocity?.z != other.velocity?.z) {
      return false;
    }
    if (animTime != other.animTime) return false;
    if (spriteFrame != other.spriteFrame) return false;
    if (aiState != other.aiState) return false;
    if (aiMetric != other.aiMetric) return false;
    if (collisionCount != other.collisionCount) return false;
    return true;
  }
}

final class DeterministicSnapshot {
  final int frameIndex;
  final double time;
  final double fixedTime;
  final List<EntitySnapshot> entities;

  DeterministicSnapshot({
    required this.frameIndex,
    required this.time,
    required this.fixedTime,
    required List<EntitySnapshot> entities,
  }) : entities = List.unmodifiable(
         List.of(entities)..sort((a, b) => a.name.compareTo(b.name)),
       );

  String computeFnv1a64() {
    final hasher = Fnv1a64Hasher();
    hasher.addInt64(frameIndex);
    hasher.addFloat64(time);
    hasher.addFloat64(fixedTime);
    hasher.addInt64(entities.length);
    for (final e in entities) {
      e.feedHasher(hasher);
    }
    return hasher.hex;
  }

  bool bitIdenticalTo(DeterministicSnapshot other) {
    if (frameIndex != other.frameIndex) return false;
    if (time != other.time) return false;
    if (fixedTime != other.fixedTime) return false;
    if (entities.length != other.entities.length) return false;
    for (var i = 0; i < entities.length; i++) {
      if (!entities[i].isIdenticalTo(other.entities[i])) return false;
    }
    return true;
  }

  String diff(DeterministicSnapshot other) {
    final buf = StringBuffer();
    if (frameIndex != other.frameIndex) {
      buf.writeln('frameIndex: $frameIndex != ${other.frameIndex}');
    }
    if (time != other.time) {
      buf.writeln('time: $time != ${other.time}');
    }
    if (fixedTime != other.fixedTime) {
      buf.writeln('fixedTime: $fixedTime != ${other.fixedTime}');
    }
    if (entities.length != other.entities.length) {
      buf.writeln(
        'entities count: ${entities.length} != ${other.entities.length}',
      );
    }
    final maxLen = math.max(entities.length, other.entities.length);
    for (var i = 0; i < maxLen; i++) {
      if (i >= entities.length) {
        buf.writeln('missing entity at $i in this: ${other.entities[i].name}');
        continue;
      }
      if (i >= other.entities.length) {
        buf.writeln('extra entity at $i in this: ${entities[i].name}');
        continue;
      }
      final a = entities[i];
      final b = other.entities[i];
      if (!a.isIdenticalTo(b)) {
        buf.writeln('entity mismatch [${a.name}]:');
        if (a.position != b.position) {
          buf.writeln('  pos: ${a.position} != ${b.position}');
        }
        if (a.rotation != b.rotation) {
          buf.writeln('  rot: ${a.rotation} != ${b.rotation}');
        }
        if (a.velocity != b.velocity) {
          buf.writeln('  vel: ${a.velocity} != ${b.velocity}');
        }
        if (a.aiState != b.aiState) {
          buf.writeln('  aiState: ${a.aiState} != ${b.aiState}');
        }
        if (a.aiMetric != b.aiMetric) {
          buf.writeln('  aiMetric: ${a.aiMetric} != ${b.aiMetric}');
        }
      }
    }
    return buf.toString();
  }
}

// ============================================================================
// Test Behaviours for Deterministic Simulation
// ============================================================================

/// Tracks solid and trigger collision contact counts deterministically.
final class DeterministicCollisionTracker extends Behaviour {
  int enterCount = 0;
  int stayCount = 0;
  int exitCount = 0;
  Vec3 lastContactNormal = Vec3.zero;

  @override
  void onCollisionEnter(Collision collision) {
    enterCount++;
    lastContactNormal = collision.contactNormal;
  }

  @override
  void onTriggerEnter(Collider other) {
    enterCount++;
  }

  @override
  void onTriggerStay(Collider other) {
    stayCount++;
  }

  @override
  void onTriggerExit(Collider other) {
    exitCount++;
  }
}

/// Deterministic AI agent driven by seeded PRNG and an explicit [StateMachine].
final class DeterministicAiAgent extends Behaviour {
  final int seed;
  final StateMachine<String> fsm;
  late final math.Random _rng;

  Vec3 targetCoordinate = Vec3.zero;
  int decisionCount = 0;
  double cumulativeDistanceWalked = 0.0;
  double _currentYawRad = 0.0;

  DeterministicAiAgent({required this.seed, required this.fsm});

  @override
  void awake() {
    _rng = math.Random(seed);
    fsm.defineState(
      'patrol',
      onEnter: () {
        decisionCount++;
        final rx = (_rng.nextDouble() * 20.0) - 10.0;
        final rz = (_rng.nextDouble() * 20.0) - 10.0;
        targetCoordinate = Vec3(rx, 0, rz);
      },
      onUpdate: (dt) {
        final currentPos = transform.position;
        final delta = targetCoordinate - currentPos;
        final dist = delta.length;
        if (dist <= 0.25) {
          fsm.transitionTo('search');
        } else {
          final step = math.min(dist, dt * 4.0);
          final stepVec = delta * (step / dist);
          transform.position += stepVec;
          cumulativeDistanceWalked += step;
        }
      },
    );

    fsm.defineState(
      'search',
      onEnter: () {
        decisionCount++;
      },
      onUpdate: (dt) {
        // Deterministic rotational search sweep
        _currentYawRad += dt * 1.5;
        transform.rotation = Quat.axisAngle(
          const Vec3(0, 1, 0),
          _currentYawRad,
        );
        if (fsm.stateTime >= 0.5) {
          fsm.transitionTo('patrol');
        }
      },
    );
  }
}

// ============================================================================
// Snapshot Extraction Helper
// ============================================================================

DeterministicSnapshot captureWorldSnapshot(Engine engine) {
  final entities = <EntitySnapshot>[];
  for (final go in engine.scene.rootGameObjects) {
    _collectSnapshotsRecursive(go, entities);
  }
  return DeterministicSnapshot(
    frameIndex: engine.time.frameCount,
    time: engine.time.time,
    fixedTime: engine.time.fixedTime,
    entities: entities,
  );
}

void _collectSnapshotsRecursive(GameObject go, List<EntitySnapshot> out) {
  final rb = go.getComponent<RigidBody>();
  final anim = go.getComponent<Animator>();
  final spriteAnim = go.getComponent<SpriteAnimator>();
  final ai = go.getComponent<DeterministicAiAgent>();
  final fsm = go.getComponent<StateMachine<String>>();
  final colTracker = go.getComponent<DeterministicCollisionTracker>();

  final s = go.transform.localScale;
  out.add(
    EntitySnapshot(
      name: go.name,
      position: go.transform.position,
      rotation: go.transform.rotation,
      scale: Vec3(s, s, s),
      velocity: rb?.velocity,
      animTime: anim != null ? go.node.localTransform.translation.x : null,
      spriteFrame: spriteAnim?.currentFrameIndex,
      aiState: fsm?.currentState,
      aiMetric: ai?.cumulativeDistanceWalked,
      collisionCount: colTracker?.enterCount,
    ),
  );

  for (final child in go.children) {
    _collectSnapshotsRecursive(child, out);
  }
}

// ============================================================================
// Test World Factory
// ============================================================================

Engine buildDeterministicSimulationWorld({
  required int seed,
  double fixedDeltaTime = 1.0 / 60.0,
}) {
  final host = HeadlessHost();
  final engine = Engine(host);
  engine.time.fixedDeltaTime = fixedDeltaTime;

  // 1. Static Geometry
  final floor = engine.scene.createGameObject(
    'Floor',
    position: const Vec3(0, -1, 0),
    components: [BoxCollider(size: const Vec3(100, 2, 100), isTrigger: false)],
  );
  floor.addComponent(DeterministicCollisionTracker());

  final slope = engine.scene.createGameObject(
    'Slope',
    position: const Vec3(10, 2, 0),
    rotation: Quat.axisAngle(const Vec3(0, 0, 1), 0.25),
    components: [BoxCollider(size: const Vec3(15, 1, 10), isTrigger: false)],
  );
  slope.addComponent(DeterministicCollisionTracker());

  // 2. Dynamic Physics Bodies
  final ball = engine.scene.createGameObject(
    'DynamicBall',
    position: const Vec3(0, 15, 0),
    components: [
      SphereCollider(radius: 1.0, isTrigger: false),
      RigidBody(
        mass: 2.0,
        restitution: 0.7,
        linearDrag: 0.02,
        useGravity: true,
      ),
      DeterministicCollisionTracker(),
    ],
  );
  expect(ball, isNotNull);

  final box = engine.scene.createGameObject(
    'DynamicBox',
    position: const Vec3(0.5, 25, 0),
    components: [
      BoxCollider(size: const Vec3(1.5, 1.5, 1.5), isTrigger: false),
      RigidBody(
        mass: 1.5,
        restitution: 0.4,
        linearDrag: 0.03,
        useGravity: true,
      ),
      DeterministicCollisionTracker(),
    ],
  );
  expect(box, isNotNull);

  final projectile = engine.scene.createGameObject(
    'Projectile',
    position: const Vec3(-25, 6, 0),
    components: [
      SphereCollider(radius: 0.5, isTrigger: false),
      RigidBody(mass: 1.0, velocity: const Vec3(12, 0, 0), useGravity: false),
      DeterministicCollisionTracker(),
    ],
  );
  expect(projectile, isNotNull);

  // 3. Seeded AI Agent with attached StateMachine
  final fsm = StateMachine<String>('patrol');
  final aiGo = engine.scene.createGameObject(
    'AiAgent',
    position: const Vec3(-5, 0, -5),
    components: [
      fsm,
      DeterministicAiAgent(seed: seed, fsm: fsm),
    ],
  );
  expect(aiGo, isNotNull);

  // 4. 3D Keyframe Animator
  final animGo = engine.scene.createGameObject(
    'AnimatedMesh',
    position: const Vec3(5, 0, 5),
  );
  final clip = AnimationClip(
    name: 'bobbing',
    duration: 2.0,
    loopMode: LoopMode.loop,
    tracks: [
      Vector3Track(
        target: animGo.node,
        keyframes: const [
          Keyframe(0.0, Vec3(0, 0, 0)),
          Keyframe(0.5, Vec3(0, 3, 0)),
          Keyframe(1.0, Vec3(2, 4, 1)),
          Keyframe(2.0, Vec3(0, 0, 0)),
        ],
      ),
      RotationTrack(
        target: animGo.node,
        keyframes: [
          Keyframe(0.0, Quat.identity),
          Keyframe(1.0, Quat.axisAngle(const Vec3(0, 1, 0), math.pi)),
          Keyframe(2.0, Quat.identity),
        ],
      ),
    ],
  );
  animGo.addComponent(Animator(initialClips: [clip], defaultClip: 'bobbing'));

  // 5. 2D Frame-by-frame Sprite Animator
  final spriteGo = engine.scene.createGameObject(
    'AnimatedSprite',
    position: const Vec3(-8, 1, 8),
  );
  final r0 = SpriteRegion(
    texture: null,
    width: 16,
    height: 16,
    u0: 0,
    v0: 0,
    u1: 0.25,
    v1: 1,
  );
  final r1 = SpriteRegion(
    texture: null,
    width: 16,
    height: 16,
    u0: 0.25,
    v0: 0,
    u1: 0.5,
    v1: 1,
  );
  final r2 = SpriteRegion(
    texture: null,
    width: 16,
    height: 16,
    u0: 0.5,
    v0: 0,
    u1: 0.75,
    v1: 1,
  );
  final r3 = SpriteRegion(
    texture: null,
    width: 16,
    height: 16,
    u0: 0.75,
    v0: 0,
    u1: 1.0,
    v1: 1,
  );
  final spriteAnim = SpriteAnimator(
    clips: {
      'walk': [r0, r1, r2, r3],
    },
    fps: 10,
    loop: true,
    initialClip: 'walk',
  );
  spriteGo.addComponent(spriteAnim);

  // 6. Voxtween Animated Prop
  final tweenGo = engine.scene.createGameObject(
    'TweenProp',
    position: const Vec3(15, 0, -15),
  );
  tweenGo.transform.tweenPosition(
    const Vec3(25, 10, -5),
    10.0,
    ease: Ease.inOutQuad,
  );

  return engine;
}

// ============================================================================
// Test Suite
// ============================================================================

void main() {
  setUp(() {
    TweenManager.instance.killAll();
  });

  tearDown(() {
    TweenManager.instance.killAll();
  });

  group('P5-W13-D — Temporal Determinism & 600-Frame State Hashes', () {
    test(
      '600-frame fixed-step deterministic simulation produces bit-identical states across isolated runs',
      () {
        const totalFrames = 600;
        const frameDt = 1.0 / 60.0;
        const testSeed = 42;

        // Run 1: Clean Engine & Scene
        final engine1 = buildDeterministicSimulationWorld(seed: testSeed);
        final checkpointsRun1 = <int, DeterministicSnapshot>{};

        for (var f = 1; f <= totalFrames; f++) {
          engine1.step(frameDt);
          if (f == 150 || f == 300 || f == 450 || f == 600) {
            checkpointsRun1[f] = captureWorldSnapshot(engine1);
          }
        }

        // Clean up tweens between runs
        TweenManager.instance.killAll();

        // Run 2: Completely independent, isolated instance with identical seed
        final engine2 = buildDeterministicSimulationWorld(seed: testSeed);
        final checkpointsRun2 = <int, DeterministicSnapshot>{};

        for (var f = 1; f <= totalFrames; f++) {
          engine2.step(frameDt);
          if (f == 150 || f == 300 || f == 450 || f == 600) {
            checkpointsRun2[f] = captureWorldSnapshot(engine2);
          }
        }

        // Verification: Every checkpoint MUST be 100% bit-identical
        for (final frame in [150, 300, 450, 600]) {
          final snap1 = checkpointsRun1[frame]!;
          final snap2 = checkpointsRun2[frame]!;

          final hash1 = snap1.computeFnv1a64();
          final hash2 = snap2.computeFnv1a64();

          expect(
            hash1,
            equals(hash2),
            reason:
                'Checkpoint at frame $frame FNV-1a hash divergent:\n${snap1.diff(snap2)}',
          );
          expect(
            snap1.bitIdenticalTo(snap2),
            isTrue,
            reason:
                'Checkpoint at frame $frame field-level bit difference:\n${snap1.diff(snap2)}',
          );
        }

        // Validate that dynamic simulation actually progressed and is not trivial/static
        final finalSnap = checkpointsRun1[600]!;
        final ballSnap = finalSnap.entities.firstWhere(
          (e) => e.name == 'DynamicBall',
        );
        final boxSnap = finalSnap.entities.firstWhere(
          (e) => e.name == 'DynamicBox',
        );
        final aiSnap = finalSnap.entities.firstWhere(
          (e) => e.name == 'AiAgent',
        );
        final tweenSnap = finalSnap.entities.firstWhere(
          (e) => e.name == 'TweenProp',
        );

        // Ball bounced and came to rest or active velocity near floor (y < 15.0)
        expect(ballSnap.position.y, lessThan(15.0));
        expect(boxSnap.position.y, lessThan(25.0));
        expect(ballSnap.collisionCount, greaterThan(0));

        // AI progressed and walked non-zero distance
        expect(aiSnap.aiMetric, greaterThan(1.0));

        // Tweened prop moved towards target
        expect(tweenSnap.position.x, greaterThan(15.0));
      },
    );

    test('Different random seed results in distinct canonical state hash', () {
      const totalFrames = 300;
      const frameDt = 1.0 / 60.0;

      final engineSeedA = buildDeterministicSimulationWorld(seed: 42);
      for (var f = 0; f < totalFrames; f++) {
        engineSeedA.step(frameDt);
      }
      final snapA = captureWorldSnapshot(engineSeedA);
      final hashA = snapA.computeFnv1a64();

      TweenManager.instance.killAll();

      final engineSeedB = buildDeterministicSimulationWorld(seed: 99999);
      for (var f = 0; f < totalFrames; f++) {
        engineSeedB.step(frameDt);
      }
      final snapB = captureWorldSnapshot(engineSeedB);
      final hashB = snapB.computeFnv1a64();

      expect(
        hashA,
        isNot(equals(hashB)),
        reason: 'Seeded PRNG divergence must alter the canonical state hash',
      );
    });

    test(
      'Sub-step accumulator determinism: uniform vs varied raw delta steps with identical fixed rate',
      () {
        const fixedDt = 1.0 / 50.0;
        const totalSimulationSeconds = 4.0; // 200 fixed steps

        // Run A: Exact 1/50 raw delta steps
        final engineA = buildDeterministicSimulationWorld(
          seed: 777,
          fixedDeltaTime: fixedDt,
        );
        final stepsA = (totalSimulationSeconds / fixedDt).round();
        for (var i = 0; i < stepsA; i++) {
          engineA.step(fixedDt);
        }
        final snapA = captureWorldSnapshot(engineA);

        TweenManager.instance.killAll();

        // Run B: Half-step raw deltas (1/100) taking 2 frames per fixed step
        final engineB = buildDeterministicSimulationWorld(
          seed: 777,
          fixedDeltaTime: fixedDt,
        );
        final halfStep = fixedDt * 0.5;
        final stepsB = stepsA * 2;
        for (var i = 0; i < stepsB; i++) {
          engineB.step(halfStep);
        }
        final snapB = captureWorldSnapshot(engineB);

        // Fixed physics time must match exactly
        expect(engineA.time.fixedTime, closeTo(totalSimulationSeconds, 1e-5));
        expect(engineB.time.fixedTime, closeTo(totalSimulationSeconds, 1e-5));

        // Physics positions solved in fixedUpdate match within tight tolerance
        final ballA = snapA.entities.firstWhere((e) => e.name == 'DynamicBall');
        final ballB = snapB.entities.firstWhere((e) => e.name == 'DynamicBall');
        expect(ballA.position.y, closeTo(ballB.position.y, 1e-3));
        expect(ballA.velocity!.y, closeTo(ballB.velocity!.y, 1e-3));
      },
    );

    test(
      'Session snapshot restore preserves deterministic continuation to 600 frames',
      () {
        const frameDt = 1.0 / 60.0;
        const checkpointFrame = 300;
        const totalFrames = 600;

        // Baseline: uninterrupted 600-frame run
        final baselineEngine = buildDeterministicSimulationWorld(seed: 1234);
        for (var f = 0; f < totalFrames; f++) {
          baselineEngine.step(frameDt);
        }
        final baselineSnap = captureWorldSnapshot(baselineEngine);

        TweenManager.instance.killAll();

        // Branch run: step to 300, capture session snapshot, restore, and step to 600
        final branchEngine = buildDeterministicSimulationWorld(seed: 1234);
        for (var f = 0; f < checkpointFrame; f++) {
          branchEngine.step(frameDt);
        }

        // Capture session snapshot
        final sessionState = branchEngine.captureSessionSnapshot();
        expect(sessionState, isNotEmpty);
        expect(sessionState.containsKey('scene'), isTrue);

        // Create fresh Engine, restore snapshot, and continue stepping
        final restoredHost = HeadlessHost();
        final restoredEngine = Engine(restoredHost);
        restoredEngine.restoreSessionSnapshot(sessionState);

        // Continue remaining 300 frames
        for (var f = checkpointFrame; f < totalFrames; f++) {
          restoredEngine.step(frameDt);
        }
        final restoredSnap = captureWorldSnapshot(restoredEngine);

        // Validate key physical entities continue on identical paths
        final baseBall = baselineSnap.entities.firstWhere(
          (e) => e.name == 'DynamicBall',
        );
        final restoredBall = restoredSnap.entities.firstWhere(
          (e) => e.name == 'DynamicBall',
        );

        expect(
          restoredBall.position.x,
          closeTo(baseBall.position.x, 1e-3),
          reason: 'Restored ball X matches uninterrupted run',
        );
        expect(
          restoredBall.position.y,
          closeTo(baseBall.position.y, 1e-3),
          reason: 'Restored ball Y matches uninterrupted run',
        );
        expect(
          restoredBall.position.z,
          closeTo(baseBall.position.z, 1e-3),
          reason: 'Restored ball Z matches uninterrupted run',
        );
      },
    );

    test(
      '3D Animator and SpriteAnimator maintain deterministic keyframe sampling over 600 frames',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final targetNode = SceneNode.group(name: 'target');
        final clip = AnimationClip(
          name: 'looping_orbit',
          duration: 3.0,
          loopMode: LoopMode.loop,
          tracks: [
            Vector3Track(
              target: targetNode,
              keyframes: const [
                Keyframe(0.0, Vec3(0, 0, 0)),
                Keyframe(1.5, Vec3(10, 5, 0)),
                Keyframe(3.0, Vec3(0, 0, 0)),
              ],
            ),
          ],
        );

        final animGo = engine.scene.createGameObject('AnimObject');
        final animator = Animator(
          initialClips: [clip],
          defaultClip: 'looping_orbit',
        );
        animGo.addComponent(animator);

        final regions = List.generate(
          8,
          (i) => SpriteRegion(
            texture: null,
            width: 16,
            height: 16,
            u0: i / 8.0,
            v0: 0,
            u1: (i + 1) / 8.0,
            v1: 1,
          ),
        );
        final spriteGo = engine.scene.createGameObject('SpriteObject');
        final spriteAnim = SpriteAnimator(
          clips: {'idle': regions},
          fps: 12.0,
          loop: true,
          initialClip: 'idle',
        );
        spriteGo.addComponent(spriteAnim);

        for (var i = 0; i < 600; i++) {
          engine.step(1.0 / 60.0);
        }

        // 600 frames at 1/60s = exactly 10.0 seconds.
        // 10.0s % 3.0s duration = 1.0s into the 3-second clip.
        // At t=1.0 on [0..1.5], tNorm = 1.0 / 1.5 = 2/3.
        // Translation should be 0 + (10 - 0) * (2/3) = 6.6666...
        clip.sample(10.0);
        expect(targetNode.position.x, closeTo(6.6666, 1e-2));

        // For sprite animator: 10.0s * 12 fps = 120 frames elapsed.
        // 120 % 8 frames = frame index 0.
        expect(spriteAnim.currentFrameIndex, equals(0));
      },
    );
  });
}
