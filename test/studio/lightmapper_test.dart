/// S4-C test: Verifies UV2 chart packing (zero overlaps), deterministic
/// seeded Cornell-box progressive lightmap baking, A-trous denoising, and
/// gutter dilation.
library;

import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S4-C — Progressive Lightmapper & UV2 Atlas Packer', () {
    test(
      'UvAtlasPacker packs charts with zero overlap and valid UV scale/offset',
      () {
        final charts = [
          for (var i = 0; i < 12; i++)
            UvChart(
              id: 'mesh_$i',
              width: 32 + (i % 3) * 16,
              height: 32 + (i % 2) * 16,
            ),
        ];
        final packed = UvAtlasPacker.pack(charts, atlasSize: 256, padding: 2);
        expect(packed, hasLength(12));
        for (var i = 0; i < packed.length; i++) {
          final a = packed[i];
          expect(a.x + a.width, lessThanOrEqualTo(256));
          expect(a.y + a.height, lessThanOrEqualTo(256));
          expect(a.scaleU, greaterThan(0));
          expect(a.scaleV, greaterThan(0));
          for (var j = i + 1; j < packed.length; j++) {
            expect(a.overlaps(packed[j]), isFalse);
          }
        }
      },
    );

    test(
      'Cornell-box progressive bake is deterministic across identical seeds and denoises cleanly',
      () {
        const floor = BakeQuad(
          center: Vec3(0, 0, 0),
          normal: Vec3(0, 1, 0),
          tangentU: Vec3(1, 0, 0),
          tangentV: Vec3(0, 0, 1),
          halfWidth: 2.0,
          halfHeight: 2.0,
          albedo: Vec3(0.8, 0.8, 0.8),
        );
        const ceilingLight = BakeQuad(
          center: Vec3(0, 3, 0),
          normal: Vec3(0, -1, 0),
          tangentU: Vec3(1, 0, 0),
          tangentV: Vec3(0, 0, 1),
          halfWidth: 0.8,
          halfHeight: 0.8,
          albedo: Vec3(1, 1, 1),
          emission: Vec3(12, 11, 10),
        );
        const redWall = BakeQuad(
          center: Vec3(-2, 1.5, 0),
          normal: Vec3(1, 0, 0),
          tangentU: Vec3(0, 0, 1),
          tangentV: Vec3(0, 1, 0),
          halfWidth: 2.0,
          halfHeight: 1.5,
          albedo: Vec3(0.85, 0.15, 0.12),
        );

        final bakerA = ProgressiveLightmapper(
          width: 16,
          height: 16,
          seed: 2026,
        );
        final bakerB = ProgressiveLightmapper(
          width: 16,
          height: 16,
          seed: 2026,
        );

        for (var p = 0; p < 4; p++) {
          bakerA.stepPass(
            receiver: floor,
            emitters: const [ceilingLight],
            bounceSurfaces: const [redWall],
          );
          bakerB.stepPass(
            receiver: floor,
            emitters: const [ceilingLight],
            bounceSurfaces: const [redWall],
          );
        }

        final imgA = bakerA.resolve();
        final imgB = bakerB.resolve();
        expect(imgA, equals(imgB));

        // Center of floor directly under ceiling light should be brighter than corner
        final centerIdx = (8 * 16 + 8) * 3;
        final cornerIdx = (0 * 16 + 0) * 3;
        expect(imgA[centerIdx], greaterThan(imgA[cornerIdx]));

        // Denoise and dilate gutter preserve finite positive values
        final denoised = ProgressiveLightmapper.denoiseAtrous(imgA, 16, 16);
        expect(denoised[centerIdx], greaterThan(0.0));

        final mask = Uint8List(16 * 16)..fillRange(0, 16 * 16, 1);
        mask[0] = 0;
        denoised[0] = 0.0;
        final dilated = ProgressiveLightmapper.dilateGutter(
          denoised,
          mask,
          16,
          16,
        );
        expect(dilated[0], greaterThan(0.0));
      },
    );
  });
}
