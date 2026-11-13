part of '../../engine.dart';

/// Steering behavioral mode preset for [SteeringAgentComponent].
enum SteeringBehaviorMode {
  arrive,
  seek,
  pursue,
  evade,
  wander,
  flock,
  formation,
}

/// Reynolds steering, flocking & tactical formation agent (`voxsteer`) (E82-2).
final class SteeringAgentComponent extends Behaviour {
  SteeringBehaviorMode mode;
  double maxSpeed;
  double maxForce;
  double slowingRadius;
  double wallAvoidanceWeight;
  double feelerLength;
  steer.FormationShape formationShape;
  double formationSpacing;
  int formationSlotIndex;
  int formationTotalSlots;
  bool paused;

  GameObject? target;
  Vec3 fallbackTargetPosition;
  final List<steer.SteeringObstacle> obstacles = [];

  late steer.SteeringAgent agent;
  Vec3? _prevTargetPos;

  SteeringAgentComponent({
    this.mode = SteeringBehaviorMode.arrive,
    this.maxSpeed = 6.0,
    this.maxForce = 18.0,
    this.slowingRadius = 3.0,
    this.wallAvoidanceWeight = 1.5,
    this.feelerLength = 4.0,
    this.formationShape = steer.FormationShape.wedge,
    this.formationSpacing = 2.2,
    this.formationSlotIndex = 0,
    this.formationTotalSlots = 4,
    this.paused = false,
    this.target,
    this.fallbackTargetPosition = Vec3.zero,
  }) {
    agent = steer.SteeringAgent(
      id: instanceId,
      maxSpeed: maxSpeed,
      maxForce: maxForce,
    );
  }

  static final spec = ComponentSpec<SteeringAgentComponent>(
    'SteeringAgentComponent',
    SteeringAgentComponent.new,
    [
      Field.enumValue<SteeringAgentComponent, SteeringBehaviorMode>(
        'mode',
        SteeringBehaviorMode.values,
        (c) => c.mode,
        (c, v) => c.mode = v,
      ),
      Field.number('maxSpeed', (c) => c.maxSpeed, (c, v) => c.maxSpeed = v),
      Field.number('maxForce', (c) => c.maxForce, (c, v) => c.maxForce = v),
      Field.number(
        'slowingRadius',
        (c) => c.slowingRadius,
        (c, v) => c.slowingRadius = v,
      ),
      Field.number(
        'wallAvoidanceWeight',
        (c) => c.wallAvoidanceWeight,
        (c, v) => c.wallAvoidanceWeight = v,
      ),
      Field.number(
        'feelerLength',
        (c) => c.feelerLength,
        (c, v) => c.feelerLength = v,
      ),
      Field.enumValue<SteeringAgentComponent, steer.FormationShape>(
        'formationShape',
        steer.FormationShape.values,
        (c) => c.formationShape,
        (c, v) => c.formationShape = v,
      ),
      Field.number(
        'formationSpacing',
        (c) => c.formationSpacing,
        (c, v) => c.formationSpacing = v,
      ),
      Field.integer(
        'formationSlotIndex',
        (c) => c.formationSlotIndex,
        (c, v) => c.formationSlotIndex = v,
      ),
      Field.integer(
        'formationTotalSlots',
        (c) => c.formationTotalSlots,
        (c, v) => c.formationTotalSlots = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  double get currentSpeed => agent.speed;
  Vec3 get currentVelocity =>
      Vec3(agent.velocity.x, agent.velocity.y, agent.velocity.z);
  Vec3 get lastAppliedForce => Vec3(
    agent.lastAppliedForce.x,
    agent.lastAppliedForce.y,
    agent.lastAppliedForce.z,
  );

  void cycleNextMode() {
    final vals = SteeringBehaviorMode.values;
    mode = vals[(vals.indexOf(mode) + 1) % vals.length];
  }

  void addObstacle(Vec3 center, double radius) {
    obstacles.add(
      steer.SteeringObstacle(
        center: steer.SteerVec3(center.x, center.y, center.z),
        radius: radius,
      ),
    );
  }

  /// Evaluates steering forces against target/flockmates/obstacles and steps transform pose.
  void stepSteering(double dt) {
    if (dt <= 0.0) return;
    agent.maxSpeed = math.max(0.1, maxSpeed);
    agent.maxForce = math.max(0.1, maxForce);

    if (isAttached) {
      final wp = transform.position;
      final wf = transform.forward;
      agent.position = steer.SteerVec3(wp.x, wp.y, wp.z);
      agent.forward = steer.SteerVec3(wf.x, wf.y, wf.z);
    }

    final tgtGo = target;
    final tgtPosVec = tgtGo?.transform.position ?? fallbackTargetPosition;
    final tgtVelVec = (_prevTargetPos != null && dt > 1e-5)
        ? (tgtPosVec - _prevTargetPos!) * (1.0 / dt)
        : Vec3.zero;
    _prevTargetPos = tgtPosVec;

    final sTargetPos = steer.SteerVec3(tgtPosVec.x, tgtPosVec.y, tgtPosVec.z);
    final sTargetVel = steer.SteerVec3(tgtVelVec.x, tgtVelVec.y, tgtVelVec.z);

    final peers = <steer.SteeringAgent>[];
    if (isAttached && scene.isLoaded) {
      for (final other in scene.findObjectsOfType<SteeringAgentComponent>()) {
        if (!other.isActiveAndEnabled) continue;
        peers.add(other.agent);
      }
    }

    agent.resetForce();
    switch (mode) {
      case SteeringBehaviorMode.arrive:
        agent.addForce(
          steer.SteeringBehaviors.arrive(
            agent,
            sTargetPos,
            slowingRadius: slowingRadius,
          ),
        );
      case SteeringBehaviorMode.seek:
        agent.addForce(steer.SteeringBehaviors.seek(agent, sTargetPos));
      case SteeringBehaviorMode.pursue:
        agent.addForce(
          steer.SteeringBehaviors.pursue(
            agent,
            targetPos: sTargetPos,
            targetVelocity: sTargetVel,
          ),
        );
      case SteeringBehaviorMode.evade:
        agent.addForce(
          steer.SteeringBehaviors.evade(
            agent,
            threatPos: sTargetPos,
            threatVelocity: sTargetVel,
          ),
        );
      case SteeringBehaviorMode.wander:
        agent.addForce(
          steer.SteeringBehaviors.wander(agent, deltaAngleRad: 0.6 * dt),
        );
      case SteeringBehaviorMode.flock:
        agent.addForce(steer.SteeringBehaviors.flock(agent, peers));
        if (tgtGo != null) {
          agent.addForce(
            steer.SteeringBehaviors.seek(agent, sTargetPos),
            weight: 0.65,
          );
        }
      case SteeringBehaviorMode.formation:
        final planner = steer.FormationSlotPlanner(
          shape: formationShape,
          spacing: formationSpacing,
        );
        final leaderFwd = tgtGo?.transform.forward ?? kForward;
        final slotPos = planner.computeSlotWorldPosition(
          slotIndex: formationSlotIndex,
          totalSlots: math.max(1, formationTotalSlots),
          leaderPos: sTargetPos,
          leaderForward: steer.SteerVec3(leaderFwd.x, leaderFwd.y, leaderFwd.z),
        );
        agent.addForce(
          steer.SteeringBehaviors.arrive(
            agent,
            slotPos,
            slowingRadius: slowingRadius,
          ),
        );
    }

    if (obstacles.isNotEmpty && wallAvoidanceWeight > 0.0) {
      agent.addForce(
        steer.SteeringBehaviors.wallAvoidance(
          agent,
          obstacles,
          feelerLength: feelerLength,
        ),
        weight: wallAvoidanceWeight,
      );
    }

    agent.step(dt);

    if (isAttached) {
      transform.position = Vec3(
        agent.position.x,
        agent.position.y,
        agent.position.z,
      );
      final fwd = Vec3(agent.forward.x, agent.forward.y, agent.forward.z);
      if (fwd.lengthSquared > 1e-6) {
        transform.lookAt(transform.position + fwd);
      }
    }
  }

  @override
  void update() {
    if (paused) return;
    stepSteering(time.deltaTime);
  }
}

/// Persistent UI state for [SteeringInspectorUI.render].
final class SteeringInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` Reynolds steering, flocking & formation inspector (E82-2).
final class SteeringInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    SteeringInspectorUiState state,
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
    SteeringAgentComponent steerComp, {
    SteeringInspectorUiState? state,
    String title = 'Steering Agent',
    double x = 20.0,
    double y = 20.0,
    double width = 395.0,
    double height = 245.0,
  }) {
    final uiState = state ?? SteeringInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Mode / Status',
      '${steerComp.mode.name} | ${steerComp.paused ? 'Paused' : 'Active'}',
      valueColor: steerComp.paused ? VoxColor.yellow : VoxColor.cyan,
    );
    ui.labelValue(
      'Speed / Force',
      '${steerComp.currentSpeed.toStringAsFixed(2)} m/s | ${steerComp.lastAppliedForce.length.toStringAsFixed(1)} N',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Formation Slot',
      '${steerComp.formationShape.name} #${steerComp.formationSlotIndex}/${steerComp.formationTotalSlots}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Obstacles / Feelers',
      '${steerComp.obstacles.length} obs | feeler ${steerComp.feelerLength.toStringAsFixed(1)}m',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'st_pause',
      steerComp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      steerComp.paused = !steerComp.paused;
    }

    final modeRect = VoxRect(pauseRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'st_mode', 'Next Mode', modeRect)) {
      steerComp.cycleNextMode();
    }

    final spdRect = VoxRect(modeRect.right + 8.0, barY, 86.0, 22.0);
    if (_drawButton(ui, uiState, 'st_spd', 'Speed +2', spdRect)) {
      steerComp.maxSpeed += 2.0;
    }

    final stepRect = VoxRect(spdRect.right + 8.0, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'st_step', 'Step 20ms', stepRect)) {
      steerComp.stepSteering(0.02);
    }

    ui.endWindow();
  }
}
