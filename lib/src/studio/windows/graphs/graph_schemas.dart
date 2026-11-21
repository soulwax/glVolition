/// S7-B: Unified Multi-Schema Graph Editors (`voxgraph`, `voxflow`, `voxtalk`,
/// `voxhtn`, `voxcircuit`, `voxrule`) with live play-mode debugger state.
library;

import '../../graph/graph_model.dart';

/// Supported graph editor schemas built on the shared [StudioGraphModel].
enum StudioGraphSchemaKind {
  flowGraph('voxflow'),
  dialogue('voxtalk'),
  htn('voxhtn'),
  logicCircuit('voxcircuit'),
  ruleGraph('voxrule');

  final String modulePackage;
  const StudioGraphSchemaKind(this.modulePackage);
}

/// Live play-mode debugger state for any graph schema (active node, live port
/// values, and breakpoints, `[S7-B]`).
final class GraphDebuggerState {
  String? activeNodeId;
  final Set<String> breakpoints = {};
  final Map<String, Object?> livePortValues = {};

  bool toggleBreakpoint(String nodeId) {
    if (breakpoints.contains(nodeId)) {
      breakpoints.remove(nodeId);
      return false;
    }
    breakpoints.add(nodeId);
    return true;
  }

  bool isPausedAtBreakpoint() =>
      activeNodeId != null && breakpoints.contains(activeNodeId);
}

/// Factory creating starter graphs for every S7-B schema (`[S7-B]`).
abstract final class StudioGraphSchemaFactory {
  static StudioGraphModel createTemplate(StudioGraphSchemaKind kind) {
    final g = StudioGraphModel(schemaId: kind.name);
    g.addNode(
      GraphNode(
        id: 'start',
        typeId: '${kind.name}.entry',
        title: 'Entry',
        ports: const [
          GraphPort(
            id: 'out',
            label: 'Out',
            dataType: 'exec',
            direction: GraphPortDirection.output,
          ),
        ],
      ),
    );
    g.addNode(
      GraphNode(
        id: 'action',
        typeId: '${kind.name}.node',
        title: 'Action',
        ports: const [
          GraphPort(
            id: 'in',
            label: 'In',
            dataType: 'exec',
            direction: GraphPortDirection.input,
          ),
        ],
      ),
    );
    g.connect(
      edgeId: 'e0',
      fromNodeId: 'start',
      fromPortId: 'out',
      toNodeId: 'action',
      toPortId: 'in',
    );
    g.autoLayout();
    return g;
  }
}
