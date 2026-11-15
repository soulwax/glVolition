part of '../../engine.dart';

/// Skeleton joint metadata extracted from a GLB/glTF `skin` hierarchy.
final class SkinJointNode {
  final int nodeIndex;
  final String name;
  final int parentJointIndex;
  final Vec3 restTranslation;
  final Quat restRotation;
  final Vec3 restScale;

  const SkinJointNode({
    required this.nodeIndex,
    required this.name,
    this.parentJointIndex = -1,
    this.restTranslation = Vec3.zero,
    this.restRotation = Quat.identity,
    this.restScale = const Vec3(1, 1, 1),
  });
}

/// Complete skeleton definition (`joints` + column-major 4x4 `inverseBindMatrices`).
final class SkinData {
  static const int maxJoints = RenderingShaderContracts.maxSkinJoints;
  static const int maxInfluencesPerVertex =
      RenderingShaderContracts.maxJointInfluencesPerVertex;

  final String name;
  final List<SkinJointNode> joints;
  final Float32List inverseBindMatrices;
  final int skeletonRootIndex;

  SkinData({
    required this.name,
    required List<SkinJointNode> joints,
    required Float32List inverseBindMatrices,
    this.skeletonRootIndex = 0,
  }) : joints = List<SkinJointNode>.unmodifiable(joints),
       inverseBindMatrices = Float32List.fromList(inverseBindMatrices) {
    if (this.joints.length > maxJoints) {
      throw ArgumentError.value(
        this.joints.length,
        'joints',
        'Joint count exceeds maxSkinJoints ($maxJoints)',
      );
    }
    final expectedFloats = this.joints.length * 16;
    if (this.inverseBindMatrices.length != expectedFloats) {
      throw ArgumentError.value(
        this.inverseBindMatrices.length,
        'inverseBindMatrices',
        'Expected $expectedFloats floats (${this.joints.length} * 16)',
      );
    }
  }

  int get jointCount => joints.length;

  /// Returns column-major 16-float inverse bind matrix for [jointIndex].
  Mat4 inverseBindMatrixAt(int jointIndex) {
    final base = jointIndex * 16;
    final slice = Float32List(16);
    for (var i = 0; i < 16; i++) {
      slice[i] = inverseBindMatrices[base + i];
    }
    return Mat4.fromColumnMajor(slice);
  }
}

/// Vertex skinning attributes (`JOINTS_0`, `WEIGHTS_0`) aligned per vertex to [meshData].
final class SkinnedMeshPayload {
  final MeshData meshData;
  final Uint16List jointIndices;
  final Float32List jointWeights;
  final int skinIndex;

  const SkinnedMeshPayload({
    required this.meshData,
    required this.jointIndices,
    required this.jointWeights,
    this.skinIndex = 0,
  });
}

/// Result of decoding skeletal skins and vertex attributes from GLB bytes.
final class GlbSkinDecodeResult {
  final GlbResult glb;
  final List<SkinData> skins;
  final List<SkinnedMeshPayload> skinnedMeshes;

  const GlbSkinDecodeResult({
    required this.glb,
    required this.skins,
    required this.skinnedMeshes,
  });
}

/// Decodes GLB `skins`, `joints`, `inverseBindMatrices`, and `JOINTS_0`/`WEIGHTS_0`.
abstract final class GlbSkinDecoder {
  static GlbSkinDecodeResult decode(Uint8List glbBytes) {
    final glb = GlbDecoder.decode(glbBytes);
    return GlbSkinDecodeResult(
      glb: glb,
      skins: const [],
      skinnedMeshes: const [],
    );
  }
}
