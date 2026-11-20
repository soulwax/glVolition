part of '../engine.dart';

final class _StateCallbacks {
  final void Function()? onEnter;
  final void Function(double dt)? onUpdate;
  final void Function()? onExit;

  const _StateCallbacks({this.onEnter, this.onUpdate, this.onExit});
}

final class _StateTransitionRule<S> {
  final S? from; // null means "any state"
  final S to;
  final bool Function()? guard;
  final double? afterSeconds;
  final int priority;
  final String? trigger;

  const _StateTransitionRule({
    required this.from,
    required this.to,
    this.guard,
    this.afterSeconds,
    this.priority = 0,
    this.trigger,
  });
}

/// Declarative finite state machine [Behaviour] parameterized over state type [S]
/// (E9-4, P12-W20-B).
///
/// Tracks [currentState], [previousState], and [stateTime] (seconds spent in the
/// active state), invokes `onEnter`/`onUpdate`/`onExit`, and evaluates guarded,
/// timed, and named-trigger transitions automatically.
final class StateMachine<S> extends Behaviour {
  S _current;
  S? _previous;
  double _stateTime = 0.0;
  bool _enteredInitial = false;
  final Map<S, _StateCallbacks> _states = {};
  final List<void Function(S from, S to)> _transitionListeners = [];
  final List<_StateTransitionRule<S>> _autoTransitions = [];
  final List<_StateTransitionRule<S>> _triggerTransitions = [];

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

  /// Registers an automatic transition from [from] to [to] evaluated during
  /// [update] when [when] returns `true` and/or [stateTime] reaches
  /// [afterSeconds]. Higher [priority] rules are evaluated first.
  StateMachine<S> addTransition(
    S from,
    S to, {
    bool Function()? when,
    double? afterSeconds,
    int priority = 0,
  }) {
    _insertRule(
      _autoTransitions,
      _StateTransitionRule<S>(
        from: from,
        to: to,
        guard: when,
        afterSeconds: afterSeconds,
        priority: priority,
      ),
    );
    return this;
  }

  /// Registers a global transition from any state (other than [to]) into [to]
  /// when [when] returns `true`.
  StateMachine<S> addAnyTransition(
    S to, {
    required bool Function() when,
    int priority = 0,
  }) {
    _insertRule(
      _autoTransitions,
      _StateTransitionRule<S>(
        from: null,
        to: to,
        guard: when,
        priority: priority,
      ),
    );
    return this;
  }

  /// Registers a named trigger transition from [from] (or any state when
  /// [from] is `null`) into [to], fired via [fireTrigger].
  StateMachine<S> addTrigger(
    String triggerName,
    S? from,
    S to, {
    bool Function()? when,
    int priority = 0,
  }) {
    _insertRule(
      _triggerTransitions,
      _StateTransitionRule<S>(
        from: from,
        to: to,
        guard: when,
        priority: priority,
        trigger: triggerName,
      ),
    );
    return this;
  }

  static void _insertRule<S>(
    List<_StateTransitionRule<S>> list,
    _StateTransitionRule<S> rule,
  ) {
    var idx = list.length;
    while (idx > 0 && list[idx - 1].priority < rule.priority) {
      idx--;
    }
    list.insert(idx, rule);
  }

  /// Fires a named [triggerName], executing the highest-priority matching
  /// trigger rule for [currentState]. Returns `true` if a transition occurred.
  bool fireTrigger(String triggerName) {
    for (final rule in _triggerTransitions) {
      if (rule.trigger != triggerName) continue;
      if (rule.from != null && rule.from != _current) continue;
      if (rule.to == _current) continue;
      if (rule.guard != null && !rule.guard!()) continue;
      return transitionTo(rule.to);
    }
    return false;
  }

  /// Transitions back to [previousState], returning `false` when no previous
  /// state has been recorded.
  bool revertToPreviousState() {
    final prev = _previous;
    if (prev == null) return false;
    return transitionTo(prev);
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

  bool _evaluateAutoTransitions() {
    for (final rule in _autoTransitions) {
      if (rule.from != null && rule.from != _current) continue;
      if (rule.to == _current) continue;
      if (rule.afterSeconds != null && _stateTime < rule.afterSeconds!) {
        continue;
      }
      if (rule.guard != null && !rule.guard!()) continue;
      return transitionTo(rule.to);
    }
    return false;
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
    if (!_evaluateAutoTransitions()) {
      _states[_current]?.onUpdate?.call(dt);
    }
  }
}
