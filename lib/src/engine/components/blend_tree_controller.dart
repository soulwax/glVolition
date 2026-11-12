part of '../../engine.dart';

/// Animation blendspace, sprite-sheet clip sampler & root-motion state machine controller (`voxblend`) (E84-2).
final class BlendTreeControllerComponent extends Behaviour {
  double parameterX;
  double parameterY;
  double speedScale;
  bool applyRootMotion;
  bool paused;

  blend.BlendSpace1D? blendSpace1D;
  blend.BlendSpace2D? blendSpace2D;
  late blend.StateBlendMachine stateMachine;

  blend.StateBlendSnapshot? _lastSnapshot;
  blend.BlendSpaceResult? _lastBlendResult;
  Vec3 _lastRootMotionDelta = Vec3.zero;

  BlendTreeControllerComponent({
    this.parameterX = 0.0,
    this.parameterY = 0.0,
    this.speedScale = 1.0,
    this.applyRootMotion = true,
    this.paused = false,
    this.blendSpace1D,
    this.blendSpace2D,
    blend.StateBlendMachine? stateMachine,
  }) {
    if (stateMachine != null) {
      this.stateMachine = stateMachine;
    } else {
      const idleClip = blend.MotionClip(
        name: 'idle',
        durationSeconds: 1.0,
        frameCount: 4,
        rootVelocity: blend.BlendVec3.zero,
      );
      const runClip = blend.MotionClip(
        name: 'run',
        durationSeconds: 0.6,
        frameCount: 8,
        rootVelocity: blend.BlendVec3(0.0, 0.0, 5.0),
      );
      const jumpClip = blend.MotionClip(
        name: 'jump',
        durationSeconds: 0.4,
        frameCount: 4,
        loop: false,
        rootVelocity: blend.BlendVec3(0.0, 4.0, 2.0),
      );

      blendSpace1D ??= blend.BlendSpace1D(const [
        blend.BlendSample1D(clip: idleClip, position: 0.0),
        blend.BlendSample1D(clip: runClip, position: 5.0),
      ]);

      this.stateMachine = blend.StateBlendMachine(
        states: const [
          blend.BlendStateDef(name: 'Idle', clip: idleClip),
          blend.BlendStateDef(name: 'Run', clip: runClip),
          blend.BlendStateDef(name: 'Jump', clip: jumpClip),
        ],
        initialState: 'Idle',
        rules: [
          blend.BlendTransitionRule(
            fromState: 'Idle',
            toState: 'Run',
            crossfadeDuration: 0.2,
            condition: (p, _) => (p['speed'] ?? 0.0) > 0.5,
          ),
          blend.BlendTransitionRule(
            fromState: 'Run',
            toState: 'Idle',
            crossfadeDuration: 0.2,
            condition: (p, _) => (p['speed'] ?? 0.0) <= 0.5,
          ),
          blend.BlendTransitionRule(
            fromState: '*',
            toState: 'Jump',
            crossfadeDuration: 0.1,
            condition: (_, t) => t.contains('jump'),
          ),
          blend.BlendTransitionRule(
            fromState: 'Jump',
            toState: 'Idle',
            crossfadeDuration: 0.15,
            exitTimeNormalized: 0.9,
          ),
        ],
      );
    }
  }

  static final spec = ComponentSpec<BlendTreeControllerComponent>(
    'BlendTreeControllerComponent',
    BlendTreeControllerComponent.new,
    [
      Field.number('parameterX', (c) => c.parameterX, (c, v) => c.parameterX = v),
      Field.number('parameterY', (c) => c.parameterY, (c, v) => c.parameterY = v),
      Field.number('speedScale', (c) => c.speedScale, (c, v) => c.speedScale = v),
      Field.boolean(
        'applyRootMotion',
        (c) => c.applyRootMotion,
        (c, v) => c.applyRootMotion = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  String get activeStateName => stateMachine.currentStateName;
  String? get transitionFromState => _lastSnapshot?.transitionFromState;
  double get transitionAlpha => _lastSnapshot?.transitionAlpha ?? 1.0;
  int get activeFrameIndex => _lastSnapshot?.activeFrameIndex ?? 0;
  Vec3 get lastRootMotionDelta => _lastRootMotionDelta;
  blend.BlendSpaceResult? get lastBlendResult => _lastBlendResult;
  blend.StateBlendSnapshot? get lastSnapshot => _lastSnapshot;

  void setFloat(String name, double value) => stateMachine.setFloat(name, value);
  void trigger(String name) => stateMachine.setTrigger(name);

  void transitionTo(String stateName, {double crossfadeDuration = 0.2}) {
    stateMachine.forceTransition(stateName, crossfadeDuration: crossfadeDuration);
  }

  /// Evaluates blendspaces, steps the animation state machine, and applies root motion to Transform.
  blend.StateBlendSnapshot stepController(double dt) {
    final scaledDt = math.max(0.0, dt * speedScale);
    final scalarSpeed = math.sqrt(parameterX * parameterX + parameterY * parameterY);
    stateMachine.setFloat('speed', scalarSpeed);

    if (blendSpace2D != null) {
      _lastBlendResult = blendSpace2D!.evaluate(parameterX, parameterY);
    } else if (blendSpace1D != null) {
      _lastBlendResult = blendSpace1D!.evaluate(parameterY);
    }

    final snap = stateMachine.step(scaledDt);
    _lastSnapshot = snap;
    _lastRootMotionDelta = Vec3(
      snap.rootMotionDelta.x,
      snap.rootMotionDelta.y,
      snap.rootMotionDelta.z,
    );

    if (applyRootMotion && isAttached && _lastRootMotionDelta.lengthSquared > 1e-12) {
      transform.position = transform.position + _lastRootMotionDelta;
    }
    return snap;
  }

  @override
  void update() {
    if (paused) return;
    stepController(time.deltaTime);
  }
}

/// Persistent UI state for [BlendTreeInspectorUI.render].
final class BlendTreeInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` blendspace & root-motion state machine inspector (E84-2).
final class BlendTreeInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    BlendTreeInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked = hovered && state.activeButtonId == id && inp.wasMouseReleased;
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
    BlendTreeControllerComponent ctrl, {
    BlendTreeInspectorUiState? state,
    String title = 'Blend Tree FSM',
    double x = 20.0,
    double y = 20.0,
    double width = 405.0,
    double height = 245.0,
  }) {
    final uiState = state ?? BlendTreeInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final blendStr = ctrl.transitionFromState != null
        ? '${ctrl.transitionFromState} -> ${ctrl.activeStateName} (${(ctrl.transitionAlpha * 100).round()}%)'
        : ctrl.activeStateName;
    ui.labelValue(
      'State / Blend',
      blendStr,
      valueColor: ctrl.paused ? VoxColor.yellow : VoxColor.cyan,
    );
    ui.labelValue(
      'Param (X, Y) / Frame',
      '(${ctrl.parameterX.toStringAsFixed(1)}, ${ctrl.parameterY.toStringAsFixed(1)}) | f#${ctrl.activeFrameIndex}',
      valueColor: VoxColor.green,
    );
    final dom = ctrl.lastBlendResult?.dominantClipName ?? '-';
    ui.labelValue(
      'Dominant / Root Motion',
      '$dom | ${ctrl.applyRootMotion ? 'Root On' : 'In-Place'}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Delta',
      '(${ctrl.lastRootMotionDelta.x.toStringAsFixed(2)}, ${ctrl.lastRootMotionDelta.y.toStringAsFixed(2)}, ${ctrl.lastRootMotionDelta.z.toStringAsFixed(2)})',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'bt_pause', ctrl.paused ? 'Resume' : 'Pause', pauseRect)) {
      ctrl.paused = !ctrl.paused;
    }

    final jumpRect = VoxRect(pauseRect.right + 8.0, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'bt_jump', 'Jump', jumpRect)) {
      ctrl.trigger('jump');
    }

    final spdRect = VoxRect(jumpRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'bt_spd', 'Speed +1.5', spdRect)) {
      ctrl.parameterY += 1.5;
    }

    final stepRect = VoxRect(spdRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'bt_step', 'Step 50ms', stepRect)) {
      ctrl.stepController(0.05);
    }

    ui.endWindow();
  }
}
