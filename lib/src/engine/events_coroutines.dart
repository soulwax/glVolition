part of '../engine.dart';

/// Handle returned by [SceneEvents.on] to cancel an event listener.
final class EventSubscription {
  final void Function() _cancel;
  bool _cancelled = false;

  EventSubscription._(this._cancel);

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

final class _ListenerEntry<E> {
  final void Function(E event) handler;
  final Component? owner;
  final int priority;
  final int sequence;
  final bool once;
  bool cancelled = false;

  _ListenerEntry(
    this.handler,
    this.owner, {
    this.priority = 0,
    this.sequence = 0,
    this.once = false,
  });
}

/// Typed, zero-dependency publish/subscribe event bus scoped to a [Scene]
/// (E8-1, P11-W19-B).
///
/// Supports priority ordering (higher priority runs first), one-shot [once]
/// subscriptions, deferred event queues ([emitDeferred] / [flushDeferred]),
/// and automatic lifecycle cleanup for [owner] components.
final class SceneEvents {
  final Map<Type, List<Object>> _listenersByType = {};
  final List<void Function()> _deferredQueue = [];
  int _nextSeq = 0;

  /// Subscribes [handler] to events of type [E]. Higher [priority] runs first.
  ///
  /// When [owner] is provided, the listener only fires while
  /// `owner.isActiveAndEnabled` is true and is automatically garbage-collected
  /// once `owner.isDestroyed` is true.
  EventSubscription on<E>(
    void Function(E event) handler, {
    Component? owner,
    int priority = 0,
  }) => _addListener<E>(handler, owner: owner, priority: priority, once: false);

  /// Subscribes a one-shot [handler] that automatically unsubscribes upon
  /// receiving the first matching event of type [E].
  EventSubscription once<E>(
    void Function(E event) handler, {
    Component? owner,
    int priority = 0,
  }) => _addListener<E>(handler, owner: owner, priority: priority, once: true);

  EventSubscription _addListener<E>(
    void Function(E event) handler, {
    Component? owner,
    required int priority,
    required bool once,
  }) {
    final list = _listenersByType.putIfAbsent(E, () => <_ListenerEntry<E>>[]);
    final entry = _ListenerEntry<E>(
      handler,
      owner,
      priority: priority,
      sequence: _nextSeq++,
      once: once,
    );
    var idx = list.length;
    while (idx > 0) {
      final prev = list[idx - 1] as _ListenerEntry<E>;
      if (prev.priority > priority ||
          (prev.priority == priority && prev.sequence < entry.sequence)) {
        break;
      }
      idx--;
    }
    list.insert(idx, entry);
    return EventSubscription._(() {
      entry.cancelled = true;
      list.remove(entry);
    });
  }

  /// Number of active listeners currently registered for event type [E].
  int listenerCount<E>() {
    final rawList = _listenersByType[E];
    if (rawList == null) return 0;
    var count = 0;
    for (final raw in rawList) {
      final entry = raw as _ListenerEntry<E>;
      if (!entry.cancelled && !(entry.owner?.isDestroyed ?? false)) {
        count++;
      }
    }
    return count;
  }

  /// Number of queued deferred events awaiting [flushDeferred].
  int get pendingDeferredCount => _deferredQueue.length;

  /// Enqueues [event] to be dispatched when [flushDeferred] is called.
  void emitDeferred<E>(E event) {
    _deferredQueue.add(() => emit<E>(event));
  }

  /// Dispatches all queued deferred events in FIFO order.
  void flushDeferred() {
    if (_deferredQueue.isEmpty) return;
    final batch = List<void Function()>.of(_deferredQueue);
    _deferredQueue.clear();
    for (final dispatch in batch) {
      dispatch();
    }
  }

  /// Dispatches [event] synchronously to all active listeners of type [E].
  void emit<E>(E event) {
    final rawList = _listenersByType[E];
    if (rawList == null || rawList.isEmpty) return;

    for (final raw in List.of(rawList)) {
      final entry = raw as _ListenerEntry<E>;
      if (entry.cancelled) continue;
      final owner = entry.owner;
      if (owner != null) {
        if (owner.isDestroyed) {
          entry.cancelled = true;
          rawList.remove(entry);
          continue;
        }
        if (!owner.isActiveAndEnabled) continue;
      }
      if (entry.once) {
        entry.cancelled = true;
        rawList.remove(entry);
      }
      entry.handler(event);
    }
  }

  /// Removes all listeners and pending deferred events registered on this bus.
  void clear() {
    _listenersByType.clear();
    _deferredQueue.clear();
  }
}

/// Base class for instructions yielded by a [Coroutine] generator (`sync*`) (E8-1).
sealed class YieldInstruction {
  const YieldInstruction();
}

/// Resumes the coroutine on the next frame's update step.
final class NextFrame extends YieldInstruction {
  const NextFrame();
}

/// Suspends the coroutine for [seconds] of scaled game time (`time.deltaTime`).
final class WaitForSeconds extends YieldInstruction {
  final double seconds;
  const WaitForSeconds(this.seconds);
}

/// Suspends the coroutine for [seconds] of unscaled real time (`time.unscaledDeltaTime`).
final class WaitForRealtime extends YieldInstruction {
  final double seconds;
  const WaitForRealtime(this.seconds);
}

/// Suspends the coroutine until [predicate] returns `true`.
final class WaitUntil extends YieldInstruction {
  final bool Function() predicate;
  const WaitUntil(this.predicate);
}

/// Suspends the coroutine while [predicate] returns `true` (P11-W19-B).
final class WaitWhile extends YieldInstruction {
  final bool Function() predicate;
  const WaitWhile(this.predicate);
}

/// Suspends the coroutine for [frames] update frames (P11-W19-B).
final class WaitForFrames extends YieldInstruction {
  final int frames;
  const WaitForFrames(this.frames);
}

/// Suspends the coroutine until [coroutine] has finished or been cancelled
/// (P11-W19-B).
final class WaitForCoroutine extends YieldInstruction {
  final Coroutine coroutine;
  const WaitForCoroutine(this.coroutine);
}

/// Handle to a running generator coroutine started via [Behaviour.startCoroutine].
final class Coroutine {
  final Behaviour owner;
  final Iterator<YieldInstruction?> _iterator;
  double _waitRemaining = 0;
  int _waitFrames = 0;
  bool _waitingRealtime = false;
  bool Function()? _waitPredicate;
  Coroutine? _waitSubCoroutine;
  bool _finished = false;
  bool _started = false;

  Coroutine._(this.owner, Iterable<YieldInstruction?> iterable)
    : _iterator = iterable.iterator;

  bool get isFinished => _finished;

  void cancel() {
    _finished = true;
    _waitPredicate = null;
    _waitSubCoroutine = null;
    _waitFrames = 0;
  }

  bool _step(double dt, double unscaledDt) {
    if (_finished || owner.isDestroyed) {
      _finished = true;
      return false;
    }
    if (!owner.isActiveAndEnabled) {
      return true;
    }

    if (_waitSubCoroutine != null) {
      if (!_waitSubCoroutine!.isFinished) return true;
      _waitSubCoroutine = null;
    } else if (_waitPredicate != null) {
      if (!_waitPredicate!()) return true;
      _waitPredicate = null;
    } else if (_waitFrames > 0) {
      _waitFrames--;
      if (_waitFrames > 0) return true;
    } else if (_waitRemaining > 0) {
      _waitRemaining -= _waitingRealtime ? unscaledDt : dt;
      if (_waitRemaining > 1e-9) return true;
      _waitRemaining = 0;
    }

    if (!_started) {
      _started = true;
    }

    if (!_iterator.moveNext()) {
      _finished = true;
      return false;
    }

    final yielded = _iterator.current;
    switch (yielded) {
      case null || NextFrame():
        _waitRemaining = 0;
        _waitingRealtime = false;
      case WaitForSeconds(:final seconds):
        _waitRemaining = math.max(0, seconds);
        _waitingRealtime = false;
      case WaitForRealtime(:final seconds):
        _waitRemaining = math.max(0, seconds);
        _waitingRealtime = true;
      case WaitUntil(:final predicate):
        _waitPredicate = predicate;
      case WaitWhile(:final predicate):
        _waitPredicate = () => !predicate();
      case WaitForFrames(:final frames):
        _waitFrames = math.max(1, frames);
      case WaitForCoroutine(:final coroutine):
        _waitSubCoroutine = coroutine;
    }
    return true;
  }
}
