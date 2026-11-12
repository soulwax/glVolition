part of '../../engine.dart';

/// Beat-synced rhythm chart sequencer, hit timing judge & DSP latency calibration (`voxrhythm`) (E76-2).
final class RhythmSequencerComponent extends Behaviour {
  double bpm;
  int beatsPerBar;
  int subdivision;
  double audioOffsetSeconds;
  double lookaheadSeconds;
  bool paused;
  bool loopChart;
  bool autoPlayDemo;

  rhythm.RhythmChart? chart;
  rhythm.BeatGrid? _grid;
  rhythm.HitWindows hitWindows;
  late rhythm.RhythmSessionTracker tracker;

  AudioSource? syncAudioSource;
  double songSeconds = 0.0;
  int _lastWholeBeat = -1;

  void Function(rhythm.NoteJudgment judgment)? onJudgment;
  void Function(int beatIndex, int barIndex)? onBeatCrossed;

  RhythmSequencerComponent({
    this.bpm = 120.0,
    this.beatsPerBar = 4,
    this.subdivision = 4,
    this.audioOffsetSeconds = 0.0,
    this.lookaheadSeconds = 1.5,
    this.paused = false,
    this.loopChart = false,
    this.autoPlayDemo = false,
    this.chart,
    this.hitWindows = const rhythm.HitWindows.standard(),
    this.syncAudioSource,
  }) {
    tracker = rhythm.RhythmSessionTracker(windows: hitWindows);
    _syncGrid();
  }

  static final spec = ComponentSpec<RhythmSequencerComponent>(
    'RhythmSequencerComponent',
    RhythmSequencerComponent.new,
    [
      Field.number('bpm', (r) => r.bpm, (r, v) => r.setBpm(v)),
      Field.integer('beatsPerBar', (r) => r.beatsPerBar, (r, v) => r.beatsPerBar = v),
      Field.integer('subdivision', (r) => r.subdivision, (r, v) => r.subdivision = v),
      Field.number(
        'audioOffsetSeconds',
        (r) => r.audioOffsetSeconds,
        (r, v) => r.setAudioOffsetSeconds(v),
      ),
      Field.number(
        'lookaheadSeconds',
        (r) => r.lookaheadSeconds,
        (r, v) => r.lookaheadSeconds = v,
      ),
      Field.boolean('paused', (r) => r.paused, (r, v) => r.paused = v),
      Field.boolean('loopChart', (r) => r.loopChart, (r, v) => r.loopChart = v),
      Field.boolean(
        'autoPlayDemo',
        (r) => r.autoPlayDemo,
        (r, v) => r.autoPlayDemo = v,
      ),
    ],
  );

  void _syncGrid() {
    final safeBpm = math.max(1.0, bpm);
    final safeSub = math.max(1, subdivision);
    final safeBpb = math.max(1, beatsPerBar);
    final g = _grid;
    if (g == null) {
      _grid = rhythm.BeatGrid(
        bpm: safeBpm,
        beatsPerBar: safeBpb,
        subdivision: safeSub,
        audioOffsetSeconds: audioOffsetSeconds,
      );
    } else {
      if ((g.bpm - safeBpm).abs() > 1e-6) {
        g.setBaseBpm(safeBpm);
      }
      g.beatsPerBar = safeBpb;
      g.subdivision = safeSub;
      g.audioOffsetSeconds = audioOffsetSeconds;
    }
  }

  rhythm.BeatGrid get beatGrid {
    _syncGrid();
    return _grid!;
  }

  int get score => tracker.score;
  int get combo => tracker.combo;
  int get maxCombo => tracker.maxCombo;
  int get multiplier => tracker.multiplier;
  double get accuracy => tracker.accuracy;
  double get currentBeat => beatGrid.secondsToBeat(songSeconds);
  double get beatPhase => beatGrid.beatPhaseAt(songSeconds);
  rhythm.NoteJudgment? get lastJudgment => tracker.lastJudgment;

  void setBpm(double nextBpm) {
    bpm = math.max(1.0, nextBpm);
    _syncGrid();
  }

  void setAudioOffsetSeconds(double offsetSeconds) {
    audioOffsetSeconds = offsetSeconds.clamp(-0.5, 0.5).toDouble();
    _syncGrid();
  }

  void loadChart(rhythm.RhythmChart nextChart, {bool resetClock = true}) {
    chart = nextChart;
    if (resetClock) {
      resetSession();
    }
  }

  void resetSession() {
    songSeconds = 0.0;
    _lastWholeBeat = -1;
    tracker.reset();
  }

  List<rhythm.LookaheadNoteView> queryActiveNotes({
    double pastGraceSeconds = 0.25,
    bool excludeJudged = true,
  }) {
    final c = chart;
    if (c == null) return const [];
    return c.queryLookahead(
      grid: beatGrid,
      songSeconds: songSeconds,
      lookaheadSeconds: lookaheadSeconds,
      pastGraceSeconds: pastGraceSeconds,
      excludeNoteIds: excludeJudged ? tracker.judgedNoteIds : null,
    );
  }

  rhythm.NoteJudgment? submitLaneInput(int lane) {
    final c = chart;
    if (c == null) return null;
    final judgment = tracker.judgeInput(
      lane: lane,
      songSeconds: songSeconds,
      chart: c,
      grid: beatGrid,
    );
    if (judgment != null) {
      onJudgment?.call(judgment);
    }
    return judgment;
  }

  rhythm.NoteJudgment? releaseLaneHold(int lane) {
    final judgment = tracker.releaseHold(
      lane: lane,
      songSeconds: songSeconds,
    );
    if (judgment != null) {
      onJudgment?.call(judgment);
    }
    return judgment;
  }

  /// Applies outlier-trimmed DSP latency calibration from recent hit offsets.
  double calibrateLatencyFromRecentHits({double damping = 0.75}) {
    if (tracker.recentHitDeltas.isEmpty) return audioOffsetSeconds;
    final next = beatGrid.calibrateOffsetFromSamples(
      tracker.recentHitDeltas,
      damping: damping,
    );
    audioOffsetSeconds = next;
    return next;
  }

  /// Advances song playback clock, emits beat callbacks, auto-hits in demo mode & expires missed notes.
  List<rhythm.NoteJudgment> stepSequencer(double dt) {
    _syncGrid();
    final grid = _grid!;
    if (dt > 0.0) {
      songSeconds += dt;
    }

    final c = chart;
    final barPos = grid.barPositionAt(songSeconds);
    final wholeBeat = (barPos.exactBeat + 1e-9).floor();
    if (wholeBeat > _lastWholeBeat) {
      _lastWholeBeat = wholeBeat;
      onBeatCrossed?.call(wholeBeat, barPos.bar);
    }

    final emitted = <rhythm.NoteJudgment>[];
    if (c != null) {
      if (autoPlayDemo) {
        for (final n in c.notes) {
          if (tracker.judgedNoteIds.contains(n.id)) continue;
          final targetSec = grid.judgedSecondsForBeat(n.beat);
          if (songSeconds >= targetSec - 0.004 &&
              (songSeconds - targetSec).abs() <= hitWindows.miss) {
            final j = tracker.judgeInput(
              lane: n.lane,
              songSeconds: targetSec,
              chart: c,
              grid: grid,
            );
            if (j != null) {
              emitted.add(j);
              onJudgment?.call(j);
            }
          }
        }
      }

      final advJudgments = tracker.advance(
        songSeconds: songSeconds,
        chart: c,
        grid: grid,
      );
      for (final j in advJudgments) {
        emitted.add(j);
        onJudgment?.call(j);
      }

      if (loopChart &&
          songSeconds > c.totalDurationSeconds(grid) + hitWindows.miss + 0.25) {
        resetSession();
      }
    }

    return emitted;
  }

  @override
  void update() {
    if (paused) return;
    stepSequencer(time.deltaTime);
  }
}

/// Persistent UI state for [RhythmJudgeUI.render].
final class RhythmJudgeUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` rhythm timing, combo & DSP latency calibration overlay (E76-2).
final class RhythmJudgeUI {
  static bool _drawButton(
    VoxUiContext ui,
    RhythmJudgeUiState state,
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
    RhythmSequencerComponent seq, {
    RhythmJudgeUiState? state,
    String title = 'Rhythm Sequencer',
    double x = 20.0,
    double y = 20.0,
    double width = 390.0,
    double height = 250.0,
  }) {
    final uiState = state ?? RhythmJudgeUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final barPos = seq.beatGrid.barPositionAt(seq.songSeconds);
    ui.labelValue(
      'Tempo / DSP',
      '${seq.bpm.toStringAsFixed(1)} BPM | ofs ${(seq.audioOffsetSeconds * 1000.0).toStringAsFixed(1)} ms',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Beat / Chart',
      'Bar ${barPos.bar + 1}.${barPos.beatInBar + 1} | ${seq.chart?.title ?? 'None'}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Score / Combo',
      '${seq.score} | ${seq.combo}x (mult ${seq.multiplier}x, ${(seq.accuracy * 100.0).toStringAsFixed(1)}%)',
      valueColor: VoxColor.green,
    );

    final last = seq.lastJudgment;
    final judgeText = last == null
        ? 'Waiting for input'
        : '${last.grade.name.toUpperCase()} (${last.deltaMs >= 0 ? '+' : ''}${last.deltaMs.toStringAsFixed(1)} ms)';
    ui.labelValue(
      'Last Judge',
      judgeText,
      valueColor: last == null
          ? VoxColor.lightGray
          : (last.isHit ? VoxColor.yellow : VoxColor.red),
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final playRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'rhy_play', seq.paused ? 'Play' : 'Pause', playRect)) {
      seq.paused = !seq.paused;
    }

    final minusRect = VoxRect(playRect.right + 8.0, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'rhy_minus', 'Ofs -5ms', minusRect)) {
      seq.setAudioOffsetSeconds(seq.audioOffsetSeconds - 0.005);
    }

    final plusRect = VoxRect(minusRect.right + 8.0, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'rhy_plus', 'Ofs +5ms', plusRect)) {
      seq.setAudioOffsetSeconds(seq.audioOffsetSeconds + 0.005);
    }

    final calRect = VoxRect(plusRect.right + 8.0, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'rhy_cal', 'Calibrate', calRect)) {
      seq.calibrateLatencyFromRecentHits();
    }

    ui.endWindow();
  }
}
