part of '../../engine.dart';

/// Procedural foot-stepping IK locomotion, support gating & slope adaptation (`voxgait`) (E77-2).
final class ProceduralGaitComponent extends Behaviour {
  gait.GaitPreset preset;
  double stanceDutyFactor;
  double baseStepFrequencyHz;
  double stepHeightScale;
  double pelvisBobAmplitude;
  double velocityLeadTime;
  double slopeAdaptationRate;
  bool paused;
  bool applyPelvisBobToTarget;
  bool autoApplySlopeTilt;
  bool autoSampleSceneTerrain;

  GameObject? pelvisTarget;
  Vec3 pelvisBaseLocalPosition = Vec3.zero;
  Vec3? explicitVelocity;
  gait.GaitTerrainSampler? terrainSampler;

  late gait.ProceduralGaitSolver solver;
  gait.GaitPreset _builtPreset;
  gait.GaitPoseSnapshot? _lastSnapshot;
  Vec3? _prevWorldPos;
  bool _pelvisBaseCaptured = false;

  final Map<String, GameObject> _footTargets = {};
  final Map<String, TwoBoneIkComponent> _ikTargets = {};

  ProceduralGaitComponent({
    this.preset = gait.GaitPreset.biped,
    this.stanceDutyFactor = 0.60,
    this.baseStepFrequencyHz = 1.45,
    this.stepHeightScale = 1.0,
    this.pelvisBobAmplitude = 0.055,
    this.velocityLeadTime = 0.18,
    this.slopeAdaptationRate = 10.0,
    this.paused = false,
    this.applyPelvisBobToTarget = true,
    this.autoApplySlopeTilt = false,
    this.autoSampleSceneTerrain = true,
    this.pelvisTarget,
    this.explicitVelocity,
    this.terrainSampler,
  }) : _builtPreset = preset {
    solver = gait.ProceduralGaitSolver(
      cycle: _buildCycleForPreset(preset),
      pelvisBobAmplitude: pelvisBobAmplitude,
      velocityLeadTime: velocityLeadTime,
      slopeAdaptationRate: slopeAdaptationRate,
      stepHeightScale: stepHeightScale,
    );
  }

  static final spec = ComponentSpec<ProceduralGaitComponent>(
    'ProceduralGaitComponent',
    ProceduralGaitComponent.new,
    [
      Field.enumValue<ProceduralGaitComponent, gait.GaitPreset>(
        'preset',
        gait.GaitPreset.values,
        (g) => g.preset,
        (g, v) => g.setPreset(v),
      ),
      Field.number(
        'stanceDutyFactor',
        (g) => g.stanceDutyFactor,
        (g, v) => g.stanceDutyFactor = v,
      ),
      Field.number(
        'baseStepFrequencyHz',
        (g) => g.baseStepFrequencyHz,
        (g, v) => g.baseStepFrequencyHz = v,
      ),
      Field.number(
        'stepHeightScale',
        (g) => g.stepHeightScale,
        (g, v) => g.stepHeightScale = v,
      ),
      Field.number(
        'pelvisBobAmplitude',
        (g) => g.pelvisBobAmplitude,
        (g, v) => g.pelvisBobAmplitude = v,
      ),
      Field.number(
        'velocityLeadTime',
        (g) => g.velocityLeadTime,
        (g, v) => g.velocityLeadTime = v,
      ),
      Field.number(
        'slopeAdaptationRate',
        (g) => g.slopeAdaptationRate,
        (g, v) => g.slopeAdaptationRate = v,
      ),
      Field.boolean('paused', (g) => g.paused, (g, v) => g.paused = v),
      Field.boolean(
        'applyPelvisBobToTarget',
        (g) => g.applyPelvisBobToTarget,
        (g, v) => g.applyPelvisBobToTarget = v,
      ),
      Field.boolean(
        'autoApplySlopeTilt',
        (g) => g.autoApplySlopeTilt,
        (g, v) => g.autoApplySlopeTilt = v,
      ),
    ],
  );

  gait.GaitCycle _buildCycleForPreset(gait.GaitPreset p) {
    switch (p) {
      case gait.GaitPreset.biped:
        return gait.GaitCycle.biped(
          stanceDutyFactor: stanceDutyFactor,
          baseStepFrequencyHz: baseStepFrequencyHz,
        );
      case gait.GaitPreset.quadrupedTrot:
        return gait.GaitCycle.quadrupedTrot(
          stanceDutyFactor: stanceDutyFactor,
          baseStepFrequencyHz: baseStepFrequencyHz,
        );
      case gait.GaitPreset.quadrupedWalk:
        return gait.GaitCycle.quadrupedWalk(
          stanceDutyFactor: stanceDutyFactor,
          baseStepFrequencyHz: baseStepFrequencyHz,
        );
      case gait.GaitPreset.hexapodTripod:
        return gait.GaitCycle.hexapodTripod(
          stanceDutyFactor: stanceDutyFactor,
          baseStepFrequencyHz: baseStepFrequencyHz,
        );
    }
  }

  void setPreset(gait.GaitPreset nextPreset) {
    preset = nextPreset;
    if (_builtPreset != nextPreset) {
      _builtPreset = nextPreset;
      solver.setCycle(_buildCycleForPreset(nextPreset));
    }
  }

  void cycleNextPreset() {
    final values = gait.GaitPreset.values;
    final nextIdx = (values.indexOf(preset) + 1) % values.length;
    setPreset(values[nextIdx]);
  }

  void bindFootTarget(String legId, GameObject targetGo) {
    _footTargets[legId] = targetGo;
  }

  void bindTwoBoneIk(String legId, TwoBoneIkComponent ikComponent) {
    _ikTargets[legId] = ikComponent;
  }

  gait.GaitPoseSnapshot? get lastSnapshot => _lastSnapshot;
  int get groundedFootCount => _lastSnapshot?.groundedCount ?? 0;
  int get steppingFootCount => _lastSnapshot?.steppingCount ?? 0;
  double get pelvisVerticalOffset => _lastSnapshot?.pelvisVerticalOffset ?? 0.0;

  gait.GaitFootTarget? footTarget(String legId) =>
      _lastSnapshot?.footById(legId);

  gait.GaitTerrainSample _defaultTerrainSample(double worldX, double worldZ) {
    final custom = terrainSampler;
    if (custom != null) return custom(worldX, worldZ);

    if (autoSampleSceneTerrain && isAttached && scene.isLoaded) {
      final terrains = scene.findObjectsOfType<TerrainComponent>();
      if (terrains.isNotEmpty) {
        final terrain = terrains.first;
        final h = terrain.sampleHeight(worldX, worldZ);
        final n = terrain.sampleNormal(worldX, worldZ);
        return gait.GaitTerrainSample(
          groundY: h,
          normal: gait.GaitVec3(n.x, n.y, n.z),
        );
      }
    }
    return gait.GaitTerrainSample.flatZero;
  }

  /// Advances procedural gait state and syncs bound foot targets / IK effectors.
  gait.GaitPoseSnapshot stepGait(double dt) {
    if (_builtPreset != preset) {
      _builtPreset = preset;
      solver.setCycle(_buildCycleForPreset(preset));
    }

    solver.cycle.stanceDutyFactor = stanceDutyFactor
        .clamp(0.15, 0.92)
        .toDouble();
    solver.cycle.baseStepFrequencyHz = math.max(0.1, baseStepFrequencyHz);
    solver.stepHeightScale = math.max(0.0, stepHeightScale);
    solver.pelvisBobAmplitude = math.max(0.0, pelvisBobAmplitude);
    solver.velocityLeadTime = math.max(0.0, velocityLeadTime);
    solver.slopeAdaptationRate = math.max(0.5, slopeAdaptationRate);

    final worldPos = isAttached ? transform.position : Vec3.zero;
    final fwd = isAttached ? transform.forward : kForward;
    final right = isAttached ? transform.right : kRight;

    Vec3 vel;
    if (explicitVelocity != null) {
      vel = explicitVelocity!;
    } else if (_prevWorldPos != null && dt > 1e-5) {
      vel = (worldPos - _prevWorldPos!) * (1.0 / dt);
    } else {
      vel = Vec3.zero;
    }
    _prevWorldPos = worldPos;

    final snap = solver.step(
      bodyWorldPos: gait.GaitVec3(worldPos.x, worldPos.y, worldPos.z),
      bodyForward: gait.GaitVec3(fwd.x, fwd.y, fwd.z),
      bodyRight: gait.GaitVec3(right.x, right.y, right.z),
      velocity: gait.GaitVec3(vel.x, vel.y, vel.z),
      dt: dt,
      sampleTerrain: _defaultTerrainSample,
    );
    _lastSnapshot = snap;

    for (final foot in snap.feet) {
      final wp = Vec3(
        foot.worldPosition.x,
        foot.worldPosition.y,
        foot.worldPosition.z,
      );
      final targetGo = _footTargets[foot.legId];
      if (targetGo != null) {
        targetGo.transform.position = wp;
      }
      final ik = _ikTargets[foot.legId];
      if (ik != null) {
        ik.targetPosition = wp;
      }
    }

    final pelvis = pelvisTarget;
    if (pelvis != null && applyPelvisBobToTarget) {
      if (!_pelvisBaseCaptured) {
        pelvisBaseLocalPosition = pelvis.transform.localPosition;
        _pelvisBaseCaptured = true;
      }
      pelvis.transform.localPosition = Vec3(
        pelvisBaseLocalPosition.x,
        pelvisBaseLocalPosition.y + snap.pelvisVerticalOffset,
        pelvisBaseLocalPosition.z,
      );
    }

    if (autoApplySlopeTilt && isAttached) {
      final tiltRot =
          Quat.axisAngle(kRight, snap.bodyPitchRad) *
          Quat.axisAngle(kForward, snap.bodyRollRad);
      transform.localRotation = tiltRot.normalized;
    }

    return snap;
  }

  @override
  void update() {
    if (paused) return;
    stepGait(time.deltaTime);
  }
}

/// Persistent UI state for [GaitDebuggerUI.render].
final class GaitDebuggerUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` procedural gait phase, foot support & slope inspector (E77-2).
final class GaitDebuggerUI {
  static bool _drawButton(
    VoxUiContext ui,
    GaitDebuggerUiState state,
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
    ProceduralGaitComponent gaitComp, {
    GaitDebuggerUiState? state,
    String title = 'Procedural Gait Solver',
    double x = 20.0,
    double y = 20.0,
    double width = 395.0,
    double height = 250.0,
  }) {
    final uiState = state ?? GaitDebuggerUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final snap = gaitComp.lastSnapshot;
    ui.labelValue(
      'Preset / Freq',
      '${gaitComp.preset.name} | ${(snap?.activeFrequencyHz ?? 0.0).toStringAsFixed(2)} Hz',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Support / Bob',
      '${gaitComp.groundedFootCount}/${gaitComp.solver.cycle.legs.length} grounded | bob ${(gaitComp.pelvisVerticalOffset * 100.0).toStringAsFixed(1)} cm',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Slope Pitch/Roll',
      '${((snap?.bodyPitchRad ?? 0.0) * 180.0 / math.pi).toStringAsFixed(1)} deg / ${((snap?.bodyRollRad ?? 0.0) * 180.0 / math.pi).toStringAsFixed(1)} deg',
      valueColor: VoxColor.yellow,
    );
    final legSummary = snap == null
        ? 'No step sampled yet'
        : snap.feet
              .take(3)
              .map((f) => '${f.legId}:${f.isGrounded ? 'STN' : 'SWG'}')
              .join(' | ');
    ui.labelValue('Legs', legSummary, valueColor: VoxColor.lightGray);

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'gait_pause',
      gaitComp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      gaitComp.paused = !gaitComp.paused;
    }

    final stepRect = VoxRect(pauseRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'gait_step', 'Step 16ms', stepRect)) {
      gaitComp.stepGait(0.016);
    }

    final presetRect = VoxRect(stepRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'gait_preset', 'Next Gait', presetRect)) {
      gaitComp.cycleNextPreset();
    }

    final liftRect = VoxRect(presetRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'gait_lift', 'Lift +0.2', liftRect)) {
      gaitComp.stepHeightScale = (gaitComp.stepHeightScale + 0.2)
          .clamp(0.2, 2.5)
          .toDouble();
    }

    ui.endWindow();
  }
}
