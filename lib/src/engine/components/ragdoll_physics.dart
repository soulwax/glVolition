part of '../../engine.dart';

/// Articulated XPBD ragdoll simulation, active balance PD motors & hit-reaction flinching (`voxragdoll`) (E64-2).
final class ArticulatedRagdollComponent extends Behaviour {
  double floorY;
  double gravityY;
  double activeBalanceStrength;
  double flinchRecoveryRate;
  bool isLimp;
  int substeps;
  double floorFriction;

  ragdoll.RagdollSkeletonDef? _skeletonDef;
  ragdoll.RagdollSolver? _solver;
  ragdoll.RagdollPoseMatcher? _matcher;
  final Map<String, GameObject> _limbBindings = {};
  final Map<String, ragdoll.RagdollQuat> targetLocalRotations = {};

  ArticulatedRagdollComponent({
    this.floorY = 0.0,
    this.gravityY = -9.81,
    this.activeBalanceStrength = 0.85,
    this.flinchRecoveryRate = 2.0,
    this.isLimp = false,
    this.substeps = 6,
    this.floorFriction = 0.65,
    ragdoll.RagdollSkeletonDef? skeleton,
  }) : _skeletonDef = skeleton;

  static final spec = ComponentSpec<ArticulatedRagdollComponent>(
    'ArticulatedRagdollComponent',
    ArticulatedRagdollComponent.new,
    [
      Field.number('floorY', (r) => r.floorY, (r, v) => r.floorY = v),
      Field.number('gravityY', (r) => r.gravityY, (r, v) => r.gravityY = v),
      Field.number(
        'activeBalanceStrength',
        (r) => r.activeBalanceStrength,
        (r, v) => r.activeBalanceStrength = v,
      ),
      Field.number(
        'flinchRecoveryRate',
        (r) => r.flinchRecoveryRate,
        (r, v) => r.flinchRecoveryRate = v,
      ),
      Field.boolean('isLimp', (r) => r.isLimp, (r, v) => r.isLimp = v),
      Field.integer('substeps', (r) => r.substeps, (r, v) => r.substeps = v),
      Field.number('floorFriction', (r) => r.floorFriction, (r, v) => r.floorFriction = v),
    ],
  );

  ragdoll.RagdollSkeletonDef get skeleton =>
      _skeletonDef ??= ragdoll.RagdollSkeletonDef.humanoid();

  ragdoll.RagdollSolver _ensureSolver() {
    final s = _solver ??= ragdoll.RagdollSolver(
      skeleton: skeleton,
      rootOrigin: isAttached
          ? ragdoll.RagdollVec3(transform.position.x, transform.position.y, transform.position.z)
          : ragdoll.RagdollVec3.zero,
      gravity: ragdoll.RagdollVec3(0.0, gravityY, 0.0),
      floorY: floorY,
      floorFriction: floorFriction,
      substeps: math.max(1, substeps),
    );
    s
      ..floorY = floorY
      ..gravity = ragdoll.RagdollVec3(0.0, gravityY, 0.0)
      ..floorFriction = floorFriction
      ..substeps = math.max(1, substeps);
    return s;
  }

  ragdoll.RagdollPoseMatcher _ensureMatcher() {
    final m = _matcher ??= ragdoll.RagdollPoseMatcher(
      mode: isLimp ? ragdoll.RagdollMode.fullLimp : ragdoll.RagdollMode.activeBalanced,
      activeBalanceStrength: activeBalanceStrength,
      flinchRecoveryRate: flinchRecoveryRate,
    );
    m
      ..activeBalanceStrength = activeBalanceStrength
      ..flinchRecoveryRate = flinchRecoveryRate;
    if (isLimp && m.mode != ragdoll.RagdollMode.fullLimp) {
      m.goLimp();
    } else if (!isLimp && m.mode == ragdoll.RagdollMode.fullLimp) {
      m.restoreActiveBalance();
    }
    return m;
  }

  ragdoll.RagdollSolver get solver => _ensureSolver();
  ragdoll.RagdollPoseMatcher get matcher => _ensureMatcher();
  ragdoll.RagdollMode get mode => _ensureMatcher().mode;
  double get motorBlend => _ensureMatcher().currentMotorBlend;
  double get totalKineticEnergy => _ensureSolver().totalKineticEnergy;
  double get maxJointViolationMeters => _ensureSolver().maxJointViolationMeters;
  int get activeContactCount => _ensureSolver().activeContactCount;
  double get lowestLimbY => _ensureSolver().lowestLimbY;

  Vec3 get centerOfMass {
    final c = _ensureSolver().centerOfMass;
    return Vec3(c.x, c.y, c.z);
  }

  void bindLimb(String limbId, GameObject limbObject) {
    _limbBindings[limbId] = limbObject;
  }

  /// Creates visual/collider primitive [GameObject]s bound to each skeleton limb.
  Map<String, GameObject> spawnDebugLimbs({
    LinearColor limbTint = const LinearColor(0.28, 0.65, 0.85),
  }) {
    if (!isAttached) return const {};
    final s = _ensureSolver();
    for (final def in skeleton.limbs) {
      if (_limbBindings.containsKey(def.id)) continue;
      final body = s.body(def.id)!;
      final go = scene.createGameObject(
        '${gameObject.name}_${def.id}',
        position: Vec3(body.position.x, body.position.y, body.position.z),
        components: [
          MeshRenderer(meshData: Primitives.cube(size: 1.0), tintColor: limbTint),
        ],
      );
      go.transform.localStretch = Vec3(def.radius * 2.0, def.length, def.radius * 2.0);
      _limbBindings[def.id] = go;
    }
    return Map.unmodifiable(_limbBindings);
  }

  void pinLimb(String limbId, bool pinned) => _ensureSolver().pinLimb(limbId, pinned);

  void goLimp() {
    isLimp = true;
    _ensureMatcher().goLimp();
  }

  void standUp() {
    isLimp = false;
    _ensureMatcher().restoreActiveBalance();
  }

  void resetPose({Vec3? rootPosition}) {
    final origin = rootPosition ?? (isAttached ? transform.position : Vec3.zero);
    _ensureSolver().resetPose(
      rootOrigin: ragdoll.RagdollVec3(origin.x, origin.y, origin.z),
    );
    _syncBindings();
  }

  void applyHitImpulse(
    String limbId,
    Vec3 impulse, {
    Vec3? localHitOffset,
    bool triggerFlinch = true,
    double flinchStrength = 0.82,
    double durationSeconds = 0.65,
  }) {
    final s = _ensureSolver();
    final imp = ragdoll.RagdollVec3(impulse.x, impulse.y, impulse.z);
    final off = localHitOffset != null
        ? ragdoll.RagdollVec3(localHitOffset.x, localHitOffset.y, localHitOffset.z)
        : null;
    if (triggerFlinch && !isLimp) {
      _ensureMatcher().triggerHitReaction(
        s,
        limbId,
        imp,
        localHitOffset: off,
        flinchStrength: flinchStrength,
        durationSeconds: durationSeconds,
      );
    } else {
      s.applyImpulse(limbId, imp, localHitOffset: off);
    }
  }

  void stepSimulation(double dt) {
    if (dt <= 0.0) return;
    _ensureMatcher().step(
      _ensureSolver(),
      dt,
      targetLocalRotations: targetLocalRotations.isEmpty ? null : targetLocalRotations,
    );
    _syncBindings();
  }

  void _syncBindings() {
    final s = _ensureSolver();
    for (final entry in _limbBindings.entries) {
      final b = s.body(entry.key);
      if (b == null) continue;
      entry.value.transform.position = Vec3(b.position.x, b.position.y, b.position.z);
      entry.value.transform.rotation = Quat(
        b.rotation.x,
        b.rotation.y,
        b.rotation.z,
        b.rotation.w,
      );
    }
  }

  @override
  void fixedUpdate() {
    stepSimulation(time.fixedDeltaTime);
  }
}

/// Persistent UI interaction state for [RagdollInspectorUI.render].
final class RagdollInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` articulated ragdoll telemetry, flinch trigger & limp controls (E64-2).
final class RagdollInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    RagdollInspectorUiState state,
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
    if (inp.wasMouseReleased && state.activeButtonId == id) state.activeButtonId = null;

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(rect.x, rect.y, rect.width, rect.height, bg, cornerRadius: ui.style.frameRounding);
    dl.addRectOutline(rect.x, rect.y, rect.width, rect.height, ui.style.windowBorder, cornerRadius: ui.style.frameRounding);
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
    ArticulatedRagdollComponent rag, {
    RagdollInspectorUiState? state,
    String title = 'Articulated Ragdoll',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? RagdollInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Mode / Blend',
      '${rag.mode.name} / ${(rag.motorBlend * 100).toStringAsFixed(0)}%',
      valueColor: rag.isLimp ? VoxColor.red : VoxColor.cyan,
    );
    ui.labelValue(
      'Limbs / Contacts',
      '${rag.skeleton.limbs.length} / ${rag.activeContactCount}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Kinetic Energy',
      '${rag.totalKineticEnergy.toStringAsFixed(1)} J',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Joint Error',
      '${(rag.maxJointViolationMeters * 1000.0).toStringAsFixed(2)} mm',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final punchRect = VoxRect(x + pad, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'rag_punch', 'Punch Torso', punchRect)) {
      rag.applyHitImpulse(
        'torso',
        const Vec3(140.0, 20.0, 60.0),
        localHitOffset: const Vec3(0.0, 0.2, 0.0),
      );
    }

    final limpRect = VoxRect(punchRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'rag_limp',
      rag.isLimp ? 'Stand Up' : 'Go Limp',
      limpRect,
    )) {
      if (rag.isLimp) {
        rag.standUp();
      } else {
        rag.goLimp();
      }
    }

    final resetRect = VoxRect(limpRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'rag_reset', 'Reset', resetRect)) {
      rag.resetPose();
    }

    ui.endWindow();
  }
}
