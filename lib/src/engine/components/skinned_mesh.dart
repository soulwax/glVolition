part of '../../engine.dart';

/// Renders a GPU-skinned skeletal mesh driven by an [Animator] or [SkinData] pose.
final class SkinnedMeshRenderer extends Component {
  MeshHandle? _mesh;
  final MeshData? meshData;
  MaterialHandle? _material;
  SkinData? skin;
  Float32List _jointMatrices;
  bool _dirty = true;

  SceneNode? _leaf;

  SkinnedMeshRenderer({
    MeshHandle? mesh,
    this.meshData,
    MaterialHandle? material,
    this.skin,
    Float32List? initialPalette,
  }) : _jointMatrices = initialPalette != null
           ? Float32List.fromList(
               initialPalette.length >
                       RenderingShaderContracts.maxSkinJoints * 16
                   ? initialPalette.sublist(
                       0,
                       RenderingShaderContracts.maxSkinJoints * 16,
                     )
                   : initialPalette,
             )
           : Float32List(
               ((skin?.jointCount ?? 1).clamp(
                     1,
                     RenderingShaderContracts.maxSkinJoints,
                   )) *
                   16,
             ) {
    _mesh = mesh;
    _material = material;
  }

  static final spec = ComponentSpec<SkinnedMeshRenderer>(
    'SkinnedMeshRenderer',
    SkinnedMeshRenderer.new,
    const [],
  );

  MeshHandle? get mesh => _mesh;
  set mesh(MeshHandle? value) {
    if (_mesh == value) return;
    _mesh = value;
    if (_leaf != null) {
      _leaf!.mesh = value;
    } else if (isActiveAndEnabled && (_mesh != null || _material != null)) {
      _leaf = SceneNode(
        name: '${gameObject.name}#skinned',
        mesh: _mesh,
        material: _material,
      );
      gameObject.node.addChild(_leaf!);
    }
    _dirty = true;
  }

  MaterialHandle? get material => _material;
  set material(MaterialHandle? value) {
    if (_material == value) return;
    _material = value;
    if (_leaf != null) {
      _leaf!.material = value;
    } else if (isActiveAndEnabled && (_mesh != null || _material != null)) {
      _leaf = SceneNode(
        name: '${gameObject.name}#skinned',
        mesh: _mesh,
        material: _material,
      );
      gameObject.node.addChild(_leaf!);
    }
  }

  Float32List get jointMatrices => _jointMatrices;

  void setJointPalette(Float32List palette) {
    final maxFloats = RenderingShaderContracts.maxSkinJoints * 16;
    if (palette.length > maxFloats) {
      _jointMatrices = Float32List.fromList(palette.sublist(0, maxFloats));
    } else {
      _jointMatrices = Float32List.fromList(palette);
    }
    _dirty = true;
  }

  /// Pushes the skinning palette and uniforms to the GPU [graphics] device.
  void applySkinPalette(Graphics graphics) {
    final handle = _mesh;
    if (handle == null || !handle.isValid) return;

    final rawJoints = skin?.jointCount ?? (_jointMatrices.length ~/ 16);
    final jointCount = rawJoints.clamp(
      0,
      RenderingShaderContracts.maxSkinJoints,
    );
    final expectedFloats = jointCount * 16;

    final paletteToUpload = _jointMatrices.length == expectedFloats
        ? _jointMatrices
        : Float32List.fromList(
            _jointMatrices.length > expectedFloats
                ? _jointMatrices.sublist(0, expectedFloats)
                : [
                    ..._jointMatrices,
                    ...List<double>.filled(
                      expectedFloats - _jointMatrices.length,
                      0.0,
                    ),
                  ],
          );

    graphics.setSkinningPalette(
      handle,
      paletteToUpload,
      jointCount: jointCount,
    );

    for (final slot in const [
      ShaderSlot.safeWorld,
      ShaderSlot.texturedWorld,
      ShaderSlot.shadowedWorld,
    ]) {
      graphics.setShaderUniform(
        slot,
        RenderingShaderContracts.skinEnabledUniform,
        const ShaderUniform.float(1.0),
      );
      graphics.setShaderUniform(
        slot,
        RenderingShaderContracts.skinJointCountUniform,
        ShaderUniform.float(jointCount.toDouble()),
      );
    }
    _dirty = false;
  }

  /// Syncs the skinning palette to [graphics] if dirty.
  void syncToRenderer(Graphics graphics) {
    if (!_dirty) return;
    applySkinPalette(graphics);
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

  void dispose() {
    _leaf?.removeFromParent();
    _leaf = null;
    _mesh = null;
    _material = null;
  }
}
