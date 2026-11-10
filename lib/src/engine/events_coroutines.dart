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
  bool cancelled = false;

  _ListenerEntry(this.handler, this.owner);
}

/// Typed, zero-dependency publish/subscribe event bus scoped to a [Scene] (E8-1).
///
/// Listeners bound to an `owner` [Component] are automatically skipped when the
/// component is inactive and removed when the component is destroyed.
final class SceneEvents {
  final Map<Type, List< Object>> _listenersByType = {};

  /// Subscribes [handler] to events of type [E].
  ///
  /// When [owner] is provided, the listener only fires while
  /// `owner.isActiveAndEnabled` is true and is automatically garbage-collected
  /// once `owner.isDestroyed` is true.
  EventSubscription on<E>(
    void Function(E event) handler, {
    Component? owner,
  }) {
    final list = _listenersByType.putIfAbsent(E, () => <_ListenerEntry<E>>[]);
    final entry = _ListenerEntry<E>(handler, owner);
    list.add(entry);
    return EventSubscription._(() {
      entry.cancelled = true;
      list.remove(entry);
    });
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
      entry.handler(event);
    }
  }

  /// Removes all listeners registered on this bus.
  void clear() => _listenersByType.clear();
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

/// Handle to a running generator coroutine started via [Behaviour.startCoroutine].
final class Coroutine {
  final Behaviour owner;
  final Iterator<YieldInstruction?> _iterator;
  double _waitRemaining = 0;
  bool _waitingRealtime = false;
  bool Function()? _waitPredicate;
  bool _finished = false;
  bool _started = false;

  Coroutine._(this.owner, Iterable<YieldInstruction?> iterable)
      : _iterator = iterable.iterator;

  bool get isFinished => _finished;

  void cancel() {
    _finished = true;
    _waitPredicate = null;
  }

  bool _step(double dt, double unscaledDt) {
    if (_finished || owner.isDestroyed) {
      _finished = true;
      return false;
    }
    if (!owner.isActiveAndEnabled) {
      return true;
    }

    if (_waitPredicate != null) {
      if (!_waitPredicate!()) return true;
      _waitPredicate = null;
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
    }
    return true;
  }
}
