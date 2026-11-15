library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:test/test.dart';

/// Helper that packs a glTF JSON object and binary payload into a valid GLB container.
Uint8List _buildGlb({
  required Map<String, dynamic> json,
  required Uint8List binary,
}) {
  final jsonString = jsonEncode(json);
  final rawJsonBytes = utf8.encode(jsonString);
  final jsonPad = (4 - (rawJsonBytes.length % 4)) % 4;
  final jsonBytes = Uint8List(rawJsonBytes.length + jsonPad);
  jsonBytes.setRange(0, rawJsonBytes.length, rawJsonBytes);
  for (var i = rawJsonBytes.length; i < jsonBytes.length; i++) {
    jsonBytes[i] = 0x20; // 0x20 space padding per glTF 2.0 spec
  }

  final binPad = (4 - (binary.length % 4)) % 4;
  final binBytes = Uint8List(binary.length + binPad);
  binBytes.setRange(0, binary.length, binary);

  final totalLength = 12 + 8 + jsonBytes.length + 8 + binBytes.length;
  final out = ByteData(totalLength);

  // Header
  out.setUint32(0, 0x46546c67, Endian.little); // 'glTF' magic
  out.setUint32(4, 2, Endian.little); // version 2
  out.setUint32(8, totalLength, Endian.little);

  // Chunk 0: JSON
  var offset = 12;
  out.setUint32(offset, jsonBytes.length, Endian.little);
  out.setUint32(offset + 4, 0x4e4f534a, Endian.little); // 'JSON'
  offset += 8;
  Uint8List.view(
    out.buffer,
  ).setRange(offset, offset + jsonBytes.length, jsonBytes);
  offset += jsonBytes.length;

  // Chunk 1: BIN
  out.setUint32(offset, binBytes.length, Endian.little);
  out.setUint32(offset + 4, 0x004e4942, Endian.little); // 'BIN\0'
  offset += 8;
  Uint8List.view(
    out.buffer,
  ).setRange(offset, offset + binBytes.length, binBytes);

  return Uint8List.view(out.buffer);
}

/// Builds a synthetic skinned GLB binary with 2 joints and a 3-vertex triangle mesh.
Uint8List _buildSampleSkinnedGlb({
  int jointCount = 2,
  bool useU8Joints = false,
  bool useU8Weights = false,
  bool omitIbm = false,
}) {
  // Vertices:
  // v0: (0, 0, 0), normal (0, 0, 1), uv (0, 0), joint 0 (100%)
  // v1: (0, 2, 0), normal (0, 0, 1), uv (0, 1), joint 1 (100%)
  // v2: (1, 1, 0), normal (0, 0, 1), uv (1, 0), joint 0 (50%) + joint 1 (50%)

  final posData = Float32List.fromList([
    0.0,
    0.0,
    0.0,
    0.0,
    2.0,
    0.0,
    1.0,
    1.0,
    0.0,
  ]);
  final normData = Float32List.fromList([
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    1.0,
  ]);
  final uvData = Float32List.fromList([0.0, 0.0, 0.0, 1.0, 1.0, 0.0]);
  final indexData = Uint16List.fromList([0, 1, 2]);

  // Inverse bind matrices:
  // Joint 0: Identity
  // Joint 1: Translation by (0, -2, 0)
  final ibmData = Float32List(jointCount * 16);
  for (var j = 0; j < jointCount; j++) {
    final base = j * 16;
    ibmData[base + 0] = 1.0;
    ibmData[base + 5] = 1.0;
    ibmData[base + 10] = 1.0;
    ibmData[base + 15] = 1.0;
    if (j == 1) {
      ibmData[base + 13] = -2.0; // Ty = -2
    }
  }

  // Pack binary chunks
  final binBuilder = BytesBuilder();

  final posOffset = binBuilder.length;
  binBuilder.add(posData.buffer.asUint8List());

  final normOffset = binBuilder.length;
  binBuilder.add(normData.buffer.asUint8List());

  final uvOffset = binBuilder.length;
  binBuilder.add(uvData.buffer.asUint8List());

  final jointsOffset = binBuilder.length;
  if (useU8Joints) {
    binBuilder.add(Uint8List.fromList([0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0]));
  } else {
    binBuilder.add(
      Uint16List.fromList([
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
      ]).buffer.asUint8List(),
    );
  }

  final weightsOffset = binBuilder.length;
  if (useU8Weights) {
    binBuilder.add(
      Uint8List.fromList([255, 0, 0, 0, 255, 0, 0, 0, 128, 127, 0, 0]),
    );
  } else {
    binBuilder.add(
      Float32List.fromList([
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.5,
        0.5,
        0.0,
        0.0,
      ]).buffer.asUint8List(),
    );
  }

  // Indices aligned to 4 bytes
  while (binBuilder.length % 4 != 0) {
    binBuilder.addByte(0);
  }
  final indexOffset = binBuilder.length;
  binBuilder.add(indexData.buffer.asUint8List());

  while (binBuilder.length % 4 != 0) {
    binBuilder.addByte(0);
  }
  final ibmOffset = binBuilder.length;
  if (!omitIbm) {
    binBuilder.add(ibmData.buffer.asUint8List());
  }

  final binary = binBuilder.toBytes();

  // Build glTF nodes
  final nodes = <Map<String, dynamic>>[
    {
      'name': 'SkinnedMeshNode',
      'mesh': 0,
      'skin': 0,
      'children': [1],
    },
    {
      'name': 'RootJoint',
      'translation': [0.0, 0.0, 0.0],
      'children': [for (var i = 2; i <= jointCount; i++) i],
    },
  ];
  for (var j = 1; j < jointCount; j++) {
    nodes.add({
      'name': 'Joint_$j',
      'translation': [0.0, 2.0, 0.0],
    });
  }

  final accessors = <Map<String, dynamic>>[
    // 0: POSITION
    {
      'bufferView': 0,
      'byteOffset': 0,
      'componentType': 5126,
      'count': 3,
      'type': 'VEC3',
      'min': [0.0, 0.0, 0.0],
      'max': [1.0, 2.0, 0.0],
    },
    // 1: NORMAL
    {
      'bufferView': 1,
      'byteOffset': 0,
      'componentType': 5126,
      'count': 3,
      'type': 'VEC3',
    },
    // 2: TEXCOORD_0
    {
      'bufferView': 2,
      'byteOffset': 0,
      'componentType': 5126,
      'count': 3,
      'type': 'VEC2',
    },
    // 3: JOINTS_0
    {
      'bufferView': 3,
      'byteOffset': 0,
      'componentType': useU8Joints ? 5121 : 5123,
      'count': 3,
      'type': 'VEC4',
    },
    // 4: WEIGHTS_0
    {
      'bufferView': 4,
      'byteOffset': 0,
      'componentType': useU8Weights ? 5121 : 5126,
      'count': 3,
      'type': 'VEC4',
    },
    // 5: indices
    {
      'bufferView': 5,
      'byteOffset': 0,
      'componentType': 5123,
      'count': 3,
      'type': 'SCALAR',
    },
  ];

  if (!omitIbm) {
    accessors.add({
      'bufferView': 6,
      'byteOffset': 0,
      'componentType': 5126,
      'count': jointCount,
      'type': 'MAT4',
    });
  }

  final bufferViews = <Map<String, dynamic>>[
    {'buffer': 0, 'byteOffset': posOffset, 'byteLength': 36},
    {'buffer': 0, 'byteOffset': normOffset, 'byteLength': 36},
    {'buffer': 0, 'byteOffset': uvOffset, 'byteLength': 24},
    {
      'buffer': 0,
      'byteOffset': jointsOffset,
      'byteLength': useU8Joints ? 12 : 24,
    },
    {
      'buffer': 0,
      'byteOffset': weightsOffset,
      'byteLength': useU8Weights ? 12 : 48,
    },
    {'buffer': 0, 'byteOffset': indexOffset, 'byteLength': 6},
  ];

  if (!omitIbm) {
    bufferViews.add({
      'buffer': 0,
      'byteOffset': ibmOffset,
      'byteLength': jointCount * 64,
    });
  }

  final skinDef = <String, dynamic>{
    'name': 'TestSkin',
    'joints': [for (var i = 1; i <= jointCount; i++) i],
    'skeleton': 1,
  };
  if (!omitIbm) {
    skinDef['inverseBindMatrices'] = 6;
  }

  final json = {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': nodes,
    'skins': [skinDef],
    'meshes': [
      {
        'name': 'SkinnedTriangle',
        'primitives': [
          {
            'attributes': {
              'POSITION': 0,
              'NORMAL': 1,
              'TEXCOORD_0': 2,
              'JOINTS_0': 3,
              'WEIGHTS_0': 4,
            },
            'indices': 5,
          },
        ],
      },
    ],
    'accessors': accessors,
    'bufferViews': bufferViews,
    'buffers': [
      {'byteLength': binary.length},
    ],
  };

  return _buildGlb(json: json, binary: binary);
}

void main() {
  group('GlbSkinDecoder GLB binary parsing & error handling', () {
    test(
      'decodes valid GLB with skin, joints, inverseBindMatrices and vertex weights',
      () {
        final glbBytes = _buildSampleSkinnedGlb(jointCount: 2);
        final result = GlbSkinDecoder.decode(glbBytes);

        expect(result.glb.meshes.length, 1);
        expect(result.skins.length, 1);

        final skin = result.skins.first;
        expect(skin.name, 'TestSkin');
        expect(skin.jointCount, 2);
        expect(skin.joints[0].name, 'RootJoint');
        expect(skin.joints[0].parentJointIndex, -1);
        expect(skin.joints[1].name, 'Joint_1');
        expect(skin.joints[1].parentJointIndex, 0);

        // Verify inverseBindMatrices
        final ibm0 = skin.inverseBindMatrixAt(0);
        final ibm1 = skin.inverseBindMatrixAt(1);
        expect(ibm0.at(3, 1), closeTo(0.0, 1e-6));
        expect(ibm1.at(3, 1), closeTo(-2.0, 1e-6));

        // Verify skinned mesh payload
        expect(result.skinnedMeshes.length, 1);
        final payload = result.skinnedMeshes.first;
        expect(payload.skinIndex, 0);
        expect(payload.jointIndices.length, 12);
        expect(payload.jointWeights.length, 12);

        // Vertex 0: joint 0, weight 1.0
        expect(payload.jointIndices[0], 0);
        expect(payload.jointWeights[0], closeTo(1.0, 1e-6));

        // Vertex 1: joint 1, weight 1.0
        expect(payload.jointIndices[4], 1);
        expect(payload.jointWeights[4], closeTo(1.0, 1e-6));

        // Vertex 2: joint 0 (0.5), joint 1 (0.5)
        expect(payload.jointIndices[8], 0);
        expect(payload.jointIndices[9], 1);
        expect(payload.jointWeights[8], closeTo(0.5, 1e-6));
        expect(payload.jointWeights[9], closeTo(0.5, 1e-6));
      },
    );

    test('decodes uint8 JOINTS_0 and normalized uint8 WEIGHTS_0', () {
      final glbBytes = _buildSampleSkinnedGlb(
        jointCount: 2,
        useU8Joints: true,
        useU8Weights: true,
      );
      final result = GlbSkinDecoder.decode(glbBytes);

      expect(result.skinnedMeshes.length, 1);
      final payload = result.skinnedMeshes.first;
      expect(payload.jointIndices[0], 0);
      expect(payload.jointIndices[4], 1);
      expect(payload.jointWeights[0], closeTo(1.0, 1e-4));
      expect(payload.jointWeights[4], closeTo(1.0, 1e-4));
      // Normalized weights sum to 1.0
      final sumV2 = payload.jointWeights[8] + payload.jointWeights[9];
      expect(sumV2, closeTo(1.0, 1e-4));
    });

    test(
      'defaults to identity inverseBindMatrices when omitted in glTF skin',
      () {
        final glbBytes = _buildSampleSkinnedGlb(jointCount: 2, omitIbm: true);
        final result = GlbSkinDecoder.decode(glbBytes);

        expect(result.skins.length, 1);
        final skin = result.skins.first;
        final ibm0 = skin.inverseBindMatrixAt(0);
        final ibm1 = skin.inverseBindMatrixAt(1);

        // Identity matrix has 1 on diagonal, 0 elsewhere
        expect(ibm0.at(0, 0), 1.0);
        expect(ibm0.at(1, 1), 1.0);
        expect(ibm0.at(2, 2), 1.0);
        expect(ibm0.at(3, 3), 1.0);
        expect(ibm1.at(0, 0), 1.0);
        expect(ibm1.at(1, 1), 1.0);
      },
    );

    test('throws FormatException on truncated or malformed GLB headers', () {
      expect(() => GlbSkinDecoder.decode(Uint8List(8)), throwsFormatException);

      final badMagic = Uint8List(24)
        ..buffer.asByteData().setUint32(0, 0x12345678);
      expect(() => GlbSkinDecoder.decode(badMagic), throwsFormatException);

      final badVersion = Uint8List(24)
        ..buffer.asByteData().setUint32(0, 0x46546c67, Endian.little)
        ..buffer.asByteData().setUint32(4, 1, Endian.little);
      expect(() => GlbSkinDecoder.decode(badVersion), throwsFormatException);
    });

    test(
      'throws FormatException on missing JSON chunk or out-of-bounds accessors',
      () {
        // Container with only BIN chunk, no JSON chunk
        final noJson = _buildGlb(json: {}, binary: Uint8List(16));
        // Overwrite chunk type to BIN
        final noJsonData = ByteData.sublistView(noJson);
        noJsonData.setUint32(16, 0x004e4942, Endian.little);
        expect(() => GlbSkinDecoder.decode(noJson), throwsFormatException);

        // GLB with out-of-bounds joint node index
        final oobJson = {
          'asset': {'version': '2.0'},
          'scene': 0,
          'scenes': [
            {
              'nodes': [0],
            },
          ],
          'nodes': [
            {'name': 'Node0'},
          ],
          'skins': [
            {
              'name': 'BadSkin',
              'joints': [999], // OOB
            },
          ],
        };
        final oobGlb = _buildGlb(json: oobJson, binary: Uint8List(0));
        expect(() => GlbSkinDecoder.decode(oobGlb), throwsFormatException);
      },
    );
  });

  group('Reference skinning math & Forward Kinematics (FK) deformation', () {
    test('bind pose skinning palette produces exact identity matrices', () {
      final joints = [
        const SkinJointNode(
          nodeIndex: 0,
          name: 'Shoulder',
          parentJointIndex: -1,
          restTranslation: Vec3.zero,
        ),
        const SkinJointNode(
          nodeIndex: 1,
          name: 'Elbow',
          parentJointIndex: 0,
          restTranslation: Vec3(0, 2, 0),
        ),
        const SkinJointNode(
          nodeIndex: 2,
          name: 'Wrist',
          parentJointIndex: 1,
          restTranslation: Vec3(0, 2, 0),
        ),
      ];

      // Bind pose global matrices:
      // B0 = I
      // B1 = T(0, 2, 0)
      // B2 = T(0, 4, 0)
      // Inverse bind matrices:
      // B0^-1 = I
      // B1^-1 = T(0, -2, 0)
      // B2^-1 = T(0, -4, 0)
      final ibm = Float32List(3 * 16);
      void setMat(int j, Mat4 m) {
        for (var i = 0; i < 16; i++) {
          ibm[j * 16 + i] = m.m[i];
        }
      }

      setMat(0, Mat4.identity());
      setMat(1, Mat4.translation(const Vec3(0, -2, 0)));
      setMat(2, Mat4.translation(const Vec3(0, -4, 0)));

      final skin = SkinData(
        name: 'Arm3',
        joints: joints,
        inverseBindMatrices: ibm,
      );

      final palette = skin.computeSkinPalette();
      expect(palette.length, 3 * 16);

      // In bind pose, P_j = G_j * B_j^-1 = B_j * B_j^-1 = Identity
      for (var j = 0; j < 3; j++) {
        final pMat = Mat4.fromColumnMajor(
          palette.sublist(j * 16, (j + 1) * 16),
        );
        for (var col = 0; col < 4; col++) {
          for (var row = 0; row < 4; row++) {
            final expected = col == row ? 1.0 : 0.0;
            expect(pMat.at(col, row), closeTo(expected, 1e-6));
          }
        }
      }

      // Deforming vertices in bind pose leaves them untouched
      final vElbow = const Vec3(0, 2, 0);
      final p1 = Mat4.fromColumnMajor(palette.sublist(16, 32));
      final deformedElbow = p1.transformPoint(vElbow);
      expect(deformedElbow.x, closeTo(0.0, 1e-6));
      expect(deformedElbow.y, closeTo(2.0, 1e-6));
      expect(deformedElbow.z, closeTo(0.0, 1e-6));
    });

    test(
      'rotating root joint by 90 degrees around Z rotates the entire chain',
      () {
        final joints = [
          const SkinJointNode(
            nodeIndex: 0,
            name: 'Root',
            parentJointIndex: -1,
            restTranslation: Vec3.zero,
          ),
          const SkinJointNode(
            nodeIndex: 1,
            name: 'Arm',
            parentJointIndex: 0,
            restTranslation: Vec3(0, 2, 0),
          ),
        ];

        final ibm = Float32List(2 * 16);
        final m0 = Mat4.identity();
        final m1 = Mat4.translation(const Vec3(0, -2, 0));
        for (var i = 0; i < 16; i++) {
          ibm[i] = m0.m[i];
          ibm[16 + i] = m1.m[i];
        }

        final skin = SkinData(
          name: 'Chain',
          joints: joints,
          inverseBindMatrices: ibm,
        );

        // Rotate Joint 0 by 90 deg around Z: Quat.fromAxisAngle(unitZ, pi/2)
        final halfAngle = math.pi / 4.0;
        final rotZ90 = Quat(0, 0, math.sin(halfAngle), math.cos(halfAngle));

        final palette = skin.computeSkinPalette(
          rotations: [rotZ90, Quat.identity],
        );

        final p0 = Mat4.fromColumnMajor(palette.sublist(0, 16));
        final p1 = Mat4.fromColumnMajor(palette.sublist(16, 32));

        // Reference math:
        // G0 = Rz(90 deg)
        // G1 = G0 * L1 = Rz(90 deg) * T(0, 2, 0)
        // P1 = G1 * B1^-1 = Rz(90 deg) * T(0, 2, 0) * T(0, -2, 0) = Rz(90 deg)
        // Vertex (0, 2, 0) rotated 90 deg about Z moves to (-2, 0, 0)
        final transformed0 = p0.transformPoint(const Vec3(0, 2, 0));
        final transformed1 = p1.transformPoint(const Vec3(0, 2, 0));

        expect(transformed0.x, closeTo(-2.0, 1e-5));
        expect(transformed0.y, closeTo(0.0, 1e-5));
        expect(transformed1.x, closeTo(-2.0, 1e-5));
        expect(transformed1.y, closeTo(0.0, 1e-5));

        // Blended vertex at (0, 1, 0) with 50% joint 0 and 50% joint 1:
        // (0.5 * (-1, 0, 0)) + (0.5 * (-1, 0, 0)) = (-1, 0, 0)
        final blendPoint = const Vec3(0, 1, 0);
        final vDeformed =
            (p0.transformPoint(blendPoint) * 0.5) +
            (p1.transformPoint(blendPoint) * 0.5);
        expect(vDeformed.x, closeTo(-1.0, 1e-5));
        expect(vDeformed.y, closeTo(0.0, 1e-5));
      },
    );

    test(
      'hierarchical two-joint bend Forward Kinematics matches analytical matrices',
      () {
        final joints = [
          const SkinJointNode(
            nodeIndex: 0,
            name: 'Base',
            parentJointIndex: -1,
            restTranslation: Vec3.zero,
          ),
          const SkinJointNode(
            nodeIndex: 1,
            name: 'Forearm',
            parentJointIndex: 0,
            restTranslation: Vec3(0, 2, 0),
          ),
        ];

        final ibm = Float32List(2 * 16);
        for (var i = 0; i < 16; i++) {
          ibm[i] = Mat4.identity().m[i];
          ibm[16 + i] = Mat4.translation(const Vec3(0, -2, 0)).m[i];
        }

        final skin = SkinData(
          name: 'TwoJoint',
          joints: joints,
          inverseBindMatrices: ibm,
        );

        // Rotate Joint 0 by 90 deg around Z, and Joint 1 by another 90 deg around Z
        final q90 = Quat(0, 0, math.sin(math.pi / 4), math.cos(math.pi / 4));
        final palette = skin.computeSkinPalette(rotations: [q90, q90]);

        final p1 = Mat4.fromColumnMajor(palette.sublist(16, 32));

        // A hand tip at (0, 4, 0) in bind pose:
        // In local Joint 1 space: (0, 4, 0) - (0, 2, 0) = (0, 2, 0)
        // Joint 1 rotates local (0, 2, 0) by 90 deg -> (-2, 0, 0) relative to Joint 1
        // Joint 1's position in world space is rotated by Joint 0: (0, 2, 0) rotated by 90 deg -> (-2, 0, 0)
        // In world space, Joint 1's local direction (-2, 0, 0) is further rotated by Joint 0's 90 deg -> (0, -2, 0)
        // Total world position of tip = (-2, 0, 0) + (0, -2, 0) = (-2, -2, 0)!
        final handTipBind = const Vec3(0, 4, 0);
        final handTipDeformed = p1.transformPoint(handTipBind);
        expect(handTipDeformed.x, closeTo(-2.0, 1e-5));
        expect(handTipDeformed.y, closeTo(-2.0, 1e-5));
        expect(handTipDeformed.z, closeTo(0.0, 1e-5));
      },
    );
  });

  group(
    'Animator & SkinnedMeshRenderer HeadlessGraphics uniform & palette integration',
    () {
      test(
        'Animator drives SkinnedMeshRenderer and populates HeadlessGraphics skinningPalettes',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final joints = [
            const SkinJointNode(
              nodeIndex: 0,
              name: 'Root',
              parentJointIndex: -1,
              restTranslation: Vec3.zero,
            ),
            const SkinJointNode(
              nodeIndex: 1,
              name: 'Arm',
              parentJointIndex: 0,
              restTranslation: Vec3(0, 2, 0),
            ),
          ];

          final ibm = Float32List(2 * 16);
          for (var i = 0; i < 16; i++) {
            ibm[i] = Mat4.identity().m[i];
            ibm[16 + i] = Mat4.translation(const Vec3(0, -2, 0)).m[i];
          }

          final skin = SkinData(
            name: 'TestSkin',
            joints: joints,
            inverseBindMatrices: ibm,
          );

          final dummyMesh = host.graphics.createMesh(
            MeshData(
              layout: VertexLayoutDescriptor.surfaceV2,
              vertices: Float32List(18),
              indices: Uint16List(3),
              localBounds: Aabb(Vec3.zero, const Vec3(1, 1, 1)),
            ),
          );

          final go = engine.scene.createGameObject('Hero');
          final smr = go.addComponent(
            SkinnedMeshRenderer(mesh: dummyMesh, skin: skin),
          );

          // Create a SkeletalClip translating Joint 0 from (0, 0, 0) to (4, 0, 0) over 1.0s
          final clip = SkeletalClip(
            name: 'MoveRoot',
            duration: 1.0,
            loopMode: LoopMode.once,
            boneTracks: [
              BoneTrack(
                jointIndex: 0,
                translationKeys: [
                  const Keyframe(0.0, Vec3.zero),
                  const Keyframe(1.0, Vec3(4, 0, 0)),
                ],
              ),
            ],
          );

          final animator = go.addComponent(
            Animator(skin: skin, targetRenderer: smr),
          );
          animator.addSkeletalClip(clip);
          animator.playSkeletal('MoveRoot');

          engine.time.maximumDeltaTime = 10.0;

          // Initialize frame
          engine.step(0.0);

          // Step 0.5s forward (halfway through the animation)
          engine.step(0.5);

          final palette = smr.jointMatrices;
          expect(palette.length, 32);

          // Joint 0 should have translated halfway: Tx = 2.0
          final p0 = Mat4.fromColumnMajor(palette.sublist(0, 16));
          expect(p0.at(3, 0), closeTo(2.0, 1e-4));

          // Sync to renderer
          smr.syncToRenderer(host.graphics);

          final hGfx = host.graphics;
          expect(hGfx.skinningPalettes.containsKey(dummyMesh), isTrue);
          expect(hGfx.skinningJointCounts[dummyMesh], 2);

          final uploaded = hGfx.skinningPalettes[dummyMesh]!;
          expect(uploaded[12], closeTo(2.0, 1e-4)); // column 3 row 0 = Tx

          // Verify shader uniforms for skinning are set
          final safeUniforms = hGfx.shaderUniforms[ShaderSlot.safeWorld]!;
          expect(
            safeUniforms[RenderingShaderContracts.skinEnabledUniform]?.x,
            1.0,
          );
          expect(
            safeUniforms[RenderingShaderContracts.skinJointCountUniform]?.x,
            2.0,
          );
        },
      );

      test(
        'cross-fading smoothly blends bone transforms between two SkeletalClips',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final joints = [
            const SkinJointNode(
              nodeIndex: 0,
              name: 'Bone0',
              parentJointIndex: -1,
              restTranslation: Vec3.zero,
            ),
          ];
          final ibm = Float32List(16)..setRange(0, 16, Mat4.identity().m);
          final skin = SkinData(
            name: 'Single',
            joints: joints,
            inverseBindMatrices: ibm,
          );

          final clipA = SkeletalClip(
            name: 'Idle',
            duration: 1.0,
            boneTracks: [
              BoneTrack(
                jointIndex: 0,
                translationKeys: [
                  const Keyframe(0.0, Vec3.zero),
                  const Keyframe(1.0, Vec3.zero),
                ],
              ),
            ],
          );

          final clipB = SkeletalClip(
            name: 'Run',
            duration: 1.0,
            boneTracks: [
              BoneTrack(
                jointIndex: 0,
                translationKeys: [
                  const Keyframe(0.0, Vec3(10, 0, 0)),
                  const Keyframe(1.0, Vec3(10, 0, 0)),
                ],
              ),
            ],
          );

          final go = engine.scene.createGameObject('BlendTest');
          final smr = go.addComponent(SkinnedMeshRenderer(skin: skin));
          final animator = go.addComponent(
            Animator(skin: skin, targetRenderer: smr),
          );
          animator.addSkeletalClip(clipA);
          animator.addSkeletalClip(clipB);

          engine.time.maximumDeltaTime = 10.0;

          // Start Clip A
          animator.playSkeletal('Idle');
          engine.step(0.016);
          expect(smr.jointMatrices[12], closeTo(0.0, 1e-5));

          // Initiate 1.0s cross-fade to Clip B
          animator.crossFade('Run', 1.0);

          // Advance by 0.5s -> 50% blend
          // Idle has Tx=0, Run has Tx=10 -> blended Tx should be 5.0
          engine.step(0.5);
          expect(smr.jointMatrices[12], closeTo(5.0, 1e-4));

          // Advance by remaining 0.5s -> 100% Clip B (Tx = 10.0)
          engine.step(0.5);
          expect(smr.jointMatrices[12], closeTo(10.0, 1e-4));
        },
      );

      test('clamping enforces RenderingShaderContracts.maxSkinJoints (64)', () {
        final host = HeadlessHost();
        const excessJoints = 70; // > 64

        final joints = List.generate(
          excessJoints,
          (i) => SkinJointNode(
            nodeIndex: i,
            name: 'Joint_$i',
            parentJointIndex: i == 0 ? -1 : 0,
            restTranslation: Vec3(i.toDouble(), 0, 0),
          ),
        );

        final ibm = Float32List(excessJoints * 16);
        for (var i = 0; i < excessJoints; i++) {
          for (var k = 0; k < 16; k++) {
            ibm[i * 16 + k] = Mat4.identity().m[k];
          }
        }

        // SkinData clamps to maxJoints (64)
        final skin = SkinData(
          name: 'ExcessSkin',
          joints: joints,
          inverseBindMatrices: ibm,
          clampToMaxJoints: true,
        );
        expect(skin.jointCount, RenderingShaderContracts.maxSkinJoints);
        expect(
          skin.inverseBindMatrices.length,
          RenderingShaderContracts.maxSkinJoints * 16,
        );

        final dummyMesh = host.graphics.createMesh(
          MeshData(
            layout: VertexLayoutDescriptor.surfaceV2,
            vertices: Float32List(18),
            indices: Uint16List(3),
            localBounds: Aabb(Vec3.zero, const Vec3(1, 1, 1)),
          ),
        );

        final smr = SkinnedMeshRenderer(mesh: dummyMesh, skin: skin);
        smr.applySkinPalette(host.graphics);

        final hGfx = host.graphics;
        expect(
          hGfx.skinningJointCounts[dummyMesh],
          RenderingShaderContracts.maxSkinJoints,
        );
        expect(
          hGfx.skinningPalettes[dummyMesh]!.length,
          RenderingShaderContracts.maxSkinJoints * 16,
        );
      });

      test(
        'SkinnedMeshRenderer cleanly manages child SceneNode lifecycle and dispose',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final dummyMesh = host.graphics.createMesh(
            MeshData(
              layout: VertexLayoutDescriptor.surfaceV2,
              vertices: Float32List(18),
              indices: Uint16List(3),
              localBounds: Aabb(Vec3.zero, const Vec3(1, 1, 1)),
            ),
          );

          final go = engine.scene.createGameObject('Entity');
          final smr = go.addComponent(SkinnedMeshRenderer(mesh: dummyMesh));

          // Initial step activates components
          engine.step(0.016);

          // Enabled component should attach leaf node to gameObject.node
          expect(go.node.children.length, 1);
          expect(go.node.children.first.name, 'Entity#skinned');

          // Disabling GameObject detaches the leaf
          go.setActive(false);
          expect(go.node.children.isEmpty, isTrue);

          // Re-enabling re-attaches
          go.setActive(true);
          expect(go.node.children.length, 1);

          // dispose removes leaf
          smr.dispose();
          expect(go.node.children.isEmpty, isTrue);
        },
      );
    },
  );
}
