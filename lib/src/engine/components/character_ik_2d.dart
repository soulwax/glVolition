part of '../../engine.dart';

/// Solver preset mode for [CharacterIk2DComponent].
enum IkSolver2DMode {
  twoBone,
  fabrik,
}

/// Analytic 2-bone limb IK, multi-link FABRIK chain & spring-bone secondary motion component (`voxik2d`) (E89-2).
final class CharacterIk2DComponent extends Behaviour {
  IkSolver2DMode mode;
  double upperBoneLength;
  double lowerBoneLength;
  double bendSign;
  double springStiffness;
  double springDamping;
  double targetX;
  double targetY;
  bool enableSpringTail;
  bool paused;

  GameObject? targetObject;
  List<double> fabrikLengths = const [1.0, 0.9, 0.8];

  ik2d.PlanarTwoBoneIkResult? lastTwoBoneResult;
  List<ik2d.IkVec2> solvedJoints = const [];
  late ik2d.SpringBoneChain springChain;

  CharacterIk2DComponent({
    this.mode = IkSolver2DMode.twoBone,
    this.upperBoneLength = 1.2,
    this.lowerBoneLength = 1.1,
    this.bendSign = 1.0,
    this.springStiffness = 16.0,
    this.springDamping = 0.88,
    this.targetX = 1.5,
    this.targetY = 0.0,
    this.enableSpringTail = true,
    this.paused = false,
    this.targetObject,
  }) {
    springChain = ik2d.SpringBoneChain.linear(
      root: ik2d.IkVec2.zero,
      boneCount: 3,
      boneLength: 0.45,
      stiffness: springStiffness,
      damping: springDamping,
    );
  }

  static final spec = ComponentSpec<CharacterIk2DComponent>(
    'CharacterIk2DComponent',
    CharacterIk2DComponent.new,
    [
      Field.enumValue<CharacterIk2DComponent, IkSolver2DMode>(
        'mode',
        IkSolver2DMode.values,
        (c) => c.mode,
        (c, v) => c.mode = v,
      ),
      Field.number(
        'upperBoneLength',
        (c) => c.upperBoneLength,
        (c, v) => c.upperBoneLength = v,
      ),
      Field.number(
        'lowerBoneLength',
        (c) => c.lowerBoneLength,
        (c, v) => c.lowerBoneLength = v,
      ),
      Field.number('bendSign', (c) => c.bendSign, (c, v) => c.bendSign = v),
      Field.number(
        'springStiffness',
        (c) => c.springStiffness,
        (c, v) => c.springStiffness = v,
      ),
      Field.number(
        'springDamping',
        (c) => c.springDamping,
        (c, v) => c.springDamping = v,
      ),
      Field.number('targetX', (c) => c.targetX, (c, v) => c.targetX = v),
      Field.number('targetY', (c) => c.targetY, (c, v) => c.targetY = v),
      Field.boolean(
        'enableSpringTail',
        (c) => c.enableSpringTail,
        (c, v) => c.enableSpringTail = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  void toggleMode() {
    mode = mode == IkSolver2DMode.twoBone ? IkSolver2DMode.fabrik : IkSolver2DMode.twoBone;
  }

  void flipBend() {
    bendSign = bendSign >= 0.0 ? -1.0 : 1.0;
  }

  /// Solves active 2D IK joints against target and steps the Verlet spring chain.
  void stepIk(double dt) {
    final rootVec = isAttached ? transform.position : Vec3.zero;
    final root2 = ik2d.IkVec2(rootVec.x, rootVec.y);
    final tgt = targetObject != null
        ? ik2d.IkVec2(targetObject!.transform.position.x, targetObject!.transform.position.y)
        : ik2d.IkVec2(targetX, targetY);

    if (mode == IkSolver2DMode.twoBone) {
      final res = ik2d.PlanarTwoBoneIkSolver.solve(
        root: root2,
        target: tgt,
        upperLength: upperBoneLength,
        lowerLength: lowerBoneLength,
        bendSign: bendSign,
      );
      lastTwoBoneResult = res;
      solvedJoints = [res.root, res.midJoint, res.endEffector];
    } else {
      solvedJoints = ik2d.FabrikChainSolver.solve(
        root: root2,
        target: tgt,
        lengths: fabrikLengths,
        initialJoints: solvedJoints.isNotEmpty ? solvedJoints : null,
      );
    }

    if (enableSpringTail && dt > 0.0) {
      springChain.stiffness = springStiffness;
      springChain.damping = springDamping;
      springChain.step(dt, rootPosition: root2);
    }
  }

  @override
  void update() {
    if (paused) return;
    stepIk(time.deltaTime);
  }
}

/// Persistent UI state for [IkSolverInspectorUI.render].
final class IkSolverInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` 2-bone IK, FABRIK & spring-bone inspector (E89-2).
final class IkSolverInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    IkSolverInspectorUiState state,
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
    CharacterIk2DComponent ik, {
    IkSolverInspectorUiState? state,
    String title = '2D IK & Spring Rig',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? IkSolverInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Solver / Bend',
      '${ik.mode.name} | bend ${ik.bendSign >= 0 ? '+1' : '-1'}',
      valueColor: VoxColor.cyan,
    );
    final endPt = ik.solvedJoints.isNotEmpty
        ? '(${ik.solvedJoints.last.x.toStringAsFixed(2)}, ${ik.solvedJoints.last.y.toStringAsFixed(2)})'
        : 'unsolved';
    ui.labelValue(
      'Joints / Tip',
      '${ik.solvedJoints.length} pts -> $endPt',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Spring Tail',
      '${ik.springChain.nodes.length} nodes | k=${ik.springStiffness.toStringAsFixed(1)}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Target / Status',
      '(${ik.targetX.toStringAsFixed(1)}, ${ik.targetY.toStringAsFixed(1)}) | ${ik.paused ? 'Paused' : 'Active'}',
      valueColor: ik.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final modeRect = VoxRect(x + pad, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'ik_mode', 'Mode', modeRect)) {
      ik.toggleMode();
      ik.stepIk(0.0);
    }

    final bendRect = VoxRect(modeRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'ik_bend', 'Flip Bend', bendRect)) {
      ik.flipBend();
      ik.stepIk(0.0);
    }

    final pauseRect = VoxRect(bendRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'ik_pause', ik.paused ? 'Resume' : 'Pause', pauseRect)) {
      ik.paused = !ik.paused;
    }

    final stepRect = VoxRect(pauseRect.right + 8.0, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'ik_step', 'Step 50ms', stepRect)) {
      ik.stepIk(0.05);
    }

    ui.endWindow();
  }
}
