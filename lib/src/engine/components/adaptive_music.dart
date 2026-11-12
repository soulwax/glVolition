part of '../../engine.dart';

/// Interactive adaptive score & stem mix director binding `voxscore` onto engine [AudioSource]s (E71-2).
final class AdaptiveMusicComponent extends Behaviour {
  double targetIntensity;
  double intensitySmoothingPerSecond;
  bool paused;

  final score.InteractiveScoreConductor conductor;
  final Map<String, AudioSource> _stemSources = {};
  final Map<String, AudioClip> _stingerClips = {};
  final List<String> _sectionOrder = [];
  final List<String> _stingerOrder = [];

  score.ScoreMixSnapshot? _lastSnapshot;

  AdaptiveMusicComponent({
    double initialIntensity = 0.2,
    this.targetIntensity = 0.2,
    this.intensitySmoothingPerSecond = 2.5,
    this.paused = false,
  }) : conductor = score.InteractiveScoreConductor(
          initialIntensity: initialIntensity,
          intensitySmoothingPerSecond: intensitySmoothingPerSecond,
        ) {
    conductor.targetIntensity = targetIntensity.clamp(0.0, 1.0).toDouble();
  }

  static final spec = ComponentSpec<AdaptiveMusicComponent>(
    'AdaptiveMusicComponent',
    AdaptiveMusicComponent.new,
    [
      Field.number(
        'targetIntensity',
        (m) => m.targetIntensity,
        (m, v) => m.setIntensity(v),
      ),
      Field.number(
        'intensitySmoothingPerSecond',
        (m) => m.intensitySmoothingPerSecond,
        (m, v) => m.intensitySmoothingPerSecond = v,
      ),
      Field.boolean('paused', (m) => m.paused, (m, v) => m.paused = v),
    ],
  );

  String? get activeSectionId => conductor.activeSectionId;
  String? get pendingSectionId => conductor.pendingSectionId;
  score.ScoreMixSnapshot? get lastSnapshot => _lastSnapshot;

  void registerSection(score.MusicSectionDef section) {
    conductor.registerSection(section);
    if (!_sectionOrder.contains(section.id)) _sectionOrder.add(section.id);
  }

  void registerStinger(score.MusicStingerCue cue, {AudioClip? clip}) {
    conductor.registerStinger(cue);
    if (!_stingerOrder.contains(cue.id)) _stingerOrder.add(cue.id);
    if (clip != null) _stingerClips[cue.id] = clip;
  }

  void bindStemSource(String stemId, AudioSource source) {
    _stemSources[stemId] = source;
  }

  void setIntensity(double value, {bool immediate = false}) {
    targetIntensity = value.clamp(0.0, 1.0).toDouble();
    conductor.setIntensity(targetIntensity, immediate: immediate);
  }

  bool startSection(String sectionId) => conductor.startSection(sectionId);

  bool requestSection(
    String sectionId, {
    score.MusicQuantization quantization = score.MusicQuantization.nextBar,
  }) =>
      conductor.requestSection(sectionId, quantization: quantization);

  bool queueStinger(String stingerId) => conductor.queueStinger(stingerId);

  /// Cycles to the next registered section using beat/bar quantization.
  bool cycleNextSection({
    score.MusicQuantization quantization = score.MusicQuantization.nextBar,
  }) {
    if (_sectionOrder.isEmpty) return false;
    final currIdx = activeSectionId == null ? -1 : _sectionOrder.indexOf(activeSectionId!);
    final nextId = _sectionOrder[(currIdx + 1) % _sectionOrder.length];
    return requestSection(nextId, quantization: quantization);
  }

  score.ScoreMixSnapshot stepMusic(double dt) {
    conductor.intensitySmoothingPerSecond = intensitySmoothingPerSecond;
    conductor.targetIntensity = targetIntensity.clamp(0.0, 1.0).toDouble();
    final snap = conductor.step(dt);
    _lastSnapshot = snap;

    // Drive bound AudioSource stem volumes smoothly
    for (final entry in _stemSources.entries) {
      final gain = snap.stemGains[entry.key] ?? 0.0;
      entry.value.volume = gain;
      if (gain > 1e-3 && !entry.value.isPlaying && entry.value.clip != null && entry.value.isAttached) {
        entry.value.play();
      }
    }

    // Trigger one-shot stinger audio clips at exact beat boundary
    if (isAttached && scene.isLoaded) {
      final busGain = scene.audioMixer.effectiveBusGain('music');
      for (final stId in snap.firedStingersThisStep) {
        final clip = _stingerClips[stId];
        if (clip != null) {
          engine.audio.playOneShot(clip, volume: busGain);
        }
      }
    }

    return snap;
  }

  @override
  void update() {
    if (paused) return;
    stepMusic(time.deltaTime);
  }
}

/// Persistent UI interaction state for [MusicScoreInspectorUI.render].
final class MusicScoreInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` BPM clock, stem gains & quantized cue monitor (E71-2).
final class MusicScoreInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    MusicScoreInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked = hovered && state.activeButtonId == id && inp.wasMouseReleased;
    if (inp.wasMouseReleased && state.activeButtonId == id) state.activeButtonId = null;

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(rect.x, rect.y, rect.width, rect.height, bg, cornerRadius: ui.style.frameRounding);
    dl.addRectOutline(rect.x, rect.y, rect.width, rect.height, ui.style.windowBorder, cornerRadius: ui.style.frameRounding);
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
    AdaptiveMusicComponent music, {
    String? stingerId,
    MusicScoreInspectorUiState? state,
    String title = 'Adaptive Music Score',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? MusicScoreInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final sec = music.conductor.activeSection;
    final clock = music.conductor.clock;
    final snap = music.lastSnapshot;

    ui.labelValue(
      'Section / BPM',
      '${sec?.name ?? "None"} (${clock.bpm.round()} BPM)',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Bar : Beat',
      '${clock.currentBar + 1} : ${clock.beatInBar + 1}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Intensity / Duck',
      '${(music.conductor.intensity * 100).round()}% / ${(snap?.musicDuckMultiplier ?? 1.0).toStringAsFixed(2)}x',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Pending Transition',
      music.pendingSectionId ?? 'Steady',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final intRect = VoxRect(x + pad, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'msc_int', 'Int +0.3', intRect)) {
      music.setIntensity((music.targetIntensity + 0.3).clamp(0.0, 1.0));
    }

    final stingerRect = VoxRect(intRect.right + 8.0, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'msc_sting', 'Stinger', stingerRect)) {
      final sid = stingerId ?? (music._stingerOrder.isNotEmpty ? music._stingerOrder.first : null);
      if (sid != null) {
        music.queueStinger(sid);
      }
    }

    final secRect = VoxRect(stingerRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'msc_sec', 'Next Sec', secRect)) {
      music.cycleNextSection();
    }

    ui.endWindow();
  }
}
