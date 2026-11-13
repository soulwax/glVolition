part of '../../engine.dart';

/// Registers glVolition [GameObject] & [TransformComponent] binding nodes onto a [flow.FlowNodeRegistry].
abstract final class EngineFlowNodes {
  static flow.FlowNodeRegistry createRegistry() {
    final reg = flow.FlowNodeRegistry();
    registerInto(reg);
    return reg;
  }

  static void registerInto(flow.FlowNodeRegistry registry) {
    if (registry.contains('engine.getPosition')) return;
    registry.registerAll([
      flow.FlowNodeDef(
        typeId: 'engine.getPosition',
        title: 'Get Position',
        category: 'Engine',
        inputs: const [],
        outputs: const [
          flow.PinDef.output('position', 'Position', flow.PinType.vec3Val),
        ],
        evaluate: (ctx) {
          final hostObj = ctx.userContext;
          if (hostObj is GameObject) {
            final p = hostObj.transform.position;
            ctx.writeOutput('position', flow.FlowVec3(p.x, p.y, p.z));
          } else {
            ctx.writeOutput('position', flow.FlowVec3.zero);
          }
        },
      ),
      flow.FlowNodeDef(
        typeId: 'engine.setPosition',
        title: 'Set Position',
        category: 'Engine',
        isPure: false,
        inputs: const [
          flow.PinDef.execIn(),
          flow.PinDef.input('position', 'Position', flow.PinType.vec3Val),
        ],
        outputs: const [flow.PinDef.execOut()],
        execute: (ctx, _) {
          final hostObj = ctx.userContext;
          if (hostObj is GameObject) {
            final v = ctx.readVec3('position');
            hostObj.transform.position = Vec3(v.x, v.y, v.z);
          }
          ctx.invokeExec('out');
        },
      ),
      flow.FlowNodeDef(
        typeId: 'engine.translate',
        title: 'Translate',
        category: 'Engine',
        isPure: false,
        inputs: const [
          flow.PinDef.execIn(),
          flow.PinDef.input('delta', 'Delta', flow.PinType.vec3Val),
        ],
        outputs: const [
          flow.PinDef.execOut(),
          flow.PinDef.output('position', 'Position', flow.PinType.vec3Val),
        ],
        execute: (ctx, _) {
          final hostObj = ctx.userContext;
          if (hostObj is GameObject) {
            final d = ctx.readVec3('delta');
            hostObj.transform.translate(Vec3(d.x, d.y, d.z));
            final p = hostObj.transform.position;
            ctx.writeOutput('position', flow.FlowVec3(p.x, p.y, p.z));
          }
          ctx.invokeExec('out');
        },
      ),
      flow.FlowNodeDef(
        typeId: 'engine.rotateY',
        title: 'Rotate Y',
        category: 'Engine',
        isPure: false,
        inputs: const [
          flow.PinDef.execIn(),
          flow.PinDef.input(
            'radians',
            'Radians',
            flow.PinType.floatVal,
            defaultValue: 0.0,
          ),
        ],
        outputs: const [flow.PinDef.execOut()],
        execute: (ctx, _) {
          final hostObj = ctx.userContext;
          if (hostObj is GameObject) {
            hostObj.transform.rotateY(ctx.readFloat('radians'));
          }
          ctx.invokeExec('out');
        },
      ),
      flow.FlowNodeDef(
        typeId: 'engine.setActive',
        title: 'Set Active',
        category: 'Engine',
        isPure: false,
        inputs: const [
          flow.PinDef.execIn(),
          flow.PinDef.input(
            'active',
            'Active',
            flow.PinType.boolVal,
            defaultValue: true,
          ),
        ],
        outputs: const [flow.PinDef.execOut()],
        execute: (ctx, _) {
          final hostObj = ctx.userContext;
          if (hostObj is GameObject) {
            hostObj.setActive(ctx.readBool('active'));
          }
          ctx.invokeExec('out');
        },
      ),
    ]);
  }
}

/// Executes a visual [flow.FlowGraph] bound to the owning [GameObject].
final class FlowGraphComponent extends Behaviour {
  final flow.FlowGraph graph;
  bool autoStart;
  bool autoUpdate;

  flow.FlowRunner? _runner;
  final List<void Function(String signal, Object? payload)> _signalListeners =
      [];
  void Function(String message)? onLog;

  FlowGraphComponent(
    this.graph, {
    this.autoStart = true,
    this.autoUpdate = true,
    void Function(String signal, Object? payload)? onSignal,
    this.onLog,
  }) {
    EngineFlowNodes.registerInto(graph.registry);
    if (onSignal != null) {
      _signalListeners.add(onSignal);
    }
  }

  flow.FlowRunner get runner => _runner ??= flow.FlowRunner(
    graph,
    userContext: isAttached ? gameObject : null,
    onLog: (msg) {
      onLog?.call(msg);
      voxlog.info('[FlowGraph:${graph.name}] $msg');
    },
    onSignal: (sig, payload) {
      for (final l in List.of(_signalListeners)) {
        l(sig, payload);
      }
    },
  );

  flow.FlowBlackboard get blackboard => graph.blackboard;

  void addSignalListener(
    void Function(String signal, Object? payload) listener,
  ) => _signalListeners.add(listener);

  void removeSignalListener(
    void Function(String signal, Object? payload) listener,
  ) => _signalListeners.remove(listener);

  void setVariable(String key, Object? value) =>
      graph.blackboard.set(key, value);
  Object? getVariable(String key) => graph.blackboard.get(key);

  Object? evaluateOutput(String nodeId, String outputPinId) =>
      runner.evaluateOutput(
        nodeId,
        outputPinId,
        dt: isAttached ? time.deltaTime : 0.0,
      );

  void triggerEvent(String eventName, {Object? payload}) => runner.triggerEvent(
    eventName,
    payload: payload,
    dt: isAttached ? time.deltaTime : 0.0,
  );

  @override
  void awake() {
    EngineFlowNodes.registerInto(graph.registry);
    _runner = flow.FlowRunner(
      graph,
      userContext: gameObject,
      onLog: (msg) {
        onLog?.call(msg);
        voxlog.info('[FlowGraph:${graph.name}] $msg');
      },
      onSignal: (sig, payload) {
        for (final l in List.of(_signalListeners)) {
          l(sig, payload);
        }
      },
    );
  }

  @override
  void start() {
    if (autoStart) {
      runner.triggerStart();
    }
  }

  @override
  void update() {
    if (autoUpdate) {
      runner.step(time.deltaTime);
    }
  }
}

/// Persistent interactive viewport & drag state for [FlowGraphUI.render].
final class FlowGraphUiState {
  double panX;
  double panY;
  String? selectedNodeId;
  String? draggingNodeId;
  double dragOffsetX = 0.0;
  double dragOffsetY = 0.0;
  String? linkingFromNodeId;
  String? linkingFromPinId;
  bool isPanning = false;

  FlowGraphUiState({this.panX = 0.0, this.panY = 0.0});
}

/// Immediate-mode interactive Blueprint/Dataflow node graph editor rendered via `voxui`.
final class FlowGraphUI {
  static const double _nodeWidth = 170.0;
  static const double _headerHeight = 22.0;
  static const double _rowHeight = 18.0;
  static const double _pinRadius = 4.5;

  static VoxColor _pinColor(flow.PinType type) => switch (type) {
    flow.PinType.exec => VoxColor.white,
    flow.PinType.boolVal => VoxColor.red,
    flow.PinType.intVal => VoxColor.cyan,
    flow.PinType.floatVal => VoxColor.green,
    flow.PinType.vec2Val || flow.PinType.vec3Val => VoxColor.yellow,
    flow.PinType.stringVal => const VoxColor(225, 110, 235, 255),
    flow.PinType.colorVal => const VoxColor(255, 155, 70, 255),
    flow.PinType.any => VoxColor.lightGray,
  };

  static void render(
    VoxUiContext ui,
    flow.FlowGraph graph, {
    FlowGraphUiState? state,
    flow.FlowRunner? runner,
    String title = 'FlowGraph Editor',
    double x = 20.0,
    double y = 20.0,
    double width = 620.0,
    double height = 400.0,
  }) {
    final uiState = state ?? FlowGraphUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final canvasX = x + 6.0;
    final canvasY = y + ui.style.titleBarHeight + 4.0;
    final canvasW = width - 12.0;
    final canvasH = height - ui.style.titleBarHeight - 10.0;
    final canvasRect = VoxRect(canvasX, canvasY, canvasW, canvasH);
    final dl = ui.drawList;
    final inp = ui.input;

    dl.pushClip(canvasRect);
    dl.addRectFilled(
      canvasX,
      canvasY,
      canvasW,
      canvasH,
      const VoxColor(18, 20, 26, 245),
    );

    // Subtle canvas grid lines
    const gridSpacing = 32.0;
    final offX = uiState.panX % gridSpacing;
    final offY = uiState.panY % gridSpacing;
    for (double gx = canvasX + offX; gx < canvasRect.right; gx += gridSpacing) {
      dl.addLine(
        gx,
        canvasY,
        gx,
        canvasRect.bottom,
        const VoxColor(30, 34, 42, 200),
      );
    }
    for (
      double gy = canvasY + offY;
      gy < canvasRect.bottom;
      gy += gridSpacing
    ) {
      dl.addLine(
        canvasX,
        gy,
        canvasRect.right,
        gy,
        const VoxColor(30, 34, 42, 200),
      );
    }

    // Precompute screen positions of pins and node rectangles
    final pinPositions = <String, (double x, double y, flow.PinDef def)>{};
    final nodeRects = <String, VoxRect>{};

    for (final node in graph.nodes.values) {
      final def = graph.registry.get(node.typeId);
      if (def == null) continue;
      final rows = math.max(def.inputs.length, def.outputs.length);
      final bodyH = math.max(1, rows) * _rowHeight + 10.0;
      final nx = canvasX + uiState.panX + node.x;
      final ny = canvasY + uiState.panY + node.y;
      final rect = VoxRect(nx, ny, _nodeWidth, _headerHeight + bodyH);
      nodeRects[node.id] = rect;

      for (int i = 0; i < def.inputs.length; i++) {
        final px = nx + 10.0;
        final py = ny + _headerHeight + 12.0 + i * _rowHeight;
        pinPositions['${node.id}:in:${def.inputs[i].id}'] = (
          px,
          py,
          def.inputs[i],
        );
      }
      for (int i = 0; i < def.outputs.length; i++) {
        final px = nx + _nodeWidth - 10.0;
        final py = ny + _headerHeight + 12.0 + i * _rowHeight;
        pinPositions['${node.id}:out:${def.outputs[i].id}'] = (
          px,
          py,
          def.outputs[i],
        );
      }
    }

    // Handle pin linking or node dragging when cursor is inside canvas
    if (canvasRect.contains(inp.mouseX, inp.mouseY)) {
      if (inp.wasMouseClicked) {
        String? clickedOutPinNode;
        String? clickedOutPinId;
        for (final entry in pinPositions.entries) {
          final (px, py, pin) = entry.value;
          if (pin.direction == flow.PinDirection.output) {
            final dx = inp.mouseX - px;
            final dy = inp.mouseY - py;
            if (dx * dx + dy * dy <= 64.0) {
              final parts = entry.key.split(':out:');
              clickedOutPinNode = parts[0];
              clickedOutPinId = parts[1];
              break;
            }
          }
        }

        if (clickedOutPinNode != null) {
          uiState.linkingFromNodeId = clickedOutPinNode;
          uiState.linkingFromPinId = clickedOutPinId;
        } else {
          String? hitNodeId;
          for (final e in nodeRects.entries) {
            if (e.value.contains(inp.mouseX, inp.mouseY)) {
              hitNodeId = e.key;
            }
          }
          if (hitNodeId != null) {
            uiState.selectedNodeId = hitNodeId;
            uiState.draggingNodeId = hitNodeId;
            final r = nodeRects[hitNodeId]!;
            uiState.dragOffsetX = inp.mouseX - r.x;
            uiState.dragOffsetY = inp.mouseY - r.y;
          } else {
            uiState.selectedNodeId = null;
            uiState.isPanning = true;
          }
        }
      }

      if (inp.isMouseDown) {
        if (uiState.draggingNodeId != null) {
          final dragged = graph.getNode(uiState.draggingNodeId!);
          if (dragged != null) {
            dragged.x =
                inp.mouseX - uiState.dragOffsetX - canvasX - uiState.panX;
            dragged.y =
                inp.mouseY - uiState.dragOffsetY - canvasY - uiState.panY;
          }
        } else if (uiState.isPanning) {
          uiState.panX += inp.mouseDeltaX;
          uiState.panY += inp.mouseDeltaY;
        }
      }

      if (inp.wasMouseReleased) {
        if (uiState.linkingFromNodeId != null &&
            uiState.linkingFromPinId != null) {
          for (final entry in pinPositions.entries) {
            final (px, py, pin) = entry.value;
            if (pin.direction == flow.PinDirection.input) {
              final dx = inp.mouseX - px;
              final dy = inp.mouseY - py;
              if (dx * dx + dy * dy <= 81.0) {
                final parts = entry.key.split(':in:');
                graph.tryConnect(
                  uiState.linkingFromNodeId!,
                  uiState.linkingFromPinId!,
                  parts[0],
                  parts[1],
                );
                break;
              }
            }
          }
        }
        uiState.linkingFromNodeId = null;
        uiState.linkingFromPinId = null;
        uiState.draggingNodeId = null;
        uiState.isPanning = false;
      }
    }

    // Draw existing bezier wire links
    for (final link in graph.links) {
      final fromPos = pinPositions['${link.fromNodeId}:out:${link.fromPinId}'];
      final toPos = pinPositions['${link.toNodeId}:in:${link.toPinId}'];
      if (fromPos != null && toPos != null) {
        final col = _pinColor(fromPos.$3.type).withAlpha(220);
        _drawBezierWire(
          dl,
          fromPos.$1,
          fromPos.$2,
          toPos.$1,
          toPos.$2,
          col,
          thickness: fromPos.$3.type == flow.PinType.exec ? 2.4 : 1.7,
        );
      }
    }

    // Draw live dragged wire preview
    if (uiState.linkingFromNodeId != null && uiState.linkingFromPinId != null) {
      final fromPos =
          pinPositions['${uiState.linkingFromNodeId}:out:${uiState.linkingFromPinId}'];
      if (fromPos != null) {
        _drawBezierWire(
          dl,
          fromPos.$1,
          fromPos.$2,
          inp.mouseX,
          inp.mouseY,
          VoxColor.yellow,
          thickness: 2.0,
        );
      }
    }

    // Draw node cards & pins
    final activeSet = runner?.trace.executedNodeIds.toSet() ?? const <String>{};
    for (final node in graph.nodes.values) {
      final def = graph.registry.get(node.typeId);
      final rect = nodeRects[node.id];
      if (def == null || rect == null) continue;

      final isSelected = uiState.selectedNodeId == node.id;
      final wasExecuted = activeSet.contains(node.id);

      dl.addRectFilled(
        rect.x,
        rect.y,
        rect.width,
        rect.height,
        const VoxColor(30, 34, 44, 240),
        cornerRadius: 5.0,
      );

      final headerCol = def.isEventEntry
          ? const VoxColor(150, 42, 42, 255)
          : (def.isPure
                ? const VoxColor(38, 92, 68, 255)
                : const VoxColor(45, 76, 130, 255));
      dl.addRectFilled(
        rect.x,
        rect.y,
        _nodeWidth,
        _headerHeight,
        headerCol,
        cornerRadius: 4.0,
      );

      final borderCol = isSelected
          ? VoxColor.yellow
          : (wasExecuted ? VoxColor.cyan : const VoxColor(70, 78, 96, 255));
      dl.addRectOutline(
        rect.x,
        rect.y,
        rect.width,
        rect.height,
        borderCol,
        thickness: isSelected ? 2.0 : 1.0,
        cornerRadius: 5.0,
      );

      dl.addText(
        node.titleOverride ?? def.title,
        rect.x + 8.0,
        rect.y + 4.0,
        color: VoxColor.white,
        size: 12.0,
      );

      for (final p in def.inputs) {
        final pos = pinPositions['${node.id}:in:${p.id}']!;
        final col = _pinColor(p.type);
        dl.addCircleFilled(pos.$1, pos.$2, _pinRadius, col);
        dl.addText(
          p.label,
          pos.$1 + 8.0,
          pos.$2 - 6.0,
          color: VoxColor.lightGray,
          size: 11.0,
        );
      }

      for (final p in def.outputs) {
        final pos = pinPositions['${node.id}:out:${p.id}']!;
        final col = _pinColor(p.type);
        dl.addCircleFilled(pos.$1, pos.$2, _pinRadius, col);
        final live = runner?.trace.lastPinValues['${node.id}.${p.id}'];
        final labelStr = live != null && p.type != flow.PinType.exec
            ? '${p.label}: $live'
            : p.label;
        dl.addText(
          labelStr,
          pos.$1 - 58.0,
          pos.$2 - 6.0,
          color: VoxColor.white,
          size: 11.0,
        );
      }
    }

    dl.popClip();
    ui.endWindow();
  }

  static void _drawBezierWire(
    DrawList dl,
    double x1,
    double y1,
    double x2,
    double y2,
    VoxColor color, {
    double thickness = 1.8,
  }) {
    final dx = math.max(40.0, (x2 - x1).abs() * 0.5);
    final cx1 = x1 + dx;
    final cy1 = y1;
    final cx2 = x2 - dx;
    final cy2 = y2;

    const segments = 10;
    var px = x1;
    var py = y1;
    for (int i = 1; i <= segments; i++) {
      final t = i / segments;
      final inv = 1.0 - t;
      final nx =
          inv * inv * inv * x1 +
          3 * inv * inv * t * cx1 +
          3 * inv * t * t * cx2 +
          t * t * t * x2;
      final ny =
          inv * inv * inv * y1 +
          3 * inv * inv * t * cy1 +
          3 * inv * t * t * cy2 +
          t * t * t * y2;
      dl.addLine(px, py, nx, ny, color, thickness: thickness);
      px = nx;
      py = ny;
    }
  }
}
