part of '../../engine.dart';

/// Renders a GPU-skinned skeletal mesh driven by an [Animator] or [SkinData] pose.
final class SkinnedMeshRenderer extends Component {
  MeshHandle? _mesh;
  MaterialHandle? _material;
  SkinData? skin;
  Float32List _jointMatrices;
  bool _dirty = true;

  SceneNode? _leaf;

  SkinnedMeshRenderer({
    MeshHandle? this._mesh,
    MaterialHandle? this._material,
    this.skin,
    Float32List? initialPalette,
  }) : _jointMatrices =
           initialPalette ??
           Float32List(
             ((skin?.jointCount ?? 1).clamp(
                   1,
                   RenderingShaderContracts.maxSkinJoints,
                 )) *
                 16,
           );

  static final spec = ComponentSpec<SkinnedMeshRenderer>(
    'SkinnedMeshRenderer',
    SkinnedMeshRenderer.new,
    const [],
  );

  MeshHandle? get mesh => _mesh;
  set mesh(MeshHandle? value) {
    _mesh = value;
    _leaf?.mesh = value;
    _dirty = true;
  }

  MaterialHandle? get material => _material;
  set material(MaterialHandle? value) {
    _material = value;
    _leaf?.material = value;
  }

  Float32List get jointMatrices => _jointMatrices;

  void setJointPalette(Float32List palette) {
    _jointMatrices = Float32List.fromList(palette);
    _dirty = true;
  }

  void syncToRenderer(Graphics graphics) {
    final handle = _mesh;
    if (handle == null || !handle.isValid || !_dirty) return;
    final joints = skin?.jointCount ?? (_jointMatrices.length ~/ 16);
    graphics.setSkinningPalette(handle, _jointMatrices, jointCount: joints);
    _dirty = false;
  }

  @override
  void _onEnableInternal() {
    if (_mesh != null || _material != null) {
      _leaf = SceneNode(
        name: '${gameObject.name}#skinned',
        mesh: _mesh,
        material: _material,
      );
      gameObject.node.addChild(_leaf!);
    }
    _dirty = true;
  }

  @override
  void _onDisableInternal() {
    _leaf?.removeFromParent();
    _leaf = null;
  }
}
