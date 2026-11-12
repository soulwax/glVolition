part of '../../engine.dart';

/// Hierarchical Task Network & Utility AI planner with exponential memory decay (`voxhtn`) (E75-2).
final class HtnPlannerComponent extends Behaviour {
  bool paused;
  bool autoReplanWhenIdle;
  double pruneConfidenceThreshold;

  htn.HtnDomain? domain;
  late final htn.HtnBlackboard blackboard;
  late final htn.HtnPlanner planner;

  HtnPlannerComponent({
    this.paused = false,
    this.autoReplanWhenIdle = true,
    this.pruneConfidenceThreshold = 0.02,
    this.domain,
    int maxDecompositionDepth = 32,
  }) : blackboard = htn.HtnBlackboard(
         pruneConfidenceThreshold: pruneConfidenceThreshold,
       ),
       planner = htn.HtnPlanner(maxDecompositionDepth: maxDecompositionDepth);

  static final spec = ComponentSpec<HtnPlannerComponent>(
    'HtnPlannerComponent',
    HtnPlannerComponent.new,
    [
      Field.boolean('paused', (h) => h.paused, (h, v) => h.paused = v),
      Field.boolean(
        'autoReplanWhenIdle',
        (h) => h.autoReplanWhenIdle,
        (h, v) => h.autoReplanWhenIdle = v,
      ),
      Field.number(
        'pruneConfidenceThreshold',
        (h) => h.pruneConfidenceThreshold,
        (h, v) => h.pruneConfidenceThreshold = v,
      ),
    ],
  );

  htn.HtnPlanResult? get currentPlan => planner.currentPlan;
  htn.HtnPrimitiveTask? get activeStep => planner.activeStep;
  String get activeTaskName => planner.activeStep?.name ?? 'Idle';
  int get planLength => planner.currentPlan?.steps.length ?? 0;
  int get remainingSteps => planner.currentPlan == null
      ? 0
      : math.max(
          0,
          planner.currentPlan!.steps.length - planner.currentStepIndex,
        );
  int get replanCount => planner.replanCount;
  int get factCount => blackboard.factCount;
  htn.HtnExecStatus get lastStatus => planner.lastStatus;

  void setFact(
    String key,
    Object? value, {
    double confidence = 1.0,
    double halfLifeSeconds = 0.0,
    String? sourceTag,
  }) {
    blackboard.setFact(
      key,
      value,
      confidence: confidence,
      halfLifeSeconds: halfLifeSeconds,
      sourceTag: sourceTag,
    );
  }

  void setDomain(htn.HtnDomain nextDomain) {
    domain = nextDomain;
    planner.reset();
  }

  htn.HtnPlanResult replanNow() {
    final d = domain;
    if (d == null) {
      return const htn.HtnPlanResult(
        steps: [],
        decomposedTrace: [],
        found: false,
        totalUtilityScore: 0.0,
      );
    }
    return planner.buildPlan(d, blackboard);
  }

  htn.HtnExecStatus stepPlanner(double dt) {
    final d = domain;
    if (d == null) {
      blackboard.tickMemory(dt);
      return htn.HtnExecStatus.succeeded;
    }
    if (!autoReplanWhenIdle && planner.currentPlan == null) {
      blackboard.tickMemory(dt);
      return htn.HtnExecStatus.succeeded;
    }
    return planner.tickRuntime(d, blackboard, dt);
  }

  @override
  void update() {
    if (paused) return;
    stepPlanner(time.deltaTime);
  }
}

/// Persistent UI interaction state for [HtnDebuggerUI.render].
final class HtnDebuggerUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` HTN plan decomposition, method trace & memory monitor (E75-2).
final class HtnDebuggerUI {
  static bool _drawButton(
    VoxUiContext ui,
    HtnDebuggerUiState state,
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
    HtnPlannerComponent htnComp, {
    HtnDebuggerUiState? state,
    String title = 'HTN AI Planner',
    double x = 20.0,
    double y = 20.0,
    double width = 380.0,
    double height = 240.0,
  }) {
    final uiState = state ?? HtnDebuggerUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final trace = htnComp.currentPlan?.decomposedTrace.join(' -> ') ?? 'None';

    ui.labelValue(
      'Active / Left',
      '${htnComp.activeTaskName} (${htnComp.remainingSteps}/${htnComp.planLength})',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue('Trace', trace, valueColor: VoxColor.green);
    ui.labelValue(
      'Facts / Replans',
      '${htnComp.factCount} facts / ${htnComp.replanCount} replans',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Exec Status',
      '${htnComp.lastStatus.name.toUpperCase()} (${htnComp.paused ? "PAUSED" : "RUN"})',
      valueColor: htnComp.lastStatus == htn.HtnExecStatus.failed
          ? VoxColor.red
          : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final replanRect = VoxRect(x + pad, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'htn_replan', 'Replan', replanRect)) {
      if (htnComp.domain != null) {
        htnComp.planner.tickRuntime(
          htnComp.domain!,
          htnComp.blackboard,
          0.0,
          forceReplan: true,
        );
      }
    }

    final stepRect = VoxRect(replanRect.right + 8.0, barY, 68.0, 22.0);
    if (_drawButton(ui, uiState, 'htn_step', 'Step', stepRect)) {
      htnComp.stepPlanner(0.05);
    }

    final decayRect = VoxRect(stepRect.right + 8.0, barY, 86.0, 22.0);
    if (_drawButton(ui, uiState, 'htn_decay', 'Decay +1s', decayRect)) {
      htnComp.blackboard.tickMemory(1.0);
    }

    final pauseRect = VoxRect(decayRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'htn_pause',
      htnComp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      htnComp.paused = !htnComp.paused;
    }

    ui.endWindow();
  }
}
