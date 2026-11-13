part of '../../engine.dart';

/// Per-object reciprocal collision avoidance agent managed by [CrowdManagerComponent] (E56-2).
final class CrowdAgentComponent extends Component {
  final crowd.CrowdAgent agent;
  bool alignToVelocity;
  bool syncPositionToTransform;
  bool autoRegisterWithManager;

  Vec3? _goal;
  bool _hasTeleportCheck = false;
  Vec3 _lastSyncedWorldPos = Vec3.zero;

  CrowdAgentComponent({
    String? id,
    double radius = 0.5,
    double maxSpeed = 4.0,
    double maxAcceleration = 16.0,
    double neighborDist = 6.0,
    double timeHorizon = 2.5,
    double timeHorizonObstacles = 1.25,
    double avoidanceWeight = 0.5,
    int layerMask = 0x7fffffff,
    Vec3? goal,
    this.alignToVelocity = true,
    this.syncPositionToTransform = true,
    this.autoRegisterWithManager = true,
  }) : _goal = goal,
       agent = crowd.CrowdAgent(
         id: id ?? 'agent',
         position: crowd.CrowdVec2.zero,
         radius: radius,
         maxSpeed: maxSpeed,
         maxAcceleration: maxAcceleration,
         neighborDist: neighborDist,
         timeHorizon: timeHorizon,
         timeHorizonObstacles: timeHorizonObstacles,
         avoidanceWeight: avoidanceWeight,
         layerMask: layerMask,
         goal: goal != null ? crowd.CrowdVec2(goal.x, goal.z) : null,
       );

  static final spec = ComponentSpec<CrowdAgentComponent>(
    'CrowdAgentComponent',
    CrowdAgentComponent.new,
    [
      Field.number('radius', (a) => a.radius, (a, v) => a.radius = v),
      Field.number('maxSpeed', (a) => a.maxSpeed, (a, v) => a.maxSpeed = v),
      Field.number(
        'maxAcceleration',
        (a) => a.maxAcceleration,
        (a, v) => a.maxAcceleration = v,
      ),
      Field.number(
        'neighborDist',
        (a) => a.neighborDist,
        (a, v) => a.neighborDist = v,
      ),
      Field.number(
        'timeHorizon',
        (a) => a.timeHorizon,
        (a, v) => a.timeHorizon = v,
      ),
      Field.number(
        'avoidanceWeight',
        (a) => a.avoidanceWeight,
        (a, v) => a.avoidanceWeight = v,
      ),
      Field.boolean(
        'alignToVelocity',
        (a) => a.alignToVelocity,
        (a, v) => a.alignToVelocity = v,
      ),
    ],
  );

  double get radius => agent.radius;
  set radius(double value) => agent.radius = value;

  double get maxSpeed => agent.maxSpeed;
  set maxSpeed(double value) => agent.maxSpeed = value;

  double get maxAcceleration => agent.maxAcceleration;
  set maxAcceleration(double value) => agent.maxAcceleration = value;

  double get neighborDist => agent.neighborDist;
  set neighborDist(double value) => agent.neighborDist = value;

  double get timeHorizon => agent.timeHorizon;
  set timeHorizon(double value) => agent.timeHorizon = value;

  double get avoidanceWeight => agent.avoidanceWeight;
  set avoidanceWeight(double value) => agent.avoidanceWeight = value;

  Vec3? get goal => _goal;
  set goal(Vec3? value) {
    _goal = value;
    agent.goal = value != null ? crowd.CrowdVec2(value.x, value.z) : null;
  }

  Vec3 get velocity => Vec3(agent.velocity.x, 0.0, agent.velocity.z);
  set velocity(Vec3 value) =>
      agent.velocity = crowd.CrowdVec2(value.x, value.z);

  void _pullFromTransform() {
    if (!isAttached) return;
    final p = transform.position;
    if (!_hasTeleportCheck || (p - _lastSyncedWorldPos).lengthSquared > 1e-6) {
      agent.position = crowd.CrowdVec2(p.x, p.z);
      _lastSyncedWorldPos = p;
      _hasTeleportCheck = true;
    }
    agent.enabled = _active && gameObject.activeInHierarchy;
  }

  void _pushToTransform() {
    if (!isAttached || !syncPositionToTransform) return;
    final curr = transform.position;
    final next = Vec3(agent.position.x, curr.y, agent.position.z);
    transform.position = next;
    _lastSyncedWorldPos = next;

    if (alignToVelocity && agent.velocity.lengthSquared > 1e-4) {
      final dir = Vec3(agent.velocity.x, 0.0, agent.velocity.z).normalized;
      transform.rotation = lookRotation(dir);
    }
  }

  @override
  void onEnable() {
    _pullFromTransform();
    agent.enabled = true;
    if (autoRegisterWithManager && isAttached) {
      for (final root in scene.rootGameObjects) {
        final mgr = _findInTree<CrowdManagerComponent>(root);
        if (mgr != null) {
          mgr.registerAgent(this);
          break;
        }
      }
    }
  }

  @override
  void onDisable() {
    agent.enabled = false;
  }
}

/// Centralized ORCA / boid flocking crowd coordinator stepping all registered
/// or discovered [CrowdAgentComponent]s across the scene XZ plane (E56-2).
final class CrowdManagerComponent extends Behaviour {
  crowd.OrcaSolver solver;
  crowd.BoidFlockRule? boidRule;
  bool useFlocking;
  Vec3? flockSharedGoal;
  bool autoDiscoverAgents;
  bool fixedStep;

  final List<CrowdAgentComponent> _agents = [];
  final List<crowd.CrowdCircleObstacle> circleObstacles = [];
  final List<crowd.CrowdSegmentObstacle> segmentObstacles = [];

  crowd.CrowdStepStats _lastStats = const crowd.CrowdStepStats(
    activeAgents: 0,
    totalConstraints: 0,
    minPairwiseClearance: double.infinity,
    averageSpeed: 0.0,
  );

  CrowdManagerComponent({
    crowd.OrcaSolver? solver,
    this.boidRule,
    this.useFlocking = false,
    this.flockSharedGoal,
    this.autoDiscoverAgents = true,
    this.fixedStep = false,
  }) : solver = solver ?? const crowd.OrcaSolver();

  static final spec = ComponentSpec<CrowdManagerComponent>(
    'CrowdManagerComponent',
    CrowdManagerComponent.new,
    [
      Field.boolean(
        'useFlocking',
        (c) => c.useFlocking,
        (c, v) => c.useFlocking = v,
      ),
      Field.boolean(
        'autoDiscoverAgents',
        (c) => c.autoDiscoverAgents,
        (c, v) => c.autoDiscoverAgents = v,
      ),
      Field.boolean('fixedStep', (c) => c.fixedStep, (c, v) => c.fixedStep = v),
    ],
  );

  List<CrowdAgentComponent> get agents => List.unmodifiable(_agents);
  crowd.CrowdStepStats get lastStats => _lastStats;

  void registerAgent(CrowdAgentComponent agentComp) {
    if (!_agents.contains(agentComp)) {
      _agents.add(agentComp);
    }
  }

  void unregisterAgent(CrowdAgentComponent agentComp) =>
      _agents.remove(agentComp);

  void addCircleObstacle(Vec3 center, double radius, {String? id}) {
    circleObstacles.add(
      crowd.CrowdCircleObstacle(
        id: id ?? 'circle_${circleObstacles.length}',
        center: crowd.CrowdVec2(center.x, center.z),
        radius: radius,
      ),
    );
  }

  void addWallObstacle(Vec3 start, Vec3 end, {String? id}) {
    segmentObstacles.add(
      crowd.CrowdSegmentObstacle(
        id: id ?? 'wall_${segmentObstacles.length}',
        start: crowd.CrowdVec2(start.x, start.z),
        end: crowd.CrowdVec2(end.x, end.z),
      ),
    );
  }

  void _discoverSceneAgents() {
    if (!autoDiscoverAgents || !isAttached) return;
    void visit(GameObject go) {
      final comp = go.getComponent<CrowdAgentComponent>();
      if (comp != null && !_agents.contains(comp)) {
        _agents.add(comp);
      }
      for (final child in go.children) {
        visit(child);
      }
    }

    for (final root in scene.rootGameObjects) {
      visit(root);
    }
  }

  /// Advances ORCA avoidance and optionally boid flocking rules by [dt] seconds.
  crowd.CrowdStepStats stepCrowd(double dt) {
    _discoverSceneAgents();
    _agents.removeWhere((a) => a.isDestroyed);

    final rawAgents = <crowd.CrowdAgent>[];
    for (final comp in _agents) {
      comp._pullFromTransform();
      rawAgents.add(comp.agent);
    }

    if (useFlocking && boidRule != null) {
      boidRule!.applyToFlock(
        rawAgents,
        sharedGoal: flockSharedGoal != null
            ? crowd.CrowdVec2(flockSharedGoal!.x, flockSharedGoal!.z)
            : null,
      );
    }

    _lastStats = solver.step(
      rawAgents,
      dt,
      circleObstacles: circleObstacles,
      segmentObstacles: segmentObstacles,
      computeGoalPreferredVelocity: !(useFlocking && boidRule != null),
    );

    for (final comp in _agents) {
      if (comp.agent.enabled) {
        comp._pushToTransform();
      }
    }

    return _lastStats;
  }

  @override
  void fixedUpdate() {
    if (fixedStep) stepCrowd(time.fixedDeltaTime);
  }

  @override
  void update() {
    if (!fixedStep) stepCrowd(time.deltaTime);
  }
}

/// Organizes followers into tactical formations (`wedge`, `line`, `box`, `ring`)
/// anchored to this leader's world XZ pose and forward heading (E56-2).
final class FormationLeaderComponent extends Behaviour {
  crowd.FormationKind pattern;
  double spacing;
  double offsetBehind;
  bool updateEveryFrame;
  final List<CrowdAgentComponent> followers;

  List<Vec3> _lastSlots = const [];

  FormationLeaderComponent({
    this.pattern = crowd.FormationKind.wedge,
    this.spacing = 2.0,
    this.offsetBehind = 1.5,
    this.updateEveryFrame = true,
    List<CrowdAgentComponent>? followers,
  }) : followers = followers ?? [];

  static final spec = ComponentSpec<FormationLeaderComponent>(
    'FormationLeaderComponent',
    FormationLeaderComponent.new,
    [
      Field.enumValue<FormationLeaderComponent, crowd.FormationKind>(
        'pattern',
        crowd.FormationKind.values,
        (f) => f.pattern,
        (f, v) => f.pattern = v,
      ),
      Field.number('spacing', (f) => f.spacing, (f, v) => f.spacing = v),
      Field.number(
        'offsetBehind',
        (f) => f.offsetBehind,
        (f, v) => f.offsetBehind = v,
      ),
      Field.boolean(
        'updateEveryFrame',
        (f) => f.updateEveryFrame,
        (f, v) => f.updateEveryFrame = v,
      ),
    ],
  );

  List<Vec3> get lastSlots => _lastSlots;

  /// Recomputes formation slot goals and assigns followers via nearest-slot matching.
  List<Vec3> assignSlots() {
    if (!isAttached || followers.isEmpty) {
      _lastSlots = const [];
      return const [];
    }

    final leaderPos = transform.position;
    final fwd = transform.forward;
    final heading = (fwd.x * fwd.x + fwd.z * fwd.z) > 1e-6
        ? crowd.CrowdVec2(fwd.x, fwd.z)
        : crowd.CrowdVec2.forward;

    final rawSlots = crowd.FormationPattern.computeSlots(
      leaderPosition: crowd.CrowdVec2(leaderPos.x, leaderPos.z),
      leaderHeading: heading,
      count: followers.length,
      kind: pattern,
      spacing: spacing,
      offsetBehind: offsetBehind,
    );

    final rawAgents = [
      for (final f in followers)
        if (!f.isDestroyed) f.agent,
    ];
    for (final f in followers) {
      if (!f.isDestroyed) f._pullFromTransform();
    }
    crowd.FormationPattern.assignNearestSlots(rawAgents, rawSlots);

    for (final f in followers) {
      if (!f.isDestroyed && f.agent.goal != null) {
        f._goal = Vec3(f.agent.goal!.x, leaderPos.y, f.agent.goal!.z);
      }
    }

    _lastSlots = [for (final s in rawSlots) Vec3(s.x, leaderPos.y, s.z)];
    return _lastSlots;
  }

  @override
  void start() => assignSlots();

  @override
  void update() {
    if (updateEveryFrame) assignSlots();
  }
}

/// Persistent UI state for [CrowdInspectorUI.render].
final class CrowdInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` crowd ORCA & formation telemetry panel (E56-2).
final class CrowdInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    CrowdInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked =
        hovered && state.activeButtonId == id && inp.wasMouseReleased;
    if (inp.wasMouseReleased && state.activeButtonId == id) {
      state.activeButtonId = null;
    }

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      bg,
      cornerRadius: ui.style.frameRounding,
    );
    dl.addRectOutline(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      ui.style.windowBorder,
      cornerRadius: ui.style.frameRounding,
    );
    final textW = label.length * (ui.style.fontSize * 0.6);
    dl.addText(
      label,
      rect.x + math.max(4.0, (rect.width - textW) * 0.5),
      rect.y + (rect.height - ui.style.fontSize) * 0.5,
      color: ui.style.text,
      size: ui.style.fontSize,
    );
    return clicked;
  }

  static void render(
    VoxUiContext ui,
    CrowdManagerComponent manager, {
    FormationLeaderComponent? formation,
    CrowdInspectorUiState? state,
    String title = 'Crowd & ORCA Inspector',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? CrowdInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final stats = manager.lastStats;
    final clearanceStr = stats.minPairwiseClearance.isFinite
        ? '${stats.minPairwiseClearance.toStringAsFixed(2)}m'
        : '--';

    ui.labelValue(
      'Agents / Constraints',
      '${stats.activeAgents} / ${stats.totalConstraints}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Avg Speed / Clearance',
      '${stats.averageSpeed.toStringAsFixed(2)} m/s / $clearanceStr',
      valueColor: stats.minPairwiseClearance >= -0.05
          ? VoxColor.green
          : VoxColor.yellow,
    );
    ui.labelValue(
      'Obstacles (C/W)',
      '${manager.circleObstacles.length} / ${manager.segmentObstacles.length}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Mode / Formation',
      '${manager.useFlocking ? "Flock" : "ORCA"} / ${formation?.pattern.name ?? "none"}',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final modeRect = VoxRect(x + pad, barY, 96.0, 22.0);
    if (_drawButton(ui, uiState, 'crowd_mode', 'Toggle Flock', modeRect)) {
      manager.useFlocking = !manager.useFlocking;
    }

    final stepRect = VoxRect(modeRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'crowd_step', 'Step +0.1s', stepRect)) {
      manager.stepCrowd(0.1);
    }

    if (formation != null) {
      final fmtRect = VoxRect(stepRect.right + 8.0, barY, 96.0, 22.0);
      if (_drawButton(ui, uiState, 'crowd_fmt', 'Cycle Form', fmtRect)) {
        final values = crowd.FormationKind.values;
        formation.pattern =
            values[(formation.pattern.index + 1) % values.length];
        formation.assignSlots();
      }
    }

    ui.endWindow();
  }
}

T? _findInTree<T extends Component>(GameObject go) {
  final found = go.getComponent<T>();
  if (found != null) return found;
  for (final child in go.children) {
    final c = _findInTree<T>(child);
    if (c != null) return c;
  }
  return null;
}
