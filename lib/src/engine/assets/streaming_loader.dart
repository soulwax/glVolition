part of '../../engine.dart';

/// Priority levels ordering background decode/upload tasks in
/// [StreamingAssetLoader].
enum AssetStreamPriority { critical, high, normal, background }

/// Host-pluggable asynchronous decode transform (e.g. isolate worker on Native,
/// cooperative async chunked decode on Web/Headless).
typedef AsyncAssetDecoder = Future<Uint8List> Function(Uint8List rawBytes);

/// Thrown when a queued or in-flight [StreamingAssetRequest] is cancelled
/// before completion.
final class AssetStreamCancelledException extends StateError
    implements Exception {
  final String key;

  AssetStreamCancelledException(this.key)
    : super('Streaming asset request cancelled: "$key"');

  @override
  String toString() => 'AssetStreamCancelledException: $message';
}

/// Handle and descriptor for a queued or in-flight streaming asset request.
final class StreamingAssetRequest<T> {
  final String key;
  final AssetStreamPriority _standalonePriority;
  final _QueuedEntry? _entry;
  final Future<T>? _future;

  /// Creates a standalone immutable request descriptor.
  const StreamingAssetRequest({
    required this.key,
    AssetStreamPriority priority = AssetStreamPriority.normal,
  }) : _standalonePriority = priority,
       _entry = null,
       _future = null;

  StreamingAssetRequest._attached(
    this.key,
    _QueuedEntry this._entry,
    Future<T> this._future,
  ) : _standalonePriority = _entry._priority;

  /// Current effective scheduling priority (updates if promoted while queued).
  AssetStreamPriority get priority => _entry?._priority ?? _standalonePriority;

  /// Resolves with the loaded/decoded asset or fails on load/decode/cancellation.
  Future<T> get future =>
      _future ??
      (Future<T>.error(
        StateError('StreamingAssetRequest("$key") is not queued in a loader.'),
      )..ignore());

  /// Whether this request was cancelled before completing.
  bool get isCancelled => _entry?._cancelled ?? false;

  /// Whether this request has settled with a value or non-cancellation error.
  bool get isCompleted => _entry?._completed ?? false;

  /// Whether this request is currently queued or in-flight.
  bool get isPending => _entry?.isPending ?? false;

  /// Whether this request is currently executing inside [StreamingAssetLoader].
  bool get isInFlight => _entry?._inFlight ?? false;

  /// Cancels this request if still queued or in-flight.
  void cancel() => _entry?.cancel();
}

/// Pure-Dart priority-queued streaming loader with priority promotion,
/// cancellation, optional async decode, and bounded per-tick frame budgets.
final class StreamingAssetLoader {
  final AssetLoader source;
  final double frameBudgetMs;
  final AsyncAssetDecoder? decoder;

  final List<_PriorityBucket> _buckets = List<_PriorityBucket>.generate(
    AssetStreamPriority.values.length,
    (_) => _PriorityBucket(),
    growable: false,
  );
  final Map<({String key, bool isText}), _QueuedEntry> _activeRequests = {};
  bool _processing = false;

  StreamingAssetLoader({
    required this.source,
    this.frameBudgetMs = 2.0,
    this.decoder,
  });

  /// Total active requests (queued + currently in-flight).
  int get pendingCount => _activeRequests.length;

  /// Number of requests waiting in priority queues (not yet started).
  int get queuedCount =>
      _buckets[0].length +
      _buckets[1].length +
      _buckets[2].length +
      _buckets[3].length;

  /// Number of requests currently executing asynchronously.
  int get inFlightCount => pendingCount - queuedCount;

  /// Whether [processFrameBudget] is currently active.
  bool get isProcessing => _processing;

  /// Returns whether any queued or in-flight request exists for [key].
  bool hasPending(String key) =>
      _activeRequests.containsKey((key: key, isText: false)) ||
      _activeRequests.containsKey((key: key, isText: true));

  /// Enqueues [key] for streamed binary loading at [priority].
  ///
  /// Re-enqueuing an active binary [key] returns the existing request and
  /// promotes its priority if [priority] is higher than currently scheduled.
  StreamingAssetRequest<Uint8List> enqueueBytes(
    String key, {
    AssetStreamPriority priority = AssetStreamPriority.normal,
    AsyncAssetDecoder? decoder,
  }) => _enqueue<Uint8List>(
    key: key,
    isText: false,
    priority: priority,
    byteDecoder: decoder,
    runner: (entry) async {
      final raw = await source.loadBytes(entry.key);
      if (entry._cancelled) {
        throw AssetStreamCancelledException(entry.key);
      }
      final activeDecoder = entry.byteDecoder ?? this.decoder;
      if (activeDecoder != null) {
        return activeDecoder(raw);
      }
      return raw;
    },
  );

  /// Enqueues [key] for streamed text loading at [priority].
  ///
  /// Re-enqueuing an active text [key] returns the existing request and
  /// promotes its priority if [priority] is higher than currently scheduled.
  StreamingAssetRequest<String> enqueueText(
    String key, {
    AssetStreamPriority priority = AssetStreamPriority.normal,
  }) => _enqueue<String>(
    key: key,
    isText: true,
    priority: priority,
    runner: (entry) => source.loadText(entry.key),
  );

  /// Convenience wrapper around [enqueueBytes] returning its completion future.
  Future<Uint8List> loadBytes(
    String key, {
    AssetStreamPriority priority = AssetStreamPriority.normal,
    AsyncAssetDecoder? decoder,
  }) => enqueueBytes(key, priority: priority, decoder: decoder).future;

  /// Convenience wrapper around [enqueueText] returning its completion future.
  Future<String> loadText(
    String key, {
    AssetStreamPriority priority = AssetStreamPriority.normal,
  }) => enqueueText(key, priority: priority).future;

  /// Cancels any active (queued or in-flight) requests for [key].
  ///
  /// Returns `true` if at least one request was cancelled.
  bool cancel(String key) {
    var cancelledAny = false;
    for (final isText in const [false, true]) {
      final entry = _activeRequests[(key: key, isText: isText)];
      if (entry != null) {
        entry.cancel();
        cancelledAny = true;
      }
    }
    return cancelledAny;
  }

  /// Cancels all currently queued and in-flight requests.
  void cancelAll() {
    final snapshot = _activeRequests.values.toList(growable: false);
    for (final entry in snapshot) {
      entry.cancel();
    }
  }

  /// Processes queued requests in strict priority + FIFO order until the time
  /// budget (`maxMilliseconds ?? frameBudgetMs`) or [maxItems] cap is reached.
  ///
  /// Returns the number of requests dispatched during this tick.
  Future<int> processFrameBudget({
    double? maxMilliseconds,
    int? maxItems,
  }) async {
    if (_processing) return 0;
    final budgetMs = maxMilliseconds ?? frameBudgetMs;
    if (budgetMs <= 0 || (maxItems != null && maxItems <= 0)) {
      return 0;
    }
    if (queuedCount == 0) return 0;

    _processing = true;
    final stopwatch = Stopwatch()..start();
    var processed = 0;

    try {
      while (queuedCount > 0) {
        if (maxItems != null && processed >= maxItems) {
          break;
        }
        if (processed > 0 &&
            stopwatch.elapsedMicroseconds / 1000.0 >= budgetMs) {
          break;
        }

        final entry = _dequeueNext();
        if (entry == null) break;
        if (entry._cancelled) continue;

        processed++;
        await entry.execute();
      }
    } finally {
      stopwatch.stop();
      _processing = false;
    }

    return processed;
  }

  StreamingAssetRequest<T> _enqueue<T>({
    required String key,
    required bool isText,
    required AssetStreamPriority priority,
    required Future<T> Function(_TypedStreamEntry<T> entry) runner,
    AsyncAssetDecoder? byteDecoder,
  }) {
    final mapKey = (key: key, isText: isText);
    final existing = _activeRequests[mapKey];
    if (existing is _TypedStreamEntry<T>) {
      _promotePriority(existing, priority);
      if (byteDecoder != null && existing.byteDecoder == null) {
        existing.byteDecoder = byteDecoder;
      }
      return existing.request;
    }

    final entry = _TypedStreamEntry<T>(
      key,
      this,
      priority,
      runner,
      isText: isText,
      byteDecoder: byteDecoder,
    );
    _activeRequests[mapKey] = entry;
    _buckets[priority.index].addLast(entry);
    return entry.request;
  }

  void _promotePriority(_QueuedEntry entry, AssetStreamPriority newPriority) {
    if (newPriority.index >= entry._priority.index) return;
    final currentBucket = entry._bucket;
    if (currentBucket != null) {
      currentBucket.remove(entry);
      entry._priority = newPriority;
      _buckets[newPriority.index].addLast(entry);
    } else {
      entry._priority = newPriority;
    }
  }

  _QueuedEntry? _dequeueNext() {
    for (final bucket in _buckets) {
      final next = bucket.removeFirst();
      if (next != null) return next;
    }
    return null;
  }

  void _removeEntry(_QueuedEntry entry) {
    entry._bucket?.remove(entry);
    final mapKey = (key: entry.key, isText: entry.isText);
    if (identical(_activeRequests[mapKey], entry)) {
      _activeRequests.remove(mapKey);
    }
  }
}

final class _PriorityBucket {
  _QueuedEntry? _head;
  _QueuedEntry? _tail;
  int _length = 0;

  int get length => _length;

  void addLast(_QueuedEntry entry) {
    assert(entry._bucket == null);
    entry._bucket = this;
    entry._prev = _tail;
    entry._next = null;
    final tail = _tail;
    if (tail == null) {
      _head = entry;
    } else {
      tail._next = entry;
    }
    _tail = entry;
    _length++;
  }

  _QueuedEntry? removeFirst() {
    final head = _head;
    if (head == null) return null;
    remove(head);
    return head;
  }

  void remove(_QueuedEntry entry) {
    if (!identical(entry._bucket, this)) return;
    final prev = entry._prev;
    final next = entry._next;
    if (prev != null) {
      prev._next = next;
    } else {
      _head = next;
    }
    if (next != null) {
      next._prev = prev;
    } else {
      _tail = prev;
    }
    entry._prev = null;
    entry._next = null;
    entry._bucket = null;
    _length--;
  }
}

sealed class _QueuedEntry {
  final String key;
  final StreamingAssetLoader _loader;
  AssetStreamPriority _priority;
  _PriorityBucket? _bucket;
  _QueuedEntry? _prev;
  _QueuedEntry? _next;
  bool _inFlight = false;
  bool _cancelled = false;
  bool _completed = false;

  _QueuedEntry(this.key, this._loader, this._priority);

  bool get isText;
  bool get isPending => !_cancelled && !_completed;

  void cancel();
  Future<void> execute();
}

final class _TypedStreamEntry<T> extends _QueuedEntry {
  final Completer<T> _completer = Completer<T>();
  final Future<T> Function(_TypedStreamEntry<T> entry) _runner;
  AsyncAssetDecoder? byteDecoder;
  late final StreamingAssetRequest<T> request;

  _TypedStreamEntry(
    super.key,
    super.loader,
    super.priority,
    this._runner, {
    required this.isText,
    this.byteDecoder,
  }) {
    // Prevent unhandled zone exceptions if a caller cancels or abandons a
    // failing request before attaching a listener to `request.future`.
    _completer.future.ignore();
    request = StreamingAssetRequest<T>._attached(key, this, _completer.future);
  }

  @override
  final bool isText;

  @override
  void cancel() {
    if (_cancelled || _completed) return;
    _cancelled = true;
    _loader._removeEntry(this);
    if (!_completer.isCompleted) {
      _completer.completeError(
        AssetStreamCancelledException(key),
        StackTrace.current,
      );
    }
  }

  @override
  Future<void> execute() async {
    if (_cancelled || _completed) return;
    _inFlight = true;
    try {
      final result = await _runner(this);
      if (_cancelled || _completed) return;
      _completed = true;
      _loader._removeEntry(this);
      if (!_completer.isCompleted) {
        _completer.complete(result);
      }
    } catch (error, stackTrace) {
      if (_cancelled || _completed) return;
      _completed = true;
      _loader._removeEntry(this);
      if (!_completer.isCompleted) {
        _completer.completeError(error, stackTrace);
      }
    } finally {
      _inFlight = false;
    }
  }
}
