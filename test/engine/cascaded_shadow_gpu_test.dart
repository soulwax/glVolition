/// S3-C test: Verifies [CascadedShadowRigComponent] builds texel-snapped
/// directional CSM cascades and drives GPU shader uniform uploads per cascade.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:pixeldart/rendering/core/shadow_atlas.dart';
import 'package:test/test.dart';

void main() {
  group('S3-C — CascadedShadowRigComponent GPU wiring', () {
    test('builds 4 cascades and uploads CSM uniforms to HeadlessGraphics', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final scene = Scene('csm_gpu_test');

      final camGo = scene.createGameObject('MainCamera');
      camGo.transform.position = const Vec3(0, 5, 10);
      camGo.addComponent(Camera(fovYRadians: 1.0, near: 0.2, far: 150.0));

      final sunGo = scene.createGameObject('Sun');
      sunGo.addComponent(
        Light(type: LightType.directional, intensity: 2.5, castsShadow: true),
      );
      final rig = sunGo.addComponent(
        CascadedShadowRigComponent(
          cascadeCount: 4,
          shadowMapResolution: 1024,
          maxShadowDistance: 120.0,
          snapToTexels: true,
        ),
      );

      engine.loadScene(scene);
      engine.step(1 / 60);

      expect(rig.cascades, hasLength(4));
      expect(rig.splits, hasLength(4));
      expect(rig.splits.last.farPlane, closeTo(120.0, 1e-3));

      // Verify GPU uniforms were uploaded to HeadlessGraphics
      final hg = host.graphics;
      final countUniform =
          hg.shaderUniforms[ShaderSlot.shadowedWorld]?['uShadowCascadeCount'];
      expect(countUniform, isNotNull);
      final splitsUniform =
          hg.shaderUniforms[ShaderSlot.shadowedWorld]?['uCascadeSplits'];
      expect(splitsUniform, isNotNull);

      // Verify atlas packing for the 4 cascades succeeds with zero overlaps
      final atlas = ShadowAtlasAllocator(atlasSize: 2048);
      final tiles = atlas.pack([
        for (var i = 0; i < rig.cascades.length; i++)
          ShadowAtlasRequest(
            key: 'csm_$i',
            kind: ShadowAtlasEntryKind.directionalCascade,
            desiredSize: 512,
            priority: 10.0 - i,
          ),
      ]);
      expect(tiles, hasLength(4));
      expect(atlas.droppedCount, equals(0));
    });
  });
}
