/// Native AOT Studio Application Host (`[Wave G1]` / `[Wave G2]`):
/// Drives [StudioWorkspaceShell] and [VoxUiGlRenderer] on top of a native
/// [GpuDevice] (`Gles3FfiDevice` or `RecordingGlesDevice`) with zero browser
/// dependency.
library;

import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:voxui/voxui.dart';

import '../../studio/studio.dart';
import 'voxui_gl_renderer.dart';

/// AOT-compilable native Studio frame driver (`[Wave G1]` / `[Wave G2]`).
final class NativeStudioApp {
  final StudioWorkspaceShell shell;
  final VoxUiGlRenderer uiRenderer;
  final DrawList _drawList = DrawList();
  int frameCount = 0;

  NativeStudioApp({required this.shell, required GpuDevice device})
    : uiRenderer = VoxUiGlRenderer(device);

  /// Executes one native Studio frame: solves the Unity-style docking layout,
  /// emits the UI [DrawList], and flushes batched GPU draw commands.
  SolvedDockWorkspace stepFrame({
    required VoxInput input,
    required int pixelWidth,
    required int pixelHeight,
    double dtSeconds = 1.0 / 60.0,
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
    uiRenderer.render(
      _drawList,
      viewportWidth: pixelWidth,
      viewportHeight: pixelHeight,
    );
    frameCount++;
    return solved;
  }

  void dispose() => uiRenderer.dispose();
}
