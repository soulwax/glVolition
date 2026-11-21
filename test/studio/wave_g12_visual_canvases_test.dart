/// Wave G12 test: Verifies dockable Node-Graph (`graph`) and Timeline
/// (`timeline`) visual canvas editors — node dragging, port-to-port wire
/// creation, and Timeline playhead scrubbing + clip/keyframe rendering.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G12 — Dockable Node-Graph & Timeline Visual Canvases', () {
    test('Node-Graph canvas drags nodes and connects output-to-input ports', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.loadScene(Scene('GraphTest'));

      final graph = StudioGraphModel(schemaId: 'shader_graph');
      graph.addNode(
        GraphNode(
          id: 'src',
          typeId: 'color',
          title: 'Albedo',
          x: 40,
          y: 40,
          ports: const [
            GraphPort(
              id: 'out',
              label: 'Out',
              dataType: 'vec4',
              direction: GraphPortDirection.output,
            ),
          ],
        ),
      );
      graph.addNode(
        GraphNode(
          id: 'dst',
          typeId: 'pbr',
          title: 'PBR Output',
          x: 260,
          y: 40,
          ports: const [
            GraphPort(
              id: 'in',
              label: 'In',
              dataType: 'vec4',
              direction: GraphPortDirection.input,
            ),
          ],
        ),
      );

      final session = EditorSession(engine);
      final bridge = SessionEditorHostBridge(session);
      final shell = StudioWorkspaceShell(
        bridge: bridge,
        graphModel: graph,
        layout: const StudioDockLayout(
          root: DockTabsNode(
            id: 'graph_only',
            panelIds: ['graph'],
            activeIndex: 0,
          ),
        ),
      );

      final dl = DrawList();
      final solved = shell.buildFrame(
        dl: dl,
        input: VoxInput(),
        width: 900,
        height: 500,
      );
      final r = solved.areas.single.contentRect;
      final canvasTop = r.y + 26;

      // Drag 'src' node header (+30px X, +20px Y)
      shell.buildFrame(
        dl: dl..clear(),
        input: VoxInput(
          mouseX: r.x + 60,
          mouseY: canvasTop + 50,
          isMouseDown: true,
          wasMouseClicked: true,
        ),
        width: 900,
        height: 500,
      );
      shell.buildFrame(
        dl: dl..clear(),
        input: VoxInput(
          mouseX: r.x + 90,
          mouseY: canvasTop + 70,
          mouseDeltaX: 30,
          mouseDeltaY: 20,
          isMouseDown: true,
        ),
        width: 900,
        height: 500,
      );
      shell.buildFrame(
        dl: dl..clear(),
        input: VoxInput(
          mouseX: r.x + 90,
          mouseY: canvasTop + 70,
          isMouseDown: false,
          wasMouseReleased: true,
        ),
        width: 900,
        height: 500,
      );
      expect(graph.nodeById('src')!.x, closeTo(70.0, 1e-4));
      expect(graph.nodeById('src')!.y, closeTo(60.0, 1e-4));

      // Connect src.out -> dst.in by clicking output port and releasing on input port
      final srcOutX = r.x + 70 + 152;
      final srcOutY = canvasTop + 60 + 32;
      final dstInX = r.x + 260;
      final dstInY = canvasTop + 40 + 32;

      shell.buildFrame(
        dl: dl..clear(),
        input: VoxInput(
          mouseX: srcOutX,
          mouseY: srcOutY,
          isMouseDown: true,
          wasMouseClicked: true,
        ),
        width: 900,
        height: 500,
      );
      shell.buildFrame(
        dl: dl..clear(),
        input: VoxInput(
          mouseX: dstInX,
          mouseY: dstInY,
          isMouseDown: false,
          wasMouseReleased: true,
        ),
        width: 900,
        height: 500,
      );
      expect(graph.edges, hasLength(1));
      expect(graph.edges.single.fromNodeId, equals('src'));
      expect(graph.edges.single.toNodeId, equals('dst'));
    });

    test('Timeline canvas scrubs playhead and renders clips & keyframes', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.loadScene(Scene('TimelineTest'));

      final timeline = StudioTimelineModel(
        tracks: [
          TimelineTrack(
            id: 't1',
            name: 'HeroWalk',
            kind: TimelineTrackKind.animation,
            clips: [
              TimelineClip(
                id: 'WalkCycle',
                assetGuid: 'guid_walk',
                startTime: 0.5,
                duration: 2.0,
              ),
            ],
            keys: const [
              TimelineKey(time: 1.0, propertyPath: 'transform.x', value: 2.0),
            ],
          ),
        ],
      );

      final session = EditorSession(engine);
      final bridge = SessionEditorHostBridge(session);
      final shell = StudioWorkspaceShell(
        bridge: bridge,
        timelineModel: timeline,
        layout: const StudioDockLayout(
          root: DockTabsNode(
            id: 'tl_only',
            panelIds: ['timeline'],
            activeIndex: 0,
          ),
        ),
      );

      final dl = DrawList();
      final solved = shell.buildFrame(
        dl: dl,
        input: VoxInput(),
        width: 800,
        height: 300,
      );
      final r = solved.areas.single.contentRect;
      expect(
        dl.commands.any((c) => (c.text ?? '').contains('WalkCycle')),
        isTrue,
      );

      // Click & drag on time ruler at +160px (= 2.0s at 80px/s)
      final rulerX = r.x + 140;
      final rulerY = r.y + 34;
      shell.buildFrame(
        dl: dl..clear(),
        input: VoxInput(
          mouseX: rulerX + 160,
          mouseY: rulerY,
          isMouseDown: true,
          wasMouseClicked: true,
        ),
        width: 800,
        height: 300,
      );
      expect(timeline.playheadSeconds, closeTo(2.0, 0.05));
    });
  });
}
