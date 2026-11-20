/// S1-B test: Verifies 256-joint capacity in RenderingShaderContracts,
/// SkinData, Animator, and SkinnedMeshRenderer against a 200-joint CPU
/// reference within 1e-4.
library;

import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('S1-B — 256-Joint Skinning Capacity & 200-Joint CPU Reference', () {
    test('evaluates a 200-joint articulated chain within 1e-4 of CPU reference', () {
      expect(RenderingShaderContracts.maxSkinJoints, equals(256));
      expect(SkinData.maxJoints, equals(256));

      const jointCount = 200;
      final joints = <SkinJointNode>[];
      final invBind = Float32List(jointCount * 16);
      final identity = Mat4.identity();

      // Build a 200-joint chain where each joint translates +0.5 along X from its parent
      for (var i = 0; i < jointCount; i++) {
        joints.add(
          SkinJointNode(
            nodeIndex: i,
            name: 'Joint_$i',
            parentJointIndex: i == 0 ? -1 : i - 1,
            restTranslation: Vec3(i == 0 ? 0.0 : 0.5, 0.0, 0.0),
          ),
        );
        // Identity inverse bind matrices so final palette matrix == world joint matrix
        for (var k = 0; k < 16; k++) {
          invBind[i * 16 + k] = identity.m[k];
        }
      }

      final skin = SkinData(
        name: 'Chain200',
        joints: joints,
        inverseBindMatrices: invBind,
      );
      expect(skin.jointCount, equals(jointCount));

      // Animate joint 199 with an extra +2.0 Y translation at t = 0.5
      final clip = SkeletalClip(
        name: 'LiftTip',
        duration: 1.0,
        boneTracks: [
          BoneTrack(
            jointIndex: jointCount - 1,
            translationKeys: const [
              Keyframe(0.0, Vec3(0.5, 0.0, 0.0)),
              Keyframe(1.0, Vec3(0.5, 4.0, 0.0)),
            ],
          ),
        ],
      );

      final engine = Engine(HeadlessHost());
      final go = engine.scene.createGameObject('Worm200');
      final skinned = go.addComponent(
        SkinnedMeshRenderer(
          mesh: const MeshHandle(1, 0, 'worm'),
          material: const MaterialHandle(1, 0, 'mat'),
          skin: skin,
        ),
      );
      final animator = go.addComponent(
        Animator(skin: skin, initialSkeletalClips: [clip]),
      );
      animator.play('LiftTip');
      for (var i = 0; i < 5; i++) {
        engine.step(0.1);
      }

      final palette = skinned.jointMatrices;
      expect(palette.length, equals(jointCount * 16));

      // Verify every single joint's translation matches the exact CPU reference within 1e-4
      for (var i = 0; i < jointCount; i++) {
        final expectedX = i * 0.5;
        final expectedY = (i == jointCount - 1) ? 2.0 : 0.0;
        final actualX = palette[i * 16 + 12];
        final actualY = palette[i * 16 + 13];
        final actualZ = palette[i * 16 + 14];
        expect(actualX, closeTo(expectedX, 1e-4));
        expect(actualY, closeTo(expectedY, 1e-4));
        expect(actualZ, closeTo(0.0, 1e-4));
      }
    });
  });
}
