part of '../engine.dart';

/// Platform-neutral state for the in-engine scene editor & live inspector
/// (E7-1..E7-3).
///
/// Manages:
/// - **Play / Stop** mode with full JSON scene snapshot & restore
/// - **Free-look editor camera** ([OrbitCameraController]) when inspecting
/// - **3D axis gizmo drag** math ([computeAxisDragDelta]) for translating
///   selected [GameObject]s along world X/Y/Z axes from pointer rays.
final class EditorSession {
  final Engine engine;
  final Map<String, Prefab> prefabs;

  final List<GameObject> _selection = [];
  Map<String, Object?>? _playModeSnapshot;
  bool _inPlayMode = true;
  bool _freeLookEnabled = false;
  CameraController? _savedSceneCamera;

  final int maxUndoSteps;
  final List<EditorCommand> _undoStack = [];
  final List<EditorCommand> _redoStack = [];

  final OrbitCameraController freeLookCamera = OrbitCameraController(
    target: Vec3.zero,
    distance: 18,
    azimuthRadians: 0.4,
    elevationRadians: 0.35,
  );

  EditorSession(this.engine, {this.prefabs = const {}, this.maxUndoSteps = 32});

  /// Primary selected object (most recently added in multi-selection).
  GameObject? get selected {
    _pruneDestroyedSelection();
    return _selection.isEmpty ? null : _selection.last;
  }

  set selected(GameObject? value) {
    _selection.clear();
    if (value != null && !value.isDestroyed && !value._destroyRequested) {
      _selection.add(value);
    }
  }

  /// Immutable list of all currently selected live objects (P9-W17-C).
  List<GameObject> get selectedObjects {
    _pruneDestroyedSelection();
    return List.unmodifiable(_selection);
  }

  int get selectionCount {
    _pruneDestroyedSelection();
    return _selection.length;
  }

  bool isSelected(GameObject object) =>
      !object.isDestroyed &&
      !object._destroyRequested &&
      _selection.contains(object);

  void _pruneDestroyedSelection() {
    _selection.removeWhere((go) => go.isDestroyed || go._destroyRequested);
  }

  /// Updates the active selection with optional additive or toggle semantics.
  void select(
    GameObject? object, {
    bool additive = false,
    bool toggle = false,
  }) {
    _pruneDestroyedSelection();
    if (object == null || object.isDestroyed || object._destroyRequested) {
      if (!additive && !toggle) _selection.clear();
      return;
    }
    if (toggle) {
      if (!_selection.remove(object)) {
        _selection.add(object);
      }
    } else if (additive) {
      if (!_selection.contains(object)) {
        _selection.add(object);
      }
    } else {
      _selection
        ..clear()
        ..add(object);
    }
  }

  /// Replaces the current selection with all valid objects in [objects].
  void selectAll(Iterable<GameObject> objects) {
    _selection.clear();
    for (final go in objects) {
      if (!go.isDestroyed &&
          !go._destroyRequested &&
          !_selection.contains(go)) {
        _selection.add(go);
      }
    }
  }

  void clearSelection() => _selection.clear();

  /// Average world-space position of all currently selected objects.
  Vec3? get selectionCentroid {
    _pruneDestroyedSelection();
    if (_selection.isEmpty) return null;
    var sum = Vec3.zero;
    for (final go in _selection) {
      sum = sum + go.transform.position;
    }
    return sum * (1.0 / _selection.length);
  }

  /// Combined world-space AABB encompassing all currently selected objects.
  Aabb? get selectionWorldBounds {
    _pruneDestroyedSelection();
    if (_selection.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;

    void expand(Vec3 p) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.z < minZ) minZ = p.z;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
      if (p.z > maxZ) maxZ = p.z;
    }

    for (final go in _selection) {
      final col = go.getComponent<Collider>();
      final mr = go.getComponent<MeshRenderer>();
      if (col != null) {
        final b = col.worldBounds;
        expand(b.min);
        expand(b.max);
      } else if (mr != null) {
        final b = mr.worldAabb;
        expand(Vec3(b.min.x, b.min.y, b.min.z));
        expand(Vec3(b.max.x, b.max.y, b.max.z));
      } else {
        final p = go.transform.position;
        final ext = 0.5 * go.transform.lossyScale.abs();
        final half = Vec3(ext, ext, ext);
        expand(p - half);
        expand(p + half);
      }
    }
    return Aabb(Vec3(minX, minY, minZ), Vec3(maxX, maxY, maxZ));
  }

  /// Frames [freeLookCamera] around the current selection's combined world bounds.
  bool focusSelection({double padding = 1.4}) {
    final bounds = selectionWorldBounds;
    if (bounds == null) return false;
    final center = (bounds.min + bounds.max) * 0.5;
    final extent = (bounds.max - bounds.min).length;
    freeLookCamera.target = center;
    freeLookCamera.distance = math.max(2.0, extent * padding);
    return true;
  }

  /// Filters scene hierarchy objects by optional name substring, tag, layer,
  /// or attached component type.
  List<GameObject> searchHierarchy({
    String? nameQuery,
    String? tag,
    int? layer,
    Type? componentType,
    bool includeInactive = true,
  }) {
    final needle = nameQuery?.trim().toLowerCase();
    final results = <GameObject>[];
    for (final go in engine.scene._allObjects(
      includeInactive: includeInactive,
    )) {
      if (needle != null &&
          needle.isNotEmpty &&
          !go.name.toLowerCase().contains(needle)) {
        continue;
      }
      if (tag != null && go.tag != tag) continue;
      if (layer != null && go.layer != layer) continue;
      if (componentType != null &&
          !go.components.any((c) => c.runtimeType == componentType)) {
        continue;
      }
      results.add(go);
    }
    return results;
  }

  bool get isPlaying => _inPlayMode;
  bool get isFreeLookEnabled => _freeLookEnabled;
  bool get hasSnapshot => _playModeSnapshot != null;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// Executes an [EditorCommand] immediately and records it on the undo stack (P7-W15-A).
  void executeCommand(EditorCommand command) {
    command.execute(this);
    _undoStack.add(command);
    if (_undoStack.length > maxUndoSteps) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Records the current scene state onto the undo stack before an authoring
  /// mutation (E13-2).
  void recordUndoState([String label = 'edit']) {
    _undoStack.add(
      _LegacySnapshotCommand(
        name: label,
        sceneJson: SceneSerializer.toJson(
          engine.scene,
          registry: engine.registry,
        ),
        selectedName: selected?.name,
      ),
    );
    if (_undoStack.length > maxUndoSteps) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Reverts the most recent command pushed onto the undo stack (E13-2, P7-W15-A).
  bool undo() {
    if (_undoStack.isEmpty) return false;
    final cmd = _undoStack.removeLast();
    cmd.undo(this);
    _redoStack.add(cmd);
    return true;
  }

  /// Re-applies the most recent undone command (E13-2, P7-W15-A).
  bool redo() {
    if (_redoStack.isEmpty) return false;
    final cmd = _redoStack.removeLast();
    cmd.execute(this);
    _undoStack.add(cmd);
    return true;
  }

  void clearUndoHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  /// Captures the current scene as the baseline snapshot that [stopPlayMode]
  /// will restore to.
  void captureBaselineSnapshot() {
    _playModeSnapshot = SceneSerializer.toJson(
      engine.scene,
      registry: engine.registry,
    );
  }

  /// Enters Play mode, taking a snapshot of the current scene first so any
  /// runtime mutations or destroyed objects can be reverted via [stopPlayMode].
  void enterPlayMode() {
    captureBaselineSnapshot();
    _inPlayMode = true;
    if (_freeLookEnabled) {
      setFreeLook(false);
    }
    engine.time.timeScale = 1.0;
  }

  /// Stops Play mode and restores the scene to the snapshot captured when
  /// [enterPlayMode] (or [captureBaselineSnapshot]) was called.
  void stopPlayMode() {
    final snap = _playModeSnapshot;
    _inPlayMode = false;
    engine.time.timeScale = 0.0;
    if (snap != null) {
      final restored = SceneSerializer.fromJson(
        snap,
        registry: engine.registry,
        prefabs: prefabs,
      );
      final prevName = selected?.name;
      engine.loadScene(restored);
      selected = prevName != null ? engine.scene.find(prevName) : null;
    }
  }

  /// Toggles between the scene's gameplay camera and the editor's
  /// [freeLookCamera].
  void setFreeLook(bool enabled) {
    if (_freeLookEnabled == enabled) return;
    _freeLookEnabled = enabled;
    if (enabled) {
      _savedSceneCamera = engine.graphics.camera;
      final sel = selected;
      if (sel != null) {
        freeLookCamera.target = sel.transform.position;
      }
      engine.graphics.camera = freeLookCamera;
    } else {
      engine.graphics.camera = _savedSceneCamera;
      _savedSceneCamera = null;
    }
  }

  /// Clones [target] (or [selected] when omitted) and its entire hierarchy/
  /// serialized components into the active scene as a sibling [GameObject]
  /// (`<name>_Copy`), selects the clone, and returns it (E12-4).
  GameObject? duplicate([GameObject? target]) {
    final src = target ?? selected;
    if (src == null || src.isDestroyed) return null;
    final data = Map<String, Object?>.of(
      SceneSerializer._objectToJson(src, engine.registry),
    );
    data['name'] = '${src.name}_Copy';
    final clone = SceneSerializer._buildObjectFromJson(
      engine.scene,
      src.parent,
      data,
      engine.registry,
      prefabs,
    );
    selected = clone;
    return clone;
  }

  /// Exports the active scene to a JSON string (E12-4).
  String exportSceneJson() =>
      SceneSerializer.toJsonString(engine.scene, registry: engine.registry);

  /// Replaces the active scene with one deserialized from [jsonSource] (E12-4).
  Scene importSceneJson(String jsonSource) {
    final loaded = SceneSerializer.fromJsonString(
      jsonSource,
      registry: engine.registry,
      prefabs: prefabs,
    );
    selected = null;
    engine.loadScene(loaded);
    return loaded;
  }

  /// Computes the signed scalar parameter `s` along the line passing through
  /// [axisOrigin] in direction [axisDir] (unit vector) that is closest to
  /// [ray]. Used by 3D translation gizmos to drag an object along X, Y, or Z.
  static double projectRayOntoAxis(Ray ray, Vec3 axisOrigin, Vec3 axisDir) {
    final d1 = ray.direction.normalized;
    final d2 = axisDir.normalized;
    final r = ray.origin - axisOrigin;
    final b = d1.dot(d2);
    final denom = 1.0 - b * b;
    if (denom.abs() < 1e-6) return 0.0;
    final c = d1.dot(r);
    final f = d2.dot(r);
    return (f - b * c) / denom;
  }

  /// Translates [target] along world [axisDir] by the delta between [startRay]
  /// and [currentRay] relative to [initialWorldPosition].
  static Vec3 computeAxisDragPosition({
    required Vec3 initialWorldPosition,
    required Vec3 axisDir,
    required Ray startRay,
    required Ray currentRay,
  }) {
    final unitAxis = axisDir.normalized;
    final s0 = projectRayOntoAxis(startRay, initialWorldPosition, unitAxis);
    final s1 = projectRayOntoAxis(currentRay, initialWorldPosition, unitAxis);
    return initialWorldPosition + unitAxis * (s1 - s0);
  }
}
