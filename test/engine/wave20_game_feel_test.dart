/// Wave 20 game-feel tests: Time hitstop, guarded/timed/triggered StateMachine,
/// AudioMixer snapshots & bus ducking, and rotation/color/sequence tweens (P12-W20-A..D).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

final class _TweenRunnerBehaviour extends Behaviour {}

void main() {
  group('P12-W20-A — Time Hitstop Freeze-Frames', () {
    test(
      'freezes scaled deltaTime for hitstop duration without mutating timeScale',
      () {
        final engine = Engine(HeadlessHost());
        engine.time.timeScale = 1.0;

        engine.step(0.02);
        final timeBefore = engine.time.time;
        expect(timeBefore, closeTo(0.02, 1e-6));

        engine.time.triggerHitstop(0.05);
        expect(engine.time.isInHitstop, isTrue);

        // Two 0.02s frames remain frozen (deltaTime = 0), unscaledTime advances
        engine.step(0.02);
        expect(engine.time.deltaTime, closeTo(0.0, 1e-6));
        expect(engine.time.time, closeTo(timeBefore, 1e-6));

        engine.step(0.02);
        expect(engine.time.deltaTime, closeTo(0.0, 1e-6));

        // Third 0.02s frame finishes hitstop; fourth frame resumes normal timeScale
        engine.step(0.02);
        expect(engine.time.isInHitstop, isFalse);

        engine.step(0.02);
        expect(engine.time.timeScale, closeTo(1.0, 1e-6));
        expect(engine.time.deltaTime, closeTo(0.02, 1e-6));
        expect(engine.time.time, closeTo(0.04, 1e-6));
      },
    );
  });

  group('P12-W20-B — Guarded, Triggered & Timed StateMachine Transitions', () {
    test(
      'evaluates guarded, timed, any-state, trigger, and revertToPreviousState transitions',
      () {
        final engine = Engine(HeadlessHost());
        final go = engine.scene.createGameObject('Agent');
        final fsm = go.addComponent(StateMachine<String>('idle'));

        var enemyVisible = false;
        var health = 100;

        fsm
          ..addTransition(
            'idle',
            'alert',
            when: () => enemyVisible,
            priority: 5,
          )
          ..addTransition('alert', 'patrol', afterSeconds: 0.05)
          ..addAnyTransition('dead', when: () => health <= 0, priority: 100)
          ..addTrigger('stun', null, 'stunned');

        engine.step(0.02);
        expect(fsm.currentState, equals('idle'));

        // Guarded transition fires automatically on update
        enemyVisible = true;
        engine.step(0.02);
        expect(fsm.currentState, equals('alert'));

        // Timed transition fires once stateTime >= 0.05
        for (var i = 0; i < 4; i++) {
          engine.step(0.02);
        }
        expect(fsm.currentState, equals('patrol'));

        // Trigger transition & revert
        expect(fsm.fireTrigger('stun'), isTrue);
        expect(fsm.currentState, equals('stunned'));
        expect(fsm.revertToPreviousState(), isTrue);
        expect(fsm.currentState, equals('patrol'));

        // High-priority any-state transition overrides everything
        health = 0;
        engine.step(0.02);
        expect(fsm.currentState, equals('dead'));
      },
    );
  });

  group('P12-W20-C — AudioMixer Snapshots & Bus Ducking', () {
    test(
      'blends named snapshots smoothly and ducks buses over attack/hold/release',
      () {
        final engine = Engine(HeadlessHost());
        final mixer = engine.scene.audioMixer;

        mixer.captureSnapshot('normal');
        mixer.defineSnapshot(
          AudioMixerSnapshot(
            name: 'paused',
            busVolumes: const {'music': 0.2, 'sfx': 0.0},
          ),
        );

        expect(mixer.applySnapshot('paused', transitionSeconds: 0.1), isTrue);
        expect(mixer.activeSnapshotName, equals('paused'));

        // Halfway through 0.1s blend -> music ~0.6, sfx ~0.5
        engine.step(0.05);
        expect(mixer.effectiveBusGain('music'), closeTo(0.6, 0.05));
        expect(mixer.effectiveBusGain('sfx'), closeTo(0.5, 0.05));

        // Finish blend
        engine.step(0.06);
        expect(mixer.effectiveBusGain('music'), closeTo(0.2, 1e-4));
        expect(mixer.effectiveBusGain('sfx'), closeTo(0.0, 1e-4));

        // Restore normal immediately and test bus ducking
        mixer.applySnapshot('normal');
        expect(mixer.effectiveBusGain('music'), closeTo(1.0, 1e-4));

        mixer.duckBus(
          'music',
          targetGain: 0.25,
          attackSeconds: 0.05,
          holdSeconds: 0.10,
          releaseSeconds: 0.05,
        );
        engine.step(0.06);
        expect(mixer.effectiveBusGain('music'), closeTo(0.25, 0.05));

        // After full envelope completes (0.20s total), music returns to 1.0
        for (var i = 0; i < 10; i++) {
          engine.step(0.02);
        }
        expect(mixer.effectiveBusGain('music'), closeTo(1.0, 1e-4));
      },
    );
  });

  group('P12-W20-D — Rotation, Color & Sequence Tweens', () {
    test('executes tweenRotation, tweenColor, and tweenSequence in order', () {
      final engine = Engine(HeadlessHost());
      final go = engine.scene.createGameObject('AnimatedProp');
      final runner = go.addComponent(_TweenRunnerBehaviour());

      final targetRot = Quat.axisAngle(const Vec3(0, 1, 0), 1.57079632679);
      var lastColor = const LinearColor(0, 0, 0);
      var seqDone = false;
      final milestones = <String>[];

      final seq = runner.tweenSequence([
        () => runner.tweenRotation(
          targetRot,
          duration: 0.05,
          onComplete: () => milestones.add('rot'),
        ),
        () => runner.tweenColor(
          const LinearColor(0, 0, 0),
          const LinearColor(1, 0.5, 0.25),
          duration: 0.05,
          onUpdate: (c) => lastColor = c,
          onComplete: () => milestones.add('color'),
        ),
      ], onComplete: () => seqDone = true);

      for (var i = 0; i < 20; i++) {
        engine.step(0.02);
      }

      expect(seq.isFinished, isTrue);
      expect(seqDone, isTrue);
      expect(milestones, equals(['rot', 'color']));
      expect(go.transform.localRotation.y, closeTo(targetRot.y, 1e-3));
      expect(lastColor.r, closeTo(1.0, 1e-3));
      expect(lastColor.g, closeTo(0.5, 1e-3));
      expect(lastColor.b, closeTo(0.25, 1e-3));
    });
  });
}
