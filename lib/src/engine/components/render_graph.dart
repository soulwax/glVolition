part of '../../engine.dart';

/// Convenience alias matching Wave 12 subsystem contract.
typedef RenderGraph = RenderGraphComponent;

/// Declarative render/compute pass DAG, barriers & transient aliasing manager (`voxgraph`) (E83-2).
final class RenderGraphComponent extends Component {
  int viewportWidth;
  int viewportHeight;
  bool enableTransientAliasing;
  bool includePostProcessPass;
  bool includeUnusedDebugPass;

  final Map<String, RenderPassAnchor> passAnchors = {};
  final Map<String, ShaderOverride> passShaders = {};
  final Map<String, Map<String, ShaderUniform>> passUniforms = {};
  final Map<String, Map<String, TextureHandle>> passTextures = {};
  final Map<String, int> passPriorities = {};
  final Set<String> disabledPasses = {};
  final List<RenderPassDecl> customPasses = [];
  final Set<String> _declaredPassIds = {};
  Graphics? _lastGfx;

  graph.CompiledRenderGraph? _lastCompiled;
  graph.TransientAliasingPlan? _lastAliasingPlan;
  int _compileCount = 0;

  RenderGraphComponent({
    this.viewportWidth = 1280,
    this.viewportHeight = 720,
    this.enableTransientAliasing = true,
    this.includePostProcessPass = true,
    this.includeUnusedDebugPass = false,
  });

  static final spec = ComponentSpec<RenderGraphComponent>(
    'RenderGraphComponent',
    RenderGraphComponent.new,
    [
      Field.integer(
        'viewportWidth',
        (c) => c.viewportWidth,
        (c, v) => c.viewportWidth = v,
      ),
      Field.integer(
        'viewportHeight',
        (c) => c.viewportHeight,
        (c, v) => c.viewportHeight = v,
      ),
      Field.boolean(
        'enableTransientAliasing',
        (c) => c.enableTransientAliasing,
        (c, v) => c.enableTransientAliasing = v,
      ),
      Field.boolean(
        'includePostProcessPass',
        (c) => c.includePostProcessPass,
        (c, v) => c.includePostProcessPass = v,
      ),
      Field.boolean(
        'includeUnusedDebugPass',
        (c) => c.includeUnusedDebugPass,
        (c, v) => c.includeUnusedDebugPass = v,
      ),
    ],
  );

  int get compileCount => _compileCount;
  graph.CompiledRenderGraph get compiled =>
      _lastCompiled ?? rebuildStandardPipeline();
  graph.TransientAliasingPlan? get aliasingPlan => _lastAliasingPlan;

  /// Compiles any user-authored [graph.RenderGraphBuilder] DAG and evaluates transient aliasing.
  graph.CompiledRenderGraph compileBuilder(graph.RenderGraphBuilder builder) {
    final compiledGraph = const graph.RenderGraphCompiler().compile(builder);
    _lastCompiled = compiledGraph;
    _lastAliasingPlan = enableTransientAliasing
        ? const graph.TransientResourceAliaser().buildPlan(compiledGraph)
        : null;
    _compileCount++;
    return compiledGraph;
  }

  /// Builds and compiles a standard deferred/forward+ scene pipeline scaled to [viewportWidth]x[viewportHeight].
  graph.CompiledRenderGraph rebuildStandardPipeline() {
    final w = math.max(64, viewportWidth);
    final h = math.max(64, viewportHeight);
    final b = graph.RenderGraphBuilder();

    final depth = b.createTexture(
      'depth_z',
      width: w,
      height: h,
      format: graph.RenderResourceFormat.d32f,
    );
    final hdrColor = b.createTexture(
      'hdr_color',
      width: w,
      height: h,
      format: graph.RenderResourceFormat.rgba16f,
    );
    final bloomScratch = b.createTexture(
      'bloom_half',
      width: w ~/ 2,
      height: h ~/ 2,
      format: graph.RenderResourceFormat.rgba16f,
    );
    final swapchain = b.createTexture(
      'backbuffer',
      width: w,
      height: h,
      format: graph.RenderResourceFormat.rgba8,
      external: true,
    );

    if (includeUnusedDebugPass) {
      final deadDebug = b.createTexture(
        'unused_heatmap',
        width: 256,
        height: 256,
      );
      b.addPass('UnusedHeatmap', (s) => s.write(deadDebug));
    }

    b.addPass('DepthPrePass', (s) {
      s.write(depth, usage: graph.RenderResourceUsage.depthTarget);
    });
    b.addPass('OpaqueLighting', (s) {
      s.read(depth);
      s.write(hdrColor, usage: graph.RenderResourceUsage.colorTarget);
    });

    if (includePostProcessPass) {
      b.addPass('BloomExtract', (s) {
        s.read(hdrColor);
        s.write(bloomScratch, usage: graph.RenderResourceUsage.storageWrite);
      }, passType: graph.RenderGraphPassType.compute);

      b.addPass('ToneMapPresent', (s) {
        s.read(hdrColor);
        s.read(bloomScratch);
        s.write(swapchain, usage: graph.RenderResourceUsage.present);
      });
    } else {
      b.addPass('DirectPresent', (s) {
        s.read(hdrColor);
        s.write(swapchain, usage: graph.RenderResourceUsage.present);
      });
    }

    return compileBuilder(b);
  }

  /// Registers an explicit custom [RenderPassDecl] to be reconciled onto the renderer.
  void addCustomPass(RenderPassDecl pass) => customPasses.add(pass);

  /// Removes an explicit custom [RenderPassDecl] by [id].
  void removeCustomPass(String id) =>
      customPasses.removeWhere((p) => p.id == id);

  RenderPassAnchor _resolveAnchor(String passName) {
    if (passAnchors.containsKey(passName)) return passAnchors[passName]!;
    final lower = passName.toLowerCase();
    if (lower.contains('shadow')) return RenderPassAnchor.afterShadow;
    if (lower.contains('depth')) return RenderPassAnchor.beforeDepth;
    if (lower.contains('bloom')) return RenderPassAnchor.beforeGrade;
    if (lower.contains('tone') || lower.contains('present')) {
      return RenderPassAnchor.beforePresent;
    }
    if (lower.contains('resolve')) return RenderPassAnchor.afterResolve;
    return RenderPassAnchor.afterWorld;
  }

  /// Converts all scheduled render graph passes and user custom passes into
  /// Pixeldart host [RenderPassDecl] descriptors (`R3`).
  List<RenderPassDecl> toRenderPassDecls() {
    final comp = compiled;
    final results = <RenderPassDecl>[];

    for (final pass in comp.scheduledPasses) {
      final attachments = <RenderPassAttachmentDecl>[];
      for (final access in pass.accesses) {
        final res = comp.resourcesByIndex[access.resourceIndex];
        if (res == null) continue;
        final format = switch (res.desc.format) {
          graph.RenderResourceFormat.rgba8 => RenderPassTargetFormat.rgba8,
          graph.RenderResourceFormat.rgba16f => RenderPassTargetFormat.rgba16f,
          graph.RenderResourceFormat.rgba32f => RenderPassTargetFormat.rgba16f,
          graph.RenderResourceFormat.d32f => RenderPassTargetFormat.depth32f,
          graph.RenderResourceFormat.r32u => RenderPassTargetFormat.rgba8,
        };
        final accessKind = access.isWrite
            ? RenderPassAccess.write
            : RenderPassAccess.read;
        final scale = viewportWidth > 0
            ? (res.desc.width / viewportWidth)
            : 1.0;
        attachments.add(
          RenderPassAttachmentDecl(
            name: res.name,
            format: format,
            access: accessKind,
            transient: !res.desc.external,
            scale: scale,
          ),
        );
      }

      final dependsOn = <String>[];
      for (final readIdx in pass.readResourceIndices) {
        for (final prior in comp.scheduledPasses) {
          if (prior.id == pass.id) break;
          if (prior.writtenResourceIndices.contains(readIdx)) {
            if (!dependsOn.contains(prior.name)) {
              dependsOn.add(prior.name);
            }
          }
        }
      }

      final decl = RenderPassDecl(
        id: pass.name,
        anchor: _resolveAnchor(pass.name),
        attachments: attachments,
        dependsOn: dependsOn,
        shader: passShaders[pass.name],
        uniforms: passUniforms[pass.name] ?? const {},
        textures: passTextures[pass.name] ?? const {},
        priority: passPriorities[pass.name] ?? 0,
        enabled: !disabledPasses.contains(pass.name),
      );
      results.add(decl);
    }

    results.addAll(customPasses);
    return results;
  }

  /// Declares all compiled graph passes and custom passes onto [gfx], reconciling
  /// and removing any previously declared passes that are no longer active.
  void syncToRenderer(Graphics gfx) {
    _lastGfx = gfx;
    final decls = toRenderPassDecls();
    final currentIds = <String>{};

    for (final decl in decls) {
      currentIds.add(decl.id);
      gfx.declareRenderPass(decl);
    }

    final toRemove = _declaredPassIds.difference(currentIds);
    for (final id in toRemove) {
      gfx.removeDeclaredRenderPass(id);
    }

    _declaredPassIds
      ..clear()
      ..addAll(currentIds);
  }

  /// Removes all declared render passes from [gfx].
  void clearDeclaredPasses([Graphics? gfx]) {
    final g = gfx ?? _lastGfx;
    if (g != null) {
      for (final id in _declaredPassIds) {
        g.removeDeclaredRenderPass(id);
      }
    }
    _declaredPassIds.clear();
  }

  @override
  void onDisable() {
    clearDeclaredPasses(_lastGfx);
  }

  @override
  void onDestroy() {
    clearDeclaredPasses(_lastGfx);
  }
}

/// Persistent UI state for [RenderGraphInspectorUI.render].
final class RenderGraphInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` render graph pass DAG, barrier & VRAM aliasing inspector (E83-2).
final class RenderGraphInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    RenderGraphInspectorUiState state,
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
    RenderGraphComponent rgComp, {
    RenderGraphInspectorUiState? state,
    String title = 'Render Graph DAG',
    double x = 20.0,
    double y = 20.0,
    double width = 395.0,
    double height = 245.0,
  }) {
    final uiState = state ?? RenderGraphInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final comp = rgComp.compiled;
    final alias = rgComp.aliasingPlan;
    ui.labelValue(
      'Resolution / Runs',
      '${rgComp.viewportWidth}x${rgComp.viewportHeight} | ${rgComp.compileCount} builds',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Passes / Culled',
      '${comp.activePassCount} active | ${comp.culledPassCount} culled | ${comp.barrierCount} barriers',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Transient Aliasing',
      alias == null
          ? 'Disabled'
          : '${alias.slots.length} slots (${(alias.memorySavingsFraction * 100.0).toStringAsFixed(1)}% saved)',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Schedule',
      comp.executionOrderNames.take(3).join(' -> '),
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final rebuildRect = VoxRect(x + pad, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'rg_rebuild', 'Recompile', rebuildRect)) {
      rgComp.rebuildStandardPipeline();
    }

    final postRect = VoxRect(rebuildRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'rg_post',
      rgComp.includePostProcessPass ? 'Post: On' : 'Post: Off',
      postRect,
    )) {
      rgComp.includePostProcessPass = !rgComp.includePostProcessPass;
      rgComp.rebuildStandardPipeline();
    }

    final aliasRect = VoxRect(postRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'rg_alias', 'Aliasing', aliasRect)) {
      rgComp.enableTransientAliasing = !rgComp.enableTransientAliasing;
      rgComp.rebuildStandardPipeline();
    }

    final deadRect = VoxRect(aliasRect.right + 8.0, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'rg_dead', 'Dead Pass', deadRect)) {
      rgComp.includeUnusedDebugPass = !rgComp.includeUnusedDebugPass;
      rgComp.rebuildStandardPipeline();
    }

    ui.endWindow();
  }
}
