part of '../../engine.dart';

/// Supported primitive types for [Scene.createPrimitive] (E23-1).
enum PrimitiveType { cube, sphere, capsule, cylinder, plane, quad }

/// Draws a single mesh with a material on its [GameObject]'s scene node, or
/// on an offset child node when [localOffset] is given (handy when a primitive's
/// pivot is at its centre rather than its base).
final class MeshRenderer extends Component {
  MeshHandle? _mesh;
  final MeshData? meshData;
  MaterialHandle? _material;
  MaterialDefinition? _materialOverride;
  LinearColor? _tintColor;
  Transform _localOffset = Transform.identity;
  bool _castsShadow = true;
  bool _receivesShadow = true;
  DrawMode _drawMode = DrawMode.opaque;
  BlendMode _blendMode = BlendMode.alpha;

  SceneNode? _leaf;

  MeshRenderer({
    MeshHandle? mesh,
    this.meshData,
    MaterialHandle? material,
    MaterialDefinition? materialOverride,
    LinearColor? tintColor,
    Transform localOffset = Transform.identity,
    bool castsShadow = true,
    bool receivesShadow = true,
    DrawMode drawMode = DrawMode.opaque,
    BlendMode blendMode = BlendMode.alpha,
  }) {
    _mesh = mesh;
    _material = material;
    _materialOverride = materialOverride;
    _tintColor = tintColor;
    _localOffset = localOffset;
    _castsShadow = castsShadow;
    _receivesShadow = receivesShadow;
    _drawMode = drawMode;
    _blendMode = blendMode;
  }

  MeshHandle? get mesh => _mesh;
  set mesh(MeshHandle? value) {
    _mesh = value;
    _leaf?.mesh = value;
  }

  MaterialHandle? get material => _material;
  set material(MaterialHandle? value) {
    _material = value;
    _leaf?.material = value;
  }

  MaterialDefinition? get materialOverride => _materialOverride;
  set materialOverride(MaterialDefinition? value) {
    _materialOverride = value;
    if (value != null && isAttached && scene.isLoaded) {
      material = engine.graphics.createMaterial(value);
    }
  }

  /// Optional per-renderer tint color (E20-2).
  /// When set, applies a dielectric/tinted material override if an engine graphics context is active.
  LinearColor? get tintColor => _tintColor;
  set tintColor(LinearColor? value) {
    _tintColor = value;
    if (value != null && isAttached && scene.isLoaded) {
      material = engine.graphics.createMaterial(
        _materialOverride != null
            ? _materialOverride!.copyWith(
                tintR: value.r,
                tintG: value.g,
                tintB: value.b,
              )
            : MaterialDefinition.dielectric(
                key: '${gameObject.name}#tint',
                color: value,
              ),
      );
    }
  }

  /// Convenience setter for [tintColor].
  void setTint(LinearColor? color) => tintColor = color;

  Transform get localOffset => _localOffset;
  set localOffset(Transform value) {
    _localOffset = value;
    _leaf?.localTransform = value;
  }

  bool get castsShadow => _castsShadow;
  set castsShadow(bool value) {
    _castsShadow = value;
    _leaf?.castsShadow = value;
  }

  bool get receivesShadow => _receivesShadow;
  set receivesShadow(bool value) {
    _receivesShadow = value;
    _leaf?.receivesShadow = value;
  }

  DrawMode get drawMode => _drawMode;
  set drawMode(DrawMode value) {
    _drawMode = value;
    _leaf?.drawMode = value;
  }

  BlendMode get blendMode => _blendMode;
  set blendMode(BlendMode value) {
    _blendMode = value;
    _leaf?.blendMode = value;
  }

  /// Computes the approximate world-space bounding box for this renderer (E29-2).
  Aabb3 get worldAabb {
    final pos = transform.position;
    final s = transform.lossyScale;
    final stretch = transform.localStretch;
    final halfExtents = GeomVec3(
      (s * stretch.x).abs() * 0.5,
      (s * stretch.y).abs() * 0.5,
      (s * stretch.z).abs() * 0.5,
    );
    final center = GeomVec3(pos.x, pos.y, pos.z);
    return Aabb3.fromCenterExtents(center, halfExtents);
  }

  static final spec =
      ComponentSpec<MeshRenderer>('MeshRenderer', MeshRenderer.new, [
        Field.color(
          'tintColor',
          (m) => m.tintColor ?? LinearColor.white,
          (m, v) => m.tintColor = v,
        ),
        Field.boolean(
          'castsShadow',
          (m) => m.castsShadow,
          (m, v) => m.castsShadow = v,
        ),
        Field.boolean(
          'receivesShadow',
          (m) => m.receivesShadow,
          (m, v) => m.receivesShadow = v,
        ),
        Field.enumValue<MeshRenderer, DrawMode>(
          'drawMode',
          DrawMode.values,
          (m) => m.drawMode,
          (m, v) => m.drawMode = v,
        ),
        Field.enumValue<MeshRenderer, BlendMode>(
          'blendMode',
          BlendMode.values,
          (m) => m.blendMode,
          (m, v) => m.blendMode = v,
        ),
        Field.vec3(
          'localOffsetPos',
          (m) => m.localOffset.translation,
          (m, v) => m.localOffset = m.localOffset.copyWith(translation: v),
        ),
      ]);

  @override
  void _onAttach() {
    if (_materialOverride != null && _material == null && scene.isLoaded) {
      _material = engine.graphics.createMaterial(_materialOverride!);
    } else if (_tintColor != null && _material == null && scene.isLoaded) {
      _material = engine.graphics.createMaterial(
        MaterialDefinition.dielectric(
          key: '${gameObject.name}#tint',
          color: _tintColor!,
        ),
      );
    }
    final leaf = SceneNode(
      name: '${gameObject.name}#mesh',
      transform: _localOffset,
      mesh: _mesh,
      meshData: meshData,
      bounds: meshData?.bounds,
      material: _material,
      visibilityMask: 1 << gameObject.layer,
      castsShadow: _castsShadow,
      receivesShadow: _receivesShadow,
      drawMode: _drawMode,
      blendMode: _blendMode,
    )..visible = false;
    gameObject.node.addChild(leaf);
    _leaf = leaf;
    _syncVisibilityMask();
  }

  void _syncVisibilityMask() {
    _leaf?.visibilityMask = 1 << gameObject.layer;
  }

  @override
  void _onEnableInternal() => _leaf?.visible = true;

  @override
  void _onDisableInternal() => _leaf?.visible = false;

  @override
  void _onDestroyInternal() {
    _leaf?.removeFromParent();
    _leaf = null;
  }
}

/// Instantiates a multi-node [ModelAsset] (loaded from a `.glb`) under its
/// [GameObject]. When [centerOrigin] is true the model is shifted so the
/// centre of its bounding box sits on the object's origin.
final class ModelRenderer extends Component {
  final ModelAsset model;
  final bool centerOrigin;
  final Transform localOffset;

  SceneNode? _instance;

  ModelRenderer(
    this.model, {
    this.centerOrigin = false,
    this.localOffset = Transform.identity,
  });

  /// Half-diagonal of the model's authored bounding box, before scaling.
  double get boundingRadius =>
      (model.bounds.max - model.bounds.min).length * 0.5;

  @override
  void _onAttach() {
    final shift = centerOrigin
        ? Transform.at(-(model.bounds.min + model.bounds.max) * 0.5)
        : Transform.identity;
    final instance = model.instantiate(
      name: '${gameObject.name}#model',
      transform: localOffset * shift,
    )..visible = false;
    gameObject.node.addChild(instance);
    _instance = instance;
    _syncVisibilityMask();
  }

  void _syncVisibilityMask() {
    final mask = 1 << gameObject.layer;
    _instance?.traverse((node) => node.visibilityMask = mask);
  }

  @override
  void _onEnableInternal() => _instance?.visible = true;

  @override
  void _onDisableInternal() => _instance?.visible = false;

  @override
  void _onDestroyInternal() {
    _instance?.removeFromParent();
    _instance = null;
  }
}

/// Renders many instances of a single mesh in a single GPU draw call using
/// pixeldart's [InstancedMeshNode] (E9-1).
///
/// Supports per-instance raycast picking (`RaycastHit.instanceIndex`) via
/// [Scene.raycastVisuals].
final class InstancedMeshRenderer extends Component {
  MeshHandle? _mesh;
  final MeshData? meshData;
  MaterialHandle? _material;
  final MaterialDefinition? materialDefinition;
  bool _castsShadow = true;
  bool _receivesShadow = true;
  DrawMode _drawMode = DrawMode.opaque;
  BlendMode _blendMode = BlendMode.alpha;
  final List<Transform> _initialTransforms;

  InstancedMeshNode? _node;

  InstancedMeshRenderer({
    MeshHandle? mesh,
    this.meshData,
    MaterialHandle? material,
    this.materialDefinition,
    Iterable<Transform> transforms = const [],
    bool castsShadow = true,
    bool receivesShadow = true,
    DrawMode drawMode = DrawMode.opaque,
    BlendMode blendMode = BlendMode.alpha,
  }) : _initialTransforms = List.of(transforms) {
    _mesh = mesh;
    _material = material;
    _castsShadow = castsShadow;
    _receivesShadow = receivesShadow;
    _drawMode = drawMode;
    _blendMode = blendMode;
  }

  InstancedMeshNode? get instancedNode => _node;

  int get instanceCount => _node?.instanceCount ?? _initialTransforms.length;

  List<Transform> get instanceTransforms =>
      _node?.instanceTransforms ?? List.unmodifiable(_initialTransforms);

  Transform getInstanceTransform(int index) => _node != null
      ? _node!.getInstanceTransform(index)
      : _initialTransforms[index];

  void addInstance(Transform instanceTransform) {
    final n = _node;
    if (n != null) {
      n.addInstance(instanceTransform);
    } else {
      _initialTransforms.add(instanceTransform);
    }
  }

  void setInstanceTransform(int index, Transform instanceTransform) {
    final n = _node;
    if (n != null) {
      n.setInstanceTransform(index, instanceTransform);
    } else {
      _initialTransforms[index] = instanceTransform;
    }
  }

  void setTransforms(Iterable<Transform> transforms) {
    final n = _node;
    if (n != null) {
      n.setTransforms(transforms);
    } else {
      _initialTransforms
        ..clear()
        ..addAll(transforms);
    }
  }

  void clearInstances() {
    final n = _node;
    if (n != null) {
      n.clearInstances();
    } else {
      _initialTransforms.clear();
    }
  }

  bool get castsShadow => _castsShadow;
  set castsShadow(bool value) {
    _castsShadow = value;
    _node?.castsShadow = value;
  }

  bool get receivesShadow => _receivesShadow;
  set receivesShadow(bool value) {
    _receivesShadow = value;
    _node?.receivesShadow = value;
  }

  @override
  void _onAttach() {
    final node = InstancedMeshNode(
      name: '${gameObject.name}#instanced',
      mesh: _mesh,
      meshData: meshData,
      bounds: meshData?.bounds,
      material: _material,
      visibilityMask: 1 << gameObject.layer,
      castsShadow: _castsShadow,
      receivesShadow: _receivesShadow,
      drawMode: _drawMode,
      blendMode: _blendMode,
      transforms: _initialTransforms,
    )..visible = false;
    gameObject.node.addChild(node);
    _node = node;
    _syncVisibilityMask();
  }

  void _syncVisibilityMask() {
    _node?.visibilityMask = 1 << gameObject.layer;
  }

  @override
  void _onEnableInternal() {
    final n = _node;
    if (n != null) {
      if (n.mesh == null && meshData != null) {
        _mesh = engine.graphics.createMesh(
          meshData!,
          debugLabel: '${gameObject.name}#instanced_mesh',
        );
        n.mesh = _mesh;
      }
      if (n.material == null && materialDefinition != null) {
        _material = engine.graphics.createMaterial(materialDefinition!);
        n.material = _material;
      }
      n.visible = true;
    }
  }

  @override
  void _onDisableInternal() => _node?.visible = false;

  @override
  void _onDestroyInternal() {
    _node?.removeFromParent();
    _node = null;
  }
}
