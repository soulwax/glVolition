/// Pure-Dart Interactive Timeline & Dopesheet Canvas (`[Wave G12]`):
/// Renders [StudioTimelineModel] inside any docked `'timeline'` tab with
/// Play/Stop/Record controls, time ruler, draggable red playhead scrubber,
/// track headers, colored clip bars, and keyframe diamonds.
library;

import '../../../gl_volition.dart';
import '../timeline/timeline_model.dart';

/// Interactive Timeline & Dopesheet UI controller (`[Wave G12]`).
final class StudioTimelineCanvasController {
  double pixelsPerSecond = 80.0;
  double scrollSeconds = 0.0;
  bool isPlaying = false;
  bool _scrubbing = false;

  static const double _toolbarHeight = 26.0;
  static const double _rulerHeight = 22.0;
  static const double _headerWidth = 140.0;
  static const double _trackHeight = 28.0;

  /// Renders [timeline] inside [bounds] and processes playback & scrubbing.
  void render({
    required StudioTimelineModel timeline,
    required DrawList dl,
    required VoxInput input,
    required VoxRect bounds,
    double dtSeconds = 1.0 / 60.0,
  }) {
    if (isPlaying && dtSeconds > 0) {
      timeline.scrubTo(timeline.playheadSeconds + dtSeconds);
    }

    dl.addRectFilled(
      bounds.x,
      bounds.y,
      bounds.width,
      bounds.height,
      const VoxColor(34, 36, 40, 255),
    );

    // 1. Top Timeline toolbar
    dl.addRectFilled(
      bounds.x,
      bounds.y,
      bounds.width,
      _toolbarHeight,
      const VoxColor(42, 44, 48, 255),
    );
    final playRect = VoxRect(bounds.x + 8, bounds.y + 3, 52, 20);
    _miniButton(
      dl,
      input,
      playRect,
      isPlaying ? 'Stop' : 'Play',
      active: isPlaying,
      onClick: () => isPlaying = !isPlaying,
    );
    final recRect = VoxRect(bounds.x + 66, bounds.y + 3, 46, 20);
    _miniButton(
      dl,
      input,
      recRect,
      'Rec',
      active: timeline.recordMode,
      activeColor: const VoxColor(215, 65, 65, 255),
      onClick: () => timeline.recordMode = !timeline.recordMode,
    );
    final snapRect = VoxRect(bounds.x + 118, bounds.y + 3, 54, 20);
    _miniButton(
      dl,
      input,
      snapRect,
      'Snap',
      active: timeline.snapToFrames,
      onClick: () => timeline.snapToFrames = !timeline.snapToFrames,
    );
    dl.addText(
      't=${timeline.playheadSeconds.toStringAsFixed(2)}s  (${timeline.frameRate.round()} fps)',
      bounds.x + 184,
      bounds.y + 7,
      color: const VoxColor(210, 214, 222, 255),
      size: 11,
    );

    // 2. Time Ruler & Playhead Scrubbing
    final rulerX = bounds.x + _headerWidth;
    final rulerY = bounds.y + _toolbarHeight;
    final rulerW = (bounds.width - _headerWidth).clamp(40.0, double.infinity);
    final rulerRect = VoxRect(rulerX, rulerY, rulerW, _rulerHeight);

    dl.addRectFilled(
      bounds.x,
      rulerY,
      bounds.width,
      _rulerHeight,
      const VoxColor(46, 48, 54, 255),
    );
    dl.addText(
      'Tracks (${timeline.tracks.length})',
      bounds.x + 8,
      rulerY + 5,
      color: const VoxColor(165, 170, 180, 255),
      size: 11,
    );

    final visibleSecs = (rulerW / pixelsPerSecond).ceil() + 1;
    final startSec = scrollSeconds.floor();
    for (var s = startSec; s <= startSec + visibleSecs; s++) {
      final sx = rulerX + (s - scrollSeconds) * pixelsPerSecond;
      if (sx < rulerX || sx > bounds.right) continue;
      dl.addLine(
        sx,
        rulerY + 12,
        sx,
        rulerY + _rulerHeight,
        const VoxColor(110, 115, 125, 255),
      );
      dl.addText(
        '${s}s',
        sx + 3,
        rulerY + 3,
        color: const VoxColor(165, 170, 180, 255),
        size: 10,
      );
    }

    if (rulerRect.contains(input.mouseX, input.mouseY) &&
        input.wasMouseClicked) {
      _scrubbing = true;
    }
    if (_scrubbing && input.isMouseDown) {
      final t = scrollSeconds + (input.mouseX - rulerX) / pixelsPerSecond;
      timeline.scrubTo(t < 0 ? 0 : t);
    }
    if (input.wasMouseReleased) {
      _scrubbing = false;
    }

    // 3. Tracks, Clips & Keyframes
    var ty = rulerY + _rulerHeight;
    for (var i = 0; i < timeline.tracks.length && ty < bounds.bottom; i++) {
      final track = timeline.tracks[i];
      final bg = i.isEven
          ? const VoxColor(40, 42, 46, 255)
          : const VoxColor(36, 38, 42, 255);
      dl.addRectFilled(bounds.x, ty, bounds.width, _trackHeight, bg);
      dl.addLine(
        bounds.x,
        ty + _trackHeight - 1,
        bounds.right,
        ty + _trackHeight - 1,
        const VoxColor(26, 28, 32, 255),
      );
      dl.addText(
        '${track.name} [${track.kind.name}]',
        bounds.x + 8,
        ty + 8,
        color: track.muted
            ? const VoxColor(120, 120, 125, 255)
            : const VoxColor(215, 218, 224, 255),
        size: 10,
      );

      final clipColor = switch (track.kind) {
        TimelineTrackKind.animation => const VoxColor(58, 121, 187, 225),
        TimelineTrackKind.audio => const VoxColor(68, 165, 108, 225),
        TimelineTrackKind.camera => const VoxColor(158, 92, 196, 225),
        TimelineTrackKind.signal => const VoxColor(215, 155, 58, 225),
        TimelineTrackKind.activation => const VoxColor(95, 175, 165, 225),
      };
      for (final clip in track.clips) {
        final cx = rulerX + (clip.startTime - scrollSeconds) * pixelsPerSecond;
        final cw = (clip.duration * pixelsPerSecond).clamp(8.0, rulerW);
        if (cx + cw < rulerX || cx > bounds.right) continue;
        dl.addRectFilled(
          cx,
          ty + 4,
          cw,
          _trackHeight - 8,
          clipColor,
          cornerRadius: 3,
        );
        dl.addText(
          clip.id,
          cx + 4,
          ty + 8,
          color: const VoxColor(240, 240, 245, 255),
          size: 10,
        );
      }

      for (final key in track.keys) {
        final kx = rulerX + (key.time - scrollSeconds) * pixelsPerSecond;
        if (kx < rulerX || kx > bounds.right) continue;
        dl.addRectFilled(
          kx - 3,
          ty + _trackHeight * 0.5 - 3,
          6,
          6,
          const VoxColor(245, 210, 65, 255),
        );
      }

      ty += _trackHeight;
    }

    // 4. Red Playhead Line
    final playX =
        rulerX + (timeline.playheadSeconds - scrollSeconds) * pixelsPerSecond;
    if (playX >= rulerX && playX <= bounds.right) {
      dl.addRectFilled(
        playX - 4,
        rulerY,
        8,
        10,
        const VoxColor(235, 72, 72, 255),
      );
      dl.addLine(
        playX,
        rulerY,
        playX,
        bounds.bottom,
        const VoxColor(235, 72, 72, 255),
        thickness: 2,
      );
    }
  }

  void _miniButton(
    DrawList dl,
    VoxInput input,
    VoxRect r,
    String label, {
    bool active = false,
    VoxColor activeColor = const VoxColor(58, 121, 187, 255),
    required void Function() onClick,
  }) {
    final hov = r.contains(input.mouseX, input.mouseY);
    dl.addRectFilled(
      r.x,
      r.y,
      r.width,
      r.height,
      active
          ? activeColor
          : (hov
                ? const VoxColor(66, 68, 74, 255)
                : const VoxColor(54, 56, 60, 255)),
      cornerRadius: 3,
    );
    dl.addText(
      label,
      r.x + 8,
      r.y + 4,
      color: const VoxColor(230, 230, 235, 255),
      size: 11,
    );
    if (hov && input.wasMouseClicked) {
      onClick();
    }
  }
}
