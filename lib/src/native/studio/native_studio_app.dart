/// Native AOT Studio Application Host (`[Wave G1]`–`[Wave G6]`):
/// Drives [StudioWorkspaceShell], [ViewportFboHost] + [StudioViewport3DRenderer]
/// (live offscreen 3D Scene & Game FBOs), and [VoxUiGlRenderer] (batched UI +
/// mixed-case bitmap font atlas + clip-rect batching) using a clean **3-pass
/// compositor**:
/// 1. Render offscreen 3D Scene/Game FBOs (stepping Play Mode when active).
/// 2. Render base dock chrome & panels (`_baseDrawList`).
/// 3. Composite live viewport FBO textures, then render floating overlays,
///    drag previews, and dropdown menus (`_overlayDrawList`) on top.
library;

import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:voxui/voxui.dart';

import '../../studio/studio.dart';
import 'studio_viewport_3d_renderer.dart';
import 'viewport_fbo_host.dart';
import 'voxui_gl_renderer.dart';

/// AOT-compilable native Studio frame driver (`[Wave G1]`–`[Wave G6]`).
final class NativeStudioApp {
  final StudioWorkspaceShell shell;
  final VoxUiGlRenderer uiRenderer;
  final ViewportFboHost viewportHost;
  final StudioViewport3DRenderer viewport3dRenderer;
  final DrawList _baseDrawList = DrawList();
  final DrawList _overlayDrawList = DrawList();
  int frameCount = 0;

  NativeStudioApp({required this.shell, required GpuDevice device})
    : uiRenderer = VoxUiGlRenderer(device),
      viewportHost = ViewportFboHost(device),
      viewport3dRenderer = StudioViewport3DRenderer(device);

  /// Number of overlay UI commands emitted in the most recent [stepFrame].
  int get lastOverlayCommandCount => _overlayDrawList.commands.length;

  /// Executes one complete native Studio 3-pass frame:
  /// 1. Solves the Unity-style docking layout into `_baseDrawList` + `_overlayDrawList`.
  /// 2. Steps Play Mode (if playing) and renders live 3D Scene/Game FBOs.
  /// 3. Flushes `_baseDrawList`, composites live viewport FBO quads, and
  ///    flushes `_overlayDrawList` on top so floating overlays & menus never
  ///    get covered by the 3D FBOs.
  SolvedDockWorkspace stepFrame({
    required VoxInput input,
    required int pixelWidth,
    required int pixelHeight,
    double dtSeconds = 1.0 / 60.0,
    void Function(StudioViewportSlot slot, ViewportFboEntry fbo)?
    onRenderViewport,
  }) {
    if (dtSeconds > 0) {
      shell.lastFrameMs = dtSeconds * 1000.0;
      shell.lastFps = 1.0 / dtSeconds;
    }

    if (shell.isPlaying && dtSeconds > 0) {
      shell.bridge.session.engine.step(dtSeconds);
    }

    _baseDrawList.clear();
    _overlayDrawList.clear();
    final solved = shell.buildFrame(
      dl: _baseDrawList,
      overlayDl: _overlayDrawList,
      input: input,
      width: pixelWidth.toDouble(),
      height: pixelHeight.toDouble(),
    );

    // Pass 1: Render live 3D Scene & Game FBOs
    final renderedViewports = viewportHost.renderViewports(
      shell.activeViewportSlots,
      renderPass: (slot, fbo) {
        viewport3dRenderer.renderViewport(shell: shell, slot: slot, fbo: fbo);
        onRenderViewport?.call(slot, fbo);
      },
    );

    // Pass 2: Render base Unity dock chrome & panels
    uiRenderer.render(
      _baseDrawList,
      viewportWidth: pixelWidth,
      viewportHeight: pixelHeight,
    );

    // Pass 3a: Composite live 3D FBO quads into their exact docked slots
    viewportHost.compositeViewports(
      uiRenderer,
      renderedViewports,
      windowWidth: pixelWidth,
      windowHeight: pixelHeight,
    );

    // Pass 3b: Render floating Scene/Game overlays, drag previews & dropdowns on top
    if (_overlayDrawList.commands.isNotEmpty) {
      uiRenderer.render(
        _overlayDrawList,
        viewportWidth: pixelWidth,
        viewportHeight: pixelHeight,
        resetStats: false,
      );
    }

    frameCount++;
    return solved;
  }

  void dispose() {
    viewport3dRenderer.dispose();
    viewportHost.dispose();
    uiRenderer.dispose();
  }
}
