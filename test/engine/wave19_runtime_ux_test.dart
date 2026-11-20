/// Wave 19 runtime UX tests: rebindable keyboard+gamepad InputActions profiles,
/// prioritized/deferred SceneEvents & composable Coroutines, DebugConsole
/// commands, and scoped Stopwatch FrameProfiler spans (P11-W19-A..D).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

final class _CoroutineHostBehaviour extends Behaviour {}

void main() {
  group('P11-W19-A — InputActions Rebinding, Gamepad & Profile Persistence', () {
    test(
      'supports gamepad buttons/axes with deadzone, runtime rebinding, and store round-trip',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final input = engine.input;

        // Gamepad deadzone filtering on Horizontal axis (default deadzone 0.15)
        host.input.setGamepadAxis(0, 0, 0.10);
        expect(input.getAxis('Horizontal'), closeTo(0.0, 1e-6));

        host.input.setGamepadAxis(0, 0, 0.80);
        expect(input.getAxis('Horizontal'), closeTo(0.80, 1e-6));

        // Gamepad button edge detection (Submit defaults to button 0)
        host.input.setGamepadButton(0, 0, true);
        expect(input.isDown('Submit'), isTrue);
        expect(input.wasPressed('Submit'), isTrue);
        input.syncGamepadState();
        expect(input.wasPressed('Submit'), isFalse);

        host.input.setGamepadButton(0, 0, false);
        expect(input.wasReleased('Submit'), isTrue);
        input.syncGamepadState();

        // Rebind custom action + save/load profile through MemoryStore
        input.rebindButton('Dash', ['ShiftLeft'], gamepadButtons: const [2]);
        input.rebindAxis('Horizontal', deadzone: 0.25);
        input.saveToStore(host.storage, key: 'profile.p1');

        final restoredEngine = Engine(HeadlessHost());
        expect(
          restoredEngine.input.loadFromStore(host.storage, key: 'profile.p1'),
          isTrue,
        );
        expect(restoredEngine.input.hasButton('Dash'), isTrue);

        final restoredHost = restoredEngine.host as HeadlessHost;
        restoredHost.input.setGamepadButton(0, 2, true);
        expect(restoredEngine.input.isDown('Dash'), isTrue);
        restoredHost.input.setGamepadAxis(0, 0, 0.20);
        expect(restoredEngine.input.getAxis('Horizontal'), closeTo(0.0, 1e-6));
        restoredHost.input.setGamepadAxis(0, 0, 0.60);
        expect(restoredEngine.input.getAxis('Horizontal'), closeTo(0.60, 1e-6));
      },
    );
  });

  group(
    'P11-W19-B — Prioritized/Deferred SceneEvents & Composable Coroutines',
    () {
      test(
        'dispatches by priority, fires once() a single time, and flushes deferred events',
        () {
          final engine = Engine(HeadlessHost());
          final events = engine.scene.events;
          final order = <String>[];

          events.on<String>((e) => order.add('low:$e'), priority: -1);
          events.on<String>((e) => order.add('high:$e'), priority: 10);
          events.once<String>((e) => order.add('once:$e'), priority: 5);

          expect(events.listenerCount<String>(), equals(3));

          events.emit<String>('A');
          expect(order, equals(['high:A', 'once:A', 'low:A']));
          expect(events.listenerCount<String>(), equals(2));

          order.clear();
          events.emitDeferred<String>('B');
          events.emitDeferred<String>('C');
          expect(events.pendingDeferredCount, equals(2));
          expect(order, isEmpty);

          events.flushDeferred();
          expect(events.pendingDeferredCount, equals(0));
          expect(order, equals(['high:B', 'low:B', 'high:C', 'low:C']));
        },
      );

      test(
        'supports WaitWhile, WaitForFrames, and WaitForCoroutine nesting',
        () {
          final engine = Engine(HeadlessHost());
          final go = engine.scene.createGameObject('Runner');
          final runner = go.addComponent(_CoroutineHostBehaviour());

          var gateOpen = false;
          final trace = <String>[];

          Iterable<YieldInstruction?> subRoutine() sync* {
            trace.add('sub:start');
            yield const WaitForFrames(2);
            trace.add('sub:end');
          }

          Iterable<YieldInstruction?> mainRoutine() sync* {
            trace.add('main:start');
            yield WaitWhile(() => !gateOpen);
            trace.add('main:after_gate');
            final child = runner.startCoroutine(subRoutine());
            yield WaitForCoroutine(child);
            trace.add('main:done');
          }

          final mainCo = runner.startCoroutine(mainRoutine());
          engine.step(0.016);
          expect(trace, equals(['main:start']));

          engine.step(0.016);
          expect(trace, equals(['main:start']));

          gateOpen = true;
          for (var i = 0; i < 8; i++) {
            engine.step(0.016);
          }

          expect(mainCo.isFinished, isTrue);
          expect(
            trace,
            equals([
              'main:start',
              'main:after_gate',
              'sub:start',
              'sub:end',
              'main:done',
            ]),
          );
        },
      );
    },
  );

  group('P11-W19-C — DebugConsole Command Registry & Built-Ins', () {
    test(
      'executes built-in & custom commands with quoted args, history, and autocomplete',
      () {
        final engine = Engine(HeadlessHost());
        final dbgGo = engine.scene.createGameObject('Debug');
        final dbg = dbgGo.addComponent(DebugController());
        final target = engine.scene.createGameObject(
          'Player One',
          position: Vec3.zero,
        );

        expect(dbg.console.autocomplete('ti'), equals(['timescale']));
        expect(dbg.console.execute('help'), contains('timescale'));
        expect(dbg.console.execute('timescale 0.5'), contains('0.500'));
        expect(engine.time.timeScale, closeTo(0.5, 1e-6));

        expect(dbg.console.execute('pause'), contains('paused'));
        expect(dbg.isPaused, isTrue);
        expect(dbg.console.execute('resume'), contains('resumed'));
        expect(dbg.isPaused, isFalse);

        // Quoted entity name teleport & active toggle
        final tpRes = dbg.console.execute('tp "Player One" 4 5 -2');
        expect(tpRes, contains('Teleported Player One'));
        expect(target.transform.position.x, closeTo(4.0, 1e-4));
        expect(target.transform.position.y, closeTo(5.0, 1e-4));
        expect(target.transform.position.z, closeTo(-2.0, 1e-4));

        dbg.console.execute('active "Player One" false');
        expect(target.activeSelf, isFalse);
        expect(dbg.console.execute('entities player'), contains('[inactive]'));

        // Custom command registration & error isolation
        dbg.console.register(
          'echo',
          (args) => args.join('|'),
          description: 'Echoes args',
        );
        expect(dbg.console.execute('echo "hello world" 42'), 'hello world|42');
        expect(dbg.console.commandHistory.length, greaterThanOrEqualTo(7));
        expect(dbg.console.execute('unknown_cmd'), contains('Unknown command'));
      },
    );
  });

  group('P11-W19-D — FrameProfilerComponent Scoped Spans & Telemetry Export', () {
    test(
      'records real Stopwatch-measured nested spans and exports JSON telemetry',
      () {
        final engine = Engine(HeadlessHost());
        final go = engine.scene.createGameObject('Profiler');
        final profiler = go.addComponent(FrameProfilerComponent());

        final result = profiler.measureSpan('OuterPass', () {
          return profiler.measureSpan('InnerWork', () {
            var sum = 0;
            for (var i = 0; i < 1000; i++) {
              sum += i;
            }
            return sum;
          });
        });
        expect(result, equals(499500));

        engine.step(0.016);

        expect(profiler.lastRecordedSpans.length, equals(2));
        expect(profiler.lastRecordedSpans[0].name, equals('InnerWork'));
        expect(profiler.lastRecordedSpans[0].depth, equals(1));
        expect(profiler.lastRecordedSpans[1].name, equals('OuterPass'));
        expect(profiler.lastRecordedSpans[1].depth, equals(0));

        final json = profiler.exportTelemetryJson();
        expect(json['totalFramesRecorded'], greaterThanOrEqualTo(1));
        expect((json['lastSpans'] as List).length, equals(2));
        expect(json['budgetMs'], closeTo(16.6667, 1e-3));
      },
    );
  });
}
