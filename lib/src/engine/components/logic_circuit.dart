part of '../../engine.dart';

/// Deterministic discrete-tick digital logic circuit solver & lamp sync component (`voxcircuit`) (E66-2).
final class LogicCircuitComponent extends Behaviour {
  double tickHz;
  bool paused;
  bool autoSyncLinkedVisuals;

  final circuit.CircuitGraphSolver solver = circuit.CircuitGraphSolver();
  final Map<
    String,
    ({
      GameObject target,
      LinearColor onColor,
      LinearColor offColor,
      double onIntensity,
    })
  >
  _lampBindings = {};
  double _tickAccumulator = 0.0;

  LogicCircuitComponent({
    this.tickHz = 20.0,
    this.paused = false,
    this.autoSyncLinkedVisuals = true,
  });

  static final spec = ComponentSpec<LogicCircuitComponent>(
    'LogicCircuitComponent',
    LogicCircuitComponent.new,
    [
      Field.number('tickHz', (c) => c.tickHz, (c, v) => c.tickHz = v),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
      Field.boolean(
        'autoSyncLinkedVisuals',
        (c) => c.autoSyncLinkedVisuals,
        (c, v) => c.autoSyncLinkedVisuals = v,
      ),
    ],
  );

  int get tickCount => solver.tickCount;
  int get gateCount => solver.gateCount;
  int get wireCount => solver.wireCount;
  int get activeHighGates => solver.activeHighGates;

  void addGate(circuit.CircuitGateDef def) => solver.addGate(def);

  void connect(
    String fromGateId,
    int fromPinIndex,
    String toGateId,
    int toPinIndex, {
    String? wireId,
    int delayTicks = 0,
  }) {
    solver.connect(
      fromGateId,
      fromPinIndex,
      toGateId,
      toPinIndex,
      wireId: wireId,
      delayTicks: delayTicks,
    );
  }

  void setInput(String gateId, bool value, {int busValue = 0}) {
    solver.setInput(gateId, value, busValue: busValue);
    if (autoSyncLinkedVisuals) _syncVisuals();
  }

  bool toggleInput(String gateId) {
    final res = solver.toggleInput(gateId);
    if (autoSyncLinkedVisuals) _syncVisuals();
    return res;
  }

  bool readOutput(String gateId, {int pinIndex = 0}) =>
      solver.readOutput(gateId, pinIndex: pinIndex);

  int readBusOutput(String gateId, {int pinIndex = 0}) =>
      solver.readBusOutput(gateId, pinIndex: pinIndex);

  void bindLampObject(
    String gateId,
    GameObject target, {
    LinearColor onColor = const LinearColor(0.2, 1.0, 0.45),
    LinearColor offColor = const LinearColor(0.14, 0.14, 0.18),
    double onIntensity = 2.5,
  }) {
    _lampBindings[gateId] = (
      target: target,
      onColor: onColor,
      offColor: offColor,
      onIntensity: onIntensity,
    );
    if (autoSyncLinkedVisuals) _syncVisuals();
  }

  void stepFixedTicks([int ticks = 1]) {
    if (ticks <= 0) return;
    solver.stepTicks(ticks);
    if (autoSyncLinkedVisuals) _syncVisuals();
  }

  int settleCombinational({int maxTicks = 32}) {
    final taken = solver.settleCombinational(maxTicks: maxTicks);
    if (autoSyncLinkedVisuals) _syncVisuals();
    return taken;
  }

  void _syncVisuals() {
    for (final entry in _lampBindings.entries) {
      final isHigh = solver.readOutput(entry.key);
      final b = entry.value;
      final c = isHigh ? b.onColor : b.offColor;
      b.target.getComponent<MeshRenderer>()?.setTint(c);
      final light = b.target.getComponent<Light>();
      if (light != null) {
        light.color = c;
        light.intensity = isHigh ? b.onIntensity : 0.0;
      }
    }
  }

  @override
  void update() {
    if (paused || tickHz <= 0.0 || time.deltaTime <= 0.0) return;
    _tickAccumulator += time.deltaTime * tickHz;
    final steps = (_tickAccumulator + 1e-9).floor();
    if (steps > 0) {
      _tickAccumulator = math.max(0.0, _tickAccumulator - steps);
      solver.stepTicks(math.min(steps, 64));
      if (autoSyncLinkedVisuals) _syncVisuals();
    }
  }
}

/// Persistent UI interaction state for [CircuitDebuggerUI.render].
final class CircuitDebuggerUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` digital logic probe, tick counter & step debugger (E66-2).
final class CircuitDebuggerUI {
  static bool _drawButton(
    VoxUiContext ui,
    CircuitDebuggerUiState state,
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
    LogicCircuitComponent circuitComp, {
    CircuitDebuggerUiState? state,
    String title = 'Logic Circuit',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? CircuitDebuggerUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Gates / Wires',
      '${circuitComp.gateCount} / ${circuitComp.wireCount}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Ticks / Clock',
      '${circuitComp.tickCount} / ${circuitComp.tickHz.toStringAsFixed(0)} Hz',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'High Signals',
      '${circuitComp.activeHighGates} / ${circuitComp.gateCount}',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'State',
      circuitComp.paused ? 'PAUSED' : 'RUNNING',
      valueColor: circuitComp.paused ? VoxColor.red : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final step1Rect = VoxRect(x + pad, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'cir_step1', 'Step +1', step1Rect)) {
      circuitComp.stepFixedTicks(1);
    }

    final step4Rect = VoxRect(step1Rect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'cir_step4', 'Step +4', step4Rect)) {
      circuitComp.stepFixedTicks(4);
    }

    final pauseRect = VoxRect(step4Rect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'cir_pause',
      circuitComp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      circuitComp.paused = !circuitComp.paused;
    }

    ui.endWindow();
  }
}
