part of '../../engine.dart';

/// Draws a single mesh with a material on its [GameObject]'s scene node, or
/// on an offset child node when [localOffset] is given (handy when a primitive's
/// pivot is at its centre rather than its base).
final class MeshRenderer extends Component {
  MeshHandle? _mesh;
  final MeshData? meshData;
  MaterialHandle? _material;
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
    Transform localOffset = Transform.identity,
    bool castsShadow = true,
    bool receivesShadow = true,
    DrawMode drawMode = DrawMode.opaque,
    BlendMode blendMode = BlendMode.alpha,
  }) {
    _mesh = mesh;
    _material = material;
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

  @override
  void _onAttach() {
    final leaf = SceneNode(
      name: '${gameObject.name}#mesh',
      transform: _localOffset,
      mesh: _mesh,
      meshData: meshData,
      bounds: meshData?.bounds,
      material: _material,
      castsShadow: _castsShadow,
      receivesShadow: _receivesShadow,
      drawMode: _drawMode,
      blendMode: _blendMode,
    )..visible = false;
    gameObject.node.addChild(leaf);
    _leaf = leaf;
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
  double get boundingRadius => (model.bounds.max - model.bounds.min).length * 0.5;

  @override
  void _onAttach() {
    final shift = centerOrigin ? Transform.at(-(model.bounds.min + model.bounds.max) * 0.5) : Transform.identity;
    final instance = model.instantiate(
      name: '${gameObject.name}#model',
      transform: localOffset * shift,
    )..visible = false;
    gameObject.node.addChild(instance);
    _instance = instance;
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
