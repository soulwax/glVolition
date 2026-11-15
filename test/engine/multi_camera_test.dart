/// Multi-camera viewport sorting, per-pass culling masks, and offscreen
/// render-to-texture pipeline tests across HeadlessHost and NativeEngineHost.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P2-W10-C — Multi-Camera Sorting, Viewports & Render Targets', () {
    test(
      'HeadlessHost sorts cameras deterministically by depth ascending with stable tie-breaker',
      () {
        final host = HeadlessHost();
        host.graphics
          ..viewportWidth = 800
          ..viewportHeight = 600;
        final engine = Engine(host);

        engine.scene.createGameObject(
          'HighCam',
          position: const Vec3(0, 10, 10),
          components: [Camera(depth: 10, cullingMask: 1 << 2)],
        );
        engine.scene.createGameObject(
          'BackCam',
          position: const Vec3(0, 2, 10),
          components: [Camera(depth: -2, cullingMask: 1 << 0)],
        );
        engine.scene.createGameObject(
          'MidCamFirst',
          position: const Vec3(5, 2, 10),
          components: [Camera(depth: 5, cullingMask: 1 << 1)],
        );
        final midSecondGo = engine.scene.createGameObject(
          'MidCamSecond',
          position: const Vec3(-5, 2, 10),
          components: [Camera(depth: 5, cullingMask: 1 << 3)],
        );

        final sorted = engine.scene.sortedActiveCameras;
        expect(sorted.map((c) => c.gameObject.name).toList(), [
          'BackCam',
          'MidCamFirst',
          'MidCamSecond',
          'HighCam',
        ]);
        expect(Camera.of(engine.scene)!.gameObject.name, 'HighCam');

        engine.step(1 / 60);

        final passes = host.graphics.renderedCameraPasses;
        expect(passes.length, 4);
        expect(passes.map((p) => p.depth).toList(), [-2, 5, 5, 10]);
        expect(passes.map((p) => p.visibilityMask).toList(), [
          1 << 0,
          1 << 1,
          1 << 3,
          1 << 2,
        ]);

        // Disabling a camera removes it from sortedActiveCameras and subsequent passes.
        host.graphics.renderedCameraPasses.clear();
        midSecondGo.setActive(false);
        engine.step(1 / 60);
        expect(engine.scene.sortedActiveCameras.map((c) => c.gameObject.name), [
          'BackCam',
          'MidCamFirst',
          'HighCam',
        ]);
        expect(
          host.graphics.renderedCameraPasses.map((p) => p.depth).toList(),
          [-2, 5, 10],
        );

        engine.dispose();
      },
    );

    test(
      'Single default camera preserves legacy non-multi-pass submission; custom viewport or target enables pass submission',
      () {
        final host = HeadlessHost();
        host.graphics
          ..viewportWidth = 640
          ..viewportHeight = 480;
        final engine = Engine(host);

        final camGo = engine.scene.createGameObject(
          'MainCam',
          components: [Camera(cullingMask: 0x05)],
        );
        engine.step(1 / 60);

        expect(host.graphics.renderedCameraPasses, isEmpty);
        expect(host.graphics.visibilityMask, 0x05);

        // Switching to a custom viewport rect submits an explicit pass.
        final cam = camGo.getComponent<Camera>()!;
        cam.normalizedViewportRect = const Vec4(0.25, 0.25, 0.5, 0.5);
        engine.step(1 / 60);

        expect(host.graphics.renderedCameraPasses.length, 1);
        expect(host.graphics.activeViewportX, 160);
        expect(host.graphics.activeViewportY, 120);
        expect(host.graphics.activeViewportWidth, 320);
        expect(host.graphics.activeViewportHeight, 240);

        // Editor free-look overrides camera passes cleanly.
        host.graphics.renderedCameraPasses.clear();
        engine.editor.setFreeLook(true);
        engine.step(1 / 60);
        expect(host.graphics.renderedCameraPasses, isEmpty);
        expect(host.graphics.visibilityMask, -1);

        engine.dispose();
      },
    );

    test(
      'HeadlessHost supports PIP offscreen RenderTargetHandle, viewport pixel math, and clean releaseRenderTarget cleanup',
      () {
        final host = HeadlessHost();
        host.graphics
          ..viewportWidth = 1000
          ..viewportHeight = 500;
        final engine = Engine(host);

        final minimapRt = host.graphics.createRenderTarget(
          width: 256,
          height: 128,
          debugLabel: 'minimap',
        );
        expect(host.graphics.liveRenderTargets, contains(minimapRt));
        expect(host.graphics.liveTextures, contains(minimapRt.colorTexture));

        // Higher-depth offscreen camera + lower-depth screen camera verify primary screen fallback.
        final mainCam = Camera(
          depth: 0,
          cullingMask: LayerMask.fromLayer(0),
          normalizedViewportRect: const Vec4(0.2, 0.1, 0.5, 0.5),
          clearColor: true,
          clearDepth: true,
        );
        final minimapCam = Camera.ortho(
          orthoHeight: 20,
          depth: 10,
          cullingMask: LayerMask.fromLayer(1),
          normalizedViewportRect: const Vec4(0.0, 0.25, 0.5, 0.5),
          targetTexture: minimapRt,
          clearColor: true,
          clearDepth: false,
        );
        expect(minimapCam.renderTarget, minimapRt);

        engine.scene.createGameObject('MainCam', components: [mainCam]);
        engine.scene.createGameObject('MinimapCam', components: [minimapCam]);

        engine.step(1 / 60);

        final passes = host.graphics.renderedCameraPasses;
        expect(passes.length, 2);
        expect(passes[0].target, isNull);
        expect(passes[0].depth, 0);
        expect(passes[0].visibilityMask, LayerMask.fromLayer(0));

        expect(passes[1].target, minimapRt);
        expect(passes[1].depth, 10);
        expect(passes[1].clearColor, isTrue);
        expect(passes[1].clearDepth, isFalse);
        expect(passes[1].visibilityMask, LayerMask.fromLayer(1));

        // Minimap pass applied viewport against target dimensions (256x128), not surface.
        expect(host.graphics.activeViewportX, 0);
        expect(host.graphics.activeViewportY, 32);
        expect(host.graphics.activeViewportWidth, 128);
        expect(host.graphics.activeViewportHeight, 64);

        // Camera.of returns highest-depth camera (10), while graphics tracks primary screen camera (0).
        expect(Camera.of(engine.scene), minimapCam);
        expect(host.graphics.camera, mainCam.controller);
        expect(host.graphics.visibilityMask, LayerMask.fromLayer(0));

        // Release render target and verify both target handle and backing color texture are freed.
        host.graphics.releaseRenderTarget(minimapRt);
        expect(host.graphics.liveRenderTargets, isNot(contains(minimapRt)));
        expect(
          host.graphics.liveTextures,
          isNot(contains(minimapRt.colorTexture)),
        );
        // Double release is a safe no-op.
        host.graphics.releaseRenderTarget(minimapRt);

        engine.dispose();
      },
    );

    test(
      'NativeEngineHost sorts multi-camera passes, isolates layers per pass via FrameSequencer visibilityMask, dispatches GL target/viewport commands, and frees targets cleanly',
      () async {
        final device = GlesDevice();
        final scene = Scene('MultiCamNative');

        final runner = await NativeEngineHost.boot(
          device: device,
          width: 800,
          height: 600,
          requestedProfile: QualityProfile.clean,
          initialScene: scene,
        );
        final graphics = runner.host.graphics;

        final minimapRt = graphics.createRenderTarget(
          width: 256,
          height: 256,
          debugLabel: 'native_minimap',
        );
        expect(graphics.liveRenderTargets, contains(minimapRt));
        expect(graphics.gpuTargetFor(minimapRt), isNotNull);

        // Light + objects on distinct layers facing the cameras.
        final cubeMesh = graphics.createMesh(Primitives.cube(size: 1.0));
        final sphereMesh = graphics.createMesh(Primitives.sphere(radius: 0.5));
        final sharedMat = graphics.createMaterial(
          MaterialDefinition.dielectric(
            key: 'multi_cam_shared',
            color: const LinearColor(0.8, 0.8, 0.8),
          ),
        );
        scene.createGameObject(
          'Sun',
          rotation: lookRotation(const Vec3(-0.3, -1.0, -0.4)),
          components: [Light(intensity: 1.5)],
        );
        scene.createGameObject(
          'Layer0Cube',
          layer: 0,
          position: const Vec3(0, 0, 0),
          components: [
            MeshRenderer(
              mesh: cubeMesh,
              meshData: Primitives.cube(size: 1.0),
              material: sharedMat,
            ),
          ],
        );
        scene.createGameObject(
          'Layer1SphereA',
          layer: 1,
          position: const Vec3(-1.2, 0, 0),
          components: [
            MeshRenderer(
              mesh: sphereMesh,
              meshData: Primitives.sphere(radius: 0.5),
              material: sharedMat,
            ),
          ],
        );
        scene.createGameObject(
          'Layer1SphereB',
          layer: 1,
          position: const Vec3(1.2, 0, 0),
          components: [
            MeshRenderer(
              mesh: sphereMesh,
              meshData: Primitives.sphere(radius: 0.5),
              material: sharedMat,
            ),
          ],
        );

        // Add higher-depth main camera BEFORE lower-depth minimap camera to test sorting.
        scene.createGameObject(
          'MainSplitCam',
          position: const Vec3(0, 0, 6),
          rotation: lookRotation(const Vec3(0, 0, -1)),
          components: [
            Camera(
              depth: 2,
              cullingMask: LayerMask.fromLayer(0),
              normalizedViewportRect: const Vec4(0.5, 0.25, 0.5, 0.5),
            ),
          ],
        );
        scene.createGameObject(
          'MinimapOffscreenCam',
          position: const Vec3(0, 0, 8),
          rotation: lookRotation(const Vec3(0, 0, -1)),
          components: [
            Camera.ortho(
              orthoHeight: 8,
              depth: -1,
              cullingMask: LayerMask.fromLayer(1),
              normalizedViewportRect: const Vec4(0.0, 0.0, 1.0, 1.0),
              targetTexture: minimapRt,
              clearColor: true,
              clearDepth: false,
            ),
          ],
        );
        scene.createGameObject(
          'TieOverlayCam',
          position: const Vec3(0, 0, 7),
          rotation: lookRotation(const Vec3(0, 0, -1)),
          components: [
            Camera(
              depth: 2,
              cullingMask: LayerMask.fromLayer(0) | LayerMask.fromLayer(1),
              normalizedViewportRect: const Vec4(0.0, 0.0, 0.5, 1.0),
            ),
          ],
        );

        device.drawLog.clear();
        device.viewportLog.clear();
        device.clearLog.clear();

        final combinedStats = runner.renderFrame(1 / 60);

        // Verify deterministic ascending depth sort (-1, 2 [first], 2 [second]).
        expect(graphics.renderedCameraPasses.length, 3);
        expect(graphics.renderedCameraPasses.map((p) => p.depth).toList(), [
          -1,
          2,
          2,
        ]);
        expect(graphics.renderedCameraPasses[0].target, minimapRt);
        expect(graphics.renderedCameraPasses[1].target, isNull);
        expect(graphics.renderedCameraPasses[2].target, isNull);

        // Verify GL viewport commands recorded cleanly per pass.
        expect(device.viewportLog, [
          (x: 0, y: 0, width: 256, height: 256),
          (x: 400, y: 150, width: 400, height: 300),
          (x: 0, y: 0, width: 400, height: 600),
        ]);
        expect(graphics.activeViewportX, 0);
        expect(graphics.activeViewportY, 0);
        expect(graphics.activeViewportWidth, 400);
        expect(graphics.activeViewportHeight, 600);

        // Verify offscreen target binding and clear command were dispatched to RecordingGlesDevice.
        expect(device.drawLog, contains('clear(colorOnly)'));
        expect(device.drawLog, contains('setViewport(0, 0, 256, 256)'));
        expect(device.drawLog, contains('setViewport(400, 150, 400, 300)'));
        expect(device.drawLog, contains('setViewport(0, 0, 400, 600)'));
        final hasTargetBind = device.drawLog.any(
          (entry) =>
              entry.startsWith('bindTarget(') && entry != 'bindTarget(canvas)',
        );
        expect(hasTargetBind, isTrue);

        // Verify FrameSequencer visibilityMask culling isolated each pass's instances:
        // - Pass 0 (minimap, layer 1): submits 2 spheres, culls 1 cube.
        // - Pass 1 (main split, layer 0): submits 1 cube, culls 2 spheres.
        // - Pass 2 (tie overlay, layer 0 | layer 1): submits all 3 instances, culls 0.
        expect(graphics.lastFramePassStats.length, 3);
        expect(graphics.lastFramePassStats[0].stats.instancesSubmitted, 2);
        expect(graphics.lastFramePassStats[0].stats.instancesCulled, 1);
        expect(graphics.lastFramePassStats[1].stats.instancesSubmitted, 1);
        expect(graphics.lastFramePassStats[1].stats.instancesCulled, 2);
        expect(graphics.lastFramePassStats[2].stats.instancesSubmitted, 3);
        expect(graphics.lastFramePassStats[2].stats.instancesCulled, 0);

        expect(combinedStats.instancesSubmitted, 6);
        expect(combinedStats.instancesCulled, 3);

        // Explicit releaseRenderTarget frees target handle and its GPU target, and dispose cleans up all remaining objects.
        graphics.releaseRenderTarget(minimapRt);
        expect(graphics.liveRenderTargets, isEmpty);
        expect(graphics.gpuTargetFor(minimapRt), isNull);

        runner.dispose();
        expect(device.liveObjectCount, 0);
      },
    );
  });
}
