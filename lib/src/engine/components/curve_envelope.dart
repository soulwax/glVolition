part of '../../engine.dart';

/// Piecewise Hermite animation curve, ADSR envelope & critical spring modulator (`voxcurve`) (E90-2).
final class CurveEnvelopeComponent extends Behaviour {
  double playbackTime;
  double timeScale;
  curve.CurveWrapMode wrapMode;
  double springTarget;
  double springSmoothTime;
  bool paused;

  late curve.KeyframeCurve keyframeCurve;
  late curve.AdsrEnvelope adsr;
  late curve.CriticalSpringDamper spring;

  double _currentCurveValue = 0.0;

  CurveEnvelopeComponent({
    this.playbackTime = 0.0,
    this.timeScale = 1.0,
    this.wrapMode = curve.CurveWrapMode.loop,
    this.springTarget = 1.0,
    this.springSmoothTime = 0.15,
    this.paused = false,
    curve.KeyframeCurve? keyframeCurve,
    curve.AdsrEnvelope? adsr,
    curve.CriticalSpringDamper? spring,
  }) {
    this.keyframeCurve = keyframeCurve ??
        curve.KeyframeCurve.smooth(
          const [(0.0, 0.0), (0.5, 1.0), (1.0, 0.2)],
          wrapMode: wrapMode,
        );
    this.adsr = adsr ?? curve.AdsrEnvelope();
    this.spring = spring ?? curve.CriticalSpringDamper(smoothTime: springSmoothTime);
    _currentCurveValue = this.keyframeCurve.evaluate(playbackTime);
  }

  static final spec = ComponentSpec<CurveEnvelopeComponent>(
    'CurveEnvelopeComponent',
    CurveEnvelopeComponent.new,
    [
      Field.number('playbackTime', (c) => c.playbackTime, (c, v) => c.playbackTime = v),
      Field.number('timeScale', (c) => c.timeScale, (c, v) => c.timeScale = v),
      Field.enumValue<CurveEnvelopeComponent, curve.CurveWrapMode>(
        'wrapMode',
        curve.CurveWrapMode.values,
        (c) => c.wrapMode,
        (c, v) => c.wrapMode = v,
      ),
      Field.number('springTarget', (c) => c.springTarget, (c, v) => c.springTarget = v),
      Field.number(
        'springSmoothTime',
        (c) => c.springSmoothTime,
        (c, v) => c.springSmoothTime = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  double get currentCurveValue => _currentCurveValue;
  double get currentAdsrValue => adsr.value;
  curve.AdsrPhase get adsrPhase => adsr.phase;
  double get currentSpringValue => spring.value;

  void triggerEnvelope({double velocity = 1.0}) => adsr.trigger(velocity: velocity);
  void releaseEnvelope() => adsr.release();

  void cycleWrapMode() {
    final vals = curve.CurveWrapMode.values;
    wrapMode = vals[(vals.indexOf(wrapMode) + 1) % vals.length];
    keyframeCurve = curve.KeyframeCurve(keyframeCurve.keys, wrapMode: wrapMode);
  }

  /// Advances the animation curve cursor, ADSR phase & critically damped spring over [dt] seconds.
  void stepEvaluator(double dt) {
    final scaledDt = math.max(0.0, dt * timeScale);
    playbackTime += scaledDt;
    if (keyframeCurve.wrapMode != wrapMode) {
      keyframeCurve = curve.KeyframeCurve(keyframeCurve.keys, wrapMode: wrapMode);
    }
    _currentCurveValue = keyframeCurve.evaluate(playbackTime);
    adsr.step(scaledDt);
    spring.smoothTime = springSmoothTime;
    spring.step(springTarget, scaledDt);
  }

  @override
  void update() {
    if (paused) return;
    stepEvaluator(time.deltaTime);
  }
}

/// Persistent UI state for [CurveEditorInspectorUI.render].
final class CurveEditorInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` keyframe curve, ADSR envelope & spring inspector (E90-2).
final class CurveEditorInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    CurveEditorInspectorUiState state,
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
    CurveEnvelopeComponent env, {
    CurveEditorInspectorUiState? state,
    String title = 'Curve & ADSR',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? CurveEditorInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Curve / Wrap',
      '${env.currentCurveValue.toStringAsFixed(3)} @ ${env.playbackTime.toStringAsFixed(2)}s (${env.wrapMode.name})',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'ADSR / Phase',
      '${env.currentAdsrValue.toStringAsFixed(3)} | ${env.adsrPhase.name}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Spring / Target',
      '${env.currentSpringValue.toStringAsFixed(3)} -> ${env.springTarget.toStringAsFixed(2)}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Scale / Status',
      '${env.timeScale.toStringAsFixed(1)}x | ${env.paused ? 'Paused' : 'Active'}',
      valueColor: env.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'ce_pause', env.paused ? 'Resume' : 'Pause', pauseRect)) {
      env.paused = !env.paused;
    }

    final trigRect = VoxRect(pauseRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'ce_trig', 'Trigger', trigRect)) {
      env.triggerEnvelope();
    }

    final relRect = VoxRect(trigRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'ce_rel', 'Release', relRect)) {
      env.releaseEnvelope();
    }

    final wrapRect = VoxRect(relRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'ce_wrap', 'WrapMode', wrapRect)) {
      env.cycleWrapMode();
    }

    ui.endWindow();
  }
}
