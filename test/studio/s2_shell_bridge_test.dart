/// S2-0 tests: StudioDockLayout serialization, SessionEditorHostBridge,
/// StudioMenuRegistry hierarchy/shortcuts, FieldMetadata / Field.assetRef,
/// and EditorOverlayState contract.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

final class _SampleComponent extends Component {
  double speed = 5.0;
  Vec2 offset = Vec2.zero;
  AssetRef? materialRef;
}

void main() {
  group('S2-0 — StudioDockLayout', () {
    test(
      'round-trips default Unity-style docking layout and supports focus/resize',
      () {
        final layout = StudioDockLayout.defaultLayout();
        expect(
          layout.panelIds,
          containsAll([
            'hierarchy',
            'scene',
            'game',
            'inspector',
            'project',
            'console',
            'tools',
          ]),
        );

        final updated = layout
            .focusPanel('game')
            .resizeSplit('root_vertical', 0.65);
        final restored = StudioDockLayout.fromJson(updated.toJson());
        final rootSplit = restored.root as DockSplitNode;
        expect(rootSplit.ratio, closeTo(0.65, 1e-6));
        expect(restored.panelIds, equals(layout.panelIds));
      },
    );
  });

  group('S2-0 — SessionEditorHostBridge', () {
    test(
      'bridges selection, undoable commands, dirty state, and play/pause/step/stop',
      () async {
        final engine = Engine(HeadlessHost());
        final go = engine.scene.createGameObject('Cube', position: Vec3.zero);
        final session = EditorSession(engine)..stopPlayMode();
        final bridge = SessionEditorHostBridge(session);

        final snapshots = <EditorBridgeSnapshot>[];
        final sub = bridge.stateChanges.listen(snapshots.add);

        bridge.selectObjects([go]);
        expect(bridge.snapshot().selectedNames, equals(['Cube']));

        bridge.dispatchCommand(
          TransformMoveCommand(
            targetName: 'Cube',
            oldPosition: Vec3.zero,
            newPosition: const Vec3(3, 4, 5),
          ),
        );
        expect(bridge.isDirty, isTrue);
        expect(go.transform.position, equals(const Vec3(3, 4, 5)));

        expect(bridge.undo(), isTrue);
        expect(go.transform.position, equals(Vec3.zero));
        expect(bridge.redo(), isTrue);
        expect(go.transform.position, equals(const Vec3(3, 4, 5)));

        bridge.enterPlayMode();
        expect(bridge.playState, equals(StudioPlayState.playing));
        bridge.pausePlayMode();
        expect(bridge.playState, equals(StudioPlayState.paused));
        bridge.stepPlayMode(0.016);
        expect(bridge.playState, equals(StudioPlayState.paused));
        bridge.exitPlayMode();
        expect(bridge.playState, equals(StudioPlayState.editing));

        await Future<void>.delayed(Duration.zero);
        expect(snapshots, isNotEmpty);
        await sub.cancel();
        await bridge.dispose();
      },
    );
  });

  group('S2-0 — StudioMenuRegistry', () {
    test('builds menu tree and dispatches keyboard shortcuts', () {
      var saved = false;
      final menu = StudioMenuRegistry(registerDefaults: true);
      menu.register(
        StudioMenuItem(
          id: 'file.save_scene',
          menuPath: 'File/Save Scene',
          shortcut: const StudioShortcut('s', ctrl: true),
          action: () => saved = true,
        ),
      );

      final tree = menu.buildTree();
      expect(
        tree.map((n) => n.label),
        containsAll(['File', 'Edit', 'GameObject', 'Assets', 'Window']),
      );
      expect(menu.handleShortcut(key: 's', ctrl: true), isTrue);
      expect(saved, isTrue);
    });
  });

  group('S2-0 — ComponentSpec FieldMetadata & EditorOverlayState', () {
    test(
      'supports range/tooltip/header/assetRef metadata and round-trips cleanly',
      () {
        final spec = ComponentSpec<_SampleComponent>(
          '_SampleComponent',
          _SampleComponent.new,
          [
            Field.number(
              'speed',
              (c) => c.speed,
              (c, v) => c.speed = v,
              min: 0,
              max: 10,
              step: 0.25,
              tooltip: 'Movement speed',
              header: 'Locomotion',
            ),
            Field.vec2('offset', (c) => c.offset, (c, v) => c.offset = v),
            Field.assetRef(
              'materialRef',
              (c) => c.materialRef,
              (c, v) => c.materialRef = v,
              assetTypeFilter: 'material',
            ),
          ],
        );

        final comp = _SampleComponent()
          ..speed = 7.5
          ..offset = const Vec2(1, -2)
          ..materialRef = const AssetRef('deadbeef00112233445566778899aabb');

        final json = spec.toJson(comp);
        final restored = _SampleComponent();
        spec.applyJson(restored, json);

        expect(restored.speed, equals(7.5));
        expect(restored.offset, equals(const Vec2(1, -2)));
        expect(restored.materialRef, equals(comp.materialRef));
        expect(spec.fields.first.metadata.hasRange, isTrue);
        expect(spec.fields.last.metadata.assetTypeFilter, equals('material'));

        // EditorOverlayState contract smoke check
        const overlay = EditorOverlayState(
          lines: [
            EditorGizmoLine(
              start: Vec3.zero,
              end: Vec3(1, 0, 0),
              color: LinearColor(1, 0, 0),
            ),
          ],
          selectedObjectIds: {42},
          pickRequest: EditorPickRequest(
            pixelX: 100,
            pixelY: 50,
            viewportWidth: 1280,
            viewportHeight: 720,
          ),
        );
        expect(overlay.selectedObjectIds, contains(42));
        expect(overlay.grid.enabled, isTrue);
      },
    );
  });
}
