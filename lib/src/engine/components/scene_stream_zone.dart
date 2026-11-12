part of '../../engine.dart';

/// Residency state for a [SceneStreamZone] chunk (E98-2).
enum StreamZoneState { unloaded, loaded }

/// Additive distance-based world/scene streaming zone with hysteresis (E98-2).
///
/// Streams in child objects via [zoneBuilder] and/or [zoneSceneJson] (`'objects'`
/// array compatible with [SceneSerializer]) when a target enters [loadRadius],
/// and unloads them when the target exits `max(unloadRadius, loadRadius + 1.0)`.
final class SceneStreamZone extends Behaviour {
  String zoneId;
  double loadRadius;
  double unloadRadius;
  String targetTag;
  bool autoStream;
  bool paused;

  StreamZoneState state = StreamZoneState.unloaded;
  GameObject? targetOverride;
  List<GameObject> Function(Scene scene, SceneStreamZone zone)? zoneBuilder;
  Map<String, Object?>? zoneSceneJson;
  ComponentRegistry? registry;
  final List<GameObject> spawnedRoots = [];

  SceneStreamZone({
    this.zoneId = 'Zone_A',
    this.loadRadius = 24.0,
    this.unloadRadius = 32.0,
    this.targetTag = 'Player',
    this.autoStream = true,
    this.paused = false,
    this.targetOverride,
    this.zoneBuilder,
    this.zoneSceneJson,
    this.registry,
  });

  static final spec = ComponentSpec<SceneStreamZone>(
    'SceneStreamZone',
    SceneStreamZone.new,
    [
      Field.text('zoneId', (c) => c.zoneId, (c, v) => c.zoneId = v),
      Field.number('loadRadius', (c) => c.loadRadius, (c, v) => c.loadRadius = v),
      Field.number(
        'unloadRadius',
        (c) => c.unloadRadius,
        (c, v) => c.unloadRadius = v,
      ),
      Field.text('targetTag', (c) => c.targetTag, (c, v) => c.targetTag = v),
      Field.boolean('autoStream', (c) => c.autoStream, (c, v) => c.autoStream = v),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  /// Count of non-destroyed root [GameObject]s currently owned by this zone.
  int get loadedObjectCount => spawnedRoots.where((g) => !g.isDestroyed).length;

  /// Measures world distance from this zone's transform to [targetOverride],
  /// else the first active [GameObject] tagged [targetTag], else the active
  /// [Camera.of] transform position, or [double.infinity] if none exist.
  double distanceToTarget() {
    if (!isAttached || isDestroyed) return double.infinity;

    Vec3? targetPos;
    final override = targetOverride;
    if (override != null &&
        !override.isDestroyed &&
        !override._destroyRequested &&
        override.activeInHierarchy) {
      targetPos = override.transform.position;
    } else {
      final tagged = targetTag.isNotEmpty ? scene.findWithTag(targetTag) : null;
      if (tagged != null) {
        targetPos = tagged.transform.position;
      } else {
        final cam = Camera.of(scene);
        if (cam != null &&
            cam.isAttached &&
            !cam.isDestroyed &&
            cam.gameObject.activeInHierarchy) {
          targetPos = cam.transform.position;
        }
      }
    }

    if (targetPos == null) return double.infinity;
    return (transform.position - targetPos).length;
  }

  /// Populates the zone's additive objects via [zoneBuilder] and/or
  /// [zoneSceneJson]. Idempotent when already [StreamZoneState.loaded].
  void loadZone() {
    if (state == StreamZoneState.loaded) return;
    if (!isAttached || isDestroyed || gameObject.isDestroyed) return;

    final s = scene;
    final builder = zoneBuilder;
    if (builder != null) {
      final built = builder(s, this);
      for (final go in built) {
        if (!go.isDestroyed && !spawnedRoots.contains(go)) {
          spawnedRoots.add(go);
        }
      }
    }

    final jsonMap = zoneSceneJson;
    if (jsonMap != null) {
      final rawObjects = jsonMap['objects'];
      if (rawObjects is List) {
        final reg =
            registry ?? (s.isLoaded ? s.engine.registry : ComponentRegistry.defaults());
        for (final raw in rawObjects) {
          if (raw is Map) {
            final data = raw is Map<String, Object?>
                ? raw
                : Map<String, Object?>.from(raw);
            final go = SceneSerializer._buildObjectFromJson(
              s,
              gameObject,
              data,
              reg,
              const {},
            );
            spawnedRoots.add(go);
          }
        }
      }
    }

    state = StreamZoneState.loaded;
  }

  /// Destroys all non-destroyed [spawnedRoots], clears tracking, and transitions
  /// to [StreamZoneState.unloaded].
  void unloadZone() => _unloadZone(
        forceImmediate: !isAttached || !scene.isLoaded || !scene.engine._stepping,
      );

  void _unloadZone({required bool forceImmediate}) {
    if (isAttached) {
      final s = scene;
      for (final go in List.of(spawnedRoots)) {
        if (!go.isDestroyed && go.scene == s) {
          if (forceImmediate) {
            s._destroyObjectImmediate(go);
          } else {
            s.destroy(go);
          }
        }
      }
    }
    spawnedRoots.clear();
    state = StreamZoneState.unloaded;
  }

  /// Evaluates streaming hysteresis against [distanceToTarget] and transitions
  /// between [StreamZoneState.unloaded] and [StreamZoneState.loaded].
  void stepStreaming() {
    if (!isAttached || isDestroyed) return;
    final dist = distanceToTarget();
    final effectiveUnload = math.max(unloadRadius, loadRadius + 1.0);
    if (state == StreamZoneState.unloaded) {
      if (dist <= loadRadius) {
        loadZone();
      }
    } else {
      if (dist >= effectiveUnload) {
        unloadZone();
      }
    }
  }

  @override
  void update() {
    if (!paused && autoStream) {
      stepStreaming();
    }
  }

  @override
  void onDestroy() {
    _unloadZone(forceImmediate: true);
  }
}

/// Persistent UI state for [SceneStreamZoneInspectorUI.render].
final class SceneStreamZoneUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` inspector for [SceneStreamZone] (E98-2).
final class SceneStreamZoneInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    SceneStreamZoneUiState state,
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
    SceneStreamZone zone, {
    SceneStreamZoneUiState? state,
    String title = 'Scene Stream Zone',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? SceneStreamZoneUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final isLoaded = zone.state == StreamZoneState.loaded;
    final effectiveUnload = math.max(zone.unloadRadius, zone.loadRadius + 1.0);
    final dist = zone.distanceToTarget();

    ui.labelValue(
      'Zone / State',
      '${zone.zoneId} | ${isLoaded ? 'Loaded' : 'Unloaded'}',
      valueColor: isLoaded ? VoxColor.green : VoxColor.yellow,
    );
    ui.labelValue(
      'Loaded Objects',
      '${zone.loadedObjectCount} objs',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Radii (In / Out)',
      '${zone.loadRadius.toStringAsFixed(1)}m / ${effectiveUnload.toStringAsFixed(1)}m',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Target / Dist',
      '${zone.targetTag.isEmpty ? 'Camera' : zone.targetTag} | ${dist.isFinite ? '${dist.toStringAsFixed(1)}m' : 'N/A'} | ${zone.paused ? 'Paused' : 'Active'}',
      valueColor: zone.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'ssz_pause', zone.paused ? 'Resume' : 'Pause', pauseRect)) {
      zone.paused = !zone.paused;
    }

    final loadRect = VoxRect(pauseRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'ssz_load', 'Load', loadRect)) {
      zone.loadZone();
    }

    final unloadRect = VoxRect(loadRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'ssz_unload', 'Unload', unloadRect)) {
      zone.unloadZone();
    }

    final stepRect = VoxRect(unloadRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'ssz_step', 'Step', stepRect)) {
      zone.stepStreaming();
    }

    ui.endWindow();
  }
}
