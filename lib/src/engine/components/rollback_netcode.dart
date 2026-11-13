part of '../../engine.dart';

/// Captured scene actor transforms and custom simulation state for a rollback checkpoint (E73-2).
final class EngineRollbackSnapshot {
  final Map<int, ({Vec3 pos, Quat rot, double scale})> transforms;
  final Map<String, Object?>? customState;

  const EngineRollbackSnapshot({required this.transforms, this.customState});
}

/// Deterministic rollback netcode session coordinator binding `voxrollback` onto scene
/// transforms and custom simulation state (E73-2).
final class RollbackSessionComponent extends Behaviour {
  int playerCount;
  int localPlayerId;
  int maxRollbackFrames;
  int inputDelayFrames;
  int quantizationScale;
  bool autoStepInFixedUpdate;
  bool paused;

  void Function(int frame, List<rollback.RollbackFrameInput> inputs)?
  onSimulateFrame;
  Map<String, Object?> Function()? onCaptureCustomState;
  void Function(Map<String, Object?> state)? onRestoreCustomState;
  void Function(rollback.StateChecksum builder)? onHashCustomState;

  final List<GameObject> _trackedObjects = [];
  rollback.DeterministicRollbackSession<EngineRollbackSnapshot>? _session;
  rollback.RollbackStepReport? _lastStepReport;

  RollbackSessionComponent({
    this.playerCount = 2,
    this.localPlayerId = 0,
    this.maxRollbackFrames = 16,
    this.inputDelayFrames = 1,
    this.quantizationScale = 1000,
    this.autoStepInFixedUpdate = true,
    this.paused = false,
    this.onSimulateFrame,
    this.onCaptureCustomState,
    this.onRestoreCustomState,
    this.onHashCustomState,
  });

  static final spec = ComponentSpec<RollbackSessionComponent>(
    'RollbackSessionComponent',
    RollbackSessionComponent.new,
    [
      Field.integer(
        'playerCount',
        (r) => r.playerCount,
        (r, v) => r.playerCount = v,
      ),
      Field.integer(
        'localPlayerId',
        (r) => r.localPlayerId,
        (r, v) => r.localPlayerId = v,
      ),
      Field.integer(
        'maxRollbackFrames',
        (r) => r.maxRollbackFrames,
        (r, v) => r.maxRollbackFrames = v,
      ),
      Field.integer(
        'inputDelayFrames',
        (r) => r.inputDelayFrames,
        (r, v) => r.inputDelayFrames = v,
      ),
      Field.integer(
        'quantizationScale',
        (r) => r.quantizationScale,
        (r, v) => r.quantizationScale = v,
      ),
      Field.boolean(
        'autoStepInFixedUpdate',
        (r) => r.autoStepInFixedUpdate,
        (r, v) => r.autoStepInFixedUpdate = v,
      ),
      Field.boolean('paused', (r) => r.paused, (r, v) => r.paused = v),
    ],
  );

  rollback.DeterministicRollbackSession<EngineRollbackSnapshot>
  _ensureSession() {
    final s = _session ??=
        rollback.DeterministicRollbackSession<EngineRollbackSnapshot>(
          playerCount: math.max(1, playerCount),
          localPlayerId: localPlayerId.clamp(0, math.max(0, playerCount - 1)),
          maxRollbackFrames: math.max(2, maxRollbackFrames),
          inputDelayFrames: math.max(0, inputDelayFrames),
          captureState: _captureSnapshot,
          restoreState: _restoreSnapshot,
          stepSimulation: _stepFrame,
          computeChecksum: _computeSnapshotChecksum,
        );
    s.inputDelayFrames = math.max(0, inputDelayFrames);
    return s;
  }

  rollback.DeterministicRollbackSession<EngineRollbackSnapshot> get session =>
      _ensureSession();
  int get currentFrame => _ensureSession().currentFrame;
  int get confirmedFrame => _ensureSession().confirmedFrame;
  int get totalRollbacks => _ensureSession().totalRollbacks;
  int get totalResimulatedFrames => _ensureSession().totalResimulatedFrames;
  int get maxRollbackDepth => _ensureSession().maxRollbackDepth;
  bool get desyncDetected => _ensureSession().desyncDetected;
  int? get lastDesyncFrame => _ensureSession().lastDesyncFrame;
  rollback.RollbackStepReport? get lastStepReport => _lastStepReport;

  int get latestChecksum {
    final s = _ensureSession();
    final f = s.currentFrame - 1;
    if (f < 0) return _computeSnapshotChecksum(_captureSnapshot());
    return s.checksumForFrame(f) ??
        _computeSnapshotChecksum(_captureSnapshot());
  }

  void trackGameObject(GameObject go) {
    if (!_trackedObjects.contains(go)) {
      _trackedObjects.add(go);
    }
  }

  void untrackGameObject(GameObject go) {
    _trackedObjects.remove(go);
  }

  EngineRollbackSnapshot _captureSnapshot() {
    final transforms = <int, ({Vec3 pos, Quat rot, double scale})>{};
    for (var i = 0; i < _trackedObjects.length; i++) {
      final go = _trackedObjects[i];
      if (go.isDestroyed) continue;
      transforms[i] = (
        pos: go.transform.position,
        rot: go.transform.rotation,
        scale: go.transform.localScale,
      );
    }
    final custom = onCaptureCustomState?.call();
    return EngineRollbackSnapshot(
      transforms: transforms,
      customState: custom == null ? null : Map<String, Object?>.from(custom),
    );
  }

  void _restoreSnapshot(EngineRollbackSnapshot snap) {
    for (var i = 0; i < _trackedObjects.length; i++) {
      final go = _trackedObjects[i];
      final entry = snap.transforms[i];
      if (entry != null && !go.isDestroyed) {
        go.transform.position = entry.pos;
        go.transform.rotation = entry.rot;
        go.transform.localScale = entry.scale;
      }
    }
    if (snap.customState != null && onRestoreCustomState != null) {
      onRestoreCustomState!(Map<String, Object?>.from(snap.customState!));
    }
  }

  void _stepFrame(int frame, List<rollback.RollbackFrameInput> inputs) {
    if (onSimulateFrame != null) {
      onSimulateFrame!(frame, inputs);
      return;
    }
    // Default fixed-step deterministic motion across tracked actors indexed by playerId
    final dt = isAttached ? time.fixedDeltaTime : (1.0 / 60.0);
    for (var i = 0; i < _trackedObjects.length && i < inputs.length; i++) {
      final go = _trackedObjects[i];
      if (go.isDestroyed) continue;
      final inp = inputs[i];
      go.transform.position += Vec3(
        inp.moveX * 5.0 * dt,
        0.0,
        inp.moveY * 5.0 * dt,
      );
    }
  }

  int _computeSnapshotChecksum(EngineRollbackSnapshot snap) {
    final c = rollback.StateChecksum();
    final ids = snap.transforms.keys.toList()..sort();
    for (final id in ids) {
      final t = snap.transforms[id]!;
      c.addInt32(id);
      c.addQuantizedDouble(t.pos.x, scale: quantizationScale);
      c.addQuantizedDouble(t.pos.y, scale: quantizationScale);
      c.addQuantizedDouble(t.pos.z, scale: quantizationScale);
      c.addQuantizedDouble(t.rot.x, scale: quantizationScale);
      c.addQuantizedDouble(t.rot.y, scale: quantizationScale);
      c.addQuantizedDouble(t.rot.z, scale: quantizationScale);
      c.addQuantizedDouble(t.rot.w, scale: quantizationScale);
      c.addQuantizedDouble(t.scale, scale: quantizationScale);
    }
    if (snap.customState != null) {
      final keys = snap.customState!.keys.toList()..sort();
      for (final k in keys) {
        c.addString(k);
        final v = snap.customState![k];
        if (v is int) {
          c.addInt32(v);
        } else if (v is double) {
          c.addQuantizedDouble(v, scale: quantizationScale);
        } else if (v is bool) {
          c.addBool(v);
        } else if (v != null) {
          c.addString(v.toString());
        }
      }
    }
    onHashCustomState?.call(c);
    return c.finalize();
  }

  void submitLocalInput(
    rollback.RollbackFrameInput input, {
    int? overrideTargetFrame,
  }) {
    _ensureSession().submitLocalInput(
      input,
      overrideTargetFrame: overrideTargetFrame,
    );
  }

  void submitLocalRawAxes({
    int buttonsMask = 0,
    double moveX = 0.0,
    double moveY = 0.0,
    double aimX = 0.0,
    double aimY = 0.0,
    int? overrideTargetFrame,
  }) {
    final s = _ensureSession();
    final f =
        overrideTargetFrame ?? (s.currentFrame + math.max(0, inputDelayFrames));
    s.submitLocalInput(
      rollback.RollbackFrameInput.fromAxes(
        frame: f,
        playerId: localPlayerId,
        buttonsMask: buttonsMask,
        moveX: moveX,
        moveY: moveY,
        aimX: aimX,
        aimY: aimY,
      ),
      overrideTargetFrame: f,
    );
  }

  bool receiveRemoteInput(rollback.RollbackFrameInput input) =>
      _ensureSession().receiveRemoteInput(input);

  bool receiveRemoteChecksum(int frame, int remoteChecksum) =>
      _ensureSession().receiveRemoteChecksum(frame, remoteChecksum);

  rollback.RollbackStepReport processPendingRollback() {
    final rep = _ensureSession().processPendingRollback();
    _lastStepReport = rep;
    return rep;
  }

  rollback.RollbackStepReport stepRollbackTick() {
    final rep = _ensureSession().advanceFrame();
    _lastStepReport = rep;
    return rep;
  }

  void resetSession() {
    _ensureSession().reset();
    _lastStepReport = null;
  }

  @override
  void fixedUpdate() {
    if (paused || !autoStepInFixedUpdate) return;
    stepRollbackTick();
  }
}

/// Persistent UI interaction state for [RollbackDiagnosticsUI.render].
final class RollbackDiagnosticsUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` deterministic rollback frame buffer & desync monitor (E73-2).
final class RollbackDiagnosticsUI {
  static bool _drawButton(
    VoxUiContext ui,
    RollbackDiagnosticsUiState state,
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
    RollbackSessionComponent comp, {
    RollbackDiagnosticsUiState? state,
    String title = 'Rollback Netcode',
    double x = 20.0,
    double y = 20.0,
    double width = 380.0,
    double height = 240.0,
  }) {
    final uiState = state ?? RollbackDiagnosticsUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final sess = comp.session;
    final hexHash = comp.latestChecksum
        .toRadixString(16)
        .padLeft(8, '0')
        .toUpperCase();

    ui.labelValue(
      'Frame / Conf',
      'F${sess.currentFrame} / C${sess.confirmedFrame}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Rollbacks / MaxD',
      '${comp.totalRollbacks} (${comp.totalResimulatedFrames}f) / ${comp.maxRollbackDepth}f',
      valueColor: comp.totalRollbacks > 0 ? VoxColor.yellow : VoxColor.green,
    );
    ui.labelValue(
      'Checksum / Sync',
      '0x$hexHash / ${comp.desyncDetected ? "DESYNC F${comp.lastDesyncFrame}" : "SYNCED"}',
      valueColor: comp.desyncDetected ? VoxColor.red : VoxColor.green,
    );
    ui.labelValue(
      'Delay / Adv',
      '${comp.inputDelayFrames}f / adv ${sess.frameAdvantage}f',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final stepRect = VoxRect(x + pad, barY, 70.0, 22.0);
    if (_drawButton(ui, uiState, 'rb_step', 'Step', stepRect)) {
      comp.stepRollbackTick();
    }

    final resimRect = VoxRect(stepRect.right + 8.0, barY, 74.0, 22.0);
    if (_drawButton(ui, uiState, 'rb_resim', 'Resim', resimRect)) {
      comp.processPendingRollback();
    }

    final delayRect = VoxRect(resimRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'rb_delay', 'Delay +1', delayRect)) {
      comp.inputDelayFrames = (comp.inputDelayFrames + 1) % 5;
    }

    final pauseRect = VoxRect(delayRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'rb_pause',
      comp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      comp.paused = !comp.paused;
    }

    ui.endWindow();
  }
}
