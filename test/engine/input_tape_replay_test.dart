/// Deterministic input recording, JSON serialization, replay verification, and
/// scene state checksum tests (P9-W17-B).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

final class _DelegateInputHost implements EngineHost {
  final HeadlessHost _inner = HeadlessHost();
  @override
  final Input input;

  _DelegateInputHost(this.input);

  @override
  SceneNode get sceneRoot => _inner.sceneRoot;
  @override
  Graphics get graphics => _inner.graphics;
  @override
  AssetLoader get assets => _inner.assets;
  @override
  AudioDevice get audio => _inner.audio;
  @override
  KeyValueStore get storage => _inner.storage;
  @override
  void reportError(Object error, StackTrace stack) =>
      _inner.reportError(error, stack);
}

final class _ReplayPlayerBehaviour extends Behaviour {
  double totalWheelY = 0;
  double totalPointerDeltaX = 0;
  int jumpPresses = 0;
  int pointerClicks = 0;
  int maxTouchCount = 0;
  double lastGamepadAxisX = 0;
  String capturedText = '';

  @override
  void update() {
    final dt = time.deltaTime;
    final rb = gameObject.getComponent<RigidBody>();
    final h = engine.input.getAxis('Horizontal');
    final gpX = engine.input.raw.gamepadAxis(0, 0);
    lastGamepadAxisX = gpX;

    if (rb != null) {
      rb.addForce(Vec3((h + gpX) * 18.0, 0, 0));
      if (engine.input.raw.wasPressed('Space')) {
        jumpPresses++;
        rb.addForce(const Vec3(0, 240.0, 0));
      }
    } else {
      transform.localPosition =
          transform.localPosition + Vec3((h + gpX) * dt, 0, 0);
    }

    if (engine.input.raw.pointerPressed) {
      pointerClicks++;
    }
    totalWheelY += engine.input.raw.wheelDeltaY;
    totalPointerDeltaX += engine.input.raw.pointerDeltaX;
    if (engine.input.raw.touches.length > maxTouchCount) {
      maxTouchCount = engine.input.raw.touches.length;
    }
    if (engine.input.raw.textInputBuffer.isNotEmpty) {
      capturedText += engine.input.raw.textInputBuffer;
    }
  }
}

ComponentRegistry _buildTestRegistry() {
  final reg = ComponentRegistry.defaults();
  reg.register<_ReplayPlayerBehaviour>(
    ComponentSpec<_ReplayPlayerBehaviour>(
      'ReplayPlayerBehaviour',
      _ReplayPlayerBehaviour.new,
      const [],
    ),
  );
  return reg;
}

void main() {
  group('P9-W17-B — InputTape Recorder & Replay Verification', () {
    test(
      'records 60 frames with multi-modal input, round-trips JSON, and replays bit-identically',
      () {
        final liveInput = ScriptedInput();
        final recorder = InputTapeRecorder(liveInput);
        final registry = _buildTestRegistry();
        final recordEngine = Engine(
          _DelegateInputHost(recorder),
          registry: registry,
        );

        final ground = recordEngine.scene.createGameObject(
          'Ground',
          position: const Vec3(0, -1, 0),
        );
        ground.addComponent(BoxCollider(size: const Vec3(50, 2, 50)));

        final player = recordEngine.scene.createGameObject(
          'Player',
          tag: 'Player',
          position: const Vec3(0, 2, 0),
        );
        player.addComponent(RigidBody(mass: 1.0));
        player.addComponent(BoxCollider(size: const Vec3(1, 1, 1)));
        player.addComponent(_ReplayPlayerBehaviour());

        final initialSnapshot = SceneSerializer.toJson(
          recordEngine.scene,
          registry: registry,
        );

        const dt = 0.02;
        for (var f = 0; f < 60; f++) {
          if (f == 5) liveInput.press('KeyD');
          if (f == 25) liveInput.release('KeyD');
          if (f == 10) liveInput.press('Space');
          if (f == 12) liveInput.release('Space');
          if (f == 15) {
            liveInput.pointerDown = true;
            liveInput.pointerPressed = true;
            liveInput.pointerX = 320;
            liveInput.pointerY = 180;
            liveInput.scrollWheel(0, 1.5);
            liveInput.addPointerDelta(12.5, -4.0);
          }
          if (f == 18) {
            liveInput.pointerDown = false;
            liveInput.pointerReleased = true;
          }
          if (f == 20) {
            liveInput.setTouches(const [
              TouchPoint(id: 1, x: 100, y: 200, pressure: 0.8),
              TouchPoint(id: 2, x: 150, y: 240, pressure: 0.6),
            ]);
            liveInput.appendTextInput('hi');
          }
          if (f == 21) {
            liveInput.clearTouches();
          }
          if (f >= 30 && f < 45) {
            liveInput.setGamepadAxis(0, 0, 0.75);
            liveInput.setGamepadButton(0, 0, true);
          } else {
            liveInput.setGamepadAxis(0, 0, 0.0);
            liveInput.setGamepadButton(0, 0, false);
          }

          recordEngine.step(dt);
          final shouldCheckpoint = f == 0 || f == 29 || f == 59;
          recorder.recordFrame(
            dt,
            checkpointScene: shouldCheckpoint ? recordEngine.scene : null,
          );
          liveInput.endFrame();
        }

        final originalHash = SceneStateHasher.computeHash(recordEngine.scene);
        final originalPlayer = recordEngine.scene.find('Player')!;
        final originalBehaviour = originalPlayer
            .getComponent<_ReplayPlayerBehaviour>()!;
        expect(originalBehaviour.jumpPresses, equals(1));
        expect(originalBehaviour.pointerClicks, equals(1));
        expect(originalBehaviour.maxTouchCount, equals(2));
        expect(originalBehaviour.capturedText, equals('hi'));

        // Serialize and deserialize full InputTape via JSON string.
        final tape = recorder.toTape(
          name: 'smoke_60f',
          initialSceneJson: initialSnapshot,
        );
        final roundTrippedTape = InputTape.fromJsonString(tape.toJsonString());
        expect(roundTrippedTape.frames.length, equals(60));
        expect(roundTrippedTape.checkpoints.length, equals(3));

        // Replay in a completely clean Engine instance.
        final driver = ReplayInputDriver();
        final replayEngine = Engine(
          _DelegateInputHost(driver),
          registry: _buildTestRegistry(),
        );
        final result = EngineReplayHarness.run(
          replayEngine,
          roundTrippedTape,
          driver: driver,
        );

        expect(result.passed, isTrue, reason: '${result.mismatches}');
        expect(result.framesExecuted, equals(60));
        expect(result.mismatches, isEmpty);
        expect(result.finalSceneHash, equals(originalHash));

        final replayedPlayer = replayEngine.scene.find('Player')!;
        final replayedBehaviour = replayedPlayer
            .getComponent<_ReplayPlayerBehaviour>()!;
        expect(replayedBehaviour.jumpPresses, equals(1));
        expect(replayedBehaviour.pointerClicks, equals(1));
        expect(
          replayedBehaviour.totalWheelY,
          closeTo(originalBehaviour.totalWheelY, 1e-6),
        );
        expect(
          replayedBehaviour.totalPointerDeltaX,
          closeTo(originalBehaviour.totalPointerDeltaX, 1e-6),
        );
        expect(replayedBehaviour.capturedText, equals('hi'));
        expect(
          replayedPlayer.transform.localPosition.x,
          closeTo(originalPlayer.transform.localPosition.x, 1e-6),
        );
      },
    );

    test(
      'detects divergent replay when a recorded input frame is tampered',
      () {
        final liveInput = ScriptedInput();
        final recorder = InputTapeRecorder(liveInput);
        final registry = _buildTestRegistry();
        final recordEngine = Engine(
          _DelegateInputHost(recorder),
          registry: registry,
        );

        final actor = recordEngine.scene.createGameObject('Actor');
        actor.addComponent(_ReplayPlayerBehaviour());
        final initialSnapshot = SceneSerializer.toJson(
          recordEngine.scene,
          registry: registry,
        );

        const dt = 0.02;
        for (var f = 0; f < 10; f++) {
          if (f == 2) liveInput.press('KeyD');
          if (f == 6) liveInput.release('KeyD');
          recordEngine.step(dt);
          recorder.recordFrame(
            dt,
            checkpointScene: f == 9 ? recordEngine.scene : null,
          );
          liveInput.endFrame();
        }

        final originalTape = recorder.toTape(initialSceneJson: initialSnapshot);
        final mutatedFrames = List<InputFrameSample>.of(originalTape.frames);
        // Flip KeyD -> KeyA on frame 3 so trajectory diverges.
        mutatedFrames[3] = InputFrameSample(
          frameIndex: 3,
          dt: dt,
          keysDown: const ['KeyA'],
        );
        final tamperedTape = InputTape(
          name: originalTape.name,
          initialSceneJson: originalTape.initialSceneJson,
          frames: mutatedFrames,
          checkpoints: originalTape.checkpoints,
        );

        final driver = ReplayInputDriver();
        final replayEngine = Engine(
          _DelegateInputHost(driver),
          registry: _buildTestRegistry(),
        );
        final result = EngineReplayHarness.run(
          replayEngine,
          tamperedTape,
          driver: driver,
        );

        expect(result.passed, isFalse);
        expect(result.mismatches, isNotEmpty);
      },
    );
  });
}
