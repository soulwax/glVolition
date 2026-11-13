part of '../../engine.dart';

/// Perceptual OKLab/OKLCH gradient & procedural 3D LUT color grading component (`voxcolor`) (E93-2).
final class ColorGradingLutComponent extends Behaviour {
  int lutSize;
  double temperature;
  double contrast;
  double saturation;
  double gamma;
  double gradientCursor;
  bool paused;

  late vcolor.ColorLut3D lut;
  late vcolor.PerceptualGradient gradient;
  LinearColor sampledGradientColor = const LinearColor(0.22, 0.74, 0.97);
  double lastDeltaE = 0.0;
  TextureHandle? bakedLutTexture;
  bool _lutDirty = true;

  bool get isLutTextureDirty => _lutDirty;

  ColorGradingLutComponent({
    this.lutSize = 16,
    this.temperature = 0.15,
    this.contrast = 1.08,
    this.saturation = 1.12,
    this.gamma = 1.0,
    this.gradientCursor = 0.5,
    this.paused = false,
  }) {
    gradient = vcolor.PerceptualGradient([
      vcolor.ColorStop(0.0, vcolor.OkLabColor.fromHexRgb(0x0EA5E9)),
      vcolor.ColorStop(0.5, vcolor.OkLabColor.fromHexRgb(0x8B5CF6)),
      vcolor.ColorStop(1.0, vcolor.OkLabColor.fromHexRgb(0xF43F5E)),
    ], useOkLchHueArc: true);
    rebuildLut();
  }

  static final spec = ComponentSpec<ColorGradingLutComponent>(
    'ColorGradingLutComponent',
    ColorGradingLutComponent.new,
    [
      Field.integer('lutSize', (c) => c.lutSize, (c, v) => c.lutSize = v),
      Field.number(
        'temperature',
        (c) => c.temperature,
        (c, v) => c.temperature = v,
      ),
      Field.number('contrast', (c) => c.contrast, (c, v) => c.contrast = v),
      Field.number(
        'saturation',
        (c) => c.saturation,
        (c, v) => c.saturation = v,
      ),
      Field.number('gamma', (c) => c.gamma, (c, v) => c.gamma = v),
      Field.number(
        'gradientCursor',
        (c) => c.gradientCursor,
        (c, v) => c.gradientCursor = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  void rebuildLut() {
    lut = vcolor.ColorLut3D.procedural(
      size: lutSize.clamp(4, 32),
      temperature: temperature,
      contrast: contrast,
      saturation: saturation,
      gamma: gamma,
    );
    _lutDirty = true;
    evaluateSample();
  }

  /// Encodes the current 3D [lut] (`N x N` width by `N` height RGBA8 horizontal slice strip).
  Uint8List bakeRgbaLutBytes() {
    final n = lut.size;
    final bytes = Uint8List(n * n * n * 4);
    final inv = 1.0 / (n - 1);
    for (var b = 0; b < n; b++) {
      final fb = b * inv;
      for (var g = 0; g < n; g++) {
        final fg = g * inv;
        for (var r = 0; r < n; r++) {
          final sample = lut.sample(r * inv, fg, fb);
          final idx = ((g * n + b) * n + r) * 4;
          bytes[idx] = (sample.r.clamp(0.0, 1.0) * 255.0).round();
          bytes[idx + 1] = (sample.g.clamp(0.0, 1.0) * 255.0).round();
          bytes[idx + 2] = (sample.b.clamp(0.0, 1.0) * 255.0).round();
          bytes[idx + 3] = 255;
        }
      }
    }
    return bytes;
  }

  /// Returns the cached GPU LUT [TextureHandle], uploading a new strip when dirty.
  TextureHandle ensureLutTexture(Graphics graphics) {
    final existing = bakedLutTexture;
    if (existing != null && !_lutDirty) return existing;
    if (existing != null) {
      graphics.releaseTexture(existing);
    }
    final handle = graphics.createTexture(
      width: lut.size * lut.size,
      height: lut.size,
      pixels: bakeRgbaLutBytes(),
      minFilter: GpuTextureFilter.linear,
      magFilter: GpuTextureFilter.linear,
      debugLabel: 'voxcolor_lut_${lut.size}',
    );
    bakedLutTexture = handle;
    _lutDirty = false;
    return handle;
  }

  void evaluateSample() {
    final lab = gradient.evaluate(gradientCursor);
    final lin = lab.toLinearRgb();
    sampledGradientColor = LinearColor(
      lin.r.clamp(0.0, 1.0),
      lin.g.clamp(0.0, 1.0),
      lin.b.clamp(0.0, 1.0),
    );
    final srgb = lab.toSrgb();
    final graded = lut.sample(srgb.r, srgb.g, srgb.b);
    lastDeltaE = lab.deltaE(
      vcolor.OkLabColor.fromSrgb(graded.r, graded.g, graded.b),
    );
  }

  LinearColor gradeLinearColor(LinearColor input) {
    final srgb = vcolor.OkLabColor.fromLinearRgb(
      input.r,
      input.g,
      input.b,
    ).toSrgb();
    final g = lut.sample(srgb.r, srgb.g, srgb.b);
    final lin = vcolor.OkLabColor.fromSrgb(g.r, g.g, g.b).toLinearRgb();
    return LinearColor(
      lin.r.clamp(0.0, 1.0),
      lin.g.clamp(0.0, 1.0),
      lin.b.clamp(0.0, 1.0),
    );
  }

  @override
  void update() {
    if (paused) return;
    evaluateSample();
    if (isAttached && scene.isLoaded) {
      scene.renderSettings.post = scene.renderSettings.post.copyWith(
        colorGradeStrength: (contrast - 1.0).abs() > 1e-4 ? 1.0 : 0.5,
      );
    }
  }

  @override
  void onDestroy() {
    if (bakedLutTexture != null && isAttached && scene.isLoaded) {
      engine.graphics.releaseTexture(bakedLutTexture!);
      bakedLutTexture = null;
    }
  }
}

/// Persistent UI state for [ColorGradingInspectorUI.render].
final class ColorGradingInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` OKLab gradient & 3D LUT inspector (E93-2).
final class ColorGradingInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    ColorGradingInspectorUiState state,
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
    ColorGradingLutComponent comp, {
    ColorGradingInspectorUiState? state,
    String title = 'OKLab Color LUT',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? ColorGradingInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'LUT / Temp',
      '${comp.lutSize}^3 | temp ${comp.temperature.toStringAsFixed(2)} | contrast ${comp.contrast.toStringAsFixed(2)}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Sat / Gamma',
      'sat ${comp.saturation.toStringAsFixed(2)} | gamma ${comp.gamma.toStringAsFixed(2)}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Gradient / dE',
      't=${comp.gradientCursor.toStringAsFixed(2)} | deltaE ${comp.lastDeltaE.toStringAsFixed(3)}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Sample RGB / Status',
      '(${comp.sampledGradientColor.r.toStringAsFixed(2)}, ${comp.sampledGradientColor.g.toStringAsFixed(2)}, ${comp.sampledGradientColor.b.toStringAsFixed(2)}) | ${comp.paused ? 'Paused' : 'Active'}',
      valueColor: comp.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'cg_pause',
      comp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      comp.paused = !comp.paused;
    }

    final warmRect = VoxRect(pauseRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'cg_warm', 'Temp +0.2', warmRect)) {
      comp.temperature = (comp.temperature + 0.2).clamp(-1.0, 1.0);
      comp.rebuildLut();
    }

    final satRect = VoxRect(warmRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'cg_sat', 'Sat +0.1', satRect)) {
      comp.saturation = (comp.saturation + 0.1).clamp(0.0, 2.0);
      comp.rebuildLut();
    }

    final resetRect = VoxRect(satRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'cg_reset', 'Neutral', resetRect)) {
      comp
        ..temperature = 0.0
        ..contrast = 1.0
        ..saturation = 1.0
        ..gamma = 1.0;
      comp.rebuildLut();
    }

    ui.endWindow();
  }
}
