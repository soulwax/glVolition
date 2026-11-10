part of '../engine.dart';

final class _StateCallbacks {
  final void Function()? onEnter;
  final void Function(double dt)? onUpdate;
  final void Function()? onExit;

  const _StateCallbacks({this.onEnter, this.onUpdate, this.onExit});
}

/// Declarative finite state machine [Behaviour] parameterized over state type [S] (E9-4).
///
/// Tracks [currentState], [previousState], and [stateTime] (seconds spent in the
/// active state), and invokes registered `onEnter`, `onUpdate(dt)`, and `onExit`
/// callbacks on state transitions and per-frame updates.
final class StateMachine<S> extends Behaviour {
  S _current;
  S? _previous;
  double _stateTime = 0.0;
  bool _enteredInitial = false;
  final Map<S, _StateCallbacks> _states = {};
  final List<void Function(S from, S to)> _transitionListeners = [];

  StateMachine(S initialState) : _current = initialState;

  S get currentState => _current;
  S? get previousState => _previous;

  /// Seconds elapsed since entering [currentState].
  double get stateTime => _stateTime;

  bool isInState(S state) => _current == state;

  /// Registers lifecycle callbacks for [state]. Returns `this` for chaining.
  StateMachine<S> defineState(
    S state, {
    void Function()? onEnter,
    void Function(double dt)? onUpdate,
    void Function()? onExit,
  }) {
    _states[state] = _StateCallbacks(
      onEnter: onEnter,
      onUpdate: onUpdate,
      onExit: onExit,
    );
    return this;
  }

  /// Subscribes [listener] to state transitions `(from, to)`.
  void onTransition(void Function(S from, S to) listener) {
    _transitionListeners.add(listener);
  }

  /// Transitions to [nextState]. When [force] is `false` (default) and
  /// `nextState == currentState`, this is a no-op.
  bool transitionTo(S nextState, {bool force = false}) {
    if (!force && _current == nextState) return false;
    final prev = _current;
    if (_enteredInitial) {
      _states[prev]?.onExit?.call();
    }
    _previous = prev;
    _current = nextState;
    _stateTime = 0.0;
    _enteredInitial = true;
    _states[nextState]?.onEnter?.call();
    for (final listener in List.of(_transitionListeners)) {
      listener(prev, nextState);
    }
    return true;
  }

  @override
  void start() {
    if (!_enteredInitial) {
      _enteredInitial = true;
      _states[_current]?.onEnter?.call();
    }
  }

  @override
  void update() {
    if (!_enteredInitial) {
      _enteredInitial = true;
      _states[_current]?.onEnter?.call();
    }
    final dt = time.deltaTime;
    _stateTime += dt;
    _states[_current]?.onUpdate?.call(dt);
  }
}
