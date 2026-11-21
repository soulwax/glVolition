/// Native AOT Offscreen Viewport FBO Host (`[Wave G3]`):
/// Manages per-viewport GLES3 offscreen render targets (`scene` and `game`)
/// that automatically resize when their docked `DockArea` pane resizes and
/// composite cleanly into [VoxUiGlRenderer].
library;

import 'package:pixeldart/rendering/webgl/device_api.dart';

import '../../studio/studio.dart';
import 'voxui_gl_renderer.dart';

/// Single managed offscreen FBO for a docked Studio viewport (`scene` / `game`).
final class ViewportFboEntry {
  final String panelId;
  GpuObject? target;
  int width = 0;
  int height = 0;
  int resizeCount = 0;

  ViewportFboEntry(this.panelId);
}

/// Manages offscreen GLES3 FBOs for docked Scene & Game viewports (`[Wave G3]`).
final class ViewportFboHost {
  final GpuDevice _device;
  final Map<String, ViewportFboEntry> _entries = {};
  bool _disposed = false;

  ViewportFboHost(this._device);

  ViewportFboEntry? entryFor(String panelId) => _entries[panelId];

  /// Ensures an offscreen FBO exists for [slot] at its exact pixel dimensions
  /// (minimum 16×16), recreating cleanly on resize without leaking GPU targets.
  ViewportFboEntry ensureTarget(StudioViewportSlot slot) {
    if (_disposed) {
      throw StateError('ViewportFboHost has been disposed');
    }
    final w = slot.rect.width.round().clamp(16, 4096);
    final h = slot.rect.height.round().clamp(16, 4096);
    final entry = _entries.putIfAbsent(
      slot.panelId,
      () => ViewportFboEntry(slot.panelId),
    );
    if (entry.target == null || entry.width != w || entry.height != h) {
      if (entry.target != null) {
        _device.deleteTarget(entry.target!);
        entry.target = null;
      }
      entry.target = _device.createTarget(
        GpuTargetDescriptor(width: w, height: h, hasDepth: true),
      );
      entry.width = w;
      entry.height = h;
      entry.resizeCount++;
    }
    return entry;
  }

  /// Renders each active [StudioViewportSlot] into its offscreen FBO (invoking
  /// [renderPass] while bound), restores the default backbuffer, and returns
  /// the list of ready `(slot, entry)` pairs for compositing.
  List<(StudioViewportSlot, ViewportFboEntry)> renderViewports(
    List<StudioViewportSlot> slots, {
    void Function(StudioViewportSlot slot, ViewportFboEntry fbo)? renderPass,
  }) {
    final ready = <(StudioViewportSlot, ViewportFboEntry)>[];
    for (final slot in slots) {
      final entry = ensureTarget(slot);
      _device.bindTarget(entry.target);
      final isScene = slot.panelId == 'scene';
      _device.clear(
        ClearMask.colorAndDepth,
        r: isScene ? 0.11 : 0.08,
        g: isScene ? 0.13 : 0.10,
        b: isScene ? 0.17 : 0.14,
        a: 1.0,
      );
      renderPass?.call(slot, entry);
      ready.add((slot, entry));
    }
    _device.bindTarget(null);
    return ready;
  }

  /// Composites all rendered viewport FBOs into their exact docked rectangles.
  void compositeViewports(
    VoxUiGlRenderer uiRenderer,
    List<(StudioViewportSlot, ViewportFboEntry)> rendered, {
    required int windowWidth,
    required int windowHeight,
  }) {
    for (final (slot, entry) in rendered) {
      final target = entry.target;
      if (target == null) continue;
      uiRenderer.compositeViewportTexture(
        colorTexture: target,
        rect: slot.rect,
        viewportWidth: windowWidth,
        viewportHeight: windowHeight,
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _entries.values) {
      if (entry.target != null) {
        _device.deleteTarget(entry.target!);
        entry.target = null;
      }
    }
    _entries.clear();
  }
}
