part of '../../engine.dart';

/// Supported noise sampler modes in [NoiseFieldVolumeComponent].
enum NoiseFieldMode { simplexFbm, ridged, worleyCell, domainWarp }

/// 3D coherent noise, Worley cellular & divergence-free curl velocity component (`voxnoise3d`) (E92-2).
final class NoiseFieldVolumeComponent extends Behaviour {
  int seed;
  double frequency;
  double warpAmplitude;
  int octaves;
  NoiseFieldMode mode;
  bool paused;

  late noise3d.SimplexNoise3D _simplex;
  late noise3d.WorleyNoise3D _worley;
  late noise3d.DomainWarpField3D _warpField;

  double lastSampleScalar = 0.0;
  Vec3 lastCurlVelocity = Vec3.zero;
  int lastCellId = 0;

  NoiseFieldVolumeComponent({
    this.seed = 1337,
    this.frequency = 0.25,
    this.warpAmplitude = 1.25,
    this.octaves = 4,
    this.mode = NoiseFieldMode.domainWarp,
    this.paused = false,
  }) {
    rebuildSamplers();
  }

  static final spec = ComponentSpec<NoiseFieldVolumeComponent>(
    'NoiseFieldVolumeComponent',
    NoiseFieldVolumeComponent.new,
    [
      Field.integer('seed', (c) => c.seed, (c, v) => c.seed = v),
      Field.number('frequency', (c) => c.frequency, (c, v) => c.frequency = v),
      Field.number(
        'warpAmplitude',
        (c) => c.warpAmplitude,
        (c, v) => c.warpAmplitude = v,
      ),
      Field.integer('octaves', (c) => c.octaves, (c, v) => c.octaves = v),
      Field.enumValue<NoiseFieldVolumeComponent, NoiseFieldMode>(
        'mode',
        NoiseFieldMode.values,
        (c) => c.mode,
        (c, v) => c.mode = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  void rebuildSamplers() {
    _simplex = noise3d.SimplexNoise3D(seed: seed);
    _worley = noise3d.WorleyNoise3D(seed: seed);
    _warpField = noise3d.DomainWarpField3D(
      seed: seed,
      baseFrequency: math.max(0.01, frequency),
      warpAmplitude: warpAmplitude,
      octaves: octaves.clamp(1, 8),
    );
  }

  /// Evaluates normalized scalar noise at world [pos].
  double sampleScalar(Vec3 pos) {
    final fx = pos.x * frequency;
    final fy = pos.y * frequency;
    final fz = pos.z * frequency;
    switch (mode) {
      case NoiseFieldMode.simplexFbm:
        lastSampleScalar = _simplex.fbm(fx, fy, fz, octaves: octaves);
      case NoiseFieldMode.ridged:
        lastSampleScalar = _simplex.ridged(fx, fy, fz, octaves: octaves);
      case NoiseFieldMode.worleyCell:
        final w = _worley.sample(fx, fy, fz);
        lastCellId = w.cellId;
        lastSampleScalar = w.edgeDistance;
      case NoiseFieldMode.domainWarp:
        lastSampleScalar = _warpField.sampleWarped(pos.x, pos.y, pos.z);
    }
    return lastSampleScalar;
  }

  /// Evaluates divergence-free 3D curl velocity at world [pos].
  Vec3 sampleCurl(Vec3 pos) {
    final c = _warpField.curl(pos.x, pos.y, pos.z);
    lastCurlVelocity = Vec3(c.x, c.y, c.z);
    return lastCurlVelocity;
  }

  void cycleMode() {
    final vals = NoiseFieldMode.values;
    mode = vals[(vals.indexOf(mode) + 1) % vals.length];
    evaluateAtSelf();
  }

  void evaluateAtSelf() {
    final pos = isAttached ? transform.position : Vec3.zero;
    sampleScalar(pos);
    sampleCurl(pos);
  }

  @override
  void update() {
    if (paused) return;
    evaluateAtSelf();
  }
}

/// Persistent UI state for [NoiseFieldInspectorUI.render].
final class NoiseFieldInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` 3D noise & curl inspector (E92-2).
final class NoiseFieldInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    NoiseFieldInspectorUiState state,
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
    NoiseFieldVolumeComponent field, {
    NoiseFieldInspectorUiState? state,
    String title = '3D Noise & Curl',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? NoiseFieldInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Mode / Octaves',
      '${field.mode.name} | ${field.octaves} oct @ ${field.frequency.toStringAsFixed(2)}Hz',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Scalar / Cell',
      '${field.lastSampleScalar.toStringAsFixed(3)} | cell #${field.lastCellId}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Curl Velocity',
      '(${field.lastCurlVelocity.x.toStringAsFixed(2)}, ${field.lastCurlVelocity.y.toStringAsFixed(2)}, ${field.lastCurlVelocity.z.toStringAsFixed(2)})',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Seed / Warp',
      '${field.seed} | warp ${field.warpAmplitude.toStringAsFixed(2)} | ${field.paused ? 'Paused' : 'Active'}',
      valueColor: field.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'nf_pause',
      field.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      field.paused = !field.paused;
    }

    final modeRect = VoxRect(pauseRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'nf_mode', 'Mode', modeRect)) {
      field.cycleMode();
    }

    final octRect = VoxRect(modeRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'nf_oct', 'Octave +1', octRect)) {
      field.octaves = field.octaves >= 8 ? 1 : field.octaves + 1;
      field.rebuildSamplers();
      field.evaluateAtSelf();
    }

    final seedRect = VoxRect(octRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'nf_seed', 'Reseed', seedRect)) {
      field.seed += 101;
      field.rebuildSamplers();
      field.evaluateAtSelf();
    }

    ui.endWindow();
  }
}
