part of '../../engine.dart';

/// Runtime shader override & post-effect component backed by `pixeldart`
/// (`ShaderSlot`, `ShaderTarget`, `ShaderOverride`, `ShaderUniform`) (E97-2).
final class ShaderOverrideComponent extends Behaviour {
  /// Minimal valid `ShaderOverride.effect` GLSL body using `u_intensity`.
  static const String defaultFragmentSource =
      'vec4 effect(vec4 color, vec2 uv) {\n'
      '  return vec4(color.rgb * u_intensity, color.a);\n'
      '}';

  String shaderKey;
  ShaderSlot targetSlot;
  bool isPostEffect;
  String fragmentSource;
  String vertexSource;
  double intensity;
  double paramA;
  double paramB;
  bool paused;

  ShaderOverride? _cachedOverride;
  String? lastValidationError;

  ShaderOverrideComponent({
    this.shaderKey = 'custom_effect',
    this.targetSlot = ShaderSlot.safeWorld,
    this.isPostEffect = true,
    this.fragmentSource = defaultFragmentSource,
    this.vertexSource = '',
    this.intensity = 1.0,
    this.paramA = 0.0,
    this.paramB = 0.0,
    this.paused = false,
  }) {
    tryBuildOverride();
  }

  static final spec = ComponentSpec<ShaderOverrideComponent>(
    'ShaderOverrideComponent',
    ShaderOverrideComponent.new,
    [
      Field.text('shaderKey', (c) => c.shaderKey, (c, v) => c.shaderKey = v),
      Field.enumValue<ShaderOverrideComponent, ShaderSlot>(
        'targetSlot',
        ShaderSlot.values,
        (c) => c.targetSlot,
        (c, v) => c.targetSlot = v,
      ),
      Field.boolean(
        'isPostEffect',
        (c) => c.isPostEffect,
        (c, v) => c.isPostEffect = v,
      ),
      Field.text(
        'fragmentSource',
        (c) => c.fragmentSource,
        (c, v) => c.fragmentSource = v,
      ),
      Field.text(
        'vertexSource',
        (c) => c.vertexSource,
        (c, v) => c.vertexSource = v,
      ),
      Field.number('intensity', (c) => c.intensity, (c, v) => c.intensity = v),
      Field.number('paramA', (c) => c.paramA, (c, v) => c.paramA = v),
      Field.number('paramB', (c) => c.paramB, (c, v) => c.paramB = v),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  /// The most recently validated [ShaderOverride], if valid.
  ShaderOverride? get cachedOverride => _cachedOverride;

  /// Whether the latest override validation succeeded.
  bool get isValid => lastValidationError == null;

  /// Target binding for `pixeldart` ([PostEffect] when [isPostEffect], else [targetSlot]).
  ShaderTarget get shaderTarget =>
      isPostEffect ? PostEffect(shaderKey) : targetSlot;

  /// Current scalar uniform map exposed to the shader override.
  Map<String, double> uniformValues() => {
    'u_intensity': intensity,
    'u_paramA': paramA,
    'u_paramB': paramB,
  };

  /// Builds, validates, caches, and returns a `pixeldart` [ShaderOverride].
  ///
  /// Throws [ArgumentError] (and records [lastValidationError]) if
  /// [ShaderOverride.validate] fails.
  ShaderOverride buildOverride() {
    final uniforms = <String, ShaderUniform>{
      for (final entry in uniformValues().entries)
        entry.key: ShaderUniform.float(entry.value),
    };
    final candidate = isPostEffect
        ? ShaderOverride.effect(fragmentSource, uniforms: uniforms)
        : ShaderOverride(
            vertex: vertexSource.trim().isEmpty ? null : vertexSource,
            fragment: fragmentSource.trim().isEmpty ? null : fragmentSource,
            uniforms: uniforms,
          );
    try {
      candidate.validate();
      lastValidationError = null;
    } on ArgumentError catch (e) {
      lastValidationError = e.message?.toString() ?? e.toString();
      rethrow;
    }
    if (_cachedOverride != candidate) {
      _cachedOverride = candidate;
    }
    return _cachedOverride!;
  }

  /// Safely rebuilds and validates the cached [ShaderOverride], returning `null`
  /// and recording [lastValidationError] if validation fails.
  ShaderOverride? tryBuildOverride() {
    try {
      return buildOverride();
    } on ArgumentError {
      return null;
    }
  }

  /// Resets uniform parameters to defaults and refreshes the cached override.
  void resetUniforms() {
    intensity = 1.0;
    paramA = 0.0;
    paramB = 0.0;
    tryBuildOverride();
  }

  @override
  void _onEnableInternal() {
    if (!scene._shaderOverrides.contains(this)) {
      scene._shaderOverrides.add(this);
    }
  }

  @override
  void _onDisableInternal() {
    scene._shaderOverrides.remove(this);
  }

  @override
  void awake() {
    tryBuildOverride();
  }

  @override
  void update() {
    if (paused) return;
    tryBuildOverride();
  }
}

/// Persistent UI state for [ShaderOverrideInspectorUI.render].
final class ShaderOverrideInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` shader override & post-effect inspector (E97-2).
final class ShaderOverrideInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    ShaderOverrideInspectorUiState state,
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
    ShaderOverrideComponent comp, {
    ShaderOverrideInspectorUiState? state,
    String title = 'Shader Override',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? ShaderOverrideInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Key / Slot',
      '${comp.shaderKey} | ${comp.targetSlot.name}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Mode / Valid',
      '${comp.isPostEffect ? 'PostEffect' : 'SlotOverride'} | ${comp.isValid ? 'Valid' : 'Invalid'}',
      valueColor: comp.isValid ? VoxColor.green : VoxColor.red,
    );
    ui.labelValue(
      'Uniforms',
      'int=${comp.intensity.toStringAsFixed(2)} | a=${comp.paramA.toStringAsFixed(2)} | b=${comp.paramB.toStringAsFixed(2)}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Source / Status',
      '${comp.fragmentSource.trim().length}ch frag | ${comp.paused ? 'Paused' : 'Active'}',
      valueColor: comp.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'so_pause',
      comp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      comp.paused = !comp.paused;
    }

    final modeRect = VoxRect(pauseRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'so_mode', 'Mode', modeRect)) {
      comp.isPostEffect = !comp.isPostEffect;
      comp.tryBuildOverride();
    }

    final intRect = VoxRect(modeRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'so_int', 'Int +0.1', intRect)) {
      var next = ((comp.intensity + 0.1) * 100.0).round() / 100.0;
      if (next > 2.0) next = 0.0;
      comp.intensity = next;
      comp.tryBuildOverride();
    }

    final resetRect = VoxRect(intRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'so_reset', 'Reset', resetRect)) {
      comp.resetUniforms();
    }

    ui.endWindow();
  }
}
