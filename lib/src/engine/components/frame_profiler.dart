part of '../../engine.dart';

/// Linear frame bump arena, generational slab pool & rolling frame telemetry component (`voxalloc`) (E87-2).
final class FrameProfilerComponent extends Behaviour {
  int arenaCapacityBytes;
  int slabCapacity;
  int historyWindow;
  double targetFrameBudgetMs;
  bool autoResetArenaOnUpdate;
  bool paused;

  late alloc.LinearFrameArena frameArena;
  late alloc.FixedSlabPool<String> slabPool;
  late alloc.FrameTelemetryRecorder telemetry;

  FrameProfilerComponent({
    this.arenaCapacityBytes = 65536,
    this.slabCapacity = 256,
    this.historyWindow = 120,
    this.targetFrameBudgetMs = 16.6667,
    this.autoResetArenaOnUpdate = true,
    this.paused = false,
  }) {
    frameArena = alloc.LinearFrameArena(capacityBytes: arenaCapacityBytes);
    slabPool = alloc.FixedSlabPool<String>(capacity: slabCapacity);
    telemetry = alloc.FrameTelemetryRecorder(
      windowSize: historyWindow,
      budgetMs: targetFrameBudgetMs,
    );
  }

  static final spec = ComponentSpec<FrameProfilerComponent>(
    'FrameProfilerComponent',
    FrameProfilerComponent.new,
    [
      Field.integer(
        'arenaCapacityBytes',
        (c) => c.arenaCapacityBytes,
        (c, v) => c.arenaCapacityBytes = v,
      ),
      Field.integer(
        'slabCapacity',
        (c) => c.slabCapacity,
        (c, v) => c.slabCapacity = v,
      ),
      Field.integer(
        'historyWindow',
        (c) => c.historyWindow,
        (c, v) => c.historyWindow = v,
      ),
      Field.number(
        'targetFrameBudgetMs',
        (c) => c.targetFrameBudgetMs,
        (c, v) => c.targetFrameBudgetMs = v,
      ),
      Field.boolean(
        'autoResetArenaOnUpdate',
        (c) => c.autoResetArenaOnUpdate,
        (c, v) => c.autoResetArenaOnUpdate = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  alloc.ArenaAllocation? allocScratchBytes(int bytes, {int alignment = 8}) =>
      frameArena.alloc(bytes, alignment: alignment);

  alloc.SlabHandle? allocateSlab(String label) => slabPool.allocate(label);
  String? resolveSlab(alloc.SlabHandle handle) => slabPool.get(handle);
  bool freeSlab(alloc.SlabHandle handle) => slabPool.free(handle);

  void recordFrameSample(
    double durationMs, {
    List<alloc.TelemetrySpan> spans = const [],
  }) {
    telemetry.recordFrame(totalFrameMs: durationMs, spans: spans);
  }

  alloc.FrameTelemetryStats computeStats() => telemetry.computeStats();

  @override
  void update() {
    if (paused) return;
    final dtMs = math.max(0.0, time.unscaledDeltaTime * 1000.0);
    telemetry.recordFrame(
      totalFrameMs: dtMs,
      spans: [
        alloc.TelemetrySpan(
          name: 'EngineUpdate',
          durationMs: dtMs * 0.65,
          depth: 0,
        ),
        alloc.TelemetrySpan(
          name: 'SceneRender',
          durationMs: dtMs * 0.35,
          depth: 0,
        ),
      ],
    );
    if (autoResetArenaOnUpdate) {
      frameArena.resetFrame();
    }
  }
}

/// Persistent UI state for [ProfilerTelemetryInspectorUI.render].
final class ProfilerTelemetryInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` frame arena, slab pool & telemetry counter inspector (E87-2).
final class ProfilerTelemetryInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    ProfilerTelemetryInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
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
    FrameProfilerComponent prof, {
    ProfilerTelemetryInspectorUiState? state,
    String title = 'Frame Telemetry',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? ProfilerTelemetryInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final stats = prof.computeStats();
    ui.labelValue(
      'Mean / P99 (ms)',
      '${stats.meanMs.toStringAsFixed(2)}ms | P99 ${stats.p99Ms.toStringAsFixed(2)}ms',
      valueColor: stats.p99Ms > prof.targetFrameBudgetMs
          ? VoxColor.yellow
          : VoxColor.cyan,
    );
    ui.labelValue(
      'Arena Used / Peak',
      '${prof.frameArena.usedBytes} / ${prof.frameArena.peakBytes} B (cap ${prof.frameArena.capacityBytes} B)',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Slab Slots / Budget',
      '${prof.slabPool.activeCount}/${prof.slabPool.capacity} | ${(stats.budgetHitRate * 100).round()}% ok',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Samples / Status',
      '${prof.telemetry.totalFramesRecorded} frames | ${prof.paused ? 'Paused' : 'Active'}',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'prof_pause',
      prof.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      prof.paused = !prof.paused;
    }

    final allocRect = VoxRect(pauseRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'prof_alloc', 'Alloc +1KB', allocRect)) {
      prof.allocScratchBytes(1024);
    }

    final resetRect = VoxRect(allocRect.right + 8.0, barY, 96.0, 22.0);
    if (_drawButton(ui, uiState, 'prof_reset', 'Reset Arena', resetRect)) {
      prof.frameArena.resetFrame();
    }

    final recRect = VoxRect(resetRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'prof_rec', 'Sample 12ms', recRect)) {
      prof.recordFrameSample(12.0);
    }

    ui.endWindow();
  }
}
