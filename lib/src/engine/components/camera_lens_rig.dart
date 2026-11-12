part of '../../engine.dart';

/// Camera dolly spline rail, trauma shake & lens transition rig (`voxlens`) (E79-2).
final class CameraLensRigComponent extends Behaviour {
  double railSpeed;
  bool playing;
  bool loopRail;
  bool alignToTangent;
  double traumaDecayPerSecond;
  double maxShakeOffset;
  double baseFovDegrees;
  double baseExposure;
  double baseVignette;

  GameObject? lookAtTarget;
  Camera? targetCamera;
  PostProcessVolume? targetPostProcess;

  late lens.CameraDollyTrack dollyTrack;
  late lens.TraumaShakeGenerator shakeGenerator;
  late lens.LensTransitionBlender transitionBlender;

  double _normalizedProgress = 0.0;
  lens.CameraSplineSample? _lastSplineSample;
  lens.TraumaShakeSample _lastShakeSample = lens.TraumaShakeSample.zero;
  lens.LensTransitionState? _lastTransitionState;

  CameraLensRigComponent({
    this.railSpeed = 0.15,
    this.playing = true,
    this.loopRail = true,
    this.alignToTangent = true,
    this.traumaDecayPerSecond = 1.6,
    this.maxShakeOffset = 0.35,
    this.baseFovDegrees = 60.0,
    this.baseExposure = 1.0,
    this.baseVignette = 0.15,
    this.lookAtTarget,
    this.targetCamera,
    this.targetPostProcess,
    List<Vec3> waypoints = const [
      Vec3(0.0, 2.0, 10.0),
      Vec3(6.0, 3.0, 6.0),
      Vec3(0.0, 2.5, -8.0),
    ],
  }) {
    dollyTrack = lens.CameraDollyTrack(
      waypoints: waypoints.map((w) => lens.LensVec3(w.x, w.y, w.z)).toList(),
      closedLoop: loopRail,
    );
    shakeGenerator = lens.TraumaShakeGenerator(
      decayPerSecond: traumaDecayPerSecond,
      maxTranslationOffset: maxShakeOffset,
    );
    transitionBlender = lens.LensTransitionBlender(
      baseFovDeg: baseFovDegrees,
      baseExposure: baseExposure,
      baseVignette: baseVignette,
    );
  }

  static final spec = ComponentSpec<CameraLensRigComponent>(
    'CameraLensRigComponent',
    CameraLensRigComponent.new,
    [
      Field.number('railSpeed', (c) => c.railSpeed, (c, v) => c.railSpeed = v),
      Field.boolean('playing', (c) => c.playing, (c, v) => c.playing = v),
      Field.boolean('loopRail', (c) => c.loopRail, (c, v) => c.setLoopRail(v)),
      Field.boolean('alignToTangent', (c) => c.alignToTangent, (c, v) => c.alignToTangent = v),
      Field.number(
        'traumaDecayPerSecond',
        (c) => c.traumaDecayPerSecond,
        (c, v) => c.traumaDecayPerSecond = v,
      ),
      Field.number(
        'maxShakeOffset',
        (c) => c.maxShakeOffset,
        (c, v) => c.maxShakeOffset = v,
      ),
      Field.number(
        'baseFovDegrees',
        (c) => c.baseFovDegrees,
        (c, v) => c.baseFovDegrees = v,
      ),
      Field.number(
        'baseExposure',
        (c) => c.baseExposure,
        (c, v) => c.baseExposure = v,
      ),
      Field.number(
        'baseVignette',
        (c) => c.baseVignette,
        (c, v) => c.baseVignette = v,
      ),
    ],
  );

  double get progress => _normalizedProgress;
  set progress(double value) =>
      _normalizedProgress = loopRail ? (value % 1.0 + 1.0) % 1.0 : value.clamp(0.0, 1.0).toDouble();

  double get trauma => shakeGenerator.trauma;
  lens.CameraSplineSample? get lastSplineSample => _lastSplineSample;
  lens.TraumaShakeSample get lastShakeSample => _lastShakeSample;
  lens.LensTransitionState? get lastTransitionState => _lastTransitionState;

  void setWaypoints(List<Vec3> waypoints, {bool? closedLoop}) {
    if (closedLoop != null) loopRail = closedLoop;
    dollyTrack = lens.CameraDollyTrack(
      waypoints: waypoints.map((w) => lens.LensVec3(w.x, w.y, w.z)).toList(),
      closedLoop: loopRail,
    );
  }

  void setLoopRail(bool value) {
    if (loopRail == value) return;
    loopRail = value;
    dollyTrack = lens.CameraDollyTrack(
      waypoints: dollyTrack.waypoints,
      closedLoop: loopRail,
    );
  }

  void addTrauma(double amount) => shakeGenerator.addTrauma(amount);

  void startTransition({
    lens.LensTransitionEffect effect = lens.LensTransitionEffect.zoomPulse,
    double durationSeconds = 0.6,
    double fovBoostDeg = 14.0,
    double exposureShift = -0.35,
    double peakVignette = 0.6,
  }) {
    transitionBlender.startTransition(
      effect: effect,
      durationSeconds: durationSeconds,
      fovBoostDeg: fovBoostDeg,
      exposureShift: exposureShift,
      peakVignette: peakVignette,
    );
  }

  void resetRig() {
    _normalizedProgress = 0.0;
    shakeGenerator.reset();
    transitionBlender.cancel();
    stepRig(0.0);
  }

  void stepRig(double dt) {
    shakeGenerator.decayPerSecond = math.max(0.05, traumaDecayPerSecond);
    shakeGenerator.maxTranslationOffset = math.max(0.0, maxShakeOffset);
    transitionBlender.baseFovDeg = baseFovDegrees.clamp(15.0, 145.0).toDouble();
    transitionBlender.baseExposure = math.max(0.05, baseExposure);
    transitionBlender.baseVignette = baseVignette.clamp(0.0, 1.0).toDouble();

    if (playing && dt > 0.0 && dollyTrack.waypointCount >= 2) {
      progress = _normalizedProgress + railSpeed * dt;
    }

    final sample = dollyTrack.sampleAt(_normalizedProgress);
    _lastSplineSample = sample;

    final shake = shakeGenerator.step(dt);
    _lastShakeSample = shake;

    final trans = transitionBlender.evaluate(dt);
    _lastTransitionState = trans;

    if (isAttached) {
      final basePos = Vec3(sample.position.x, sample.position.y, sample.position.z);
      final shakeVec = Vec3(
        shake.translationOffset.x,
        shake.translationOffset.y,
        shake.translationOffset.z,
      );
      transform.position = basePos + shakeVec;

      final lookGo = lookAtTarget;
      if (lookGo != null) {
        transform.lookAt(lookGo.transform.position);
      } else if (alignToTangent && dollyTrack.waypointCount >= 2) {
        final tang = Vec3(sample.tangent.x, sample.tangent.y, sample.tangent.z);
        transform.lookAt(transform.position + tang);
      }

      if (shake.shakeStrength > 1e-6) {
        final shakeRot = Quat.axisAngle(kRight, shake.pitchRad) *
            Quat.axisAngle(kUp, shake.yawRad) *
            Quat.axisAngle(kForward, shake.rollRad);
        transform.localRotation = (transform.localRotation * shakeRot).normalized;
      }

      final cam = targetCamera ?? getComponent<Camera>();
      if (cam != null) {
        cam.fovYRadians = trans.fovDeg * math.pi / 180.0;
      }

      final pp = targetPostProcess ?? getComponent<PostProcessVolume>();
      if (pp != null) {
        pp.exposure = trans.exposure;
        pp.vignette = trans.vignetteIntensity;
      }
    }
  }

  @override
  void lateUpdate() {
    stepRig(time.deltaTime);
  }
}

/// Persistent UI state for [LensRigInspectorUI.render].
final class LensRigInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` dolly rail, trauma shake & transition inspector (E79-2).
final class LensRigInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    LensRigInspectorUiState state,
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
    CameraLensRigComponent rig, {
    LensRigInspectorUiState? state,
    String title = 'Camera Lens Rig',
    double x = 20.0,
    double y = 20.0,
    double width = 395.0,
    double height = 245.0,
  }) {
    final uiState = state ?? LensRigInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final spline = rig.lastSplineSample;
    final trans = rig.lastTransitionState;
    ui.labelValue(
      'Dolly Rail',
      't=${(rig.progress * 100.0).toStringAsFixed(1)}% | len ${(spline?.arcLength ?? 0.0).toStringAsFixed(1)}m',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Trauma Shake',
      'trauma ${(rig.trauma * 100.0).toStringAsFixed(0)}% | roll ${(rig.lastShakeSample.rollRad * 180.0 / math.pi).toStringAsFixed(1)} deg',
      valueColor: rig.trauma > 0.05 ? VoxColor.yellow : VoxColor.green,
    );
    ui.labelValue(
      'Lens / FOV',
      '${(trans?.fovDeg ?? rig.baseFovDegrees).toStringAsFixed(1)} deg | exp ${(trans?.exposure ?? rig.baseExposure).toStringAsFixed(2)}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Transition',
      trans != null && trans.isActive
          ? '${trans.effect.name} ${(trans.progress * 100.0).toStringAsFixed(0)}%'
          : 'Idle (vig ${(trans?.vignetteIntensity ?? rig.baseVignette).toStringAsFixed(2)})',
      valueColor: trans != null && trans.isActive ? VoxColor.cyan : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final playRect = VoxRect(x + pad, barY, 70.0, 22.0);
    if (_drawButton(ui, uiState, 'lens_play', rig.playing ? 'Pause' : 'Play', playRect)) {
      rig.playing = !rig.playing;
    }

    final shakeRect = VoxRect(playRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'lens_shake', 'Shake +0.5', shakeRect)) {
      rig.addTrauma(0.5);
    }

    final transRect = VoxRect(shakeRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'lens_trans', 'Zoom Pulse', transRect)) {
      rig.startTransition(effect: lens.LensTransitionEffect.zoomPulse);
    }

    final resetRect = VoxRect(transRect.right + 8.0, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'lens_reset', 'Reset', resetRect)) {
      rig.resetRig();
    }

    ui.endWindow();
  }
}
