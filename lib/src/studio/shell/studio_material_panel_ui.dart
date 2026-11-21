/// Pure-Dart Dockable Material Editor Panel (`[Wave G17]`):
/// Renders an interactive PBR `.vmat` editor backed by [MaterialInspectorModel]
/// with live preview swatch, Metallic/Roughness/Albedo sliders, Render Queue
/// cycler, Preview Shape toggle, and `.vmat` JSON save.
library;

import 'dart:convert';

import '../../../gl_volition.dart';
import '../inspector/material_inspector.dart';
import '../project/project_fs.dart';

/// Interactive renderer for the dockable `'material'` tab (`[Wave G17]`).
final class StudioMaterialPanelRenderer {
  void render({
    required MaterialInspectorModel model,
    required ProjectFileSystem fs,
    required DrawList dl,
    required VoxInput input,
    required VoxRect bounds,
    void Function(String savedPath)? onSaved,
  }) {
    final asset = model.asset;
    final rVal = ((asset.properties['albedoR'] as num?)?.toDouble() ?? 0.72)
        .clamp(0.0, 1.0);
    final gVal = ((asset.properties['albedoG'] as num?)?.toDouble() ?? 0.56)
        .clamp(0.0, 1.0);
    final bVal = ((asset.properties['albedoB'] as num?)?.toDouble() ?? 0.42)
        .clamp(0.0, 1.0);
    final metallic = ((asset.properties['metallic'] as num?)?.toDouble() ?? 0.2)
        .clamp(0.0, 1.0);
    final roughness =
        ((asset.properties['roughness'] as num?)?.toDouble() ?? 0.45).clamp(
          0.04,
          1.0,
        );

    final x = bounds.x + 10;
    final w = (bounds.width - 20).clamp(140.0, 340.0);
    var y = bounds.y + 8;

    dl.addText(
      'Material: ${asset.guid} (${asset.shaderId})',
      x,
      y,
      color: const VoxColor(232, 234, 240, 255),
      size: 12,
    );
    y += 22;

    // Preview Swatch + Shape & Save controls
    final previewRect = VoxRect(x, y, 76, 76);
    dl.addRectFilled(
      previewRect.x,
      previewRect.y,
      previewRect.width,
      previewRect.height,
      const VoxColor(24, 26, 30, 255),
      cornerRadius: 4,
    );
    final baseColor = VoxColor(
      (rVal * 255).round().clamp(0, 255),
      (gVal * 255).round().clamp(0, 255),
      (bVal * 255).round().clamp(0, 255),
      255,
    );
    final radius = model.previewShape == MaterialPreviewShape.sphere
        ? 26.0
        : (model.previewShape == MaterialPreviewShape.cube ? 4.0 : 0.0);
    final swatchH = model.previewShape == MaterialPreviewShape.plane
        ? 22.0
        : 52.0;
    final swatchY = previewRect.y + (previewRect.height - swatchH) * 0.5;
    dl.addRectFilled(
      previewRect.x + 12,
      swatchY,
      52,
      swatchH,
      baseColor,
      cornerRadius: radius,
    );
    // Specular highlight dot scaled by (1 - roughness)
    final specAlpha = ((1.0 - roughness) * (140 + metallic * 110))
        .round()
        .clamp(20, 250);
    dl.addRectFilled(
      previewRect.x + 22,
      swatchY + 8,
      14,
      14,
      VoxColor(255, 255, 255, specAlpha),
      cornerRadius: 7,
    );

    final btnX = previewRect.right + 10;
    final btnW = (w - 86).clamp(80.0, 220.0);
    _button(
      dl,
      input,
      VoxRect(btnX, y, btnW, 22),
      'Preview: ${model.previewShape.name}',
      onClick: () {
        const shapes = MaterialPreviewShape.values;
        model.previewShape =
            shapes[(model.previewShape.index + 1) % shapes.length];
      },
    );
    final queueLabel = asset.renderQueue < 2400
        ? 'Opaque (${asset.renderQueue})'
        : (asset.renderQueue < 2900
              ? 'AlphaTest (${asset.renderQueue})'
              : 'Transparent (${asset.renderQueue})');
    _button(
      dl,
      input,
      VoxRect(btnX, y + 26, btnW, 22),
      'Queue: $queueLabel',
      onClick: () {
        final nextQ = asset.renderQueue < 2400
            ? RenderQueue.alphaTest
            : (asset.renderQueue < 2900
                  ? RenderQueue.transparent
                  : RenderQueue.geometry);
        model.setQueueAndSorting(renderQueue: nextQ);
      },
    );
    _button(
      dl,
      input,
      VoxRect(btnX, y + 52, btnW, 22),
      'Save .vmat',
      primary: true,
      onClick: () async {
        final path = 'assets/materials/${asset.guid}.vmat';
        await fs.writeString(
          path,
          const JsonEncoder.withIndent('  ').convert(asset.toJson()),
        );
        onSaved?.call(path);
      },
    );

    y += 88;
    y = _sliderRow(
      dl,
      input,
      VoxRect(x, y, w, 20),
      'Metallic',
      metallic,
      const VoxColor(95, 165, 235, 255),
      (v) => model.setProperty('metallic', v),
    );
    y = _sliderRow(
      dl,
      input,
      VoxRect(x, y, w, 20),
      'Roughness',
      roughness,
      const VoxColor(180, 140, 235, 255),
      (v) => model.setProperty('roughness', v.clamp(0.04, 1.0)),
    );
    y = _sliderRow(
      dl,
      input,
      VoxRect(x, y, w, 20),
      'Albedo R',
      rVal,
      const VoxColor(220, 75, 75, 255),
      (v) => model.setProperty('albedoR', v),
    );
    y = _sliderRow(
      dl,
      input,
      VoxRect(x, y, w, 20),
      'Albedo G',
      gVal,
      const VoxColor(75, 195, 100, 255),
      (v) => model.setProperty('albedoG', v),
    );
    _sliderRow(
      dl,
      input,
      VoxRect(x, y, w, 20),
      'Albedo B',
      bVal,
      const VoxColor(75, 135, 230, 255),
      (v) => model.setProperty('albedoB', v),
    );
  }

  double _sliderRow(
    DrawList dl,
    VoxInput input,
    VoxRect r,
    String label,
    double value,
    VoxColor fillColor,
    void Function(double next) onChanged,
  ) {
    dl.addText(
      '$label: ${value.toStringAsFixed(2)}',
      r.x,
      r.y + 3,
      color: const VoxColor(200, 205, 214, 255),
      size: 11,
    );
    final barX = r.x + 112;
    final barW = (r.width - 112).clamp(48.0, 240.0);
    final barRect = VoxRect(barX, r.y + 3, barW, 14);
    dl.addRectFilled(
      barRect.x,
      barRect.y,
      barRect.width,
      barRect.height,
      const VoxColor(30, 32, 36, 255),
      cornerRadius: 3,
    );
    dl.addRectFilled(
      barRect.x,
      barRect.y,
      barRect.width * value.clamp(0.0, 1.0),
      barRect.height,
      fillColor,
      cornerRadius: 3,
    );
    if (barRect.contains(input.mouseX, input.mouseY) && input.isMouseDown) {
      final frac = ((input.mouseX - barRect.x) / barRect.width).clamp(0.0, 1.0);
      onChanged(double.parse(frac.toStringAsFixed(3)));
    }
    return r.bottom + 6;
  }

  void _button(
    DrawList dl,
    VoxInput input,
    VoxRect r,
    String label, {
    bool primary = false,
    required void Function() onClick,
  }) {
    final hov = r.contains(input.mouseX, input.mouseY);
    dl.addRectFilled(
      r.x,
      r.y,
      r.width,
      r.height,
      primary
          ? const VoxColor(58, 121, 187, 255)
          : (hov
                ? const VoxColor(68, 72, 78, 255)
                : const VoxColor(52, 54, 60, 255)),
      cornerRadius: 3,
    );
    dl.addRectOutline(
      r.x,
      r.y,
      r.width,
      r.height,
      const VoxColor(26, 26, 26, 255),
    );
    dl.addText(
      label,
      r.x + 8,
      r.y + 5,
      color: const VoxColor(236, 238, 244, 255),
      size: 11,
    );
    if (hov && input.wasMouseClicked) {
      onClick();
    }
  }
}
