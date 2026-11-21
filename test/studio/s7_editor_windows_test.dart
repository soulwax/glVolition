/// Phase S7 test: Verifies Shared Node-Graph & Timeline models (`[S7-0]`),
/// Animator Controller (`[S7-A]`), Multi-Schema Graph Editors (`[S7-B]`),
/// World Tools (`[S7-C]`), 2D Sprite/Tilemap Tools (`[S7-D]`), UI Builder &
/// Localization Tables (`[S7-E]`), and 22/22 `editor-tooled` modules (`[S7-M]`).
library;

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S7-0 — Shared Node-Graph & Timeline Models', () {
    test(
      'StudioGraphModel validates port types, auto-layouts, and supports undo/redo',
      () {
        final g = StudioGraphModel(schemaId: 'test');
        g.addNode(
          GraphNode(
            id: 'a',
            typeId: 'const',
            title: 'Float',
            ports: const [
              GraphPort(
                id: 'out',
                label: 'Out',
                dataType: 'float',
                direction: GraphPortDirection.output,
              ),
            ],
          ),
        );
        g.addNode(
          GraphNode(
            id: 'b',
            typeId: 'sink',
            title: 'Sink',
            ports: const [
              GraphPort(
                id: 'inFloat',
                label: 'F',
                dataType: 'float',
                direction: GraphPortDirection.input,
              ),
              GraphPort(
                id: 'inBool',
                label: 'B',
                dataType: 'bool',
                direction: GraphPortDirection.input,
              ),
            ],
          ),
        );

        // Type mismatch rejected
        expect(
          g.connect(
            edgeId: 'bad',
            fromNodeId: 'a',
            fromPortId: 'out',
            toNodeId: 'b',
            toPortId: 'inBool',
          ),
          isFalse,
        );
        // Matching type succeeds
        expect(
          g.connect(
            edgeId: 'e1',
            fromNodeId: 'a',
            fromPortId: 'out',
            toNodeId: 'b',
            toPortId: 'inFloat',
          ),
          isTrue,
        );
        g.autoLayout();
        expect(g.nodeById('b')!.x, greaterThan(g.nodeById('a')!.x));

        expect(g.undo(), isTrue);
        expect(g.edges, isEmpty);
        expect(g.redo(), isTrue);
        expect(g.edges, hasLength(1));

        final roundTrip = StudioGraphModel.fromJson(g.toJson());
        expect(roundTrip.nodes, hasLength(2));
        expect(roundTrip.edges, hasLength(1));
      },
    );

    test(
      'StudioTimelineModel snaps to frames, records keys, and queries active clips',
      () {
        final tl = StudioTimelineModel(frameRate: 60.0, snapToFrames: true);
        tl.tracks.add(
          TimelineTrack(
            id: 'anim',
            name: 'HeroAnim',
            kind: TimelineTrackKind.animation,
            clips: [
              TimelineClip(
                id: 'c1',
                assetGuid: 'clip-walk',
                startTime: 0.5,
                duration: 2.0,
              ),
            ],
          ),
        );

        tl.scrubTo(1.0);
        expect(tl.activeClipsAtPlayhead(), hasLength(1));
        tl.recordMode = true;
        expect(tl.recordKey('anim', 'transform.position.x', 4.2), isTrue);
        expect(tl.tracks.single.keys, hasLength(1));

        final rt = StudioTimelineModel.fromJson(tl.toJson());
        expect(rt.tracks.single.clips.single.assetGuid, equals('clip-walk'));
      },
    );
  });

  group('S7-A..S7-E & S7-M — Specialized Editor Windows', () {
    test(
      'S7-A: AnimatorControllerModel transitions states and evaluates 1D blend tree',
      () {
        final ctrl = AnimatorControllerModel(
          name: 'Locomotion',
          states: const ['Idle', 'Run'],
          transitions: const [
            AnimatorTransitionDef(
              fromState: 'Idle',
              toState: 'Run',
              parameter: 'speed',
              greaterThan: 0.1,
            ),
          ],
        );
        expect(ctrl.evaluateStep(), equals('Idle'));
        ctrl.parameters['speed'] = 2.5;
        expect(ctrl.evaluateStep(), equals('Run'));

        final weights = AnimatorControllerModel.evaluateBlendTree1D(const [
          BlendTree1DEntry(clipGuid: 'walk', threshold: 0.0),
          BlendTree1DEntry(clipGuid: 'run', threshold: 4.0),
        ], 1.0);
        expect(weights['walk'], closeTo(0.75, 1e-6));
        expect(weights['run'], closeTo(0.25, 1e-6));
      },
    );

    test(
      'S7-B: all 5 graph schemas round-trip and support debugger breakpoints',
      () {
        for (final kind in StudioGraphSchemaKind.values) {
          final g = StudioGraphSchemaFactory.createTemplate(kind);
          final rt = StudioGraphModel.fromJson(g.toJson());
          expect(rt.schemaId, equals(kind.name));
          expect(rt.nodes, hasLength(2));
          expect(rt.edges, hasLength(1));
        }
        final dbg = GraphDebuggerState();
        expect(dbg.toggleBreakpoint('action'), isTrue);
        dbg.activeNodeId = 'action';
        expect(dbg.isPausedAtBreakpoint(), isTrue);
      },
    );

    test(
      'S7-C: TerrainSculptTool compact stroke delta undoes/redoes cleanly',
      () {
        final tool = TerrainSculptTool(width: 16, height: 16);
        final delta = tool.applyStroke(
          mode: TerrainBrushMode.raise,
          centerX: 8,
          centerY: 8,
          radius: 3.0,
          strength: 1.0,
        );
        expect(delta.modifiedCells, greaterThan(0));
        expect(tool.heightfield[8 * 16 + 8], closeTo(1.0, 1e-5));

        expect(tool.undo(), isTrue);
        expect(tool.heightfield[8 * 16 + 8], closeTo(0.0, 1e-5));
        expect(tool.redo(), isTrue);
        expect(tool.heightfield[8 * 16 + 8], closeTo(1.0, 1e-5));

        const navA = NavMeshBakeSettings(seed: 7);
        const navB = NavMeshBakeSettings(seed: 7);
        expect(navA.deterministicHash(), equals(navB.deterministicHash()));
      },
    );

    test(
      'S7-D: SpriteSlicerTool & TilePaletteTool rule-tile neighbor mask',
      () {
        final slices = SpriteSlicerTool.sliceGrid(
          textureWidth: 128,
          textureHeight: 64,
          cellWidth: 32,
          cellHeight: 32,
        );
        expect(slices, hasLength(8));

        final palette = TilePaletteTool(width: 8, height: 8);
        palette.paintRect(2, 2, 4, 4, 1);
        // Center (3,3) has all 4 cardinal neighbors (N|E|S|W = 15)
        expect(palette.neighborMask4(3, 3, 1), equals(15));
        // Top-left corner (2,2) has E|S = 2|4 = 6
        expect(palette.neighborMask4(2, 2, 1), equals(6));
      },
    );

    test(
      'S7-E: UI Builder anchor math across resolutions & Localization CSV round-trip',
      () {
        // Full-stretch panel with 20px horizontal margin
        const stretch = RectTransformSpec(
          anchorMinX: 0.0,
          anchorMinY: 0.0,
          anchorMaxX: 1.0,
          anchorMaxY: 1.0,
          sizeDeltaX: -40.0,
          sizeDeltaY: -20.0,
        );
        final r720 = stretch.resolve(1280, 720);
        final r1080 = stretch.resolve(1920, 1080);
        expect(r720.width, closeTo(1240, 1e-5));
        expect(r720.height, closeTo(700, 1e-5));
        expect(r1080.width, closeTo(1880, 1e-5));
        expect(r1080.height, closeTo(1060, 1e-5));

        final loc = LocalizationTableEditorModel(const ['en', 'de']);
        loc.setTranslation('menu.play', 'en', 'Play');
        loc.setTranslation('menu.play', 'de', 'Spielen');
        loc.setTranslation('menu.quit', 'en', 'Quit');

        final missing = loc.missingKeyReport();
        expect(missing['en'], isEmpty);
        expect(missing['de'], equals(['menu.quit']));

        final rt = LocalizationTableEditorModel.importCsv(loc.exportCsv());
        expect(rt.getTranslation('menu.play', 'de'), equals('Spielen'));
        expect(rt.missingKeyReport()['de'], equals(['menu.quit']));
      },
    );

    test('S7-M: all 22 target modules meet editor-tooled maturity', () {
      final registry = StudioModuleRegistry(kStudioModuleInventory);
      final editorTooled = registry.all
          .where((m) => m.maturity == StudioModuleMaturity.editorTooled)
          .toList();
      expect(editorTooled, hasLength(22));
      for (final m in registry.all) {
        expect(
          m.maturity.meets(m.requiredMaturity),
          isTrue,
          reason: '${m.package} is ${m.maturity} < ${m.requiredMaturity}',
        );
      }
    });
  });
}
