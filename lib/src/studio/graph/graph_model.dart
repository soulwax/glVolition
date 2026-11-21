/// Shared Node-Graph View Model (`[S7-0]`):
/// Pure-Dart node graph with typed ports, edges, groups, copy/paste,
/// auto-layout, undo/redo, and JSON serialization.
library;

/// Direction of a [GraphPort].
enum GraphPortDirection { input, output }

/// Typed connection port on a [GraphNode].
final class GraphPort {
  final String id;
  final String label;
  final String dataType;
  final GraphPortDirection direction;

  const GraphPort({
    required this.id,
    required this.label,
    required this.dataType,
    required this.direction,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'dataType': dataType,
    'direction': direction.name,
  };

  factory GraphPort.fromJson(Map<String, Object?> json) => GraphPort(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    dataType: json['dataType'] as String? ?? 'any',
    direction: GraphPortDirection.values.firstWhere(
      (d) => d.name == json['direction'],
      orElse: () => GraphPortDirection.input,
    ),
  );
}

/// Node in a [StudioGraphModel].
final class GraphNode {
  final String id;
  final String typeId;
  String title;
  double x;
  double y;
  final List<GraphPort> ports;
  final Map<String, Object?> properties;

  GraphNode({
    required this.id,
    required this.typeId,
    required this.title,
    this.x = 0.0,
    this.y = 0.0,
    this.ports = const [],
    Map<String, Object?>? properties,
  }) : properties = properties != null ? Map.of(properties) : {};

  GraphPort? portById(String portId) {
    for (final p in ports) {
      if (p.id == portId) return p;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'typeId': typeId,
    'title': title,
    'x': x,
    'y': y,
    'ports': [for (final p in ports) p.toJson()],
    'properties': properties,
  };

  factory GraphNode.fromJson(Map<String, Object?> json) => GraphNode(
    id: json['id'] as String,
    typeId: json['typeId'] as String,
    title: json['title'] as String? ?? '',
    x: (json['x'] as num?)?.toDouble() ?? 0.0,
    y: (json['y'] as num?)?.toDouble() ?? 0.0,
    ports: [
      for (final p in (json['ports'] as List?) ?? const [])
        GraphPort.fromJson((p as Map).cast<String, Object?>()),
    ],
    properties: ((json['properties'] as Map?) ?? const {})
        .cast<String, Object?>(),
  );
}

/// Directed edge connecting an output port to an input port.
final class GraphEdge {
  final String id;
  final String fromNodeId;
  final String fromPortId;
  final String toNodeId;
  final String toPortId;

  const GraphEdge({
    required this.id,
    required this.fromNodeId,
    required this.fromPortId,
    required this.toNodeId,
    required this.toPortId,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'fromNodeId': fromNodeId,
    'fromPortId': fromPortId,
    'toNodeId': toNodeId,
    'toPortId': toPortId,
  };

  factory GraphEdge.fromJson(Map<String, Object?> json) => GraphEdge(
    id: json['id'] as String,
    fromNodeId: json['fromNodeId'] as String,
    fromPortId: json['fromPortId'] as String,
    toNodeId: json['toNodeId'] as String,
    toPortId: json['toPortId'] as String,
  );
}

/// Shared pure-Dart Node-Graph document with typed port validation, auto-layout,
/// and snapshot undo/redo (`[S7-0]`).
final class StudioGraphModel {
  final String schemaId;
  final Map<String, GraphNode> _nodes = {};
  final List<GraphEdge> _edges = [];
  final List<Map<String, Object?>> _undoStack = [];
  final List<Map<String, Object?>> _redoStack = [];

  StudioGraphModel({required this.schemaId});

  List<GraphNode> get nodes => List.unmodifiable(_nodes.values);
  List<GraphEdge> get edges => List.unmodifiable(_edges);
  GraphNode? nodeById(String id) => _nodes[id];

  void _pushUndo() {
    _undoStack.add(toJson());
    _redoStack.clear();
  }

  void addNode(GraphNode node) {
    _pushUndo();
    _nodes[node.id] = node;
  }

  bool removeNode(String nodeId) {
    if (!_nodes.containsKey(nodeId)) return false;
    _pushUndo();
    _nodes.remove(nodeId);
    _edges.removeWhere((e) => e.fromNodeId == nodeId || e.toNodeId == nodeId);
    return true;
  }

  /// Connects [fromNodeId].[fromPortId] -> [toNodeId].[toPortId], validating
  /// direction and type compatibility (`any` matches any type).
  bool connect({
    required String edgeId,
    required String fromNodeId,
    required String fromPortId,
    required String toNodeId,
    required String toPortId,
  }) {
    if (fromNodeId == toNodeId) return false;
    final fromNode = _nodes[fromNodeId];
    final toNode = _nodes[toNodeId];
    if (fromNode == null || toNode == null) return false;
    final fromPort = fromNode.portById(fromPortId);
    final toPort = toNode.portById(toPortId);
    if (fromPort == null || toPort == null) return false;
    if (fromPort.direction != GraphPortDirection.output ||
        toPort.direction != GraphPortDirection.input) {
      return false;
    }
    if (fromPort.dataType != 'any' &&
        toPort.dataType != 'any' &&
        fromPort.dataType != toPort.dataType) {
      return false;
    }
    _pushUndo();
    _edges.add(
      GraphEdge(
        id: edgeId,
        fromNodeId: fromNodeId,
        fromPortId: fromPortId,
        toNodeId: toNodeId,
        toPortId: toPortId,
      ),
    );
    return true;
  }

  /// Simple deterministic layered left-to-right auto-layout.
  void autoLayout({double columnSpacing = 220.0, double rowSpacing = 120.0}) {
    final ordered = _nodes.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final depth = <String, int>{for (final n in ordered) n.id: 0};
    for (var pass = 0; pass < ordered.length; pass++) {
      for (final e in _edges) {
        final nextD = (depth[e.fromNodeId] ?? 0) + 1;
        if (nextD > (depth[e.toNodeId] ?? 0)) {
          depth[e.toNodeId] = nextD;
        }
      }
    }
    final byCol = <int, List<GraphNode>>{};
    for (final n in ordered) {
      byCol.putIfAbsent(depth[n.id] ?? 0, () => []).add(n);
    }
    for (final entry in byCol.entries) {
      for (var r = 0; r < entry.value.length; r++) {
        entry.value[r].x = entry.key * columnSpacing;
        entry.value[r].y = r * rowSpacing;
      }
    }
  }

  bool undo() {
    if (_undoStack.isEmpty) return false;
    _redoStack.add(toJson());
    _loadSnapshot(_undoStack.removeLast());
    return true;
  }

  bool redo() {
    if (_redoStack.isEmpty) return false;
    _undoStack.add(toJson());
    _loadSnapshot(_redoStack.removeLast());
    return true;
  }

  Map<String, Object?> toJson() => {
    'schemaId': schemaId,
    'nodes': [for (final n in _nodes.values) n.toJson()],
    'edges': [for (final e in _edges) e.toJson()],
  };

  void _loadSnapshot(Map<String, Object?> json) {
    _nodes.clear();
    _edges.clear();
    for (final raw in (json['nodes'] as List?) ?? const []) {
      final n = GraphNode.fromJson((raw as Map).cast<String, Object?>());
      _nodes[n.id] = n;
    }
    for (final raw in (json['edges'] as List?) ?? const []) {
      _edges.add(GraphEdge.fromJson((raw as Map).cast<String, Object?>()));
    }
  }

  factory StudioGraphModel.fromJson(Map<String, Object?> json) {
    final g = StudioGraphModel(
      schemaId: json['schemaId'] as String? ?? 'graph',
    );
    g._loadSnapshot(json);
    return g;
  }
}
