/// Native AOT Studio Application Host (`[Wave G1]`–`[Wave G3]`):
/// Drives [StudioWorkspaceShell], [ViewportFboHost] (live offscreen Scene &
/// Game FBOs), and [VoxUiGlRenderer] (batched UI + ASCII bitmap font atlas)
/// on top of any native [GpuDevice] (`Gles3FfiDevice` or `RecordingGlesDevice`).
library;

import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:voxui/voxui.dart';

import '../../studio/studio.dart';
import 'viewport_fbo_host.dart';
import 'voxui_gl_renderer.dart';

/// AOT-compilable native Studio frame driver (`[Wave G1]`–`[Wave G3]`).
final class NativeStudioApp {
  final StudioWorkspaceShell shell;
  final VoxUiGlRenderer uiRenderer;
  final ViewportFboHost viewportHost;
  final DrawList _drawList = DrawList();
  int frameCount = 0;

  NativeStudioApp({required this.shell, required GpuDevice device})
    : uiRenderer = VoxUiGlRenderer(device),
      viewportHost = ViewportFboHost(device);

  /// Executes one complete native Studio frame:
  /// 1. Solves the Unity-style docking layout and emits the UI [DrawList].
  /// 2. Renders active docked Scene/Game viewports into offscreen FBOs.
  /// 3. Flushes the batched UI + bitmap font atlas, then composites the
  ///    live viewport FBO textures into their exact docked rectangles.
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
    _drawList.clear();
    final solved = shell.buildFrame(
      dl: _drawList,
      input: input,
      width: pixelWidth.toDouble(),
      height: pixelHeight.toDouble(),
    );

    final renderedViewports = viewportHost.renderViewports(
      shell.activeViewportSlots,
      renderPass: onRenderViewport,
    );

    uiRenderer.render(
      _drawList,
      viewportWidth: pixelWidth,
      viewportHeight: pixelHeight,
    );

    viewportHost.compositeViewports(
      uiRenderer,
      renderedViewports,
      windowWidth: pixelWidth,
      windowHeight: pixelHeight,
    );

    frameCount++;
    return solved;
  }

  void dispose() {
    viewportHost.dispose();
    uiRenderer.dispose();
  }
}
