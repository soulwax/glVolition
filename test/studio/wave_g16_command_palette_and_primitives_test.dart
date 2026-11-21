/// Wave G16 test: Verifies Quick Search / Command Palette (`Ctrl+K`),
/// persistent Recent Projects (`saveRecent`/`loadRecent`), and procedural 3D
/// Sphere/Plane/Cylinder mesh emission in [StudioViewport3DRenderer].
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G16 — Command Palette (Ctrl+K), Recent Projects & 3D Primitives', () {
    test(
      'Ctrl+K opens Command Palette, fuzzy-filters GameObjects & CLI, and executes on Enter',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = Scene('PaletteTest');
        final beacon = scene.createGameObject('LighthouseBeacon');
        beacon.transform.localPosition = const Vec3(10, 3, -5);
        engine.loadScene(scene);

        final fakeCli = SimulatedStudioCliBridge();
        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final shell = StudioWorkspaceShell(bridge: bridge, cliBridge: fakeCli);
        final dl = DrawList();
        final overlayDl = DrawList();

        // Ctrl+K opens Command Palette
        shell.buildFrame(
          dl: dl,
          overlayDl: overlayDl,
          input: VoxInput(),
          keyboard: const StudioKeyboardState(ctrl: true, pressedKeys: {'k'}),
          width: 1280,
          height: 720,
        );
        expect(shell.commandPalette.isOpen, isTrue);

        // Type 'Lighthouse' + press Enter -> selects & frames LighthouseBeacon!
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          keyboard: const StudioKeyboardState(
            typedText: 'Lighthouse',
            pressedKeys: {'enter'},
          ),
          width: 1280,
          height: 720,
        );
        expect(shell.commandPalette.isOpen, isFalse);
        expect(session.selectedObjects, equals([beacon]));
        expect(
          shell.sceneViewport.editorCamera.target,
          equals(const Vec3(10, 3, -5)),
        );

        // Open again, search 'doctor', press Enter -> runs CLI doctor!
        shell.commandPalette.open();
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          keyboard: const StudioKeyboardState(
            typedText: 'doctor',
            pressedKeys: {'enter'},
          ),
          width: 1280,
          height: 720,
        );
        expect(fakeCli.recordedCommands.single, equals(['doctor']));
      },
    );

    test(
      'StudioAppLauncherModel persists and reloads recent projects JSON',
      () async {
        final fs = MemoryProjectFileSystem();
        final launcher1 = StudioAppLauncherModel()
          ..recordOpened('Alpha', '/projects/alpha', 1000)
          ..recordOpened('Beta', '/projects/beta', 2000);
        await launcher1.saveRecent(fs);

        final launcher2 = StudioAppLauncherModel();
        expect(await launcher2.loadRecent(fs), isTrue);
        expect(launcher2.recentProjects, hasLength(2));
        expect(launcher2.recentProjects.first.name, equals('Beta'));
      },
    );

    test(
      'StudioViewport3DRenderer emits procedural Sphere, Plane, and Cylinder geometry with zero leaks',
      () {
        final device = RecordingGlesDevice();
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = Scene('PrimitivesTest');
        scene.createGameObject('Sphere');
        scene.createGameObject('GroundPlane');
        scene.createGameObject('PlayerCylinder');
        engine.loadScene(scene);

        final bridge = SessionEditorHostBridge(EditorSession(engine));
        final shell = StudioWorkspaceShell(bridge: bridge);
        final app = NativeStudioApp(shell: shell, device: device);

        app.stepFrame(input: VoxInput(), pixelWidth: 1280, pixelHeight: 720);
        // Sphere (6*10*6=360) + Plane (6) + Cylinder (10*12=120) + grid > 500 verts
        expect(app.viewport3dRenderer.lastSceneVertices, greaterThan(500));

        app.dispose();
        expect(device.bufferDeleteCalls, equals(device.bufferCreateCalls));
        expect(device.textureDeleteCalls, equals(device.textureCreateCalls));
        expect(device.targetDeleteCalls, equals(device.targetCreateCalls));
        expect(device.vaoDeleteCalls, equals(device.vaoCreateCalls));
        expect(device.programDeleteCalls, equals(device.programCompileCalls));
      },
    );
  });
}
