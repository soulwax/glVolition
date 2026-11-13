part of '../../engine.dart';

/// Integrates a [BehaviorTree] from `package:voxai` into a [GameObject].
final class BehaviorTreeComponent extends Behaviour {
  BehaviorTree tree;
  bool fixedStep;

  BehaviorTreeComponent({required this.tree, this.fixedStep = false});

  Blackboard get blackboard => tree.blackboard;

  NodeStatus? _lastStatus;
  NodeStatus? get lastStatus => _lastStatus;

  @override
  void update() {
    if (fixedStep) return;
    _lastStatus = tree.tick(time.time);
  }

  @override
  void fixedUpdate() {
    if (!fixedStep) return;
    _lastStatus = tree.tick(time.fixedTime);
  }

  void reset() => tree.reset();
}

/// Integrates an [AiStateMachine] from `package:voxai` into a [GameObject].
final class AiFsmComponent<TStateId> extends Behaviour {
  late final AiStateMachine<GameObject, TStateId> fsm;
  final TStateId? initialState;

  AiFsmComponent({this.initialState});

  @override
  void awake() {
    fsm = AiStateMachine<GameObject, TStateId>(gameObject);
  }

  @override
  void start() {
    final init = initialState;
    if (init != null && fsm.currentStateId == null) {
      fsm.transitionTo(init);
    }
  }

  TStateId? get currentStateId => fsm.currentStateId;

  void addState(TStateId id, State<GameObject> state) =>
      fsm.addState(id, state);

  void addTransition(
    TStateId from,
    TStateId to,
    bool Function(GameObject go) condition,
  ) => fsm.addTransition(from, to, condition);

  void transitionTo(TStateId to) => fsm.transitionTo(to);

  @override
  void update() {
    fsm.update(time.deltaTime);
  }
}
