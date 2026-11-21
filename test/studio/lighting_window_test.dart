/// S3-E test: Verifies Studio Lighting window, Quality tier live switching,
/// Light gizmos (directional, point, spot, CSM cascade splits), and physical
/// light unit helpers (lux/lumens/Kelvin).
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:pixeldart/rendering/passes/exposure.dart';
import 'package:test/test.dart';

void main() {
  group('S3-E — Studio Lighting Window, Quality Tier & Light Gizmos', () {
    test(
      'LightingWindowModel edits exposure, tonemapper & ambient with notifications',
      () {
        final model = LightingWindowModel();
        var notifications = 0;
        model.addListener((_) => notifications++);

        model.setExposure(
          manualEv100: 2.5,
          autoExposureEnabled: true,
          tonemapper: VrpTonemapper.agx,
          bloomThreshold: 1.25,
        );
        model.setAmbient(const LinearColor(0.2, 0.3, 0.4), 0.75);

        expect(notifications, equals(2));
        expect(model.exposureSettings.manualEv100, equals(2.5));
        expect(model.exposureSettings.autoExposureEnabled, isTrue);
        expect(model.exposureSettings.tonemapper, equals(VrpTonemapper.agx));
        expect(model.ambientIntensity, equals(0.75));
        expect(
          (model.toJson()['exposure'] as Map)['tonemapper'],
          equals('agx'),
        );
      },
    );

    test(
      'QualityWindowModel switches VrpQualityTier live and notifies viewports',
      () {
        final quality = QualityWindowModel(initialTier: VrpQualityTier.low);
        final receivedTiers = <VrpQualityTier>[];
        quality.addListener((s) => receivedTiers.add(s.tier));

        expect(quality.activeSettings.hdrEnabled, isFalse);
        final ultra = quality.selectTier(VrpQualityTier.ultra);
        expect(ultra.hdrEnabled, isTrue);
        expect(ultra.shadowCascadeCount, equals(4));
        expect(ultra.maxVisibleLights, greaterThanOrEqualTo(512));
        expect(receivedTiers, equals([VrpQualityTier.ultra]));

        final overridden = quality.applyOverrides(
          msaaSamples: 8,
          renderScale: 1.25,
        );
        expect(overridden.msaaSamples, equals(8));
        expect(overridden.renderScale, equals(1.25));
      },
    );

    test('LightUnitHelper converts lux, lumens and Kelvin temperature', () {
      expect(LightUnitHelper.luxToIntensity(100000), closeTo(10.0, 1e-6));
      expect(
        LightUnitHelper.lumensToPointIntensity(1256.637),
        closeTo(1.0, 1e-2),
      );
      expect(
        LightUnitHelper.lumensToSpotIntensity(800.0, 0.5),
        greaterThan(LightUnitHelper.lumensToPointIntensity(800.0)),
      );
      final warm = LightUnitHelper.kelvinToLinearRgb(2700);
      final cool = LightUnitHelper.kelvinToLinearRgb(10000);
      expect(warm.r, greaterThan(warm.b));
      expect(cool.b, greaterThan(cool.r));
    });

    test(
      'LightGizmoBuilder emits lines for directional, point, spot & CSM splits',
      () {
        final scene = Scene('gizmos');
        final dirGo = scene.createGameObject('Sun');
        final dirL = dirGo.addComponent(Light(type: LightType.directional));
        final ptGo = scene.createGameObject('Lamp');
        final ptL = ptGo.addComponent(Light(type: LightType.point, range: 6.0));
        final spGo = scene.createGameObject('Flashlight');
        final spL = spGo.addComponent(
          Light(type: LightType.spot, range: 12.0, spotAngle: 0.5),
        );

        expect(LightGizmoBuilder.buildForLight(dirL), hasLength(5));
        expect(
          LightGizmoBuilder.buildForLight(ptL, circleSegments: 12),
          hasLength(36),
        );
        expect(
          LightGizmoBuilder.buildForLight(spL, circleSegments: 12),
          hasLength(16),
        );

        final splitLines = LightGizmoBuilder.buildCascadeSplitOverlay(
          cameraPos: Vec3.zero,
          cameraForward: const Vec3(0, 0, -1),
          splitDistances: const [8.0, 24.0, 60.0, 120.0],
          segments: 12,
        );
        expect(splitLines, hasLength(48));
      },
    );
  });
}
