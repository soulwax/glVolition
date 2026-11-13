part of '../../engine.dart';

/// Extended Position-Based Dynamics soft-body component backed by `voxverlet` (E94-2).
final class SoftBodyXpbdComponent extends Behaviour {
  double compliance;
  double volumeCompliance;
  double floorY;
  int substeps;
  bool paused;
  double halfExtent;

  late xpbd.VerletSoftBodySolver solver;
  Vec3 _initialCenter = Vec3.zero;

  SoftBodyXpbdComponent({
    this.compliance = 0.001,
    this.volumeCompliance = 0.0005,
    this.floorY = -1.0,
    this.substeps = 8,
    this.paused = false,
    this.halfExtent = 0.5,
  }) {
    resetRig();
  }

  static final spec = ComponentSpec<SoftBodyXpbdComponent>(
    'SoftBodyXpbdComponent',
    SoftBodyXpbdComponent.new,
    [
      Field.number(
        'compliance',
        (c) => c.compliance,
        (c, v) => c.compliance = v,
      ),
      Field.number(
        'volumeCompliance',
        (c) => c.volumeCompliance,
        (c, v) => c.volumeCompliance = v,
      ),
      Field.number('floorY', (c) => c.floorY, (c, v) => c.floorY = v),
      Field.integer('substeps', (c) => c.substeps, (c, v) => c.substeps = v),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
      Field.number(
        'halfExtent',
        (c) => c.halfExtent,
        (c, v) => c.halfExtent = v,
      ),
    ],
  );

  int get nodeCount => solver.nodes.length;
  double get totalConstraintError => solver.totalConstraintError();
  double get averageStrain => solver.averageStrain();

  Vec3 get centerOfMass {
    final c = solver.centerOfMass();
    return Vec3(c.x, c.y, c.z);
  }

  @override
  void awake() {
    _initialCenter = transform.position;
    resetRig();
  }

  /// Rebuilds the tetrahedral soft-body cube rig around its initial center.
  void resetRig() {
    solver = xpbd.VerletSoftBodySolver.createCubeRig(
      center: xpbd.VerletVec3(
        _initialCenter.x,
        _initialCenter.y,
        _initialCenter.z,
      ),
      halfExtent: math.max(0.05, halfExtent),
      distanceCompliance: math.max(0.0, compliance),
      volumeCompliance: math.max(0.0, volumeCompliance),
      floorY: floorY,
      substeps: math.max(1, substeps),
    );
    if (isAttached) {
      transform.position = centerOfMass;
    }
  }

  /// Advances the XPBD solver by [dt] seconds and syncs [transform.position].
  void stepPhysics(double dt) {
    solver
      ..floorY = floorY
      ..substeps = math.max(1, substeps);
    solver.step(dt);
    if (isAttached) {
      transform.position = centerOfMass;
    }
  }

  /// Applies a linear velocity impulse to all unpinned soft-body nodes.
  void applyImpulse(Vec3 impulse) {
    solver.applyImpulse(xpbd.VerletVec3(impulse.x, impulse.y, impulse.z));
  }

  @override
  void fixedUpdate() {
    if (paused) return;
    stepPhysics(time.fixedDeltaTime);
  }
}

/// Persistent UI state for [XpbdSolverInspectorUI.render].
final class SoftBodyXpbdUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` XPBD soft-body solver inspector (E94-2).
final class XpbdSolverInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    SoftBodyXpbdUiState state,
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
    SoftBodyXpbdComponent comp, {
    SoftBodyXpbdUiState? state,
    String title = 'XPBD Soft Body',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? SoftBodyXpbdUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final com = comp.centerOfMass;
    ui.labelValue(
      'Nodes / Substeps',
      '${comp.nodeCount} nodes | ${comp.substeps} substeps',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Error / Strain',
      'err ${comp.totalConstraintError.toStringAsFixed(4)} | strain ${comp.averageStrain.toStringAsFixed(4)}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Center of Mass',
      '(${com.x.toStringAsFixed(2)}, ${com.y.toStringAsFixed(2)}, ${com.z.toStringAsFixed(2)}) | floor ${comp.floorY.toStringAsFixed(1)}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Compliance / Status',
      'dist ${comp.compliance.toStringAsFixed(4)} | ${comp.paused ? 'Paused' : 'Active'}',
      valueColor: comp.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'xpbd_pause',
      comp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      comp.paused = !comp.paused;
    }

    final substepRect = VoxRect(pauseRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'xpbd_step', 'Substep +1', substepRect)) {
      comp.stepPhysics(0.016);
    }

    final dropRect = VoxRect(substepRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'xpbd_drop', 'Drop', dropRect)) {
      comp.applyImpulse(const Vec3(0.0, -2.5, 0.0));
    }

    final resetRect = VoxRect(dropRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'xpbd_reset', 'Reset', resetRect)) {
      comp.resetRig();
    }

    ui.endWindow();
  }
}
