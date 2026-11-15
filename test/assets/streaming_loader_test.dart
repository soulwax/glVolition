import 'dart:async';
import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/native/native_async_decode.dart';
import 'package:gl_volition/src/web/web_async_decode.dart';
import 'package:test/test.dart';

final class _FakeAssetLoader implements AssetLoader {
  final Map<String, Uint8List> bytesByKey;
  final Map<String, String> textByKey;
  final Future<Uint8List> Function(String path)? onLoadBytes;
  final Future<String> Function(String path)? onLoadText;

  final List<String> byteCalls = [];
  final List<String> textCalls = [];

  _FakeAssetLoader({
    Map<String, Uint8List>? bytesByKey,
    Map<String, String>? textByKey,
    this.onLoadBytes,
    this.onLoadText,
  }) : bytesByKey = bytesByKey ?? {},
       textByKey = textByKey ?? {};

  @override
  Future<Uint8List> loadBytes(String path) async {
    byteCalls.add(path);
    if (onLoadBytes != null) {
      return onLoadBytes!(path);
    }
    final data = bytesByKey[path];
    if (data == null) {
      throw StateError('Missing byte asset: $path');
    }
    return data;
  }

  @override
  Future<String> loadText(String path) async {
    textCalls.add(path);
    if (onLoadText != null) {
      return onLoadText!(path);
    }
    final text = textByKey[path];
    if (text == null) {
      throw StateError('Missing text asset: $path');
    }
    return text;
  }

  @override
  Future<ModelAsset> loadModel(
    String path, {
    MaterialOverride? materialOverride,
  }) {
    throw UnimplementedError();
  }
}

Uint8List _xorTransform(Uint8List bytes) {
  final out = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ 0x5A;
  }
  return out;
}

void main() {
  group('StreamingAssetLoader — frozen symbols & basic loading', () {
    test(
      'preserves frozen public symbol contracts and loads bytes/text',
      () async {
        const standalone = StreamingAssetRequest(
          key: 'standalone.bin',
          priority: AssetStreamPriority.high,
        );
        expect(standalone.key, 'standalone.bin');
        expect(standalone.priority, AssetStreamPriority.high);
        expect(standalone.isPending, isFalse);
        expect(standalone.isCancelled, isFalse);
        expect(standalone.isCompleted, isFalse);

        final source = _FakeAssetLoader(
          bytesByKey: {
            'mesh.bin': Uint8List.fromList([1, 2, 3, 4]),
          },
          textByKey: {'shader.glsl': 'void main() {}'},
        );
        final loader = StreamingAssetLoader(
          source: source,
          frameBudgetMs: 500.0,
        );
        expect(loader.pendingCount, 0);

        final byteFuture = loader.loadBytes('mesh.bin');
        final textFuture = loader.loadText('shader.glsl');
        expect(loader.pendingCount, 2);

        // Preserve 1-arg call signature on processFrameBudget.
        final Future<void> tick = loader.processFrameBudget(
          maxMilliseconds: 500.0,
        );
        await tick;

        expect(loader.pendingCount, 0);
        expect(await byteFuture, Uint8List.fromList([1, 2, 3, 4]));
        expect(await textFuture, 'void main() {}');
      },
    );

    test(
      'propagates source/decoder errors to request future without wedging queue',
      () async {
        final source = _FakeAssetLoader(
          bytesByKey: {
            'ok.bin': Uint8List.fromList([9, 8]),
          },
        );
        final loader = StreamingAssetLoader(
          source: source,
          frameBudgetMs: 500.0,
        );

        final missingReq = loader.enqueueBytes('missing.bin');
        final okReq = loader.enqueueBytes('ok.bin');

        final dispatched = await loader.processFrameBudget(
          maxMilliseconds: 100.0,
        );
        expect(dispatched, 2);
        expect(loader.pendingCount, 0);
        expect(loader.isProcessing, isFalse);

        await expectLater(missingReq.future, throwsStateError);
        expect(await okReq.future, Uint8List.fromList([9, 8]));
      },
    );
  });

  group('StreamingAssetLoader — priority preemption & promotion', () {
    test(
      'preempts background/normal with high/critical and preserves FIFO per priority',
      () async {
        final completionOrder = <String>[];
        final source = _FakeAssetLoader(
          onLoadBytes: (path) async {
            completionOrder.add(path);
            return Uint8List.fromList([path.codeUnitAt(0)]);
          },
        );
        final loader = StreamingAssetLoader(
          source: source,
          frameBudgetMs: 500.0,
        );

        final bg1 = loader.enqueueBytes(
          'bg_1',
          priority: AssetStreamPriority.background,
        );
        final norm1 = loader.enqueueBytes(
          'norm_1',
          priority: AssetStreamPriority.normal,
        );
        final bg2 = loader.enqueueBytes(
          'bg_2',
          priority: AssetStreamPriority.background,
        );
        final high1 = loader.enqueueBytes(
          'high_1',
          priority: AssetStreamPriority.high,
        );
        final crit1 = loader.enqueueBytes(
          'crit_1',
          priority: AssetStreamPriority.critical,
        );
        final high2 = loader.enqueueBytes(
          'high_2',
          priority: AssetStreamPriority.high,
        );
        final crit2 = loader.enqueueBytes(
          'crit_2',
          priority: AssetStreamPriority.critical,
        );
        final norm2 = loader.enqueueBytes(
          'norm_2',
          priority: AssetStreamPriority.normal,
        );

        expect(loader.pendingCount, 8);

        // Process one by one to verify exact dequeue order across ticks.
        for (var i = 0; i < 8; i++) {
          final count = await loader.processFrameBudget(maxItems: 1);
          expect(count, 1);
        }

        expect(completionOrder, [
          'crit_1',
          'crit_2',
          'high_1',
          'high_2',
          'norm_1',
          'norm_2',
          'bg_1',
          'bg_2',
        ]);

        await Future.wait([
          bg1.future,
          norm1.future,
          bg2.future,
          high1.future,
          crit1.future,
          high2.future,
          crit2.future,
          norm2.future,
        ]);
        expect(loader.pendingCount, 0);
      },
    );

    test(
      're-enqueuing an already-queued key promotes priority without duplicating work',
      () async {
        final source = _FakeAssetLoader(
          bytesByKey: {
            'bg.bin': Uint8List.fromList([1]),
            'normal.bin': Uint8List.fromList([2]),
            'promoted.bin': Uint8List.fromList([3]),
          },
        );
        final loader = StreamingAssetLoader(
          source: source,
          frameBudgetMs: 500.0,
        );

        final rBg = loader.enqueueBytes(
          'bg.bin',
          priority: AssetStreamPriority.background,
        );
        final rNorm = loader.enqueueBytes(
          'normal.bin',
          priority: AssetStreamPriority.normal,
        );
        final rPromoted1 = loader.enqueueBytes(
          'promoted.bin',
          priority: AssetStreamPriority.background,
        );

        expect(loader.pendingCount, 3);
        expect(rPromoted1.priority, AssetStreamPriority.background);

        // Promote promoted.bin to critical; lower re-request afterward must NOT demote it.
        final rPromoted2 = loader.enqueueBytes(
          'promoted.bin',
          priority: AssetStreamPriority.critical,
        );
        final rPromoted3 = loader.enqueueBytes(
          'promoted.bin',
          priority: AssetStreamPriority.normal,
        );

        expect(identical(rPromoted1, rPromoted2), isTrue);
        expect(identical(rPromoted2, rPromoted3), isTrue);
        expect(rPromoted1.priority, AssetStreamPriority.critical);
        expect(loader.pendingCount, 3);

        // First tick with maxItems=1 should run promoted.bin ahead of normal.bin and bg.bin.
        await loader.processFrameBudget(maxItems: 1);
        expect(source.byteCalls, ['promoted.bin']);
        expect(await rPromoted1.future, Uint8List.fromList([3]));
        expect(rNorm.isCompleted, isFalse);
        expect(rBg.isCompleted, isFalse);

        // Drain the remaining items.
        await loader.processFrameBudget();
        expect(source.byteCalls, ['promoted.bin', 'normal.bin', 'bg.bin']);
        expect(await rNorm.future, Uint8List.fromList([2]));
        expect(await rBg.future, Uint8List.fromList([1]));
      },
    );

    test(
      'newly enqueued critical item preempts mid-drain between ticks',
      () async {
        final source = _FakeAssetLoader(
          bytesByKey: {
            'bg_a': Uint8List.fromList([1]),
            'bg_b': Uint8List.fromList([2]),
            'urgent': Uint8List.fromList([99]),
          },
        );
        final loader = StreamingAssetLoader(
          source: source,
          frameBudgetMs: 500.0,
        );

        loader.enqueueBytes('bg_a', priority: AssetStreamPriority.background);
        loader.enqueueBytes('bg_b', priority: AssetStreamPriority.background);

        await loader.processFrameBudget(maxItems: 1);
        expect(source.byteCalls, ['bg_a']);

        // Urgent arrives after tick 1; must run before bg_b on tick 2.
        final urgentReq = loader.enqueueBytes(
          'urgent',
          priority: AssetStreamPriority.critical,
        );
        await loader.processFrameBudget(maxItems: 1);
        expect(source.byteCalls, ['bg_a', 'urgent']);
        expect(await urgentReq.future, Uint8List.fromList([99]));

        await loader.processFrameBudget();
        expect(source.byteCalls, ['bg_a', 'urgent', 'bg_b']);
      },
    );
  });

  group('StreamingAssetLoader — cancellation', () {
    test(
      'cancelling queued requests skips source/decode and fails with cancellation error',
      () async {
        var decoderCalls = 0;
        final source = _FakeAssetLoader(
          bytesByKey: {
            'skip_a': Uint8List.fromList([1]),
            'keep': Uint8List.fromList([2]),
          },
          textByKey: {'skip_txt': 'unused'},
        );
        final loader = StreamingAssetLoader(
          source: source,
          decoder: (raw) async {
            decoderCalls++;
            return raw;
          },
        );

        final reqA = loader.enqueueBytes('skip_a');
        final reqTxt = loader.enqueueText('skip_txt');
        final reqKeep = loader.enqueueBytes('keep');
        expect(loader.pendingCount, 3);

        reqA.cancel();
        expect(reqA.isCancelled, isTrue);
        expect(reqA.isPending, isFalse);
        expect(loader.cancel('skip_txt'), isTrue);
        expect(loader.cancel('non_existent'), isFalse);
        expect(reqTxt.isCancelled, isTrue);
        expect(loader.pendingCount, 1);

        await loader.processFrameBudget();

        expect(source.byteCalls, ['keep']);
        expect(source.textCalls, isEmpty);
        expect(decoderCalls, 1);
        expect(await reqKeep.future, Uint8List.fromList([2]));
        await expectLater(
          reqA.future,
          throwsA(
            allOf(isA<AssetStreamCancelledException>(), isA<StateError>()),
          ),
        );
        await expectLater(
          reqTxt.future,
          throwsA(isA<AssetStreamCancelledException>()),
        );
      },
    );

    test(
      'cancelling an in-flight request skips decode and ignores stale completion',
      () async {
        final sourceLoadStarted = Completer<void>();
        final sourceLoadGate = Completer<Uint8List>();
        var decoderCalls = 0;

        final source = _FakeAssetLoader(
          onLoadBytes: (path) async {
            if (path == 'slow.bin') {
              sourceLoadStarted.complete();
              return sourceLoadGate.future;
            }
            return Uint8List.fromList([42]);
          },
        );

        final loader = StreamingAssetLoader(
          source: source,
          decoder: (raw) async {
            decoderCalls++;
            return raw;
          },
        );

        final slowReq = loader.enqueueBytes('slow.bin');
        final tickFuture = loader.processFrameBudget();

        await sourceLoadStarted.future;
        expect(slowReq.isInFlight, isTrue);
        expect(loader.inFlightCount, 1);

        // Cancel while source.loadBytes is still awaiting.
        expect(loader.cancel('slow.bin'), isTrue);
        expect(slowReq.isCancelled, isTrue);
        expect(loader.pendingCount, 0);

        await expectLater(
          slowReq.future,
          throwsA(isA<AssetStreamCancelledException>()),
        );

        // Now let the stale source load resolve; decoder must NOT be called.
        sourceLoadGate.complete(Uint8List.fromList([7, 7, 7]));
        await tickFuture;

        expect(decoderCalls, 0);
        expect(loader.pendingCount, 0);
        expect(loader.isProcessing, isFalse);
      },
    );

    test(
      'cancelling during async decode discards decoded result and allows fresh re-enqueue',
      () async {
        final decodeStarted = Completer<void>();
        final decodeGate = Completer<Uint8List>();
        var loadCount = 0;

        final source = _FakeAssetLoader(
          onLoadBytes: (path) async {
            loadCount++;
            return Uint8List.fromList([loadCount]);
          },
        );

        final loader = StreamingAssetLoader(
          source: source,
          decoder: (raw) async {
            if (raw[0] == 1) {
              decodeStarted.complete();
              return decodeGate.future;
            }
            return Uint8List.fromList([raw[0] + 100]);
          },
        );

        final firstReq = loader.enqueueBytes('reloaded.bin');
        final firstTick = loader.processFrameBudget(maxItems: 1);

        await decodeStarted.future;
        firstReq.cancel();
        await expectLater(
          firstReq.future,
          throwsA(isA<AssetStreamCancelledException>()),
        );

        // Re-enqueue same key while first decode is still running!
        final secondReq = loader.enqueueBytes('reloaded.bin');
        expect(identical(firstReq, secondReq), isFalse);
        expect(loader.pendingCount, 1);

        // Stale decode finishes; must NOT touch secondReq or remove it from _activeRequests.
        decodeGate.complete(Uint8List.fromList([999 & 0xFF]));
        await firstTick;

        expect(secondReq.isPending, isTrue);
        expect(loader.pendingCount, 1);

        await loader.processFrameBudget();
        expect(await secondReq.future, Uint8List.fromList([102]));
        expect(loader.pendingCount, 0);
      },
    );

    test(
      'cancelAll cancels every queued and in-flight request cleanly',
      () async {
        final loader = StreamingAssetLoader(
          source: _FakeAssetLoader(
            bytesByKey: {
              'a': Uint8List.fromList([1]),
              'b': Uint8List.fromList([2]),
            },
            textByKey: {'c': 'hi'},
          ),
        );

        final r1 = loader.enqueueBytes('a');
        final r2 = loader.enqueueBytes('b');
        final r3 = loader.enqueueText('c');
        expect(loader.pendingCount, 3);

        loader.cancelAll();
        expect(loader.pendingCount, 0);
        expect(loader.queuedCount, 0);

        for (final req in [r1, r2, r3]) {
          expect(req.isCancelled, isTrue);
          await expectLater(
            req.future,
            throwsA(isA<AssetStreamCancelledException>()),
          );
        }
      },
    );

    test(
      'in-flight text cancellation ignores stale text and keeps key kinds isolated',
      () async {
        final textStarted = Completer<void>();
        final textGate = Completer<String>();
        final source = _FakeAssetLoader(
          bytesByKey: {
            'shared.json': Uint8List.fromList([123, 125]),
          },
          onLoadText: (path) async {
            textStarted.complete();
            return textGate.future;
          },
        );
        final loader = StreamingAssetLoader(
          source: source,
          frameBudgetMs: 500.0,
        );

        final textReq = loader.enqueueText(
          'shared.json',
          priority: AssetStreamPriority.high,
        );
        final bytesReq = loader.enqueueBytes(
          'shared.json',
          priority: AssetStreamPriority.normal,
        );
        expect(loader.pendingCount, 2);

        final tick = loader.processFrameBudget(maxItems: 1);
        await textStarted.future;
        textReq.cancel();
        expect(textReq.isCancelled, isTrue);
        expect(bytesReq.isPending, isTrue);

        textGate.complete('stale text');
        await tick;

        await expectLater(
          textReq.future,
          throwsA(isA<AssetStreamCancelledException>()),
        );
        await loader.processFrameBudget();
        expect(await bytesReq.future, Uint8List.fromList([123, 125]));
      },
    );
  });

  group('StreamingAssetLoader — bounded per-tick frame budget', () {
    test(
      'respects maxItems cap across heavy queues in priority + FIFO order',
      () async {
        final decodedOrder = <String>[];
        final source = _FakeAssetLoader(
          onLoadBytes: (path) async => Uint8List.fromList(path.codeUnits),
        );
        final loader = StreamingAssetLoader(
          source: source,
          frameBudgetMs: 100.0,
          decoder: (raw) async {
            decodedOrder.add(String.fromCharCodes(raw));
            return raw;
          },
        );

        for (var i = 0; i < 12; i++) {
          loader.enqueueBytes(
            'bg_$i',
            priority: AssetStreamPriority.background,
          );
        }
        for (var i = 0; i < 5; i++) {
          loader.enqueueBytes('high_$i', priority: AssetStreamPriority.high);
        }
        expect(loader.pendingCount, 17);

        final tick1 = await loader.processFrameBudget(maxItems: 4);
        expect(tick1, 4);
        expect(loader.pendingCount, 13);
        expect(decodedOrder, ['high_0', 'high_1', 'high_2', 'high_3']);

        final tick2 = await loader.processFrameBudget(maxItems: 4);
        expect(tick2, 4);
        expect(loader.pendingCount, 9);
        expect(decodedOrder, [
          'high_0',
          'high_1',
          'high_2',
          'high_3',
          'high_4',
          'bg_0',
          'bg_1',
          'bg_2',
        ]);

        final tick3 = await loader.processFrameBudget();
        expect(tick3, 9);
        expect(loader.pendingCount, 0);
        expect(decodedOrder.length, 17);
      },
    );

    test(
      'stops cleanly once maxMilliseconds time budget expires and drains over subsequent ticks',
      () async {
        final completed = <String>[];
        final source = _FakeAssetLoader(
          onLoadBytes: (path) async {
            await Future<void>.delayed(const Duration(milliseconds: 6));
            return Uint8List.fromList([1]);
          },
        );
        final loader = StreamingAssetLoader(
          source: source,
          frameBudgetMs: 4.0,
          decoder: (raw) async => raw,
        );

        final requests = <StreamingAssetRequest<Uint8List>>[];
        for (var i = 0; i < 5; i++) {
          final key = 'item_$i';
          final req = loader.enqueueBytes(key);
          requests.add(req);
          req.future.then((_) => completed.add(key));
        }

        // Tick 1: first item takes >= 6ms which exceeds 4ms budget, so tick stops after 1 item.
        final processedTick1 = await loader.processFrameBudget();
        expect(processedTick1, 1);
        expect(loader.pendingCount, 4);

        var ticks = 1;
        while (loader.pendingCount > 0 && ticks < 10) {
          final n = await loader.processFrameBudget(maxMilliseconds: 4.0);
          expect(n, 1);
          ticks++;
        }

        await Future.wait(requests.map((r) => r.future));
        expect(ticks, 5);
        expect(loader.pendingCount, 0);
        expect(completed, ['item_0', 'item_1', 'item_2', 'item_3', 'item_4']);
      },
    );

    test(
      'handles zero/negative budget and re-entrant processFrameBudget safely',
      () async {
        final gate = Completer<Uint8List>();
        final source = _FakeAssetLoader(
          onLoadBytes: (path) =>
              path == 'first' ? gate.future : Future.value(Uint8List(1)),
        );
        final loader = StreamingAssetLoader(
          source: source,
          frameBudgetMs: 500.0,
        );
        final first = loader.enqueueBytes('first');
        final second = loader.enqueueBytes('second');

        expect(await loader.processFrameBudget(maxMilliseconds: 0), 0);
        expect(await loader.processFrameBudget(maxItems: 0), 0);
        expect(loader.pendingCount, 2);

        final activeTick = loader.processFrameBudget();
        // Re-entrant tick while already processing returns 0 immediately.
        expect(await loader.processFrameBudget(), 0);

        gate.complete(Uint8List.fromList([5]));
        final count = await activeTick;
        expect(count, 2);
        expect(await first.future, Uint8List.fromList([5]));
        expect(await second.future, Uint8List.fromList([0]));
      },
    );
  });

  group('Platform async decoders (Native & Web)', () {
    test(
      'decodeBytesInIsolate round-trips buffers, subviews, empty bytes, and transforms',
      () async {
        final empty = await decodeBytesInIsolate(Uint8List(0));
        expect(empty, isEmpty);

        final backing = Uint8List.fromList(
          List<int>.generate(128 * 1024, (i) => i & 0xFF),
        );
        final slice = Uint8List.sublistView(backing, 17, 65536 + 17);
        final expectedCopy = Uint8List.fromList(slice);

        final decoded = await decodeBytesInIsolate(slice);
        expect(decoded, expectedCopy);

        // Mutating original slice after calling must not corrupt detached isolate copy.
        backing.fillRange(0, backing.length, 0);
        expect(decoded, expectedCopy);

        final transformed = await decodeBytesInIsolate(
          Uint8List.fromList([0x00, 0xFF, 0x5A, 0x12]),
          transform: _xorTransform,
        );
        expect(transformed, Uint8List.fromList([0x5A, 0xA5, 0x00, 0x48]));

        // Works directly as StreamingAssetLoader.decoder.
        final loader = StreamingAssetLoader(
          source: _FakeAssetLoader(
            bytesByKey: {
              'tex.raw': Uint8List.fromList([10, 20, 30, 40]),
            },
          ),
          decoder: decodeBytesInIsolate,
        );
        final loaded = loader.loadBytes('tex.raw');
        await loader.processFrameBudget();
        expect(await loaded, Uint8List.fromList([10, 20, 30, 40]));
      },
    );

    test(
      'decodeBytesCooperatively round-trips and yields across event-loop turns between chunks',
      () async {
        expect(
          () => decodeBytesCooperatively(Uint8List(8), chunkSize: 0),
          throwsRangeError,
        );

        // Compatible with 1-positional-arg AsyncAssetDecoder signature.
        const AsyncAssetDecoder asDecoder = decodeBytesCooperatively;
        final small = await asDecoder(Uint8List.fromList([1, 2, 3]));
        expect(small, Uint8List.fromList([1, 2, 3]));

        final empty = await decodeBytesCooperatively(Uint8List(0));
        expect(empty, isEmpty);

        final payload = Uint8List.fromList(
          List<int>.generate(10000, (i) => (i * 31) & 0xFF),
        );
        final progressUpdates = <(int, int)>[];
        var chunkCount = 0;
        var interleavedTurns = 0;
        var decodingDone = false;

        // Pump event-loop turns concurrently while decoding 10,000 bytes in 1,024-byte chunks.
        Future<void> pumpInterleaved() async {
          while (!decodingDone) {
            interleavedTurns++;
            await Future<void>.delayed(Duration.zero);
          }
        }

        final pumpFuture = pumpInterleaved();
        final decoded = await decodeBytesCooperatively(
          payload,
          chunkSize: 1024,
          onChunk: (_) => chunkCount++,
          onProgress: (done, total) => progressUpdates.add((done, total)),
        );
        decodingDone = true;
        await pumpFuture;

        expect(decoded, payload);
        expect(chunkCount, 10); // ceil(10000 / 1024) == 10 chunks
        expect(progressUpdates.last, (10000, 10000));
        expect(interleavedTurns, greaterThanOrEqualTo(5));

        // Works directly as StreamingAssetLoader.decoder.
        final loader = StreamingAssetLoader(
          source: _FakeAssetLoader(bytesByKey: {'atlas.raw': payload}),
          decoder: decodeBytesCooperatively,
        );
        final loaded = loader.loadBytes('atlas.raw');
        await loader.processFrameBudget();
        expect(await loaded, payload);
      },
    );
  });
}
