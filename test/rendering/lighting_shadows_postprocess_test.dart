/// Lighting, 2D visibility/FOW, shadows, cascades, GI probes, post-processing & shaders.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('E8 — PostProcessVolume Spatial Blending', () {
    test(
      'PostProcessVolume blends spatial exposure, bloom, and vignette by camera distance',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final camGo = engine.scene.createGameObject(
          'MainCam',
          position: const Vec3(0, 0, 20),
          components: [Camera()],
        );
        engine.scene.createGameObject(
          'BossZoneVolume',
          position: Vec3.zero,
          components: [
            PostProcessVolume(
              isGlobal: false,
              radius: 5.0,
              blendDistance: 5.0,
              exposure: 2.0,
              bloomStrength: 0.8,
              vignette: 0.6,
            ),
          ],
        );

        // Outside radius + blendDistance (dist = 20 > 10): weight = 0
        engine.scene.renderSettings.post = const PostProcessState(
          exposure: 1.0,
          bloomStrength: 0.0,
          vignette: 0.0,
        );
        engine.step(0.016);
        expect(engine.scene.renderSettings.post.exposure, closeTo(1.0, 1e-5));

        // Halfway through feather band (dist = 7.5, radius = 5, blend = 5 -> weight = 0.5)
        camGo.transform.localPosition = const Vec3(0, 0, 7.5);
        engine.scene.renderSettings.post = const PostProcessState(
          exposure: 1.0,
          bloomStrength: 0.0,
          vignette: 0.0,
        );
        engine.step(0.016);
        expect(engine.scene.renderSettings.post.exposure, closeTo(1.5, 1e-5));
        expect(
          engine.scene.renderSettings.post.bloomStrength,
          closeTo(0.4, 1e-5),
        );
        expect(engine.scene.renderSettings.post.vignette, closeTo(0.3, 1e-5));

        // Inside core radius (dist = 2 <= 5 -> weight = 1.0)
        camGo.transform.localPosition = const Vec3(0, 0, 2.0);
        engine.scene.renderSettings.post = const PostProcessState(
          exposure: 1.0,
          bloomStrength: 0.0,
          vignette: 0.0,
        );
        engine.step(0.016);
        expect(engine.scene.renderSettings.post.exposure, closeTo(2.0, 1e-5));
        expect(
          engine.scene.renderSettings.post.bloomStrength,
          closeTo(0.8, 1e-5),
        );
        expect(engine.scene.renderSettings.post.vignette, closeTo(0.6, 1e-5));
      },
    );
  });

  group('E13 — VolumetricLightSource & ThermalSourceComponent', () {
    test(
      'VolumetricLightSource and ThermalSourceComponent populate FrameEnvironment and sampleThermalDissolution',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        engine.scene.createGameObject(
          'Cam',
          position: const Vec3(0, 2, 6),
          components: [Camera()],
        );
        engine.scene.createGameObject(
          'Brazier',
          position: const Vec3(2, 0, 0),
          components: [
            VolumetricLightSource(
              color: const LinearColor(1.0, 0.6, 0.2),
              luminousIntensity: 4.0,
            ),
            ThermalSourceComponent(radiusMeters: 3.0, dissolution01: 1.0),
          ],
        );

        engine.step(0.016);
        expect(host.graphics.environment.volumetricSources.length, 1);
        expect(host.graphics.environment.thermalSources.length, 1);

        // Inside radius (distance = 1 <= 3.0) -> dissolution == 1.0
        expect(
          engine.scene.sampleThermalDissolution(const Vec3(3, 0, 0)),
          closeTo(1.0, 1e-4),
        );
        // At distance = 6.0 (2x radius) -> dissolution == 0.5
        expect(
          engine.scene.sampleThermalDissolution(const Vec3(8, 0, 0)),
          closeTo(0.5, 1e-4),
        );
      },
    );
  });

  group('E20 — MeshRenderer Tint & Material Overrides', () {
    test('MeshRenderer tintColor and materialOverride dynamic updates', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final meshHandle = host.graphics.createMesh(Primitives.cube());
      final renderer = MeshRenderer(
        mesh: meshHandle,
        tintColor: const LinearColor(1.0, 0.5, 0.2),
      );

      final obj = engine.scene.createGameObject(
        'TintedBox',
        components: [renderer],
      );
      engine.step(0.016);
      expect(obj.activeInHierarchy, isTrue);

      expect(renderer.tintColor, isNotNull);
      expect(renderer.material, isNotNull);

      // Dynamically change tint
      renderer.setTint(const LinearColor(0.1, 0.9, 0.3));
      expect(renderer.tintColor?.g, closeTo(0.9, 1e-4));
      expect(renderer.material, isNotNull);

      // Set material override
      renderer.materialOverride = const MaterialDefinition(
        key: 'custom_override',
        tintR: 0.0,
        tintG: 0.0,
        tintB: 1.0,
      );
      expect(renderer.materialOverride?.key, 'custom_override');
      expect(renderer.material, isNotNull);
    });
  });

  group('E22 — Stylized PostProcess Presets', () {
    test(
      'PostProcessVolume retro and cinematic presets configure stylized effects',
      () {
        final retro = PostProcessVolume.retro(
          weight: 0.8,
          grain: 0.5,
          vignette: 0.4,
          dither: 0.6,
          chromaticAberration: 0.35,
        );

        expect(retro.grain, 0.5);
        expect(retro.vignette, 0.4);
        expect(retro.ditherStrength, 0.6);
        expect(retro.chromaticAberration, 0.35);

        var state = const PostProcessState();
        state = retro.blendOnto(state, 1.0);
        expect(state.grain, closeTo(0.5, 1e-4));
        expect(state.vignette, closeTo(0.4, 1e-4));
        expect(state.ditherStrength, closeTo(0.6, 1e-4));
        expect(state.vhsChromaWeight, closeTo(0.35, 1e-4));

        final cine = PostProcessVolume.cinematic(
          weight: 1.0,
          exposure: 1.2,
          bloomStrength: 0.5,
          ssaoStrength: 0.7,
        );
        expect(cine.toneMapping, ToneMappingMode.aces);
        expect(cine.bloomStrength, 0.5);

        final cineState = cine.blendOnto(const PostProcessState(), 1.0);
        expect(cineState.exposure, closeTo(1.2, 1e-4));
        expect(cineState.bloomStrength, closeTo(0.5, 1e-4));
        expect(cineState.ssaoStrength, closeTo(0.7, 1e-4));
        expect(cineState.toneMapping, ToneMappingMode.aces);
      },
    );
  });

  group('E26 — LinearColor Extensions', () {
    test(
      'LinearColor extensions lerp, convert to HSV/hex, and parse hex/hsv formats',
      () {
        final red = const LinearColor(1, 0, 0);
        final blue = const LinearColor(0, 0, 1);

        // lerp
        final purple = red.lerp(blue, 0.5);
        expect(purple.r, closeTo(0.5, 1e-4));
        expect(purple.g, closeTo(0.0, 1e-4));
        expect(purple.b, closeTo(0.5, 1e-4));

        // withIntensity
        final brightRed = red.withIntensity(2.0);
        expect(brightRed.r, closeTo(2.0, 1e-4));

        // toRgba & toHex
        expect(red.toHex(), '#FF0000');
        expect(red.toRgba(1.0), 0xFF0000FF);

        // toHsv
        final hsvRed = red.toHsv();
        expect(hsvRed.h, closeTo(0.0, 1e-3));
        expect(hsvRed.s, closeTo(1.0, 1e-3));
        expect(hsvRed.v, closeTo(1.0, 1e-3));

        final green = const LinearColor(0, 1, 0);
        final hsvGreen = green.toHsv();
        expect(hsvGreen.h, closeTo(120.0, 1e-3));

        // linearColorFromHex & linearColorFromHsv
        final parsed = linearColorFromHex('#00FF00');
        expect(parsed.r, closeTo(0.0, 1e-3));
        expect(parsed.g, closeTo(1.0, 1e-3));
        expect(parsed.b, closeTo(0.0, 1e-3));

        final hsvBlue = linearColorFromHsv(240.0, 1.0, 1.0);
        expect(hsvBlue.r, closeTo(0.0, 1e-3));
        expect(hsvBlue.g, closeTo(0.0, 1e-3));
        expect(hsvBlue.b, closeTo(1.0, 1e-3));
      },
    );
  });

  group('E35 — 2D Lighting, VisibilityPolygon & Fog of War', () {
    test(
      'E35: Light2DComponent and ShadowCaster2DComponent evaluate 2D lighting with shadow occlusion',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final lightGo = engine.scene.createGameObject(
          'Torch',
          position: const Vec3(0.0, 0.0, 0.0),
        );
        lightGo.addComponent(
          Light2DComponent(
            type: Light2DType.point,
            radius: 10.0,
            intensity: 2.0,
            color: const LinearColor(1.0, 0.5, 0.0),
          ),
        );

        // Wall at y = 4 with shadow caster
        final wallGo = engine.scene.createGameObject(
          'Wall',
          position: const Vec3(0.0, 4.0, 0.0),
        );
        wallGo.addComponent(ShadowCaster2DComponent.box(const Vec2(2.0, 0.5)));

        engine.step(0.05);

        // Point before wall is brightly illuminated
        final beforeWall = engine.scene.evaluateLight2D(const Vec2(0.0, 2.0));
        expect(beforeWall.intensity, greaterThan(1.0));
        expect(beforeWall.r, greaterThan(beforeWall.g));

        // Point behind wall is occluded in shadow
        final behindWall = engine.scene.evaluateLight2D(const Vec2(0.0, 7.0));
        expect(behindWall.intensity, equals(0.0));
      },
    );

    test('E35: Light2DComponent calculates 2D VisibilityPolygon', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final lightGo = engine.scene.createGameObject(
        'PlayerLight',
        position: const Vec3(0.0, 0.0, 0.0),
      );
      final lightComp = lightGo.addComponent(Light2DComponent(radius: 15.0));

      // Wall occluder
      final wall = engine.scene.createGameObject(
        'Pillar',
        position: const Vec3(0.0, 5.0, 0.0),
      );
      wall.addComponent(ShadowCaster2DComponent.box(const Vec2(1.5, 0.5)));

      engine.step(0.05);

      final poly = lightComp.computeVisibilityPolygon();
      expect(poly.vertices.length, greaterThanOrEqualTo(8));

      // Free space in front of pillar is visible
      expect(poly.contains(const LightVec2(0.0, 2.5)), isTrue);
      // Behind pillar is occluded
      expect(poly.contains(const LightVec2(0.0, 8.0)), isFalse);
    });

    test(
      'E35: FogOfWar2DComponent reveals area and blocks exploration behind shadows',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final fogGo = engine.scene.createGameObject('FogManager');
        final fogComp = fogGo.addComponent(
          FogOfWar2DComponent(
            width: 30,
            height: 30,
            cellSize: 1.0,
            origin: const Vec2(-15.0, -15.0),
          ),
        );

        // Wall occluder at y = 3
        final wall = engine.scene.createGameObject(
          'WallOccluder',
          position: const Vec3(0.0, 3.0, 0.0),
        );
        wall.addComponent(ShadowCaster2DComponent.box(const Vec2(3.0, 0.5)));

        engine.step(0.05);

        // Reveal from origin with radius 8
        fogComp.reveal(Vec2.zero, 8.0);

        // Area in front of wall is visible and explored
        expect(fogComp.isVisible(const Vec2(0.0, 1.5)), isTrue);
        expect(fogComp.isExplored(const Vec2(0.0, 1.5)), isTrue);

        // Area behind wall is blocked by occluder
        expect(fogComp.isVisible(const Vec2(0.0, 5.0)), isFalse);
      },
    );
  });

  group('E68 — Light Probe GI Volume & SH3 Irradiance (voxprobe)', () {
    test(
      'LightProbeVolumeComponent syncs DayNight sky, bakes scene lights, samples SH27 & renders ProbeGiInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        // Sky gradient source at noon
        scene.createGameObject(
          'SkyCtrl',
          components: [DayNightSkyComponent(initialHours: 12.0, paused: true)],
        );

        // Warm point light inside the baked volume
        scene.createGameObject(
          'LanternLight',
          position: const Vec3(2.0, 2.5, 0.0),
          components: [
            Light.point(
              color: const LinearColor(1.0, 0.65, 0.25),
              intensity: 4.0,
              range: 10.0,
            ),
          ],
        );

        // Solid pillar collider to test probe interior-wall occlusion filtering
        scene.createGameObject(
          'StonePillar',
          position: const Vec3(-4.0, 0.0, -4.0),
          components: [
            BoxCollider(size: const Vec3(2.0, 8.0, 2.0), isTrigger: false),
          ],
        );

        final giGo = scene.createGameObject('GiVolume');
        final gi = giGo.addComponent(
          LightProbeVolumeComponent(
            minCorner: const Vec3(-4.0, 0.0, -4.0),
            maxCorner: const Vec3(4.0, 4.0, 4.0),
            nx: 3,
            ny: 3,
            nz: 3,
            checkColliderOcclusion: true,
          ),
        );

        engine.step(0.05);
        gi.bakeFromScene();

        expect(gi.totalProbeCount, 27);
        expect(gi.occludedProbeCount, greaterThan(0));
        expect(gi.bakeGeneration, 1);

        final nearLantern = gi.sampleIrradiance(
          const Vec3(1.2, 2.0, 0.0),
          const Vec3(1.0, 0.0, 0.0),
        );
        final awayFromLantern = gi.sampleIrradiance(
          const Vec3(-2.5, 2.0, 2.0),
          const Vec3(-1.0, 0.0, 0.0),
        );
        expect(nearLantern.r, greaterThan(awayFromLantern.r * 1.3));

        final sh27 = gi.sampleUniformSH27(const Vec3(1.2, 2.0, 0.0));
        expect(sh27.length, 27);
        expect(sh27[0], greaterThan(0.1));

        // Test ProbeGiInspectorUI buttons: 'Clear' (x=238), 'Sync Sky' (x=155), 'Bake GI' (x=68), y=156
        final ui = VoxUiContext();
        final uiState = ProbeGiInspectorUiState();
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: 238.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        ProbeGiInspectorUI.render(ui, gi, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 238.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        ProbeGiInspectorUI.render(ui, gi, state: uiState);
        ui.endFrame();
        expect(
          gi.sampleIrradiance(const Vec3(1.2, 2.0, 0.0), Vec3.unitY).r,
          closeTo(0.0, 1e-6),
        );

        ui.beginFrame(
          VoxInput(
            mouseX: 68.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        ProbeGiInspectorUI.render(ui, gi, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 68.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        ProbeGiInspectorUI.render(ui, gi, state: uiState);
        ui.endFrame();

        ui.beginFrame(VoxInput());
        ProbeGiInspectorUI.render(ui, gi, state: uiState);
        final drawList = ui.endFrame();

        expect(gi.bakeGeneration, 2);
        expect(
          gi
              .sampleIrradiance(
                const Vec3(1.2, 2.0, 0.0),
                const Vec3(1.0, 0.0, 0.0),
              )
              .r,
          greaterThan(0.5),
        );
        expect(drawList.commands.any((c) => c.text == '#2'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('LightProbeVolumeComponent'), isNotNull);
        final json = reg.specFor(gi)!.toJson(gi);
        expect(json['nx'], 3);
        expect(json['checkColliderOcclusion'], isTrue);
      },
    );
  });

  group(
    'E85 — Cascaded Shadow Splits, Texel Snapping & PCSS Kernels (voxshadow)',
    () {
      test(
        'CascadedShadowRigComponent builds practical splits, texel-snapped ortho bounds & drives ShadowCascadeInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final camGo = engine.scene.createGameObject(
            'MainCam',
            position: const Vec3(0.0, 6.0, 12.0),
          );
          final cam = camGo.addComponent(Camera(near: 0.5, far: 150.0));

          final sunGo = engine.scene.createGameObject('SunLight');
          sunGo.transform.lookAt(const Vec3(1.0, -2.0, -1.0));
          final sun = sunGo.addComponent(Light.directional());

          final rigGo = engine.scene.createGameObject('ShadowRig');
          final rig = rigGo.addComponent(
            CascadedShadowRigComponent(
              cascadeCount: 4,
              shadowMapResolution: 512,
              splitLambda: 0.65,
              maxShadowDistance: 100.0,
              snapToTexels: true,
              targetCamera: cam,
              targetLight: sun,
            ),
          );

          engine.step(0.016);
          expect(rig.splits.length, 4);
          expect(rig.cascades.length, 4);
          expect(rig.pcssKernel.taps.length, 16);
          final prevMinX = rig.cascades.first.minX;

          // Tiny sub-texel camera pan keeps snapped cascade-0 bounds locked cleanly
          camGo.transform.position = Vec3(
            rig.cascades.first.texelWorldSize * 0.1,
            6.0,
            12.0,
          );
          engine.step(0.016);
          expect(rig.cascades.first.minX, closeTo(prevMinX, 1e-6));

          // Test ShadowCascadeInspectorUI: click Cascades +1 (x=160, y=159)
          final ui = VoxUiContext();
          final uiState = ShadowCascadeInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 160.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          ShadowCascadeInspectorUI.render(ui, rig, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 160.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          ShadowCascadeInspectorUI.render(ui, rig, state: uiState);
          final dl = ui.endFrame();

          expect(rig.cascadeCount, 5);
          expect(rig.cascades.length, 5);
          expect(dl.commands.any((c) => c.text == 'Shadow Cascades'), isTrue);

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('CascadedShadowRigComponent'), isNotNull);
          final json = reg.specFor(rig)!.toJson(rig);
          expect(json['cascadeCount'], 5);
          expect(json['snapToTexels'], isTrue);
        },
      );
    },
  );

  group('E96 — ShaderOverrideComponent', () {
    test(
      'ShaderOverrideComponent builds validated ShaderOverride presets, responds to ShaderOverrideInspectorUI & serializes',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final go = engine.scene.createGameObject('PostShader');
        final so = go.addComponent(
          ShaderOverrideComponent(
            shaderKey: 'vignette_boost',
            targetSlot: ShaderSlot.present,
            isPostEffect: true,
            intensity: 1.2,
          ),
        );

        engine.step(0.016);
        expect(so.isValid, isTrue);
        expect(so.cachedOverride, isNotNull);
        expect(so.uniformValues()['u_intensity'], closeTo(1.2, 1e-6));

        // Click Int +0.1 at (248.0, 159.0) -> bumps intensity to 1.3
        final ui = VoxUiContext();
        final uiState = ShaderOverrideInspectorUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 248.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        ShaderOverrideInspectorUI.render(ui, so, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 248.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        ShaderOverrideInspectorUI.render(ui, so, state: uiState);
        final dl = ui.endFrame();
        expect(so.intensity, closeTo(1.3, 1e-5));
        expect(dl.commands.any((c) => c.text == 'Shader Override'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('ShaderOverrideComponent'), isNotNull);
        final json = reg.specFor(so)!.toJson(so);
        expect(json['shaderKey'], 'vignette_boost');
        expect(json['targetSlot'], 'present');
      },
    );
  });

  group('E97 — Active Runtime LUT Baking & Shadow Env Sync', () {
    test(
      'ColorGradingLutComponent.ensureLutTexture bakes N*N x N RGBA8 strip & CascadedShadowRigComponent syncs RenderSettings',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final camGo = engine.scene.createGameObject(
          'Cam',
          position: const Vec3(0, 5, 10),
        );
        camGo.transform.lookAt(Vec3.zero);
        camGo.addComponent(Camera());

        final rigGo = engine.scene.createGameObject('ShadowRig');
        rigGo.transform.lookAt(const Vec3(0.3, -1.0, -0.2));
        rigGo.addComponent(Light(type: LightType.directional, intensity: 2.0));
        final rig = rigGo.addComponent(
          CascadedShadowRigComponent(
            cascadeCount: 3,
            lightWorldRadius: 1.75,
            syncEnvironmentSettings: true,
          ),
        );

        final gradeComp = engine.scene
            .createGameObject('Grade')
            .addComponent(
              ColorGradingLutComponent(lutSize: 8, temperature: 0.25),
            );

        engine.step(0.016);
        final bytes = gradeComp.bakeRgbaLutBytes();
        expect(bytes.length, 8 * 8 * 8 * 4);
        final tex1 = gradeComp.ensureLutTexture(engine.graphics);
        expect(gradeComp.isLutTextureDirty, isFalse);
        expect(gradeComp.ensureLutTexture(engine.graphics), same(tex1));

        gradeComp
          ..temperature = -0.2
          ..rebuildLut();
        expect(gradeComp.isLutTextureDirty, isTrue);
        final tex2 = gradeComp.ensureLutTexture(engine.graphics);
        expect(tex2, isNot(same(tex1)));

        expect(
          engine.graphics.environment.shadowFilterRadius,
          closeTo(1.75, 1e-6),
        );
        expect(rig.cascades.length, 3);
      },
    );
  });

  group('E102 — ShadowCasterLodComponent', () {
    test(
      'E102: ShadowCasterLodComponent toggles shadow casting/mesh with hysteresis, inspector buttons & disable restore',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final fullMesh = engine.graphics.createMesh(Primitives.cube(size: 1.0));
        final reducedMesh = engine.graphics.createMesh(
          Primitives.cube(size: 0.5),
        );

        engine.scene.createGameObject(
          'Spot',
          position: Vec3.zero,
          components: [Light.spot(range: 40.0)],
        );

        final caster = engine.scene.createGameObject(
          'Caster',
          position: const Vec3(0, 0, 4), // distance 4 -> full (< 8)
          components: [
            MeshRenderer(mesh: fullMesh, castsShadow: true),
            ShadowCasterLodComponent(
              fullToReduced: 8.0,
              reducedToCulled: 20.0,
              hysteresisDistance: 1.0,
              fullMesh: fullMesh,
              reducedMesh: reducedMesh,
            ),
          ],
        );
        final mr = caster.getComponent<MeshRenderer>()!;
        final lod = caster.getComponent<ShadowCasterLodComponent>()!;

        engine.step(0.016);
        expect(lod.currentLod, ShadowCasterLod.full);
        expect(mr.castsShadow, isTrue);
        expect(mr.mesh, fullMesh);

        // Inside hysteresis band (8.5 < 8 + 1) -> stays full.
        caster.transform.position = const Vec3(0, 0, 8.5);
        engine.step(0.016);
        expect(lod.currentLod, ShadowCasterLod.full);

        // Beyond 8 + 1 -> transitions to reduced & swaps reducedMesh.
        caster.transform.position = const Vec3(0, 0, 12.0);
        engine.step(0.016);
        expect(lod.currentLod, ShadowCasterLod.reduced);
        expect(mr.castsShadow, isTrue);
        expect(mr.mesh, reducedMesh);

        // Beyond 20 + 1 -> transitions to culled & disables castsShadow.
        caster.transform.position = const Vec3(0, 0, 25.0);
        engine.step(0.016);
        expect(lod.currentLod, ShadowCasterLod.culled);
        expect(mr.castsShadow, isFalse);

        // Inspector click: click Full at (152, 159), then Auto at (68, 159).
        final ui = VoxUiContext();
        final uiState = ShadowCasterLodUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 152,
            mouseY: 159,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        ShadowCasterLodInspectorUI.render(ui, lod, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 152,
            mouseY: 159,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        ShadowCasterLodInspectorUI.render(ui, lod, state: uiState);
        final dl = ui.endFrame();
        expect(lod.currentLod, ShadowCasterLod.full);
        expect(mr.castsShadow, isTrue);
        expect(dl.commands.any((c) => c.text == 'Shadow Caster LOD'), isTrue);

        // Clearing override restores distance-based culling and onDisable restores full mesh & castsShadow.
        ui.beginFrame(
          VoxInput(
            mouseX: 68,
            mouseY: 159,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        ShadowCasterLodInspectorUI.render(ui, lod, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 68,
            mouseY: 159,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        ShadowCasterLodInspectorUI.render(ui, lod, state: uiState);
        ui.endFrame();
        expect(lod.forcedLod, isNull);
        expect(lod.currentLod, ShadowCasterLod.culled);
        expect(mr.castsShadow, isFalse);

        lod.enabled = false;
        expect(mr.castsShadow, isTrue);
        expect(mr.mesh, fullMesh);
      },
    );
  });
}
