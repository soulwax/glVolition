part of '../engine.dart';

/// Optional mixin for components managed by an [ObjectPool].
mixin Poolable on Component {
  void onSpawned() {}
  void onDespawned() {}
}

/// Reusable template for spawning [GameObject] hierarchies (`Scene.instantiate`).
final class Prefab {
  final String name;
  final void Function(GameObject root) _build;

  const Prefab(this.name, this._build);
  const Prefab.builder(this.name, this._build);

  /// Creates a prefab from a serialized GameObject JSON map and a
  /// [ComponentRegistry].
  factory Prefab.fromJson(
    Map<String, Object?> json, {
    ComponentRegistry? registry,
  }) {
    final name = (json['name'] as String?) ?? 'Prefab';
    final reg = registry ?? ComponentRegistry.defaults();
    return Prefab.builder(name, (root) {
      SceneSerializer._populateGameObjectFromJson(root, json, reg, const {});
    });
  }

  /// Creates a [Prefab] from a loaded [ModelAsset] hierarchy so every mesh
  /// node becomes a [GameObject] with [MeshFilter] + [MeshRenderer] (E14-1).
  factory Prefab.fromModelAsset(
    ModelAsset asset, {
    String? name,
    bool castShadows = true,
    bool receiveShadows = true,
  }) {
    final rootName = name ?? asset.name;
    return Prefab.builder(rootName, (root) {
      final templateRoot = asset.instantiate(name: rootName);
      _populateFromSceneNode(
        root,
        templateRoot,
        castShadows: castShadows,
        receiveShadows: receiveShadows,
      );
    });
  }

  /// Creates a [Prefab] from a decoded [GlbResult], registering meshes and
  /// materials on [engine]'s [Graphics] device (E14-1).
  factory Prefab.fromGlbResult(
    String name,
    GlbResult result,
    Engine engine, {
    MaterialOverride? materialOverride,
    bool castShadows = true,
    bool receiveShadows = true,
  }) {
    final materials = <MaterialHandle>[];
    for (var i = 0; i < result.materials.length; i++) {
      final authored = result.materials[i];
      var def = authored.copyWith(key: '$name/${authored.key}');
      if (materialOverride != null) def = materialOverride(authored.key, def);
      materials.add(engine.graphics.createMaterial(def));
    }
    if (materials.isEmpty) {
      materials.add(
        engine.graphics.createMaterial(
          MaterialDefinition(key: '$name/default'),
        ),
      );
    }

    final meshes = <MeshData, MeshHandle>{};
    result.rootNode.traverse((node) {
      final data = node.meshData;
      if (data != null && !meshes.containsKey(data)) {
        meshes[data] = engine.graphics.createMesh(
          data,
          debugLabel: '$name/${node.name ?? "mesh"}',
        );
      }
    });

    return Prefab.builder(name, (root) {
      void buildNode(GameObject targetGo, SceneNode srcNode) {
        targetGo.transform
          ..localPosition = srcNode.localTransform.translation
          ..localRotation = srcNode.localTransform.rotation
          ..localScale = srcNode.localTransform.scale;
        final data = srcNode.meshData;
        if (data != null) {
          final meshHandle = meshes[data]!;
          final matIdx = result
              .materialOf(srcNode)
              .clamp(0, materials.length - 1);
          targetGo.addComponent(
            MeshRenderer(
              mesh: meshHandle,
              meshData: data,
              material: materials[matIdx],
              castsShadow: castShadows,
              receivesShadow: receiveShadows,
            ),
          );
        }
        for (final childNode in srcNode.children) {
          final childGo = targetGo.scene.createGameObject(
            childNode.name ?? 'Node',
            parent: targetGo,
          );
          buildNode(childGo, childNode);
        }
      }

      buildNode(root, result.rootNode);
    });
  }

  /// Decodes a binary GLB byte buffer and builds a [Prefab] hierarchy (E14-1).
  factory Prefab.fromGlbBytes(
    String name,
    Uint8List glbBytes,
    Engine engine, {
    MaterialOverride? materialOverride,
    bool castShadows = true,
    bool receiveShadows = true,
  }) => Prefab.fromGlbResult(
    name,
    GlbDecoder.decode(glbBytes),
    engine,
    materialOverride: materialOverride,
    castShadows: castShadows,
    receiveShadows: receiveShadows,
  );

  /// Creates a [Prefab] from a validated [ValidatedModelPackage] by decoding
  /// its `.qmesh` part payloads at [lod] via [ModelCache] and registering
  /// meshes and slot materials on [engine]'s [Graphics] device (E98-1 / E101).
  factory Prefab.fromModelPackage(
    ValidatedModelPackage package,
    Engine engine, {
    String? name,
    String lod = 'LOD0',
    MaterialOverride? materialOverride,
    bool castShadows = true,
    bool receiveShadows = true,
    ModelCache? cache,
  }) {
    if (!package.manifest.lods.contains(lod)) {
      throw ArgumentError.value(
        lod,
        'lod',
        'package does not declare this LOD',
      );
    }
    for (final part in package.manifest.parts) {
      if (!part.lodFiles.containsKey(lod)) {
        throw StateError('part ${part.id} has no $lod payload');
      }
    }

    final assetName = name ?? package.manifest.assetId;

    final materials = <MaterialHandle>[];
    for (final matName in package.manifest.materials) {
      var def = MaterialDefinition(key: '$assetName/$matName');
      if (materialOverride != null) def = materialOverride(matName, def);
      materials.add(engine.graphics.createMaterial(def));
    }
    if (materials.isEmpty) {
      materials.add(
        engine.graphics.createMaterial(
          MaterialDefinition(key: '$assetName/default'),
        ),
      );
    }

    final meshCache = cache ?? ModelCache();
    final parts =
        <
          ({
            ModelPackagePart part,
            MeshHandle mesh,
            MeshData meshData,
            MaterialHandle material,
          })
        >[];
    for (final part in package.manifest.parts) {
      final path = part.lodFiles[lod];
      if (path == null) {
        throw StateError('part ${part.id} has no $lod payload');
      }
      final cached = meshCache.decodeAndCache(
        Uint8List.fromList(package.payload(path)),
      );
      try {
        final meshHandle = engine.graphics.createMesh(
          cached.deduplicated,
          debugLabel: '$assetName/${part.id}',
        );
        final matIdx = part.materialSlot.clamp(0, materials.length - 1);
        parts.add((
          part: part,
          mesh: meshHandle,
          meshData: cached.deduplicated,
          material: materials[matIdx],
        ));
      } finally {
        meshCache.release(cached);
      }
    }

    return Prefab.builder(assetName, (root) {
      for (final entry in parts) {
        final child = root.scene.createGameObject(entry.part.id, parent: root);
        child.addComponent(
          MeshRenderer(
            mesh: entry.mesh,
            meshData: entry.meshData,
            material: entry.material,
            castsShadow: castShadows,
            receivesShadow: receiveShadows,
          ),
        );
      }
    });
  }

  static void _populateFromSceneNode(
    GameObject targetGo,
    SceneNode srcNode, {
    required bool castShadows,
    required bool receiveShadows,
  }) {
    targetGo.transform
      ..localPosition = srcNode.localTransform.translation
      ..localRotation = srcNode.localTransform.rotation
      ..localScale = srcNode.localTransform.scale;
    if (srcNode.mesh != null && srcNode.material != null) {
      targetGo.addComponent(
        MeshRenderer(
          mesh: srcNode.mesh,
          meshData: srcNode.meshData,
          material: srcNode.material,
          castsShadow: castShadows,
          receivesShadow: receiveShadows,
        ),
      );
    }
    for (final childNode in srcNode.children) {
      final childGo = targetGo.scene.createGameObject(
        childNode.name ?? 'Node',
        parent: targetGo,
      );
      _populateFromSceneNode(
        childGo,
        childNode,
        castShadows: castShadows,
        receiveShadows: receiveShadows,
      );
    }
  }

  /// Instantiates this prefab in [scene].
  GameObject instantiate(
    Scene scene, {
    GameObject? parent,
    Vec3? position,
    Quat? rotation,
    double? scale,
    String? name,
    bool active = true,
  }) {
    // Build while inactive if requested, otherwise build and refresh.
    final root = scene.createGameObject(
      name ?? this.name,
      parent: parent,
      position: position,
      rotation: rotation,
      scale: scale ?? 1.0,
      active: false,
    );
    _build(root);
    if (position != null) root.transform.localPosition = position;
    if (rotation != null) root.transform.localRotation = rotation;
    if (scale != null) root.transform.localScale = scale;
    if (active) root.setActive(true);
    return root;
  }
}

/// Pre-allocates and recycles [GameObject]s carrying a principal component [T]
/// so high-frequency spawns (bullets, meteors, pickups, VFX) do not allocate
/// or churn the scene graph at runtime.
final class ObjectPool<T extends Component> {
  final Scene scene;
  final Prefab prefab;
  final GameObject? parent;

  final List<T> _available = [];
  final Set<T> _active = {};

  ObjectPool({
    required this.scene,
    required this.prefab,
    this.parent,
    int initialCapacity = 0,
  }) {
    if (initialCapacity > 0) warmUp(initialCapacity);
  }

  int get activeCount => _active.length;
  int get availableCount => _available.length;
  int get totalCount => _active.length + _available.length;
  Iterable<T> get activeItems => List.unmodifiable(_active);

  void warmUp(int count) {
    for (var i = 0; i < count; i++) {
      final item = _createInactive();
      _available.add(item);
    }
  }

  T _createInactive() {
    final go = prefab.instantiate(scene, parent: parent, active: false);
    final comp = go.getComponent<T>();
    if (comp == null) {
      throw StateError('Prefab "${prefab.name}" did not attach a $T component');
    }
    return comp;
  }

  /// Acquires an instance from the pool (or instantiates a new one if empty),
  /// activates its [GameObject], and invokes [Poolable.onSpawned].
  T acquire({Vec3? position, Quat? rotation, double? scale}) {
    final item = _available.isNotEmpty
        ? _available.removeLast()
        : _createInactive();
    final go = item.gameObject;
    if (position != null) go.transform.localPosition = position;
    if (rotation != null) go.transform.localRotation = rotation;
    if (scale != null) go.transform.localScale = scale;
    _active.add(item);
    go.setActive(true);
    for (final c in go.components) {
      if (c is Poolable) c.onSpawned();
    }
    return item;
  }

  /// Deactivates [item]'s [GameObject], invokes [Poolable.onDespawned], and
  /// returns it to the available list.
  void release(T item) {
    if (!_active.remove(item)) return;
    final go = item.gameObject;
    for (final c in go.components) {
      if (c is Poolable) c.onDespawned();
    }
    go.setActive(false);
    _available.add(item);
  }

  void releaseAll() {
    for (final item in List.of(_active)) {
      release(item);
    }
  }
}
