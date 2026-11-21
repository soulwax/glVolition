/// Pure-Dart Dockable Animator State Machine Panel (`[Wave G18]`):
/// Renders [AnimatorControllerModel] inside the docked `'animator'` tab with
/// interactive parameter scrubbing, live state boxes (highlighting
/// `activeState`), transition arrows with threshold labels, and `Step Eval`.
library;

import '../../../gl_volition.dart';
import '../windows/animation/animator_controller_model.dart';

/// Interactive renderer for the dockable `'animator'` tab (`[Wave G18]`).
final class StudioAnimatorPanelRenderer {
  void render({
    required AnimatorControllerModel model,
    required DrawList dl,
    required VoxInput input,
    required VoxRect bounds,
  }) {
    final sideW = (bounds.width * 0.28).clamp(120.0, 180.0);
    dl.addRectFilled(
      bounds.x,
      bounds.y,
      sideW,
      bounds.height,
      const VoxColor(42, 44, 48, 255),
    );
    dl.addLine(
      bounds.x + sideW,
      bounds.y,
      bounds.x + sideW,
      bounds.bottom,
      const VoxColor(26, 26, 26, 255),
    );

    // Left sidebar: Parameters & Step Eval
    dl.addText(
      'Parameters (${model.parameters.length})',
      bounds.x + 8,
      bounds.y + 8,
      color: const VoxColor(228, 230, 236, 255),
      size: 11,
    );
    var py = bounds.y + 28;
    for (final key in model.parameters.keys.toList()) {
      if (py > bounds.bottom - 34) break;
      final val = model.parameters[key] ?? 0.0;
      final pr = VoxRect(bounds.x + 6, py, sideW - 12, 22);
      final hov = pr.contains(input.mouseX, input.mouseY);
      dl.addRectFilled(
        pr.x,
        pr.y,
        pr.width,
        pr.height,
        hov ? const VoxColor(62, 66, 72, 255) : const VoxColor(34, 36, 40, 255),
        cornerRadius: 3,
      );
      dl.addText(
        '$key: ${val.toStringAsFixed(2)}',
        pr.x + 6,
        pr.y + 5,
        color: const VoxColor(220, 224, 232, 255),
        size: 10,
      );
      if (hov && input.isMouseDown && input.mouseDeltaX != 0.0) {
        model.parameters[key] = double.parse(
          (val + input.mouseDeltaX * 0.02).clamp(0.0, 10.0).toStringAsFixed(2),
        );
      }
      py += 26;
    }

    final evalRect = VoxRect(
      bounds.x + 8,
      (py + 6).clamp(bounds.y + 40, bounds.bottom - 28),
      sideW - 16,
      22,
    );
    final evalHov = evalRect.contains(input.mouseX, input.mouseY);
    dl.addRectFilled(
      evalRect.x,
      evalRect.y,
      evalRect.width,
      evalRect.height,
      evalHov
          ? const VoxColor(70, 138, 210, 255)
          : const VoxColor(58, 121, 187, 255),
      cornerRadius: 3,
    );
    dl.addText(
      'Step Eval',
      evalRect.x + 12,
      evalRect.y + 5,
      color: const VoxColor(242, 244, 248, 255),
      size: 11,
    );
    if (evalHov && input.wasMouseClicked) {
      model.evaluateStep();
    }

    // Right State Machine Canvas
    final cx = bounds.x + sideW;
    final cw = (bounds.width - sideW).clamp(80.0, double.infinity);
    dl.addRectFilled(
      cx,
      bounds.y,
      cw,
      bounds.height,
      const VoxColor(28, 30, 34, 255),
    );
    dl.addText(
      'Animator: ${model.name}  |  Active: ${model.activeState}',
      cx + 12,
      bounds.y + 8,
      color: const VoxColor(185, 192, 204, 255),
      size: 11,
    );

    // Lay out state boxes cleanly in a horizontal row / grid
    final stateRects = <String, VoxRect>{};
    const boxW = 112.0;
    const boxH = 36.0;
    for (var i = 0; i < model.states.length; i++) {
      final st = model.states[i];
      final col = i % 3;
      final row = i ~/ 3;
      final sx = cx + 24 + col * 144.0;
      final sy = bounds.y + 44 + row * 72.0;
      stateRects[st] = VoxRect(sx, sy, boxW, boxH);
    }

    // Draw transitions
    for (final tr in model.transitions) {
      final a = stateRects[tr.fromState];
      final b = stateRects[tr.toState];
      if (a == null || b == null) continue;
      final x0 = a.right;
      final y0 = a.y + a.height * 0.5;
      final x1 = b.x;
      final y1 = b.y + b.height * 0.5;
      dl.addLine(
        x0,
        y0,
        x1,
        y1,
        const VoxColor(190, 198, 210, 220),
        thickness: 2,
      );
      dl.addText(
        '${tr.parameter}>${tr.greaterThan}',
        (x0 + x1) * 0.5 - 24,
        (y0 + y1) * 0.5 - 14,
        color: const VoxColor(165, 175, 190, 255),
        size: 10,
      );
    }

    // Draw state nodes
    for (final st in model.states) {
      final r = stateRects[st]!;
      final isActive = model.activeState == st;
      final hov = r.contains(input.mouseX, input.mouseY);
      dl.addRectFilled(
        r.x,
        r.y,
        r.width,
        r.height,
        isActive
            ? const VoxColor(215, 128, 42, 255)
            : (hov
                  ? const VoxColor(76, 82, 92, 255)
                  : const VoxColor(60, 64, 72, 255)),
        cornerRadius: 4,
      );
      dl.addRectOutline(
        r.x,
        r.y,
        r.width,
        r.height,
        isActive
            ? const VoxColor(255, 195, 90, 255)
            : const VoxColor(24, 26, 30, 255),
      );
      dl.addText(
        st,
        r.x + 10,
        r.y + 11,
        color: const VoxColor(242, 244, 248, 255),
        size: 11,
      );
      if (hov && input.wasMouseClicked) {
        model.activeState = st;
      }
    }
  }
}
