part of '../engine.dart';

/// Environment and post-processing settings owned by a [Scene] and pushed to
/// the renderer before each frame, with active [Light] components folded in.
final class RenderSettings {
  SkyboxDeclaration? skybox;
  LinearColor clearColor = const LinearColor(0.03, 0.03, 0.04);
  LinearColor ambientColor = const LinearColor(0.18, 0.20, 0.25);
  double ambientIntensity = 1.0;
  LinearColor reflectionColor = const LinearColor(0.3, 0.35, 0.45);
  double reflectionIntensity = 0.3;
  double reflectionConfidence = 0.5;

  bool fogEnabled = false;
  LinearColor fogColor = const LinearColor(0.02, 0.02, 0.04);
  double fogStart = 40;
  double fogEnd = 160;
  double? fogHeightFalloff;
  double? fogDensity;

  PostProcessState post = const PostProcessState();
}

/// A self-contained world of [GameObject]s, their components, lighting and
/// trigger physics.
final class Scene {
  final String name;
  final SceneNode root;
  final RenderSettings renderSettings = RenderSettings();
  final SceneEvents events = SceneEvents();
  final AudioMixer audioMixer = AudioMixer();
  late final PhysicsWorld physics = PhysicsWorld._(this);

  Engine? _engine;
  final List<GameObject> _roots = [];
  final List<Behaviour> _behaviours = [];
  final List<Behaviour> _pendingStart = [];
  final List<Coroutine> _coroutines = [];
  final List<Light> _lights = [];
  final List<Camera> _cameras = [];
  final List<Camera2DComponent> _cameras2d = [];
  final List<SpriteRenderer> _sprites = [];
  final List<TilemapComponent> _tilemaps = [];
  final List<UICanvas> _uiCanvases = [];
  final List<WaterSurfaceComponent> _waters = [];
  final List<AtmosphereVolume> _atmospheres = [];
  final List<ParticleSystem> _particles = [];
  final List<AudioListener> _audioListeners = [];
  final List<AudioSource> _audioSources = [];
  final List<LineRenderer> _lines = [];
  final List<VolumetricLightSource> _volumetricSources = [];
  final List<ThermalSourceComponent> _thermalSources = [];
  final SpriteBatch _worldSprites = SpriteBatch(
    initialCapacity: 2048,
    sort: SpriteSort.layerThenY,
    debugLabel: 'scene_sprites',
  );
  final List<GameObject> _destroyObjects = [];
  final List<Component> _destroyComponents = [];

  Scene([this.name = 'Scene']) : root = SceneNode.group(name: name);

  Engine get engine => _engine ?? (throw StateError('Scene $name is not loaded in an Engine'));
  bool get isLoaded => _engine != null;

  List<GameObject> get rootGameObjects => List.unmodifiable(_roots);

  /// Creates an empty [GameObject] in this scene.
  GameObject createGameObject(
    String name, {
    GameObject? parent,
    Vec3? position,
    Quat? rotation,
    double scale = 1,
    String tag = 'Untagged',
    int layer = 0,
    bool active = true,
    List<Component> components = const [],
  }) {
    final go = GameObject._(this, name, tag: tag, layer: layer);
    if (!active) {
      go._activeSelf = false;
      go.node.visible = false;
    }
    if (parent != null) {
      if (parent.scene != this) throw ArgumentError('Parent belongs to another scene');
      go._parent = parent;
      parent._children.add(go);
      parent.node.addChild(go.node);
    } else {
      _roots.add(go);
      root.addChild(go.node);
    }
    if (position != null) go.transform.localPosition = position;
    if (rotation != null) go.transform.localRotation = rotation;
    if (scale != 1) go.transform.localScale = scale;

    _refresh(go.transform);
    for (final c in components) {
      go.addComponent(c);
    }
    return go;
  }

  /// Instantiates [prefab] into this scene with optional transform overrides.
  GameObject instantiate(
    Prefab prefab, {
    GameObject? parent,
    Vec3? position,
    Quat? rotation,
    double? scale,
    String? name,
    bool active = true,
  }) =>
      prefab.instantiate(
        this,
        parent: parent,
        position: position,
        rotation: rotation,
        scale: scale,
        name: name,
        active: active,
      );

  /// Serializes this scene into a JSON-compatible map.
  Map<String, Object?> toJson({ComponentRegistry? registry}) =>
      SceneSerializer.toJson(this, registry: registry ?? _engine?.registry);

  // ── Queries ─────────────────────────────────────────────────────────────

  GameObject? find(String name) {
    for (final r in _roots) {
      if (r._destroyRequested) continue;
      if (r.name == name) return r;
      final child = r.find(name);
      if (child != null) return child;
    }
    return null;
  }

  GameObject? findWithTag(String tag) => findGameObjectsWithTag(tag).firstOrNull;

  Iterable<GameObject> findGameObjectsWithTag(String tag) sync* {
    for (final go in _allObjects(includeInactive: false)) {
      if (go.tag == tag) yield go;
    }
  }

  T? findObjectOfType<T>({bool includeInactive = false}) =>
      findObjectsOfType<T>(includeInactive: includeInactive).firstOrNull;

  Iterable<T> findObjectsOfType<T>({bool includeInactive = false}) sync* {
    for (final go in _allObjects(includeInactive: includeInactive)) {
      for (final c in go._components) {
        if (c is T && !c._destroyRequested && (includeInactive || c._active)) {
          yield c as T;
        }
      }
    }
  }

  Iterable<GameObject> _allObjects({required bool includeInactive}) sync* {
    Iterable<GameObject> walk(GameObject g) sync* {
      if (g._destroyRequested) return;
      if (!includeInactive && !g._activeSelf) return;
      yield g;
      for (final child in g._children) {
        yield* walk(child);
      }
    }

    for (final r in _roots) {
      yield* walk(r);
    }
  }

  /// Raycasts the rendered meshes in this scene and maps the hit back to its
  /// owning [GameObject]. For collider raycasts use [PhysicsWorld.raycast].
  (GameObject, RaycastHit)? raycastVisuals(Ray ray, {bool precise = false}) {
    var best = root.raycast(
      ray,
      where: (node) => node is! InstancedMeshNode,
      precise: precise,
    );
    root.traverse((node) {
      if (node is InstancedMeshNode) {
        final instHit = node.raycast(ray, precise: precise);
        if (instHit != null && (best == null || instHit.distance < best!.distance)) {
          best = instHit;
        }
      }
    });
    final hit = best;
    if (hit == null) return null;
    final go = _ownerOf(hit.node);
    return go == null ? null : (go, hit);
  }

  GameObject? _ownerOf(SceneNode target) {
    final byNode = <SceneNode, GameObject>{};
    for (final go in _allObjects(includeInactive: true)) {
      byNode[go.node] = go;
    }
    for (SceneNode? n = target; n != null; n = n.parent) {
      final found = byNode[n];
      if (found != null) return found;
    }
    return null;
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  void _attach(Engine engine) {
    _engine = engine;
    engine.host.sceneRoot.addChild(root);
    for (final r in List.of(_roots)) {
      r._refreshTree();
    }
  }

  void _detach() {
    for (final r in List.of(_roots)) {
      _destroyObjectImmediate(r);
    }
    _destroyObjects.clear();
    _destroyComponents.clear();
    _pendingStart.clear();
    _coroutines.clear();
    events.clear();
    root.removeFromParent();
    _engine = null;
  }

  void _registerBehaviour(Behaviour b) {
    final order = b.executionOrder;
    var i = _behaviours.length;
    while (i > 0 && _behaviours[i - 1].executionOrder > order) {
      i--;
    }
    _behaviours.insert(i, b);
  }

  void _refresh(Component c) {
    if (_engine == null || c._destroyed || c._destroyRequested) return;
    final shouldBeActive = c.gameObject.activeInHierarchy && c._enabledSelf;
    if (shouldBeActive) {
      if (!c._awoken) {
        c._awoken = true;
        _guard(c.awake);
      }
      if (!c._active && !c._destroyRequested && c.gameObject.activeInHierarchy && c._enabledSelf) {
        c._active = true;
        c._onEnableInternal();
        _guard(c.onEnable);
        if (c is Behaviour && !c._started && !c._startQueued) {
          c._startQueued = true;
          _pendingStart.add(c);
        }
      }
    } else if (c._active) {
      c._active = false;
      _guard(c.onDisable);
      c._onDisableInternal();
    }
  }

  void _drainStarts() {
    while (_pendingStart.isNotEmpty) {
      final batch = List.of(_pendingStart);
      _pendingStart.clear();
      batch.sort((a, b) => a.executionOrder.compareTo(b.executionOrder));
      for (final b in batch) {
        b._startQueued = false;
        if (b._active && !b._started && !b._destroyRequested) {
          b._started = true;
          _guard(b.start);
        }
      }
    }
  }

  void _fixedStep() {
    _drainStarts();
    for (final b in List.of(_behaviours)) {
      if (b._active && !b._destroyRequested) _guard(b.fixedUpdate);
    }
    physics._step();
  }

  void _updateStep() {
    _drainStarts();
    for (final b in List.of(_behaviours)) {
      if (b._active && !b._destroyRequested) _guard(b.update);
    }
    if (_coroutines.isNotEmpty) {
      final dt = _engine?.time.deltaTime ?? 0.0;
      final unscaledDt = _engine?.time.unscaledDeltaTime ?? dt;
      for (final co in List.of(_coroutines)) {
        var keep = false;
        _guard(() {
          keep = co._step(dt, unscaledDt);
        });
        if (!keep) _coroutines.remove(co);
      }
    }
    _drainStarts();
    for (final b in List.of(_behaviours)) {
      if (b._active && !b._destroyRequested) _guard(b.lateUpdate);
    }
  }

  void _syncToRenderer(Graphics graphics) {
    for (final p in _particles) {
      p._syncTransform();
    }
    for (final line in _lines) {
      if (line._active) line._syncRibbon();
    }
    for (final src in _audioSources) {
      if (src._active) src._syncChannelVolume();
    }
    final mainCam = _cameras.lastOrNull;
    if (mainCam != null && _engine != null) {
      mainCam.shakeEngine.update(_engine!.time.deltaTime);
    }
    if (_engine != null && _engine!.editor.isFreeLookEnabled) {
      graphics.camera = _engine!.editor.freeLookCamera;
    } else if (mainCam != null) {
      mainCam._sync();
      graphics.camera = mainCam.controller;
    }

    DirectionalLight? sun;
    final points = <PointLight>[];
    final spots = <SpotLight>[];
    for (final l in _lights) {
      if (!l._active || l.intensity <= 0) continue;
      switch (l.type) {
        case LightType.directional:
          sun ??= DirectionalLight(
            direction: l.transform.forward,
            color: l.color,
            intensity: l.intensity,
          );
        case LightType.point:
          if (points.length < RuntimeLightBudget.pointLights) {
            points.add(PointLight(
              id: points.length,
              position: l.transform.position,
              color: l.color,
              intensity: l.intensity,
              radius: l.range,
              castsShadow: l.castsShadow,
            ));
          }
        case LightType.spot:
          if (spots.length < RuntimeLightBudget.unshadowedSpotLights + RuntimeLightBudget.shadowedSpotLights) {
            spots.add(SpotLight(
              id: spots.length,
              position: l.transform.position,
              direction: l.transform.forward,
              color: l.color,
              intensity: l.intensity,
              range: l.range,
              innerConeRadians: l.innerSpotAngle,
              outerConeRadians: l.spotAngle,
              castsShadow: l.castsShadow,
            ));
          }
      }
    }

    final rs = renderSettings;
    final camEye = graphics.camera?.eye ?? Vec3.zero;
    final volSources = _volumetricSources.isEmpty
        ? const <VolumetricSource>[]
        : selectVolumetricSources(
            sources: [
              for (final vs in _volumetricSources)
                if (vs._active) vs.toVolumetricSource(),
            ],
            referencePosition: camEye,
          );
    final thermSources = <ThermalSource>[
      for (final ts in _thermalSources)
        if (ts._active) ts.toThermalSource(),
    ];

    graphics.environment = graphics.environment.copyWith(
      skybox: rs.skybox,
      clearColor: rs.clearColor,
      ambientColor: rs.ambientColor,
      ambientIntensity: rs.ambientIntensity,
      reflectionColor: rs.reflectionColor,
      reflectionIntensity: rs.reflectionIntensity,
      reflectionConfidence: rs.reflectionConfidence,
      fogColor: rs.fogColor,
      fogStart: rs.fogEnabled ? rs.fogStart : 100000,
      fogEnd: rs.fogEnabled ? rs.fogEnd : 100001,
      fogHeightFalloff: rs.fogEnabled ? rs.fogHeightFalloff : null,
      fogDensity: rs.fogEnabled ? rs.fogDensity : null,
      directionalLight: sun,
      pointLights: points,
      spotLights: spots,
      volumetricSources: volSources,
      thermalSources: thermSources,
    );
    graphics.post = rs.post;
  }

  /// Evaluates the combined thermal dissolution (`0..1`) at [worldPosition]
  /// from all active [ThermalSourceComponent]s in this scene (E13-3).
  double sampleThermalDissolution(
    Vec3 worldPosition, {
    double lingeringMemory01 = 0.0,
  }) =>
      ThermalFieldEngine.dissolutionAt(
        position: worldPosition,
        sources: [
          for (final ts in _thermalSources)
            if (ts._active) ts.toThermalSource(),
        ],
        lingeringMemory01: lingeringMemory01,
      );

  void _encode(RenderEncoder encoder, FrameInput? frame) {
    if (frame != null) {
      for (final atm in _atmospheres) {
        if (atm._active) atm._encode(encoder, frame);
      }
    }
    final cam2d = _cameras2d.lastOrNull;
    if (cam2d != null && cam2d._active && _engine != null) {
      cam2d._sync(_engine!.graphics.viewportWidth, _engine!.graphics.viewportHeight);
      for (final tm in _tilemaps) {
        if (tm._active) tm.layer.drawTo(encoder, cam2d.raw);
      }
      if (_sprites.isNotEmpty) {
        _worldSprites.clear();
        for (final s in _sprites) {
          if (s._active) s._drawInto(_worldSprites);
        }
        if (!_worldSprites.isEmpty) {
          encoder.drawSprites(_worldSprites, cam2d.raw);
        }
      }
    }
    if (_engine != null) {
      final vw = _engine!.graphics.viewportWidth;
      final vh = _engine!.graphics.viewportHeight;
      for (final ui in _uiCanvases) {
        if (ui._active) ui._encode(encoder, vw, vh);
      }
    }
  }

  // ── Destruction ─────────────────────────────────────────────────────────

  /// Schedules [object] (and its subtree) for destruction at the end of the
  /// current frame.
  void destroy(GameObject object) {
    if (object.scene != this) throw ArgumentError('Object belongs to another scene');
    if (object._destroyRequested || object._destroyed) return;
    void mark(GameObject g) {
      g._destroyRequested = true;
      for (final c in g._components) {
        c._destroyRequested = true;
      }
      for (final child in g._children) {
        mark(child);
      }
    }

    mark(object);
    _destroyObjects.add(object);
  }

  void _requestDestroyComponent(Component c) {
    if (c is TransformComponent) {
      throw StateError('TransformComponent cannot be destroyed; destroy its GameObject');
    }
    if (c._destroyRequested || c._destroyed) return;
    c._destroyRequested = true;
    _destroyComponents.add(c);
  }

  void _flushDestroyed() {
    for (final c in List.of(_destroyComponents)) {
      if (!c._destroyed && c._gameObject != null && !c._gameObject!._destroyRequested) {
        _destroyComponentImmediate(c);
      }
    }
    _destroyComponents.clear();

    for (final go in List.of(_destroyObjects)) {
      if (!go._destroyed) _destroyObjectImmediate(go);
    }
    _destroyObjects.clear();
  }

  void _destroyObjectImmediate(GameObject go) {
    if (go._destroyed) return;
    for (final child in List.of(go._children)) {
      _destroyObjectImmediate(child);
    }
    for (final c in List.of(go._components.reversed)) {
      if (c is! TransformComponent) _destroyComponentImmediate(c);
    }
    go.transform._active = false;
    go.transform._destroyed = true;
    go._destroyed = true;
    (go._parent?._children ?? _roots).remove(go);
    go._parent = null;
    go.node.removeFromParent();
  }

  void _destroyComponentImmediate(Component c) {
    if (c._destroyed) return;
    if (c._active) {
      c._active = false;
      _guard(c.onDisable);
      c._onDisableInternal();
    }
    if (c._awoken) {
      _guard(c.onDestroy);
    }
    c._onDestroyInternal();
    c._destroyed = true;
    if (c is Behaviour) {
      _behaviours.remove(c);
      _pendingStart.remove(c);
      _engine?._cancelOwnedBy(c);
    }
    c._gameObject?._components.remove(c);
    c._gameObject = null;
  }

  void _guard(void Function() fn) {
    try {
      fn();
    } catch (e, s) {
      _engine?.host.reportError(e, s);
    }
  }
}
