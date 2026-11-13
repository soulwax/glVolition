part of '../../engine.dart';

/// Integrates [stat.TelemetryBus], [stat.MetricRegistry], [stat.AchievementTracker],
/// [stat.ComboTracker], and [stat.Leaderboard]s onto a [GameObject] with automatic
/// persistence via [EngineHost.storage] (E47-2).
final class ProgressionStatsComponent extends Behaviour {
  final stat.TelemetryBus telemetry = stat.TelemetryBus();
  final stat.MetricRegistry metrics = stat.MetricRegistry();
  late final stat.AchievementTracker achievements;
  final stat.ComboTracker combo;
  final Map<String, stat.Leaderboard> leaderboards = {};

  bool autoEvaluateAchievements;
  double toastDisplayDuration;

  stat.AchievementDef? _activeToast;
  double _toastTimer = 0.0;

  void Function(stat.AchievementDef unlocked)? onAchievementUnlocked;

  ProgressionStatsComponent({
    double comboDecayDuration = 3.0,
    double comboMultiplierStep = 0.25,
    double comboMaxMultiplier = 8.0,
    this.autoEvaluateAchievements = true,
    this.toastDisplayDuration = 3.0,
    this.onAchievementUnlocked,
  }) : combo = stat.ComboTracker(
         decayDuration: comboDecayDuration,
         multiplierStep: comboMultiplierStep,
         maxMultiplier: comboMaxMultiplier,
       ) {
    achievements = stat.AchievementTracker(
      metrics: metrics,
      telemetry: telemetry,
      onUnlocked: (def) {
        onAchievementUnlocked?.call(def);
        voxlog.info('[Achievement Unlocked] ${def.title} (+${def.points}pt)');
      },
    );
  }

  stat.AchievementDef? get activeToast => _activeToast;
  double get activeToastRemaining => _toastTimer;

  void registerAchievements(Iterable<stat.AchievementDef> defs) =>
      achievements.registerAll(defs);

  stat.Leaderboard leaderboard(
    String boardId, {
    bool higherIsBetter = true,
    int maxEntries = 100,
    bool keepBestPerPlayer = true,
  }) => leaderboards.putIfAbsent(
    boardId,
    () => stat.Leaderboard(
      boardId: boardId,
      higherIsBetter: higherIsBetter,
      maxEntries: maxEntries,
      keepBestPerPlayer: keepBestPerPlayer,
    ),
  );

  List<stat.AchievementDef> recordMetric(
    String id,
    double value, {
    stat.MetricAggregateMode defaultMode = stat.MetricAggregateMode.sum,
  }) {
    metrics.record(id, value, defaultMode: defaultMode);
    if (autoEvaluateAchievements) {
      return achievements.evaluate();
    }
    return const [];
  }

  List<stat.AchievementDef> incrementMetric(String id, [double amount = 1.0]) =>
      recordMetric(id, amount);

  List<stat.AchievementDef> emitEvent(
    String type, {
    double value = 1.0,
    Map<String, Object?> payload = const {},
  }) {
    telemetry.emit(type, value: value, payload: payload);
    if (autoEvaluateAchievements) {
      return achievements.evaluate();
    }
    return const [];
  }

  double registerComboHit({double basePoints = 100.0, double bonusTime = 0.0}) {
    final pts = combo.registerHit(basePoints: basePoints, bonusTime: bonusTime);
    metrics.record(
      'best_combo',
      combo.bestCombo.toDouble(),
      defaultMode: stat.MetricAggregateMode.max,
    );
    metrics.record('combo_score', pts);
    if (autoEvaluateAchievements) {
      achievements.evaluate();
    }
    return pts;
  }

  int? submitScore(
    String boardId, {
    required String playerId,
    required String displayName,
    required double score,
    int? timestampMs,
    Map<String, Object?> metadata = const {},
  }) {
    final board = leaderboard(boardId);
    final ts =
        timestampMs ??
        (isAttached ? (engine.time.unscaledTime * 1000).round() : 0);
    return board.submit(
      stat.LeaderboardEntry(
        playerId: playerId,
        displayName: displayName,
        score: score,
        timestampMs: ts,
        metadata: metadata,
      ),
    );
  }

  void saveToStorage([String key = 'voxstat_profile']) {
    if (!isAttached) return;
    final payload = <String, Object?>{
      'metrics': metrics.toJson(),
      'achievements': achievements.toJson(),
      'leaderboards': {
        for (final entry in leaderboards.entries)
          entry.key: entry.value.toJson(),
      },
    };
    engine.host.storage.write(key, jsonEncode(payload));
  }

  bool loadFromStorage([String key = 'voxstat_profile']) {
    if (!isAttached) return false;
    final raw = engine.host.storage.read(key);
    if (raw == null || raw.isEmpty) return false;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return false;

    final metricsMap = decoded['metrics'];
    if (metricsMap is Map) {
      metrics.loadJson(metricsMap.cast<String, Object?>());
    }
    final achMap = decoded['achievements'];
    if (achMap is Map) {
      achievements.loadJson(achMap.cast<String, Object?>());
    }
    final boardsMap = decoded['leaderboards'];
    if (boardsMap is Map) {
      for (final entry in boardsMap.entries) {
        if (entry.value is Map) {
          leaderboards[entry.key.toString()] = stat.Leaderboard.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          );
        }
      }
    }
    return true;
  }

  @override
  void update() {
    final dt = time.deltaTime;
    telemetry.step(dt);
    combo.step(dt);

    if (_activeToast != null) {
      _toastTimer -= dt;
      if (_toastTimer <= 0.0) {
        _activeToast = null;
        _toastTimer = 0.0;
      }
    }
    if (_activeToast == null && achievements.hasPendingToasts) {
      _activeToast = achievements.popToast();
      _toastTimer = toastDisplayDuration;
    }
  }
}

/// Immediate-mode `voxui` progression overlay showing achievement unlock toasts,
/// combo rank multiplier gauge, achievement progress list, and leaderboard entries.
final class AchievementsHudUI {
  static void render(
    VoxUiContext ui,
    ProgressionStatsComponent progression, {
    String? leaderboardId,
    String title = 'Progression & Achievements',
    double x = 20.0,
    double y = 20.0,
    double width = 340.0,
    double height = 300.0,
  }) {
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final toast = progression.activeToast;
    if (toast != null) {
      ui.text(
        'UNLOCKED: ${toast.title} (+${toast.points} pts)',
        color: VoxColor.yellow,
      );
      ui.separator();
    }

    // Combo multiplier bar
    final combo = progression.combo;
    final prevGrab = ui.style.sliderGrab;
    if (combo.count > 0) {
      ui.text(
        'Combo x${combo.count} [${combo.rank.badge}] (${combo.multiplier.toStringAsFixed(2)}x)',
        color: VoxColor.cyan,
      );
      ui.style.sliderGrab = const VoxColor(245, 165, 45, 255);
      ui.progressBar(
        combo.decayFraction,
        overlay: 'Score: ${combo.totalScore.round()}',
      );
      ui.style.sliderGrab = prevGrab;
    } else {
      ui.labelValue(
        'Total Score',
        '${combo.totalScore.round()}',
        valueColor: VoxColor.lightGray,
      );
    }

    ui.separator();
    final ach = progression.achievements;
    ui.labelValue(
      'Achievements',
      '${ach.unlockedCount}/${ach.totalCount} (${ach.totalPointsEarned} pts)',
      valueColor: VoxColor.green,
    );

    for (final state in ach.all) {
      final prefix = state.unlocked ? '[x]' : '[ ]';
      ui.text(
        '$prefix ${state.def.title} - ${state.visibleDescription}',
        color: state.unlocked ? VoxColor.green : ui.style.text,
      );
      ui.style.sliderGrab = state.unlocked ? VoxColor.green : VoxColor.blue;
      ui.progressBar(
        state.progress,
        height: 12.0,
        overlay: '${(state.progress * 100).round()}%',
      );
      ui.style.sliderGrab = prevGrab;
    }

    if (leaderboardId != null) {
      final board = progression.leaderboards[leaderboardId];
      if (board != null && board.entries.isNotEmpty) {
        ui.separator();
        ui.text('Leaderboard: ${board.boardId}', color: VoxColor.cyan);
        final top = board.top(5);
        for (int i = 0; i < top.length; i++) {
          final e = top[i];
          ui.labelValue('#${i + 1} ${e.displayName}', '${e.score.round()}');
        }
      }
    }

    ui.endWindow();
  }
}
