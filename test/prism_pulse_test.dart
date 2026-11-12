import '../example/prism_pulse/game.dart';
import 'package:gl_volition/gl_volition.dart';
import 'package:test/test.dart';

void main() {
  group('Prism Pulse — pixeldart Renderer Showcase Mini-Game', () {
    test('builds, steps, renders PBR/instanced/water/volumetric/postFX scene & maintains clean ComponentSpec registry', () {
      final host = HeadlessHost();
      final reg = ComponentRegistry.defaults();
      registerPrismPulseSpecs(reg);

      final scene = buildPrismPulseScene();
      final engine = Engine(host, initialScene: scene, registry: reg);

      // Step simulation to bootstrap GPU textures/materials/meshes and ambient fireflies
      engine.step(0.016);
      engine.step(0.016);

      final director = scene.findObjectOfType<PrismArenaDirector>()!;
      final player = scene.findObjectOfType<PulseCraftBehaviour>()!;
      final camera = Camera.of(scene)!;

      expect(director.score, 0);
      expect(director.wave, 1);
      expect(scene.find('AmbientFireflies'), isNotNull);
      expect(scene.find('ColonnadePillars')?.getComponent<InstancedMeshRenderer>()?.instanceCount, 12);
      expect(scene.findObjectsOfType<PrismCoreBehaviour>(), hasLength(3));
      expect(scene.findObjectsOfType<SentinelBehaviour>(), hasLength(2));
      expect(camera.isAttached, isTrue);

      // Move craft along arena -> TrailRenderer accumulates ribbon samples
      host.input.press('KeyD');
      for (var i = 0; i < 20; i++) {
        engine.step(0.03);
        host.input.endFrame();
      }
      host.input.release('KeyD');
      engine.step(0.016);
      host.input.endFrame();
      final trail = player.getComponent<TrailRenderer>()!;
      expect(trail.sampleCount, greaterThan(1));

      // Verify Prism collection raises score & combo
      final prism = scene.findObjectsOfType<PrismCoreBehaviour>().first;
      player.transform.position = prism.transform.position;
      engine.step(0.016);
      expect(director.prismsCollected, 1);
      expect(director.score, greaterThanOrEqualTo(100));
      expect(director.combo, 2);

      // Verify firing PulseBolt hits & shatters Sentinel
      final sentinel = scene.findObjectsOfType<SentinelBehaviour>().first;
      director.firePulseBolt(
        sentinel.transform.position - const Vec3(0, 0, 1.5),
        const Vec3(0, 0, 1),
      );
      for (var i = 0; i < 6; i++) {
        engine.step(0.03);
      }
      expect(director.sentinelsDestroyed, 1);
      expect(director.score, greaterThanOrEqualTo(300));

      // Verify ComponentSpec registry covers all custom components
      final json = scene.toJson(registry: reg);
      final encoded = json['objects'] as List;
      expect(encoded, isNotEmpty);
      expect(reg.specByName('PrismArenaDirector'), isNotNull);
      expect(reg.specByName('PulseCraftBehaviour'), isNotNull);
      expect(reg.specByName('PrismHudController'), isNotNull);
    });

    test('UICanvas HUD buttons cycle PostProcessVolume & AtmosphereVolume presets via ScriptedInput', () {
      final host = HeadlessHost();
      final reg = ComponentRegistry.defaults();
      registerPrismPulseSpecs(reg);
      final engine = Engine(host, initialScene: buildPrismPulseScene(), registry: reg);

      engine.step(0.016);
      final scene = engine.scene;
      final director = scene.findObjectOfType<PrismArenaDirector>()!;
      final atmo = scene.findObjectOfType<AtmosphereVolume>()!;
      final pp = scene.findObjectOfType<PostProcessVolume>()!;

      expect(director.postPreset, PrismPostPreset.cinematic);
      expect(atmo.timeOfDayHours, closeTo(18.2, 0.05));

      // UICanvas designWidth=640, HeadlessGraphics viewportWidth=1280x720 -> click top-right PostFX button
      // Button center in design coords (640x360): x = 640 - 14 - 74 = 552, y = 12 + 13 = 25
      // In HeadlessGraphics (1280x720): pointerX = 552 * 2 = 1104, pointerY = 25 * 2 = 50
      host.input
        ..pointerX = 1104.0
        ..pointerY = 50.0
        ..pointerDown = true
        ..pointerPressed = true;
      engine.step(0.016);
      host.input.endFrame();
      host.input
        ..pointerDown = false
        ..pointerReleased = true;
      engine.step(0.016);
      host.input.endFrame();
      expect(director.postPreset, PrismPostPreset.ps1);
      expect(pp.ditherStrength, closeTo(0.65, 1e-4));

      // Click Sky button (center design y = 44 + 13 = 57 -> viewport y = 114)
      host.input
        ..pointerX = 1104.0
        ..pointerY = 114.0
        ..pointerDown = true
        ..pointerPressed = true;
      engine.step(0.016);
      host.input.endFrame();
      host.input
        ..pointerDown = false
        ..pointerReleased = true;
      engine.step(0.016);
      host.input.endFrame();
      expect(director.skyPresetIndex, 1);
      expect(atmo.timeOfDayHours, closeTo(22.5, 0.05));
    });
  });
}
