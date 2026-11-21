/// S4-B / S4-D test: Verifies [ReflectionProbeComponent] selection, 2-probe
/// blend weights, parallax box-projection math, [ProbeGizmoBuilder], and
/// [PostProcessVolumeComponent] priority stack blending.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S4-B — ReflectionProbe & Box Projection', () {
    test(
      'selects top-2 overlapping probes by importance with normalized weights',
      () {
        final engine = Engine(HeadlessHost());
        final scene = Scene('probes');
        final p1Go = scene.createGameObject('InteriorProbe');
        p1Go.transform.position = Vec3.zero;
        final p1 = p1Go.addComponent(
          ReflectionProbeComponent(
            size: const Vec3(10, 10, 10),
            blendDistance: 2.0,
            importance: 2,
          ),
        );

        final p2Go = scene.createGameObject('ExteriorProbe');
        p2Go.transform.position = const Vec3(6, 0, 0);
        final p2 = p2Go.addComponent(
          ReflectionProbeComponent(
            size: const Vec3(10, 10, 10),
            blendDistance: 2.0,
            importance: 1,
          ),
        );
        engine.loadScene(scene);

        // Inside both boxes at x=3
        final blend = ReflectionProbeBlender.selectForPosition(
          const Vec3(3, 0, 0),
          [p2, p1],
        );
        expect(blend.primary, same(p1));
        expect(blend.secondary, same(p2));
        expect(blend.primaryWeight + blend.secondaryWeight, closeTo(1.0, 1e-6));

        // Outside p1 box at x=6 (within p1's blendDistance of 2.0 -> 0.5)
        expect(p1.weightAt(const Vec3(6, 0, 0)), closeTo(0.5, 1e-6));
        expect(p1.weightAt(const Vec3(8, 0, 0)), equals(0.0));

        // Gizmos emit 12 box + 12 blend lines
        expect(ProbeGizmoBuilder.buildForProbe(p1), hasLength(24));
      },
    );

    test('boxProject computes parallax-corrected direction toward box wall', () {
      final scene = Scene('box_proj');
      final go = scene.createGameObject('RoomProbe');
      go.transform.position = Vec3.zero;
      final probe = go.addComponent(
        ReflectionProbeComponent(
          size: const Vec3(10, 10, 10),
          boxProjection: true,
        ),
      );

      // Standing at (0, -4, 0) reflecting straight along +X hits wall at (5, -4, 0)
      final dir = probe.boxProject(const Vec3(0, -4, 0), const Vec3(1, 0, 0));
      final expected = const Vec3(5, -4, 0).normalized;
      expect(dir.x, closeTo(expected.x, 1e-5));
      expect(dir.y, closeTo(expected.y, 1e-5));
      expect(dir.z, closeTo(expected.z, 1e-5));
    });
  });

  group('S4-D — PostProcessVolumeComponent Stack Blending', () {
    test(
      'blends global + local priority volumes smoothly across blendDistance',
      () {
        final engine = Engine(HeadlessHost());
        final scene = Scene('volumes');
        final globalGo = scene.createGameObject('GlobalVol');
        final globalVol = globalGo.addComponent(
          PostProcessVolumeComponent(
            isGlobal: true,
            priority: 0,
            profile: const PostProcessVolumeProfile(
              bloomIntensity: 0.2,
              exposureEv100: 0.0,
            ),
          ),
        );

        final caveGo = scene.createGameObject('CaveVol');
        caveGo.transform.position = const Vec3(10, 0, 0);
        final caveVol = caveGo.addComponent(
          PostProcessVolumeComponent(
            isGlobal: false,
            priority: 5,
            size: const Vec3(6, 6, 6),
            blendDistance: 2.0,
            profile: const PostProcessVolumeProfile(
              bloomIntensity: 1.0,
              exposureEv100: -2.0,
            ),
          ),
        );
        engine.loadScene(scene);

        // Far outside cave (x=0) -> global only
        final outP = PostProcessVolumeComponent.evaluateStack(Vec3.zero, [
          caveVol,
          globalVol,
        ]);
        expect(outP.bloomIntensity, closeTo(0.2, 1e-6));
        expect(outP.exposureEv100, closeTo(0.0, 1e-6));

        // Halfway through blend zone (x=6 -> 1m outside cave box [7..13]) -> 50% blend
        final midP = PostProcessVolumeComponent.evaluateStack(
          const Vec3(6, 0, 0),
          [caveVol, globalVol],
        );
        expect(midP.bloomIntensity, closeTo(0.6, 1e-6));
        expect(midP.exposureEv100, closeTo(-1.0, 1e-6));

        // Inside cave (x=10) -> full cave override
        final inP = PostProcessVolumeComponent.evaluateStack(
          const Vec3(10, 0, 0),
          [caveVol, globalVol],
        );
        expect(inP.bloomIntensity, closeTo(1.0, 1e-6));
        expect(inP.exposureEv100, closeTo(-2.0, 1e-6));
      },
    );
  });
}
