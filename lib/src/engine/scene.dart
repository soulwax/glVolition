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
  late final Gizmos gizmos = Gizmos._(this);

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

  Engine get engine =>
      _engine ?? (throw StateError('Scene $name is not loaded in an Engine'));
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
      if (parent.scene != this) {
        throw ArgumentError('Parent belongs to another scene');
      }
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
  }) => prefab.instantiate(
    this,
    parent: parent,
    position: position,
    rotation: rotation,
    scale: scale,
    name: name,
    active: active,
  );

  /// Clones [original] (including all components, child GameObjects, and property
  /// values) into this [Scene] (E25-3).
  GameObject clone(
    GameObject original, {
    GameObject? parent,
    Vec3? position,
    Quat? rotation,
    double? scale,
    String? name,
    bool active = true,
    ComponentRegistry? registry,
  }) {
    final reg = registry ?? (_engine?.registry ?? ComponentRegistry.defaults());
    final json = SceneSerializer._objectToJson(original, reg);
    final copy = SceneSerializer._buildObjectFromJson(
      this,
      parent,
      json,
      reg,
      const {},
    );
    if (name != null) copy.name = name;
    if (position != null) copy.transform.position = position;
    if (rotation != null) copy.transform.rotation = rotation;
    if (scale != null) copy.transform.localScale = scale;
    if (copy.activeSelf != active) copy.setActive(active);
    return copy;
  }

  /// Serializes this scene into a JSON-compatible map.
  Map<String, Object?> toJson({ComponentRegistry? registry}) =>
      SceneSerializer.toJson(this, registry: registry ?? _engine?.registry);

  /// Creates a GameObject with a 3D primitive mesh, renderer, and matching collider (E23-1).
  ///
  /// Matches Unity's `GameObject.CreatePrimitive(PrimitiveType)`.
  GameObject createPrimitive(
    PrimitiveType type, {
    String? name,
    GameObject? parent,
    Vec3? position,
    Quat? rotation,
    double scale = 1.0,
    LinearColor? color,
    MaterialHandle? material,
    bool isTrigger = false,
  }) {
    final eng = _engine;
    final MeshData data;
    final Collider col;
    final String defaultName;

    switch (type) {
      case PrimitiveType.cube:
        defaultName = 'Cube';
        data = Primitives.cube();
        col = BoxCollider(size: const Vec3(1, 1, 1), isTrigger: isTrigger);
      case PrimitiveType.sphere:
        defaultName = 'Sphere';
        data = Primitives.sphere(radius: 0.5);
        col = SphereCollider(radius: 0.5, isTrigger: isTrigger);
      case PrimitiveType.capsule:
        defaultName = 'Capsule';
        data = Primitives.capsule(radius: 0.5, cylinderHeight: 1.0);
        col = CapsuleCollider(radius: 0.5, height: 2.0, isTrigger: isTrigger);
      case PrimitiveType.cylinder:
        defaultName = 'Cylinder';
        data = Primitives.cylinder(radius: 0.5, height: 2.0);
        col = CapsuleCollider(radius: 0.5, height: 2.0, isTrigger: isTrigger);
      case PrimitiveType.plane:
        defaultName = 'Plane';
        data = Primitives.plane(width: 10, depth: 10);
        col = BoxCollider(size: const Vec3(10, 0.01, 10), isTrigger: isTrigger);
      case PrimitiveType.quad:
        defaultName = 'Quad';
        data = Primitives.quad(width: 1, height: 1);
        col = BoxCollider(size: const Vec3(1, 1, 0.01), isTrigger: isTrigger);
    }

    final MeshHandle? handle = eng?.graphics.createMesh(
      data,
      debugLabel: defaultName,
    );
    final renderer = MeshRenderer(
      mesh: handle,
      meshData: data,
      material: material,
      tintColor: color,
    );

    return createGameObject(
      name ?? defaultName,
      parent: parent,
      position: position,
      rotation: rotation,
      scale: scale,
      components: [renderer, col],
    );
  }

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

  GameObject? findWithTag(String tag) =>
      findGameObjectsWithTag(tag).firstOrNull;

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
        if (instHit != null &&
            (best == null || instHit.distance < best!.distance)) {
          best = instHit;
        }
      }
    });
    final hit = best;
    if (hit == null) return null;
    final go = _ownerOf(hit.node);
    return go == null ? null : (go, hit);
  }

  /// Performs a 3D raycast against active MeshRenderers using voxgeom bounding volumes (E29-2).
  SceneMeshRayHit? raycastMeshes(Ray3 ray, {double maxDistance = double.infinity}) {
    SceneMeshRayHit? best;
    for (final go in _allObjects(includeInactive: false)) {
      final renderer = go.getComponent<MeshRenderer>();
      if (renderer == null || !renderer.isActiveAndEnabled) continue;

      final aabb = renderer.worldAabb;
      final dist = ray.intersectAabb(aabb);
      if (dist != null && dist <= maxDistance) {
        if (best == null || dist < best.distance) {
          best = SceneMeshRayHit(
            gameObject: go,
            renderer: renderer,
            distance: dist,
            point: ray.pointAt(dist),
          );
        }
      }
    }
    return best;
  }

  /// Shakes all active cameras in the scene with distance-attenuated trauma
  /// radiating from [epicenter] (E17-3).
  void shakeCamerasAt(
    Vec3 epicenter, {
    double trauma = 0.5,
    double maxDistance = 25.0,
    double? rotation,
  }) {
    for (final cam in _cameras) {
      if (cam._active) {
        cam.shakeAt(
          epicenter,
          trauma: trauma,
          maxDistance: maxDistance,
          rotation: rotation,
        );
      }
    }
  }

  /// Triggers a unified game explosion at [epicenter], applying radial
  /// [explosionForce] to nearby [RigidBody]s and screen shake to nearby
  /// [Camera]s (E17-3).
  void explode(
    Vec3 epicenter, {
    double force = 12.0,
    double radius = 8.0,
    double cameraTrauma = 0.6,
    double cameraMaxDistance = 25.0,
    double upwardsModifier = 0.5,
  }) {
    physics.addExplosionForce(
      force,
      epicenter,
      radius,
      upwardsModifier: upwardsModifier,
    );
    if (cameraTrauma > 0) {
      shakeCamerasAt(
        epicenter,
        trauma: cameraTrauma,
        maxDistance: cameraMaxDistance,
      );
    }
  }

  /// Plays [clip] at [position] with 3D spatial attenuation on a temporary
  /// [GameObject] that self-cleans after [duration] (E18-2).
  GameObject? playClipAt(
    AudioClip clip,
    Vec3 position, {
    double volume = 1.0,
    double pitch = 1.0,
    double spatialBlend = 1.0,
    double minDistance = 1.0,
    double maxDistance = 50.0,
    String bus = 'sfx',
    double duration = 5.0,
  }) => AudioSource.playClipAtPoint(
    this,
    clip,
    position,
    volume: volume,
    pitch: pitch,
    spatialBlend: spatialBlend,
    minDistance: minDistance,
    maxDistance: maxDistance,
    bus: bus,
    duration: duration,
  );

  /// Spawns a transient spatial one-shot GameObject playing a procedural
  /// synthesized sound effect from `package:voxsynth` (E28-1).
  GameObject? playSynthAt(
    SynthSound synth,
    Vec3 position, {
    double volume = 1.0,
    double pitch = 1.0,
    double spatialBlend = 1.0,
    double minDistance = 1.0,
    double maxDistance = 50.0,
    String bus = 'sfx',
    double duration = 3.0,
    String? name,
  }) {
    final clip = ProceduralAudioClip.fromSynth(synth, name: name);
    return playClipAt(
      clip,
      position,
      volume: volume,
      pitch: pitch,
      spatialBlend: spatialBlend,
      minDistance: minDistance,
      maxDistance: maxDistance,
      bus: bus,
      duration: duration,
    );
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
      if (!c._active &&
          !c._destroyRequested &&
          c.gameObject.activeInHierarchy &&
          c._enabledSelf) {
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
      if (src._active) {
        if (_engine != null) src._stepFade(_engine!.time.deltaTime);
        src._syncChannelVolume();
      }
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
            points.add(
              PointLight(
                id: points.length,
                position: l.transform.position,
                color: l.color,
                intensity: l.intensity,
                radius: l.range,
                castsShadow: l.castsShadow,
              ),
            );
          }
        case LightType.spot:
          if (spots.length <
              RuntimeLightBudget.unshadowedSpotLights +
                  RuntimeLightBudget.shadowedSpotLights) {
            spots.add(
              SpotLight(
                id: spots.length,
                position: l.transform.position,
                direction: l.transform.forward,
                color: l.color,
                intensity: l.intensity,
                range: l.range,
                innerConeRadians: l.innerSpotAngle,
                outerConeRadians: l.spotAngle,
                castsShadow: l.castsShadow,
              ),
            );
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
  }) => ThermalFieldEngine.dissolutionAt(
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
      cam2d._sync(
        _engine!.graphics.viewportWidth,
        _engine!.graphics.viewportHeight,
      );
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
      gizmos
        ..collectAuto()
        .._encode(encoder, vw, vh);
    }
  }

  // ── Destruction ─────────────────────────────────────────────────────────

  /// Schedules [object] (and its subtree) for destruction at the end of the
  /// current frame.
  void destroy(GameObject object) {
    if (object.scene != this) {
      throw ArgumentError('Object belongs to another scene');
    }
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
      throw StateError(
        'TransformComponent cannot be destroyed; destroy its GameObject',
      );
    }
    if (c._destroyRequested || c._destroyed) return;
    c._destroyRequested = true;
    _destroyComponents.add(c);
  }

  void _flushDestroyed() {
    for (final c in List.of(_destroyComponents)) {
      if (!c._destroyed &&
          c._gameObject != null &&
          !c._gameObject!._destroyRequested) {
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
    TweenManager.instance.killTarget(go);
    TweenManager.instance.killTarget(go.transform);
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
    TweenManager.instance.killTarget(c);
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

/// Raycast hit result returned by [Scene.raycastMeshes] (E29-2).
final class SceneMeshRayHit {
  final GameObject gameObject;
  final MeshRenderer renderer;
  final double distance;
  final GeomVec3 point;

  const SceneMeshRayHit({
    required this.gameObject,
    required this.renderer,
    required this.distance,
    required this.point,
  });
}
