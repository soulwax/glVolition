/// Wave 22 tests: Skeletal animation event markers, LodGroup hysteresis/bias/
/// forced override, and timed ParticleBurst schedules (P14-W22-A..C).
library;

import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P14-W22-A — Skeletal Animation Event Markers', () {
    test(
      'fires AnimationEventMarker callbacks accurately across normal and looped playback',
      () {
        final engine = Engine(HeadlessHost());
        final go = engine.scene.createGameObject('Knight');

        final skin = SkinData(
          name: 'KnightRig',
          joints: const [SkinJointNode(nodeIndex: 0, name: 'Root')],
          inverseBindMatrices: Float32List.fromList(const [
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
        );
        final clip = SkeletalClip(
          name: 'Swing',
          duration: 0.10,
          loopMode: LoopMode.loop,
          events: const [
            AnimationEventMarker(time: 0.03, name: 'whoosh', payload: 1),
            AnimationEventMarker(time: 0.08, name: 'impact', payload: 2),
          ],
        );

        final animator = go.addComponent(
          Animator(skin: skin, initialSkeletalClips: [clip]),
        );
        animator.addClipEvent(
          'Swing',
          const AnimationEventMarker(time: 0.05, name: 'mid'),
        );

        final fired = <String>[];
        animator.onEvent((clipName, ev) => fired.add('$clipName:${ev.name}'));

        animator.play('Swing');
        expect(animator.activeSkeletalClipName, equals('Swing'));

        // Advance 0.16s (one full 0.10s loop + 0.06s into second loop)
        for (var i = 0; i < 8; i++) {
          engine.step(0.02);
        }

        expect(
          fired,
          equals([
            'Swing:whoosh',
            'Swing:mid',
            'Swing:impact',
            'Swing:whoosh',
            'Swing:mid',
          ]),
        );
      },
    );
  });

  group('P14-W22-B — LodGroup Hysteresis, Quality Bias & Forced Override', () {
    test(
      'prevents LOD popping with hysteresis and respects lodBias and forcedLevelIndex',
      () {
        final engine = Engine(HeadlessHost());
        final camGo = engine.scene.createGameObject(
          'Cam',
          position: const Vec3(0, 0, 0),
        );
        camGo.addComponent(Camera());

        final root = engine.scene.createGameObject(
          'Tree',
          position: const Vec3(0, 0, -5),
        );
        final lod0 = engine.scene.createGameObject('LOD0', parent: root);
        final lod1 = engine.scene.createGameObject('LOD1', parent: root);

        final lodGroup = root.addComponent(
          LodGroup(
            levels: [
              LodLevel(maxDistance: 10.0, target: lod0),
              LodLevel(maxDistance: 30.0, target: lod1),
            ],
            cullDistance: 50.0,
            hysteresis: 2.0,
          ),
        );

        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, equals(0));
        expect(lod0.activeSelf, isTrue);

        // Move slightly past 10.0 (to 11.0) -> within hysteresis (10 + 2 = 12), stays at LOD0!
        root.transform.position = const Vec3(0, 0, -11.0);
        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, equals(0));

        // Move past 12.0 (to 13.0) -> switches to LOD1
        root.transform.position = const Vec3(0, 0, -13.0);
        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, equals(1));

        // Move back slightly under 10.0 (to 9.0) -> within hysteresis (10 - 2 = 8), stays at LOD1!
        root.transform.position = const Vec3(0, 0, -9.0);
        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, equals(1));

        // Increase lodBias to 2.0 -> effective distance = 9 / 2 = 4.5 <= 8 -> switches back to LOD0
        lodGroup.lodBias = 2.0;
        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, equals(0));

        // forcedLevelIndex overrides distance calculation
        lodGroup.forcedLevelIndex = 1;
        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, equals(1));
        lodGroup.forcedLevelIndex = -1;
        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, equals(-1));
      },
    );
  });

  group(
    'P14-W22-C — Timed ParticleBurstSchedule Schedules & Playback Controls',
    () {
      test(
        'triggers multi-cycle scheduled bursts and respects pause/stop/reset',
        () {
          final engine = Engine(HeadlessHost());
          final emitter = ParticleEmitter(
            mesh: const MeshHandle(1, 0, 'quad'),
            material: const MaterialHandle(1, 0, 'mat'),
            rate: 0.0,
            maxParticles: 200,
          );
          final go = engine.scene.createGameObject('Sparks');
          final ps = go.addComponent(
            ParticleSystem(
              emitter,
              bursts: const [
                ParticleBurstSchedule(
                  time: 0.04,
                  count: 10,
                  cycles: 3,
                  interval: 0.04,
                ),
              ],
            ),
          );

          // Advance 0.02s -> before first burst (0.04s)
          engine.step(0.02);
          expect(ps.totalBurstParticlesEmitted, equals(0));

          // Advance 0.02s -> hits t=0.04s -> cycle 1 fires (10 particles)
          engine.step(0.02);
          expect(ps.totalBurstParticlesEmitted, equals(10));

          // Pause prevents cycle 2 from firing
          ps.pause();
          engine.step(0.06);
          expect(ps.totalBurstParticlesEmitted, equals(10));

          // Resume and advance through remaining 2 cycles
          ps.play();
          engine.step(0.04);
          engine.step(0.04);
          expect(ps.totalBurstParticlesEmitted, equals(30));

          // Stop & reset clears playback time and allows re-triggering
          ps.stop(clearParticles: true);
          expect(ps.playbackTime, closeTo(0.0, 1e-6));
          expect(ps.isPlaying, isFalse);
        },
      );
    },
  );
}
