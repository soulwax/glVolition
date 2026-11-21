/// Pure-Dart Interactive Node-Graph Visual Canvas (`[Wave G12]`):
/// Renders [StudioGraphModel] inside any docked `'graph'` tab with pan/zoom,
/// draggable Unity-style node cards, typed input/output port circles, and
/// interactive port-to-port wire creation.
library;

import '../../../gl_volition.dart';
import '../graph/graph_model.dart';

/// Interactive visual canvas controller for [StudioGraphModel] (`[Wave G12]`).
final class StudioGraphCanvasController {
  double panX = 0.0;
  double panY = 0.0;
  double zoom = 1.0;
  String? selectedNodeId;

  String? _draggingNodeId;
  ({String nodeId, String portId, double startX, double startY})?
  _connectingFrom;
  int _edgeCounter = 1;

  static const double _nodeWidth = 152.0;
  static const double _headerHeight = 22.0;
  static const double _portRowHeight = 18.0;

  /// Renders [graph] inside [bounds] and handles node dragging, port wiring,
  /// and canvas panning/zooming.
  void render({
    required StudioGraphModel graph,
    required DrawList dl,
    required VoxInput input,
    required VoxRect bounds,
  }) {
    // 1. Canvas background + subtle grid
    dl.addRectFilled(
      bounds.x,
      bounds.y,
      bounds.width,
      bounds.height,
      const VoxColor(28, 30, 34, 255),
    );
    final gridStep = (28.0 * zoom).clamp(14.0, 64.0);
    for (
      var gx = bounds.x + (panX % gridStep);
      gx < bounds.right;
      gx += gridStep
    ) {
      dl.addLine(
        gx,
        bounds.y + 26,
        gx,
        bounds.bottom,
        const VoxColor(38, 40, 46, 255),
      );
    }
    for (
      var gy = bounds.y + 26 + (panY % gridStep);
      gy < bounds.bottom;
      gy += gridStep
    ) {
      dl.addLine(
        bounds.x,
        gy,
        bounds.right,
        gy,
        const VoxColor(38, 40, 46, 255),
      );
    }

    // 2. Top Graph toolbar
    dl.addRectFilled(
      bounds.x,
      bounds.y,
      bounds.width,
      26,
      const VoxColor(40, 42, 46, 255),
    );
    final addRect = VoxRect(bounds.x + 8, bounds.y + 3, 86, 20);
    final addHov = addRect.contains(input.mouseX, input.mouseY);
    dl.addRectFilled(
      addRect.x,
      addRect.y,
      addRect.width,
      addRect.height,
      addHov
          ? const VoxColor(58, 121, 187, 255)
          : const VoxColor(56, 56, 56, 255),
      cornerRadius: 3,
    );
    dl.addText(
      '+ Add Node',
      addRect.x + 8,
      addRect.y + 4,
      color: const VoxColor(224, 224, 224, 255),
      size: 11,
    );
    if (addHov && input.wasMouseClicked) {
      final idx = graph.nodes.length + 1;
      graph.addNode(
        GraphNode(
          id: 'node_$idx',
          typeId: 'generic',
          title: 'Node $idx',
          x: 40.0 + (idx % 4) * 180.0,
          y: 40.0 + (idx ~/ 4) * 110.0,
          ports: const [
            GraphPort(
              id: 'in',
              label: 'In',
              dataType: 'any',
              direction: GraphPortDirection.input,
            ),
            GraphPort(
              id: 'out',
              label: 'Out',
              dataType: 'any',
              direction: GraphPortDirection.output,
            ),
          ],
        ),
      );
    }
    dl.addText(
      '${graph.schemaId}  |  Nodes: ${graph.nodes.length}  |  Edges: ${graph.edges.length}  |  ${(zoom * 100).round()}%',
      bounds.x + 106,
      bounds.y + 7,
      color: const VoxColor(160, 165, 175, 255),
      size: 11,
    );

    final canvasRect = VoxRect(
      bounds.x,
      bounds.y + 26,
      bounds.width,
      (bounds.height - 26).clamp(0.0, double.infinity),
    );

    // Zoom with wheel over canvas
    if (canvasRect.contains(input.mouseX, input.mouseY) &&
        input.scrollDeltaY != 0.0) {
      zoom = (zoom + input.scrollDeltaY * 0.08).clamp(0.5, 2.0);
    }

    // Precompute port screen positions for edge rendering & hit-testing
    final portCenters = <(String, String), (double, double)>{};
    final nodeRects = <String, VoxRect>{};

    for (final node in graph.nodes) {
      final nx = canvasRect.x + panX + node.x * zoom;
      final ny = canvasRect.y + panY + node.y * zoom;
      final nw = _nodeWidth * zoom;
      final inPorts = node.ports
          .where((p) => p.direction == GraphPortDirection.input)
          .toList();
      final outPorts = node.ports
          .where((p) => p.direction == GraphPortDirection.output)
          .toList();
      final rows = inPorts.length > outPorts.length
          ? inPorts.length
          : outPorts.length;
      final nh =
          (_headerHeight + (rows < 1 ? 1 : rows) * _portRowHeight + 8.0) * zoom;
      nodeRects[node.id] = VoxRect(nx, ny, nw, nh);

      for (var i = 0; i < inPorts.length; i++) {
        final py = ny + (_headerHeight + 10.0 + i * _portRowHeight) * zoom;
        portCenters[(node.id, inPorts[i].id)] = (nx, py);
      }
      for (var i = 0; i < outPorts.length; i++) {
        final py = ny + (_headerHeight + 10.0 + i * _portRowHeight) * zoom;
        portCenters[(node.id, outPorts[i].id)] = (nx + nw, py);
      }
    }

    // 3. Render existing wires
    for (final edge in graph.edges) {
      final a = portCenters[(edge.fromNodeId, edge.fromPortId)];
      final b = portCenters[(edge.toNodeId, edge.toPortId)];
      if (a == null || b == null) continue;
      _drawWire(dl, a.$1, a.$2, b.$1, b.$2, const VoxColor(96, 185, 245, 255));
    }

    // Live preview wire when dragging from an output port
    if (_connectingFrom != null && input.isMouseDown) {
      _drawWire(
        dl,
        _connectingFrom!.startX,
        _connectingFrom!.startY,
        input.mouseX,
        input.mouseY,
        const VoxColor(245, 210, 75, 255),
      );
    }

    // 4. Render node cards & handle port / drag interactions
    var consumedByNode = false;
    for (final node in graph.nodes) {
      final nr = nodeRects[node.id]!;
      final isSelected = selectedNodeId == node.id;
      dl.addRectFilled(
        nr.x,
        nr.y,
        nr.width,
        nr.height,
        const VoxColor(48, 50, 56, 240),
        cornerRadius: 4,
      );
      dl.addRectFilled(
        nr.x,
        nr.y,
        nr.width,
        _headerHeight * zoom,
        isSelected
            ? const VoxColor(58, 121, 187, 255)
            : const VoxColor(66, 70, 78, 255),
        cornerRadius: 4,
      );
      dl.addRectOutline(
        nr.x,
        nr.y,
        nr.width,
        nr.height,
        isSelected
            ? const VoxColor(96, 175, 245, 255)
            : const VoxColor(22, 24, 28, 255),
      );
      dl.addText(
        node.title,
        nr.x + 8,
        nr.y + 5 * zoom,
        color: const VoxColor(235, 235, 235, 255),
        size: 11,
      );

      // Draw ports & hit-test port circles
      for (final p in node.ports) {
        final center = portCenters[(node.id, p.id)];
        if (center == null) continue;
        final isOut = p.direction == GraphPortDirection.output;
        final pr = VoxRect(center.$1 - 6, center.$2 - 6, 12, 12);
        dl.addRectFilled(
          pr.x,
          pr.y,
          pr.width,
          pr.height,
          isOut
              ? const VoxColor(85, 195, 120, 255)
              : const VoxColor(230, 165, 70, 255),
          cornerRadius: 6,
        );
        dl.addText(
          p.label,
          isOut ? center.$1 - 36 : center.$1 + 10,
          center.$2 - 5,
          color: const VoxColor(185, 190, 198, 255),
          size: 10,
        );

        if (isOut &&
            pr.contains(input.mouseX, input.mouseY) &&
            input.wasMouseClicked) {
          _connectingFrom = (
            nodeId: node.id,
            portId: p.id,
            startX: center.$1,
            startY: center.$2,
          );
          consumedByNode = true;
        }
        if (!isOut &&
            _connectingFrom != null &&
            pr.contains(input.mouseX, input.mouseY) &&
            input.wasMouseReleased) {
          graph.connect(
            edgeId: 'edge_${_edgeCounter++}',
            fromNodeId: _connectingFrom!.nodeId,
            fromPortId: _connectingFrom!.portId,
            toNodeId: node.id,
            toPortId: p.id,
          );
          _connectingFrom = null;
          consumedByNode = true;
        }
      }

      final headerRect = VoxRect(nr.x, nr.y, nr.width, _headerHeight * zoom);
      if (!consumedByNode &&
          headerRect.contains(input.mouseX, input.mouseY) &&
          input.wasMouseClicked) {
        selectedNodeId = node.id;
        _draggingNodeId = node.id;
        consumedByNode = true;
      }
    }

    // Move dragged node
    if (_draggingNodeId != null && input.isMouseDown) {
      final node = graph.nodeById(_draggingNodeId!);
      if (node != null) {
        node.x += input.mouseDeltaX / zoom;
        node.y += input.mouseDeltaY / zoom;
      }
    }

    if (input.wasMouseReleased) {
      _draggingNodeId = null;
      _connectingFrom = null;
    }
  }

  void _drawWire(
    DrawList dl,
    double x0,
    double y0,
    double x1,
    double y1,
    VoxColor color,
  ) {
    final midX = (x0 + x1) * 0.5;
    dl.addLine(x0, y0, midX, y0, color, thickness: 2);
    dl.addLine(midX, y0, midX, y1, color, thickness: 2);
    dl.addLine(midX, y1, x1, y1, color, thickness: 2);
  }
}
