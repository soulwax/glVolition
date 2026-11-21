/// Pure-Dart bridge contract between the Volition Studio shell and the
/// in-page [Engine] / [EditorSession] (S2-0).
library;

import 'dart:async';

import '../../../gl_volition.dart';

/// Current execution state of the Studio player.
enum StudioPlayState { editing, playing, paused }

/// Scene-view shading mode selector.
enum StudioShadingMode {
  lit,
  unlit,
  wireframe,
  overdraw,
  normals,
  roughness,
  lightHeatmap,
}

/// Result of a viewport pick query at normalized screen coordinates `(nx, ny)`.
final class EditorPickResult {
  final int objectId;
  final GameObject? gameObject;
  final Vec3? worldPoint;
  final double distance;

  const EditorPickResult({
    required this.objectId,
    this.gameObject,
    this.worldPoint,
    this.distance = 0.0,
  });
}

/// Immutable snapshot of Studio editor state broadcast to all docked panels.
final class EditorBridgeSnapshot {
  final StudioPlayState playState;
  final List<String> selectedNames;
  final bool isDirty;
  final bool canUndo;
  final bool canRedo;
  final StudioShadingMode shadingMode;
  final ViewportGizmoMode gizmoMode;
  final ViewportGizmoSpace gizmoSpace;
  final bool snapEnabled;
  final double snapStep;

  const EditorBridgeSnapshot({
    required this.playState,
    required this.selectedNames,
    required this.isDirty,
    required this.canUndo,
    required this.canRedo,
    required this.shadingMode,
    required this.gizmoMode,
    required this.gizmoSpace,
    required this.snapEnabled,
    required this.snapStep,
  });
}

/// Platform-neutral bridge between the Studio shell UI and the running engine.
abstract interface class EditorHostBridge {
  EditorSession get session;
  StudioPlayState get playState;
  bool get isDirty;
  StudioShadingMode get shadingMode;
  ViewportGizmoMode get gizmoMode;
  ViewportGizmoSpace get gizmoSpace;
  bool get snapEnabled;
  double get snapStep;

  Stream<EditorBridgeSnapshot> get stateChanges;

  void selectObjects(List<GameObject> objects);
  void dispatchCommand(EditorCommand command);
  bool undo();
  bool redo();
  EditorPickResult? pickAtNormalizedViewport(double nx, double ny);

  void enterPlayMode();
  void pausePlayMode();
  void stepPlayMode([double dt = 1 / 60]);
  void exitPlayMode();

  void setShadingMode(StudioShadingMode mode);
  void setGizmoMode(ViewportGizmoMode mode);
  void setGizmoSpace(ViewportGizmoSpace space);
  void setSnap({required bool enabled, double? step});

  void markDirty();
  void markClean();
  EditorBridgeSnapshot snapshot();
  Future<void> dispose();
}

/// Pure-Dart [EditorHostBridge] backed directly by an [EditorSession] so
/// Studio panels and headless tests drive the real engine identically.
final class SessionEditorHostBridge implements EditorHostBridge {
  @override
  final EditorSession session;

  final EditorPickResult? Function(double nx, double ny)? onPick;
  final StreamController<EditorBridgeSnapshot> _changes =
      StreamController<EditorBridgeSnapshot>.broadcast();

  StudioPlayState _playState = StudioPlayState.editing;
  bool _isDirty = false;
  StudioShadingMode _shadingMode = StudioShadingMode.lit;
  ViewportGizmoMode _gizmoMode = ViewportGizmoMode.translate;
  ViewportGizmoSpace _gizmoSpace = ViewportGizmoSpace.world;
  bool _snapEnabled = false;
  double _snapStep = 0.5;

  SessionEditorHostBridge(this.session, {this.onPick}) {
    _playState = session.isPlaying
        ? StudioPlayState.playing
        : StudioPlayState.editing;
  }

  @override
  StudioPlayState get playState => _playState;

  @override
  bool get isDirty => _isDirty;

  @override
  StudioShadingMode get shadingMode => _shadingMode;

  @override
  ViewportGizmoMode get gizmoMode => _gizmoMode;

  @override
  ViewportGizmoSpace get gizmoSpace => _gizmoSpace;

  @override
  bool get snapEnabled => _snapEnabled;

  @override
  double get snapStep => _snapStep;

  @override
  Stream<EditorBridgeSnapshot> get stateChanges => _changes.stream;

  @override
  void selectObjects(List<GameObject> objects) {
    session.selectAll(objects);
    _emit();
  }

  @override
  void dispatchCommand(EditorCommand command) {
    session.executeCommand(command);
    _isDirty = true;
    _emit();
  }

  @override
  bool undo() {
    final ok = session.undo();
    if (ok) {
      _isDirty = true;
      _emit();
    }
    return ok;
  }

  @override
  bool redo() {
    final ok = session.redo();
    if (ok) {
      _isDirty = true;
      _emit();
    }
    return ok;
  }

  @override
  EditorPickResult? pickAtNormalizedViewport(double nx, double ny) =>
      onPick?.call(nx, ny);

  @override
  void enterPlayMode() {
    if (_playState == StudioPlayState.playing) return;
    if (_playState == StudioPlayState.editing) {
      session.enterPlayMode();
    }
    _playState = StudioPlayState.playing;
    _emit();
  }

  @override
  void pausePlayMode() {
    if (_playState == StudioPlayState.playing) {
      _playState = StudioPlayState.paused;
      _emit();
    }
  }

  @override
  void stepPlayMode([double dt = 1 / 60]) {
    if (_playState == StudioPlayState.editing) {
      session.enterPlayMode();
    }
    _playState = StudioPlayState.paused;
    session.engine.step(dt);
    _emit();
  }

  @override
  void exitPlayMode() {
    if (_playState == StudioPlayState.editing) return;
    session.stopPlayMode();
    _playState = StudioPlayState.editing;
    _emit();
  }

  @override
  void setShadingMode(StudioShadingMode mode) {
    if (_shadingMode == mode) return;
    _shadingMode = mode;
    _emit();
  }

  @override
  void setGizmoMode(ViewportGizmoMode mode) {
    if (_gizmoMode == mode) return;
    _gizmoMode = mode;
    _emit();
  }

  @override
  void setGizmoSpace(ViewportGizmoSpace space) {
    if (_gizmoSpace == space) return;
    _gizmoSpace = space;
    _emit();
  }

  @override
  void setSnap({required bool enabled, double? step}) {
    _snapEnabled = enabled;
    if (step != null && step > 0) _snapStep = step;
    _emit();
  }

  @override
  void markDirty() {
    if (_isDirty) return;
    _isDirty = true;
    _emit();
  }

  @override
  void markClean() {
    if (!_isDirty) return;
    _isDirty = false;
    _emit();
  }

  @override
  EditorBridgeSnapshot snapshot() => EditorBridgeSnapshot(
    playState: _playState,
    selectedNames: [for (final go in session.selectedObjects) go.name],
    isDirty: _isDirty,
    canUndo: session.canUndo,
    canRedo: session.canRedo,
    shadingMode: _shadingMode,
    gizmoMode: _gizmoMode,
    gizmoSpace: _gizmoSpace,
    snapEnabled: _snapEnabled,
    snapStep: _snapStep,
  );

  void _emit() {
    if (!_changes.isClosed) {
      _changes.add(snapshot());
    }
  }

  @override
  Future<void> dispose() => _changes.close();
}
