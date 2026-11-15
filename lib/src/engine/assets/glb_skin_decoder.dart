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

  /// Evaluates the rest local transform matrix for this joint.
  Mat4 get restLocalMatrix => Mat4.compose(
    tx: restTranslation.x,
    ty: restTranslation.y,
    tz: restTranslation.z,
    qx: restRotation.x,
    qy: restRotation.y,
    qz: restRotation.z,
    qw: restRotation.w,
    sx: restScale.x,
    sy: restScale.y,
    sz: restScale.z,
  );

  /// Composes a local matrix overriding any of translation, rotation, or scale.
  Mat4 composeLocalMatrix({Vec3? translation, Quat? rotation, Vec3? scale}) {
    final t = translation ?? restTranslation;
    final r = rotation ?? restRotation;
    final s = scale ?? restScale;
    return Mat4.compose(
      tx: t.x,
      ty: t.y,
      tz: t.z,
      qx: r.x,
      qy: r.y,
      qz: r.z,
      qw: r.w,
      sx: s.x,
      sy: s.y,
      sz: s.z,
    );
  }
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
    bool clampToMaxJoints = true,
  }) : joints = List<SkinJointNode>.unmodifiable(
         clampToMaxJoints && joints.length > maxJoints
             ? joints.take(maxJoints)
             : joints,
       ),
       inverseBindMatrices = Float32List.fromList(
         clampToMaxJoints && joints.length > maxJoints
             ? inverseBindMatrices.sublist(0, maxJoints * 16)
             : inverseBindMatrices,
       ) {
    if (!clampToMaxJoints && this.joints.length > maxJoints) {
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
    if (jointIndex < 0 || jointIndex >= joints.length) {
      return Mat4.identity();
    }
    final base = jointIndex * 16;
    final slice = Float32List(16);
    for (var i = 0; i < 16; i++) {
      slice[i] = inverseBindMatrices[base + i];
    }
    return Mat4.fromColumnMajor(slice);
  }

  /// Returns the index of a joint matching [name], or `-1` if not found.
  int findJointIndexByName(String name) {
    for (var i = 0; i < joints.length; i++) {
      if (joints[i].name == name) return i;
    }
    return -1;
  }

  /// Evaluates hierarchical forward kinematics (FK) and multiplies by inverse
  /// bind matrices to produce a 16-float-per-joint skinning palette.
  ///
  /// Output is clamped to [maxJoints].
  Float32List computeSkinPalette({
    List<Vec3>? translations,
    List<Quat>? rotations,
    List<Vec3>? scales,
    List<Mat4>? localMatrices,
  }) {
    final effectiveCount = math.min(jointCount, maxJoints);
    final palette = Float32List(effectiveCount * 16);
    final globalMatrices = List<Mat4?>.filled(jointCount, null);

    Mat4 evaluateGlobal(int idx) {
      final cached = globalMatrices[idx];
      if (cached != null) return cached;

      Mat4 local;
      if (localMatrices != null && idx < localMatrices.length) {
        local = localMatrices[idx];
      } else {
        final node = joints[idx];
        final t = (translations != null && idx < translations.length)
            ? translations[idx]
            : node.restTranslation;
        final r = (rotations != null && idx < rotations.length)
            ? rotations[idx]
            : node.restRotation;
        final s = (scales != null && idx < scales.length)
            ? scales[idx]
            : node.restScale;
        local = Mat4.compose(
          tx: t.x,
          ty: t.y,
          tz: t.z,
          qx: r.x,
          qy: r.y,
          qz: r.z,
          qw: r.w,
          sx: s.x,
          sy: s.y,
          sz: s.z,
        );
      }

      final parentIdx = joints[idx].parentJointIndex;
      Mat4 global;
      if (parentIdx < 0 || parentIdx >= jointCount || parentIdx == idx) {
        global = local;
      } else {
        global = evaluateGlobal(parentIdx) * local;
      }
      globalMatrices[idx] = global;
      return global;
    }

    for (var j = 0; j < effectiveCount; j++) {
      final global = evaluateGlobal(j);
      final ibm = inverseBindMatrixAt(j);
      final skinMat = global * ibm;
      final base = j * 16;
      for (var k = 0; k < 16; k++) {
        palette[base + k] = skinMat.m[k];
      }
    }
    return palette;
  }

  /// Evaluates the skinning palette from a list of joint [SceneNode]s.
  Float32List computeSkinPaletteFromNodes(List<SceneNode> nodes) {
    final nodeCount = math.min(nodes.length, math.min(jointCount, maxJoints));
    final localMatrices = <Mat4>[];
    for (var i = 0; i < nodeCount; i++) {
      final t = nodes[i].position;
      final r = nodes[i].rotation;
      final s = nodes[i].scale;
      localMatrices.add(
        Mat4.compose(
          tx: t.x,
          ty: t.y,
          tz: t.z,
          qx: r.x,
          qy: r.y,
          qz: r.z,
          qw: r.w,
          sx: s,
          sy: s,
          sz: s,
        ),
      );
    }
    return computeSkinPalette(localMatrices: localMatrices);
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
    if (glbBytes.length < 12) {
      throw const FormatException('GLB header is truncated');
    }
    final header = ByteData.sublistView(glbBytes);
    if (header.getUint32(0, Endian.little) != 0x46546c67) {
      throw const FormatException('GLB magic is invalid');
    }
    final version = header.getUint32(4, Endian.little);
    if (version != 2) {
      throw FormatException('Unsupported GLB version: $version');
    }

    Map<String, dynamic>? jsonMap;
    Uint8List? binBytes;
    var offset = 12;

    while (offset < glbBytes.length) {
      if (glbBytes.length - offset < 8) break;
      final chunkLength = header.getUint32(offset, Endian.little);
      final chunkType = header.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      final end = start + chunkLength;
      if (end > glbBytes.length) {
        throw const FormatException('GLB chunk exceeds container bounds');
      }

      final payload = Uint8List.sublistView(glbBytes, start, end);
      if (chunkType == 0x4e4f534a) {
        // JSON chunk
        final decoded = jsonDecode(utf8.decode(payload).trimRight());
        if (decoded is Map<String, dynamic>) {
          jsonMap = decoded;
        } else if (decoded is Map) {
          jsonMap = decoded.cast<String, dynamic>();
        }
      } else if (chunkType == 0x004e4942) {
        // BIN chunk
        binBytes = payload;
      }
      offset = end;
    }

    if (jsonMap == null) {
      throw const FormatException('GLB is missing JSON chunk');
    }
    binBytes ??= Uint8List(0);
    final bin = ByteData.sublistView(binBytes);

    // Decode standard scene graph & mesh geometry via Pixeldart's GlbDecoder.
    final glb = GlbDecoder.decode(glbBytes);

    final rawNodes = jsonMap['nodes'] as List<dynamic>? ?? const [];
    final accessors = jsonMap['accessors'] as List<dynamic>? ?? const [];
    final bufferViews = jsonMap['bufferViews'] as List<dynamic>? ?? const [];

    // Map parent nodes
    final parentOfNode = <int, int>{};
    for (var i = 0; i < rawNodes.length; i++) {
      final n = rawNodes[i];
      if (n is! Map<String, dynamic>) continue;
      final children = n['children'] as List<dynamic>?;
      if (children != null) {
        for (final c in children) {
          if (c is int && c >= 0 && c < rawNodes.length) {
            parentOfNode[c] = i;
          }
        }
      }
    }

    Float32List readFloatAccessor(int accessorIndex, int componentsPerElement) {
      if (accessorIndex < 0 || accessorIndex >= accessors.length) {
        throw FormatException('Accessor index $accessorIndex out of bounds');
      }
      final acc = accessors[accessorIndex] as Map<String, dynamic>;
      final viewIdx = acc['bufferView'] as int?;
      if (viewIdx == null || viewIdx < 0 || viewIdx >= bufferViews.length) {
        throw FormatException(
          'BufferView index for accessor $accessorIndex out of bounds',
        );
      }
      final view = bufferViews[viewIdx] as Map<String, dynamic>;
      final baseOffset =
          (view['byteOffset'] as int? ?? 0) + (acc['byteOffset'] as int? ?? 0);
      final count = acc['count'] as int;
      final stride = view['byteStride'] as int? ?? (componentsPerElement * 4);

      if (baseOffset +
              (count > 0
                  ? (count - 1) * stride + componentsPerElement * 4
                  : 0) >
          binBytes!.length) {
        throw FormatException(
          'Accessor $accessorIndex exceeds BIN chunk bounds',
        );
      }

      final out = Float32List(count * componentsPerElement);
      for (var i = 0; i < count; i++) {
        final elemOffset = baseOffset + (i * stride);
        for (var c = 0; c < componentsPerElement; c++) {
          out[i * componentsPerElement + c] = bin.getFloat32(
            elemOffset + c * 4,
            Endian.little,
          );
        }
      }
      return out;
    }

    Uint16List readJointsAccessor(int accessorIndex) {
      if (accessorIndex < 0 || accessorIndex >= accessors.length) {
        throw FormatException('Accessor index $accessorIndex out of bounds');
      }
      final acc = accessors[accessorIndex] as Map<String, dynamic>;
      final viewIdx = acc['bufferView'] as int?;
      if (viewIdx == null || viewIdx < 0 || viewIdx >= bufferViews.length) {
        throw FormatException(
          'BufferView index for accessor $accessorIndex out of bounds',
        );
      }
      final view = bufferViews[viewIdx] as Map<String, dynamic>;
      final baseOffset =
          (view['byteOffset'] as int? ?? 0) + (acc['byteOffset'] as int? ?? 0);
      final count = acc['count'] as int;
      final compType = acc['componentType'] as int;
      final stride = view['byteStride'] as int? ?? (compType == 5121 ? 4 : 8);

      final out = Uint16List(count * 4);
      for (var i = 0; i < count; i++) {
        final elemOffset = baseOffset + (i * stride);
        for (var c = 0; c < 4; c++) {
          if (compType == 5121) {
            out[i * 4 + c] = bin.getUint8(elemOffset + c);
          } else if (compType == 5123) {
            out[i * 4 + c] = bin.getUint16(elemOffset + c * 2, Endian.little);
          } else {
            throw FormatException(
              'Unsupported JOINTS_0 componentType: $compType',
            );
          }
        }
      }
      return out;
    }

    Float32List readWeightsAccessor(int accessorIndex) {
      if (accessorIndex < 0 || accessorIndex >= accessors.length) {
        throw FormatException('Accessor index $accessorIndex out of bounds');
      }
      final acc = accessors[accessorIndex] as Map<String, dynamic>;
      final viewIdx = acc['bufferView'] as int?;
      if (viewIdx == null || viewIdx < 0 || viewIdx >= bufferViews.length) {
        throw FormatException(
          'BufferView index for accessor $accessorIndex out of bounds',
        );
      }
      final view = bufferViews[viewIdx] as Map<String, dynamic>;
      final baseOffset =
          (view['byteOffset'] as int? ?? 0) + (acc['byteOffset'] as int? ?? 0);
      final count = acc['count'] as int;
      final compType = acc['componentType'] as int;
      final stride =
          view['byteStride'] as int? ??
          (compType == 5126 ? 16 : (compType == 5121 ? 4 : 8));

      final out = Float32List(count * 4);
      for (var i = 0; i < count; i++) {
        final elemOffset = baseOffset + (i * stride);
        var sum = 0.0;
        for (var c = 0; c < 4; c++) {
          double val;
          if (compType == 5126) {
            val = bin.getFloat32(elemOffset + c * 4, Endian.little);
          } else if (compType == 5121) {
            val = bin.getUint8(elemOffset + c) / 255.0;
          } else if (compType == 5123) {
            val = bin.getUint16(elemOffset + c * 2, Endian.little) / 65535.0;
          } else {
            throw FormatException(
              'Unsupported WEIGHTS_0 componentType: $compType',
            );
          }
          out[i * 4 + c] = val;
          sum += val;
        }
        // Normalize weights if needed
        if (sum > 0.0 && (sum - 1.0).abs() > 1e-5) {
          final invSum = 1.0 / sum;
          for (var c = 0; c < 4; c++) {
            out[i * 4 + c] *= invSum;
          }
        }
      }
      return out;
    }

    // Decode skins
    final rawSkins = jsonMap['skins'] as List<dynamic>? ?? const [];
    final skins = <SkinData>[];

    for (var s = 0; s < rawSkins.length; s++) {
      final skinJson = rawSkins[s] as Map<String, dynamic>;
      final name = skinJson['name'] as String? ?? 'skin_$s';
      final jointNodeIndices =
          (skinJson['joints'] as List<dynamic>? ?? const []).cast<int>();

      final nodeToJoint = <int, int>{};
      for (var j = 0; j < jointNodeIndices.length; j++) {
        final nodeIdx = jointNodeIndices[j];
        if (nodeIdx < 0 || nodeIdx >= rawNodes.length) {
          throw FormatException(
            'Joint node index $nodeIdx out of bounds in skin $name',
          );
        }
        nodeToJoint[nodeIdx] = j;
      }

      final joints = <SkinJointNode>[];
      for (var j = 0; j < jointNodeIndices.length; j++) {
        final nodeIdx = jointNodeIndices[j];
        final node = rawNodes[nodeIdx] as Map<String, dynamic>;
        final nodeName = node['name'] as String? ?? 'joint_$j';

        int parentJointIdx = -1;
        var p = parentOfNode[nodeIdx];
        while (p != null) {
          if (nodeToJoint.containsKey(p)) {
            parentJointIdx = nodeToJoint[p]!;
            break;
          }
          p = parentOfNode[p];
        }

        final (t, r, scale) = _extractNodeTRS(node);
        joints.add(
          SkinJointNode(
            nodeIndex: nodeIdx,
            name: nodeName,
            parentJointIndex: parentJointIdx,
            restTranslation: t,
            restRotation: r,
            restScale: scale,
          ),
        );
      }

      final ibmAccessorIdx = skinJson['inverseBindMatrices'] as int?;
      Float32List ibmFloats;
      if (ibmAccessorIdx != null) {
        final rawIbm = readFloatAccessor(ibmAccessorIdx, 16);
        if (rawIbm.length < joints.length * 16) {
          throw FormatException(
            'inverseBindMatrices length mismatch: expected at least ${joints.length * 16}, got ${rawIbm.length}',
          );
        }
        ibmFloats = Float32List.sublistView(rawIbm, 0, joints.length * 16);
      } else {
        ibmFloats = Float32List(joints.length * 16);
        for (var j = 0; j < joints.length; j++) {
          final base = j * 16;
          ibmFloats[base + 0] = 1;
          ibmFloats[base + 5] = 1;
          ibmFloats[base + 10] = 1;
          ibmFloats[base + 15] = 1;
        }
      }

      final skeletonNode = skinJson['skeleton'] as int?;
      final skeletonRootIdx = skeletonNode != null
          ? (nodeToJoint[skeletonNode] ?? 0)
          : 0;

      skins.add(
        SkinData(
          name: name,
          joints: joints,
          inverseBindMatrices: ibmFloats,
          skeletonRootIndex: skeletonRootIdx,
          clampToMaxJoints: true,
        ),
      );
    }

    // Map which mesh indices correspond to which skins from scene nodes
    final meshToSkin = <int, int>{};
    for (var i = 0; i < rawNodes.length; i++) {
      final n = rawNodes[i];
      if (n is! Map<String, dynamic>) continue;
      final meshIdx = n['mesh'] as int?;
      final skinIdx = n['skin'] as int?;
      if (meshIdx != null && skinIdx != null) {
        meshToSkin[meshIdx] = skinIdx;
      }
    }

    // Extract skinned mesh payloads aligned to glb.meshes
    final rawMeshes = jsonMap['meshes'] as List<dynamic>? ?? const [];
    final skinnedMeshes = <SkinnedMeshPayload>[];
    var meshDataIndex = 0;

    for (var m = 0; m < rawMeshes.length; m++) {
      final meshJson = rawMeshes[m] as Map<String, dynamic>;
      final rawPrimitives =
          meshJson['primitives'] as List<dynamic>? ?? const [];
      final skinIdx = meshToSkin[m] ?? 0;

      for (final primJson in rawPrimitives) {
        if (primJson is! Map<String, dynamic>) continue;
        final attrs =
            primJson['attributes'] as Map<String, dynamic>? ?? const {};
        final posAccessorIdx = attrs['POSITION'] as int?;
        if (posAccessorIdx == null) continue;

        if (meshDataIndex >= glb.meshes.length) break;
        final meshData = glb.meshes[meshDataIndex++];

        final jointsAccessorIdx = attrs['JOINTS_0'] as int?;
        final weightsAccessorIdx = attrs['WEIGHTS_0'] as int?;

        if (jointsAccessorIdx != null && weightsAccessorIdx != null) {
          final jointIndices = readJointsAccessor(jointsAccessorIdx);
          final jointWeights = readWeightsAccessor(weightsAccessorIdx);
          skinnedMeshes.add(
            SkinnedMeshPayload(
              meshData: meshData,
              jointIndices: jointIndices,
              jointWeights: jointWeights,
              skinIndex: skinIdx,
            ),
          );
        }
      }
    }

    return GlbSkinDecodeResult(
      glb: glb,
      skins: skins,
      skinnedMeshes: skinnedMeshes,
    );
  }

  static (Vec3, Quat, Vec3) _extractNodeTRS(Map<String, dynamic> nodeJson) {
    var translation = Vec3.zero;
    final t = nodeJson['translation'] as List<dynamic>?;
    if (t != null && t.length >= 3) {
      translation = Vec3(
        (t[0] as num).toDouble(),
        (t[1] as num).toDouble(),
        (t[2] as num).toDouble(),
      );
    }

    var rotation = Quat.identity;
    final r = nodeJson['rotation'] as List<dynamic>?;
    if (r != null && r.length >= 4) {
      rotation = Quat(
        (r[0] as num).toDouble(),
        (r[1] as num).toDouble(),
        (r[2] as num).toDouble(),
        (r[3] as num).toDouble(),
      );
    }

    var scale = const Vec3(1, 1, 1);
    final s = nodeJson['scale'] as List<dynamic>?;
    if (s != null && s.length >= 3) {
      scale = Vec3(
        (s[0] as num).toDouble(),
        (s[1] as num).toDouble(),
        (s[2] as num).toDouble(),
      );
    }

    final matrix = nodeJson['matrix'] as List<dynamic>?;
    if (matrix != null && matrix.length == 16) {
      (translation, rotation, scale) = _decomposeMatrix([
        for (final v in matrix) (v as num).toDouble(),
      ]);
    }

    return (translation, rotation, scale);
  }

  static (Vec3, Quat, Vec3) _decomposeMatrix(List<double> m) {
    final translation = Vec3(m[12], m[13], m[14]);
    var c0 = Vec3(m[0], m[1], m[2]);
    final c1 = Vec3(m[4], m[5], m[6]);
    final c2 = Vec3(m[8], m[9], m[10]);
    var sx = c0.length;
    final sy = c1.length, sz = c2.length;
    if (c0.cross(c1).dot(c2) < 0) {
      sx = -sx;
      c0 = -c0;
    }
    if (sx.abs() < 1e-12 || sy < 1e-12 || sz < 1e-12) {
      return (translation, Quat.identity, const Vec3(1, 1, 1));
    }
    final x = c0 * (1 / sx.abs()), y = c1 * (1 / sy), z = c2 * (1 / sz);
    final trace = x.x + y.y + z.z;
    double qx, qy, qz, qw;
    if (trace > 0) {
      final k = 0.5 / math.sqrt(trace + 1);
      qw = 0.25 / k;
      qx = (y.z - z.y) * k;
      qy = (z.x - x.z) * k;
      qz = (x.y - y.x) * k;
    } else if (x.x > y.y && x.x > z.z) {
      final k = 2 * math.sqrt(1 + x.x - y.y - z.z);
      qw = (y.z - z.y) / k;
      qx = 0.25 * k;
      qy = (y.x + x.y) / k;
      qz = (z.x + x.z) / k;
    } else if (y.y > z.z) {
      final k = 2 * math.sqrt(1 + y.y - x.x - z.z);
      qw = (z.x - x.z) / k;
      qx = (y.x + x.y) / k;
      qy = 0.25 * k;
      qz = (z.y + y.z) / k;
    } else {
      final k = 2 * math.sqrt(1 + z.z - x.x - y.y);
      qw = (x.y - y.x) / k;
      qx = (z.x + x.z) / k;
      qy = (z.y + y.z) / k;
      qz = 0.25 * k;
    }
    return (
      translation,
      Quat(qx, qy, qz, qw).normalized,
      Vec3(sx.abs(), sy, sz),
    );
  }
}
