part of '../../engine.dart';

/// Drives a multi-track [seq.TimelineSequence] within an engine [Scene] (E46-2).
///
/// Provides zero-boilerplate bindings from [seq.ValueTrack], [seq.CameraCutTrack],
/// [seq.SubtitleTrack], [seq.AudioCueTrack], and [seq.EventTrack] directly onto
/// [GameObject] transforms, [Camera] shots, active subtitle captions, and scene audio.
final class CutsceneDirectorComponent extends Behaviour {
  final seq.TimelineSequence sequence;

  /// When `true`, starts playback automatically inside [start].
  bool autoPlay;

  /// When `true`, forwards [seq.AudioCueTrack] triggers through [engine.audio] /
  /// [Scene.playClipAt] automatically.
  bool autoTriggerAudio;

  seq.SubtitleClip? _activeSubtitle;
  String? _activeCameraId;

  final List<void Function(seq.SubtitleClip? clip)> _subtitleListeners = [];
  final List<void Function(String? cameraId, Camera? camera)> _cameraListeners =
      [];

  CutsceneDirectorComponent({
    seq.TimelineSequence? sequence,
    String name = 'Cutscene',
    double? duration,
    seq.SequenceWrapMode wrapMode = seq.SequenceWrapMode.once,
    double speed = 1.0,
    this.autoPlay = false,
    this.autoTriggerAudio = true,
    void Function()? onCompleted,
    void Function(seq.SeqEventMarker marker)? onEvent,
  }) : sequence =
           sequence ??
           seq.TimelineSequence(
             name: name,
             duration: duration,
             wrapMode: wrapMode,
             speed: speed,
             onCompleted: onCompleted,
             onEvent: onEvent,
           ) {
    final prevAudio = this.sequence.onAudioCue;
    this.sequence.onAudioCue = (cue) {
      prevAudio?.call(cue);
      _dispatchAudioCue(cue);
    };
  }

  seq.SubtitleClip? get activeSubtitle => _activeSubtitle;
  String? get activeCameraId => _activeCameraId;
  bool get isPlaying => sequence.isPlaying;
  double get currentTime => sequence.currentTime;
  double get duration => sequence.effectiveDuration;

  void addSubtitleListener(void Function(seq.SubtitleClip? clip) listener) =>
      _subtitleListeners.add(listener);

  void addCameraCutListener(
    void Function(String? cameraId, Camera? camera) listener,
  ) => _cameraListeners.add(listener);

  void play({bool fromStart = false}) => sequence.play(fromStart: fromStart);
  void pause() => sequence.pause();
  void stop() => sequence.stop();
  void scrubTo(double targetTime, {bool fireEvents = false}) =>
      sequence.scrubTo(targetTime, fireEvents: fireEvents);

  /// Binds a position curve track to [target]'s [TransformComponent].
  seq.ValueTrack<seq.SeqVec3> bindPosition(
    String trackId,
    GameObject target, {
    String? name,
    bool local = false,
    Iterable<seq.SeqKeyframe<seq.SeqVec3>>? keys,
  }) {
    final track = seq.ValueTrack.vec3(
      id: trackId,
      name: name ?? '${target.name}.position',
      keys: keys,
      onEvaluate: (v) {
        final vec = Vec3(v.x, v.y, v.z);
        if (local) {
          target.transform.localPosition = vec;
        } else {
          target.transform.position = vec;
        }
      },
    );
    sequence.addTrack(track);
    return track;
  }

  /// Binds a rotation curve track (normalized linear interpolation) to [target]'s transform.
  seq.ValueTrack<seq.SeqQuat> bindRotation(
    String trackId,
    GameObject target, {
    String? name,
    bool local = false,
    Iterable<seq.SeqKeyframe<seq.SeqQuat>>? keys,
  }) {
    final track = seq.ValueTrack.quat(
      id: trackId,
      name: name ?? '${target.name}.rotation',
      keys: keys,
      onEvaluate: (q) {
        final rot = Quat(q.x, q.y, q.z, q.w).normalized;
        if (local) {
          target.transform.localRotation = rot;
        } else {
          target.transform.rotation = rot;
        }
      },
    );
    sequence.addTrack(track);
    return track;
  }

  /// Binds a uniform scale track to [target.transform.localScale].
  seq.ValueTrack<double> bindScale(
    String trackId,
    GameObject target, {
    String? name,
    Iterable<seq.SeqKeyframe<double>>? keys,
  }) {
    final track = seq.ValueTrack.scalar(
      id: trackId,
      name: name ?? '${target.name}.scale',
      keys: keys,
      onEvaluate: (s) => target.transform.localScale = s,
    );
    sequence.addTrack(track);
    return track;
  }

  /// Binds a boolean activation track to `target.setActive(...)`.
  seq.ValueTrack<bool> bindActive(
    String trackId,
    GameObject target, {
    String? name,
    Iterable<seq.SeqKeyframe<bool>>? keys,
  }) {
    final track = seq.ValueTrack.toggle(
      id: trackId,
      name: name ?? '${target.name}.active',
      keys: keys,
      onEvaluate: (active) => target.setActive(active),
    );
    sequence.addTrack(track);
    return track;
  }

  /// Binds a color gradient track to any engine RGB [LinearColor] sink (light color, material tint, etc.).
  seq.ValueTrack<seq.SeqColor> bindColor(
    String trackId,
    void Function(LinearColor color) onColor, {
    String? name,
    Iterable<seq.SeqKeyframe<seq.SeqColor>>? keys,
  }) {
    final track = seq.ValueTrack.color(
      id: trackId,
      name: name ?? trackId,
      keys: keys,
      onEvaluate: (c) => onColor(LinearColor(c.r, c.g, c.b)),
    );
    sequence.addTrack(track);
    return track;
  }

  /// Registers a camera-cut track toggling `gameObject.setActive` across named scene [Camera]s.
  seq.CameraCutTrack bindCameras(
    String trackId,
    Map<String, Camera> cameras, {
    String? name,
    bool disableInactive = true,
    void Function(String? cameraId, Camera? camera)? onCut,
  }) {
    final track = seq.CameraCutTrack(
      id: trackId,
      name: name ?? 'Cameras',
      onCameraCut: (camId) {
        _activeCameraId = camId;
        Camera? chosen;
        for (final entry in cameras.entries) {
          final match = entry.key == camId;
          if (match) chosen = entry.value;
          if (disableInactive && camId != null && entry.value.isAttached) {
            entry.value.gameObject.setActive(match);
          }
        }
        onCut?.call(camId, chosen);
        for (final listener in List.of(_cameraListeners)) {
          listener(camId, chosen);
        }
      },
    );
    sequence.addTrack(track);
    return track;
  }

  /// Registers a subtitle track updating [activeSubtitle] and notifying listeners.
  seq.SubtitleTrack bindSubtitles(
    String trackId, {
    String? name,
    void Function(seq.SubtitleClip? clip)? onSubtitleChanged,
  }) {
    final track = seq.SubtitleTrack(
      id: trackId,
      name: name ?? 'Subtitles',
      onSubtitleChanged: (clip) {
        _activeSubtitle = clip;
        onSubtitleChanged?.call(clip);
        for (final listener in List.of(_subtitleListeners)) {
          listener(clip);
        }
      },
    );
    sequence.addTrack(track);
    return track;
  }

  /// Registers an audio cue track dispatched automatically via [engine.audio] / [Scene.playClipAt].
  seq.AudioCueTrack bindAudioCues(
    String trackId, {
    String? name,
    void Function(seq.AudioCueClip cue)? onTriggerCue,
  }) {
    final track = seq.AudioCueTrack(
      id: trackId,
      name: name ?? 'Audio',
      onTriggerCue: onTriggerCue,
    );
    sequence.addTrack(track);
    return track;
  }

  void _dispatchAudioCue(seq.AudioCueClip cue) {
    if (!autoTriggerAudio || !isAttached || !scene.isLoaded) return;
    final clip = engine.audio.clip(cue.clipKey, volume: cue.volume);
    if (cue.spatial && cue.position != null) {
      final p = cue.position!;
      scene.playClipAt(
        clip,
        Vec3(p.x, p.y, p.z),
        volume: cue.volume,
        pitch: cue.pitch,
        spatialBlend: 1.0,
      );
    } else {
      engine.audio.playOneShot(clip, volume: cue.volume, pitch: cue.pitch);
    }
  }

  @override
  void start() {
    if (autoPlay) {
      sequence.play(fromStart: true);
    }
  }

  @override
  void update() {
    sequence.advance(time.deltaTime);
  }
}

/// Persistent UI interaction state for [TimelineSequencerUI.render].
final class TimelineSequencerUiState {
  bool isScrubbing = false;
  String? activeButtonId;
  String? selectedTrackId;
}

/// Immediate-mode multi-track timeline & transport scrubber rendered via `voxui` (E46-2).
final class TimelineSequencerUI {
  static const double _sidebarWidth = 132.0;
  static const double _rowHeight = 24.0;
  static const double _rulerHeight = 20.0;

  static bool _drawActionButton(
    VoxUiContext ui,
    TimelineSequencerUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) {
      state.activeButtonId = id;
    }
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
    seq.TimelineSequence sequence, {
    TimelineSequencerUiState? state,
    String? subtitlePreview,
    String title = 'Timeline Sequencer',
    double x = 20.0,
    double y = 20.0,
    double width = 560.0,
    double height = 280.0,
  }) {
    final uiState = state ?? TimelineSequencerUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final dur = sequence.effectiveDuration;
    final dl = ui.drawList;
    final inp = ui.input;

    final trackOriginX = x + pad;
    final barY = y + ui.style.titleBarHeight + pad;

    // Transport strip (explicit side-by-side layout)
    final playRect = VoxRect(trackOriginX, barY, 60.0, 22.0);
    if (_drawActionButton(
      ui,
      uiState,
      'transport_play',
      sequence.isPlaying ? 'Pause' : 'Play',
      playRect,
    )) {
      if (sequence.isPlaying) {
        sequence.pause();
      } else {
        sequence.play(fromStart: sequence.hasCompleted);
      }
    }

    final stopRect = VoxRect(playRect.right + 6.0, barY, 52.0, 22.0);
    if (_drawActionButton(ui, uiState, 'transport_stop', 'Stop', stopRect)) {
      sequence.stop();
    }

    final wrapLabel = sequence.wrapMode.name;
    final wrapRect = VoxRect(x + width - pad - 82.0, barY, 82.0, 22.0);
    if (_drawActionButton(ui, uiState, 'transport_wrap', wrapLabel, wrapRect)) {
      const modes = seq.SequenceWrapMode.values;
      sequence.wrapMode = modes[(sequence.wrapMode.index + 1) % modes.length];
    }

    dl.addText(
      '${sequence.currentTime.toStringAsFixed(2)}s / ${dur.toStringAsFixed(2)}s',
      stopRect.right + 12.0,
      barY + 4.0,
      color: VoxColor.cyan,
      size: ui.style.fontSize,
    );

    final rulerX = trackOriginX + _sidebarWidth;
    final rulerW = math.max(80.0, width - pad * 2 - _sidebarWidth);
    final rulerY = barY + 30.0;

    // Time ruler & scrub bar
    final rulerRect = VoxRect(rulerX, rulerY, rulerW, _rulerHeight);
    dl.addRectFilled(
      rulerX,
      rulerY,
      rulerW,
      _rulerHeight,
      const VoxColor(30, 34, 44, 255),
      cornerRadius: 3.0,
    );
    dl.addRectOutline(
      rulerX,
      rulerY,
      rulerW,
      _rulerHeight,
      ui.style.windowBorder,
      cornerRadius: 3.0,
    );

    // Tick marks along ruler
    const tickCount = 4;
    for (int i = 0; i <= tickCount; i++) {
      final frac = i / tickCount;
      final tx = rulerX + frac * rulerW;
      dl.addLine(
        tx,
        rulerY + _rulerHeight - 6.0,
        tx,
        rulerY + _rulerHeight,
        VoxColor.lightGray,
      );
      final stamp = (frac * dur).toStringAsFixed(1);
      dl.addText(
        '${stamp}s',
        math.min(tx + 2.0, rulerRect.right - 26.0),
        rulerY + 3.0,
        color: VoxColor.lightGray,
        size: 10.0,
      );
    }

    // Handle ruler scrub interaction
    if (rulerRect.contains(inp.mouseX, inp.mouseY) && inp.wasMouseClicked) {
      uiState.isScrubbing = true;
    }
    if (!inp.isMouseDown && !inp.wasMouseClicked) {
      uiState.isScrubbing = false;
    }
    if (uiState.isScrubbing && dur > 0.0) {
      final frac = ((inp.mouseX - rulerX) / rulerW).clamp(0.0, 1.0);
      sequence.scrubTo(frac * dur, fireEvents: false);
    }

    // Tracks
    final tracks = sequence.tracks;
    var rowY = rulerY + _rulerHeight + 6.0;
    final contentBottomLimit =
        y + height - (subtitlePreview != null ? 30.0 : 12.0);

    for (final track in tracks) {
      if (rowY + _rowHeight > contentBottomLimit) break;

      // Sidebar label & Mute pill
      dl.addRectFilled(
        trackOriginX,
        rowY,
        _sidebarWidth - 6.0,
        _rowHeight - 2.0,
        uiState.selectedTrackId == track.id
            ? const VoxColor(52, 64, 86, 255)
            : const VoxColor(34, 38, 48, 255),
        cornerRadius: 3.0,
      );

      final muteRect = VoxRect(
        trackOriginX + 4.0,
        rowY + 3.0,
        18.0,
        _rowHeight - 8.0,
      );
      if (muteRect.contains(inp.mouseX, inp.mouseY) && inp.wasMouseClicked) {
        track.muted = !track.muted;
      }
      dl.addRectFilled(
        muteRect.x,
        muteRect.y,
        muteRect.width,
        muteRect.height,
        track.muted ? VoxColor.red : const VoxColor(60, 70, 90, 255),
        cornerRadius: 2.0,
      );
      dl.addText(
        'M',
        muteRect.x + 5.0,
        muteRect.y + 1.0,
        color: VoxColor.white,
        size: 10.0,
      );
      dl.addText(
        track.name,
        muteRect.right + 6.0,
        rowY + 4.0,
        color: track.muted ? VoxColor.gray : VoxColor.white,
        size: 11.0,
      );

      // Lane background
      final laneRect = VoxRect(rulerX, rowY, rulerW, _rowHeight - 2.0);
      if (laneRect.contains(inp.mouseX, inp.mouseY) && inp.wasMouseClicked) {
        uiState.selectedTrackId = track.id;
      }
      dl.addRectFilled(
        laneRect.x,
        laneRect.y,
        laneRect.width,
        laneRect.height,
        const VoxColor(22, 24, 30, 240),
        cornerRadius: 3.0,
      );

      final invDur = dur > 0.0 ? (1.0 / dur) : 0.0;
      if (track is seq.ValueTrack) {
        for (final key in track.keyframes) {
          final kx = rulerX + (key.time * invDur).clamp(0.0, 1.0) * rulerW;
          dl.addCircleFilled(
            kx,
            rowY + (_rowHeight - 2.0) * 0.5,
            4.0,
            VoxColor.yellow,
          );
        }
      } else if (track is seq.EventTrack) {
        for (final marker in track.markers) {
          final mx = rulerX + (marker.time * invDur).clamp(0.0, 1.0) * rulerW;
          dl.addLine(
            mx,
            rowY + 2.0,
            mx,
            rowY + _rowHeight - 4.0,
            const VoxColor(255, 145, 50, 255),
            thickness: 2.0,
          );
          dl.addCircleFilled(
            mx,
            rowY + 6.0,
            3.5,
            const VoxColor(255, 145, 50, 255),
          );
        }
      } else if (track is seq.AudioCueTrack) {
        for (final cue in track.cues) {
          final cx = rulerX + (cue.startTime * invDur).clamp(0.0, 1.0) * rulerW;
          final endX = cue.endTime > cue.startTime
              ? rulerX + (cue.endTime * invDur).clamp(0.0, 1.0) * rulerW
              : cx + 10.0;
          final cw = math.max(6.0, endX - cx);
          dl.addRectFilled(
            cx,
            rowY + 3.0,
            cw,
            _rowHeight - 8.0,
            const VoxColor(90, 185, 110, 220),
            cornerRadius: 2.0,
          );
        }
      } else if (track is seq.CameraCutTrack) {
        for (final shot in track.shots) {
          final sx =
              rulerX + (shot.startTime * invDur).clamp(0.0, 1.0) * rulerW;
          final ex = rulerX + (shot.endTime * invDur).clamp(0.0, 1.0) * rulerW;
          final sw = math.max(8.0, ex - sx);
          dl.addRectFilled(
            sx,
            rowY + 3.0,
            sw,
            _rowHeight - 8.0,
            const VoxColor(60, 140, 225, 220),
            cornerRadius: 2.0,
          );
          dl.addText(
            shot.cameraId,
            sx + 4.0,
            rowY + 5.0,
            color: VoxColor.white,
            size: 10.0,
          );
        }
      } else if (track is seq.SubtitleTrack) {
        for (final sub in track.clips) {
          final sx = rulerX + (sub.startTime * invDur).clamp(0.0, 1.0) * rulerW;
          final ex = rulerX + (sub.endTime * invDur).clamp(0.0, 1.0) * rulerW;
          final sw = math.max(8.0, ex - sx);
          dl.addRectFilled(
            sx,
            rowY + 3.0,
            sw,
            _rowHeight - 8.0,
            const VoxColor(175, 95, 215, 220),
            cornerRadius: 2.0,
          );
          dl.addText(
            sub.speaker,
            sx + 4.0,
            rowY + 5.0,
            color: VoxColor.white,
            size: 10.0,
          );
        }
      }

      rowY += _rowHeight + 4.0;
    }

    // Playhead vertical cursor spanning ruler & tracks
    if (dur > 0.0) {
      final px = rulerX + (sequence.currentTime / dur).clamp(0.0, 1.0) * rulerW;
      dl.addLine(
        px,
        rulerY,
        px,
        math.max(rulerY + _rulerHeight, rowY - 2.0),
        VoxColor.red,
        thickness: 2.0,
      );
    }

    if (subtitlePreview != null && subtitlePreview.isNotEmpty) {
      dl.addText(
        subtitlePreview,
        trackOriginX,
        y + height - 22.0,
        color: VoxColor.yellow,
        size: ui.style.fontSize - 1.0,
      );
    }

    ui.endWindow();
  }
}
