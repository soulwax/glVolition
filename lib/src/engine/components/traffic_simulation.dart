part of '../../engine.dart';

/// Timed multi-phase traffic signal controller synced to sibling [Light] or [MeshRenderer] (E65-2).
final class TrafficSignalComponent extends Behaviour {
  String signalId;
  String activeGroupName;
  double greenDuration;
  double yellowDuration;
  double allRedDuration;
  bool paused;

  traffic.IntersectionSignalController? _controller;

  TrafficSignalComponent({
    this.signalId = 'sig_main',
    this.activeGroupName = 'ns',
    this.greenDuration = 10.0,
    this.yellowDuration = 2.5,
    this.allRedDuration = 1.0,
    this.paused = false,
    List<traffic.TrafficPhaseSpec>? customPhases,
  }) {
    if (customPhases != null && customPhases.isNotEmpty) {
      _controller = traffic.IntersectionSignalController(
        id: signalId,
        phases: customPhases,
      );
    }
  }

  static final spec = ComponentSpec<TrafficSignalComponent>(
    'TrafficSignalComponent',
    TrafficSignalComponent.new,
    [
      Field.text('signalId', (s) => s.signalId, (s, v) => s.signalId = v),
      Field.text(
        'activeGroupName',
        (s) => s.activeGroupName,
        (s, v) => s.activeGroupName = v,
      ),
      Field.number(
        'greenDuration',
        (s) => s.greenDuration,
        (s, v) => s.greenDuration = v,
      ),
      Field.number(
        'yellowDuration',
        (s) => s.yellowDuration,
        (s, v) => s.yellowDuration = v,
      ),
      Field.number(
        'allRedDuration',
        (s) => s.allRedDuration,
        (s, v) => s.allRedDuration = v,
      ),
      Field.boolean('paused', (s) => s.paused, (s, v) => s.paused = v),
    ],
  );

  traffic.IntersectionSignalController get controller =>
      _controller ??= traffic.IntersectionSignalController(
        id: signalId,
        phases: [
          traffic.TrafficPhaseSpec(
            id: '${signalId}_p0',
            name: 'N/S Green',
            greenGroupIds: const {'ns'},
            greenDurationSeconds: greenDuration,
            yellowDurationSeconds: yellowDuration,
            allRedClearanceSeconds: allRedDuration,
          ),
          traffic.TrafficPhaseSpec(
            id: '${signalId}_p1',
            name: 'E/W Green',
            greenGroupIds: const {'ew'},
            greenDurationSeconds: greenDuration,
            yellowDurationSeconds: yellowDuration,
            allRedClearanceSeconds: allRedDuration,
          ),
        ],
      );

  traffic.TrafficSignalColor get currentColor =>
      controller.colorForGroup(activeGroupName);

  void forceNextPhase() {
    controller.forceNextPhase();
    _syncLampVisual();
  }

  void _syncLampVisual() {
    if (!isAttached) return;
    final color = switch (currentColor) {
      traffic.TrafficSignalColor.green => const LinearColor(0.15, 0.95, 0.25),
      traffic.TrafficSignalColor.yellow => const LinearColor(0.95, 0.8, 0.1),
      traffic.TrafficSignalColor.red => const LinearColor(0.95, 0.15, 0.15),
    };
    gameObject.getComponent<Light>()?.color = color;
    gameObject.getComponent<MeshRenderer>()?.setTint(color);
  }

  @override
  void update() {
    if (!paused && time.deltaTime > 0.0) {
      controller.tick(time.deltaTime);
    }
    _syncLampVisual();
  }
}

/// Autonomous lane-graph vehicle traffic simulator driving visual [GameObject]s (E65-2).
final class TrafficNetworkComponent extends Behaviour {
  double timeScale;
  bool paused;
  bool spawnVisualVehicles;

  final traffic.TrafficLaneGraph graph = traffic.TrafficLaneGraph();
  traffic.TrafficNetworkSolver? _solver;
  final Map<String, GameObject> _vehicleObjects = {};

  TrafficNetworkComponent({
    this.timeScale = 1.0,
    this.paused = false,
    this.spawnVisualVehicles = true,
  });

  static final spec = ComponentSpec<TrafficNetworkComponent>(
    'TrafficNetworkComponent',
    TrafficNetworkComponent.new,
    [
      Field.number('timeScale', (t) => t.timeScale, (t, v) => t.timeScale = v),
      Field.boolean('paused', (t) => t.paused, (t, v) => t.paused = v),
      Field.boolean(
        'spawnVisualVehicles',
        (t) => t.spawnVisualVehicles,
        (t, v) => t.spawnVisualVehicles = v,
      ),
    ],
  );

  traffic.TrafficNetworkSolver get solver =>
      _solver ??= traffic.TrafficNetworkSolver(graph: graph);

  int get vehicleCount => solver.vehicles.length;

  int get stoppedCount => solver.vehicles.where((v) => v.speedMps < 0.4).length;

  double get averageSpeedMps {
    if (solver.vehicles.isEmpty) return 0.0;
    var sum = 0.0;
    for (final v in solver.vehicles) {
      sum += v.speedMps;
    }
    return sum / solver.vehicles.length;
  }

  void attachSignalComponent(TrafficSignalComponent sigComp) {
    solver.addSignalController(sigComp.controller);
  }

  void addNode(traffic.TrafficLaneNode node) => graph.addNode(node);

  void addEdge(traffic.TrafficLaneEdge edge) => graph.addEdge(edge);

  traffic.TrafficVehicleAgent spawnVehicle(
    String id, {
    required String edgeId,
    double distanceAlongEdge = 0.0,
    double initialSpeedMps = 0.0,
    traffic.TrafficVehicleSpec spec = const traffic.TrafficVehicleSpec(),
    Iterable<String> routeEdgeIds = const [],
    LinearColor tintColor = const LinearColor(0.25, 0.55, 0.9),
  }) {
    final agent = solver.spawnVehicle(
      id,
      edgeId: edgeId,
      distanceAlongEdge: distanceAlongEdge,
      initialSpeedMps: initialSpeedMps,
      spec: spec,
      routeEdgeIds: routeEdgeIds,
    );
    if (spawnVisualVehicles && isAttached && !_vehicleObjects.containsKey(id)) {
      final go = scene.createGameObject(
        'TrafficCar_$id',
        position: Vec3(
          agent.worldPosition.x,
          agent.worldPosition.y + 0.5,
          agent.worldPosition.z,
        ),
        rotation: lookRotation(
          Vec3(
            agent.worldForward.x,
            agent.worldForward.y,
            agent.worldForward.z,
          ),
          Vec3.unitY,
        ),
        components: [
          MeshRenderer(
            meshData: Primitives.cube(size: 1.0),
            tintColor: tintColor,
          ),
          BoxCollider(size: Vec3(1.8, 1.0, agent.spec.lengthMeters)),
        ],
      );
      go.transform.localStretch = Vec3(1.8, 1.0, agent.spec.lengthMeters);
      _vehicleObjects[id] = go;
    }
    return agent;
  }

  traffic.TrafficVehicleAgent? vehicleAgent(String id) {
    for (final v in solver.vehicles) {
      if (v.id == id) return v;
    }
    return null;
  }

  GameObject? vehicleObject(String id) => _vehicleObjects[id];

  Vec3 vehiclePosition(String id) {
    final v = vehicleAgent(id);
    if (v == null) return Vec3.zero;
    return Vec3(v.worldPosition.x, v.worldPosition.y, v.worldPosition.z);
  }

  void stepTraffic(double dt) {
    if (dt <= 0.0) return;
    if (isAttached) {
      for (final sc in scene.findObjectsOfType<TrafficSignalComponent>()) {
        solver.signals.putIfAbsent(sc.controller.id, () => sc.controller);
      }
    }
    solver.step(dt);
    _syncVehicleObjects();
  }

  void _syncVehicleObjects() {
    for (final v in solver.vehicles) {
      final go = _vehicleObjects[v.id];
      if (go == null) continue;
      go.transform.position = Vec3(
        v.worldPosition.x,
        v.worldPosition.y + 0.5,
        v.worldPosition.z,
      );
      final fwd = Vec3(v.worldForward.x, v.worldForward.y, v.worldForward.z);
      if (fwd.lengthSquared > 1e-6) {
        go.transform.rotation = lookRotation(fwd.normalized, Vec3.unitY);
      }
    }
  }

  @override
  void update() {
    if (paused) return;
    final dt = dtScaled;
    if (dt <= 0.0) return;
    final s = solver;
    final componentSignalIds = <String>{};
    if (isAttached) {
      for (final sc in scene.findObjectsOfType<TrafficSignalComponent>()) {
        s.signals.putIfAbsent(sc.controller.id, () => sc.controller);
        componentSignalIds.add(sc.controller.id);
      }
    }
    // Tick signals owned directly by solver without duplicating active TrafficSignalComponents.
    for (final entry in s.signals.entries) {
      if (!componentSignalIds.contains(entry.key)) {
        entry.value.tick(dt);
      }
    }
    s.stepVehicles(dt);
    _syncVehicleObjects();
  }

  double get dtScaled => time.deltaTime * math.max(0.0, timeScale);
}

/// Persistent UI interaction state for [TrafficMonitorUI.render].
final class TrafficMonitorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` traffic flow, signal phase & congestion monitor (E65-2).
final class TrafficMonitorUI {
  static bool _drawButton(
    VoxUiContext ui,
    TrafficMonitorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked =
        hovered && state.activeButtonId == id && inp.wasMouseReleased;
    if (inp.wasMouseReleased && state.activeButtonId == id) {
      state.activeButtonId = null;
    }

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      bg,
      cornerRadius: ui.style.frameRounding,
    );
    dl.addRectOutline(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      ui.style.windowBorder,
      cornerRadius: ui.style.frameRounding,
    );
    final textW = label.length * (ui.style.fontSize * 0.6);
    dl.addText(
      label,
      rect.x + math.max(4.0, (rect.width - textW) * 0.5),
      rect.y + (rect.height - ui.style.fontSize) * 0.5,
      color: ui.style.text,
      size: ui.style.fontSize,
    );
    return clicked;
  }

  static void render(
    VoxUiContext ui,
    TrafficNetworkComponent network, {
    TrafficSignalComponent? signal,
    TrafficMonitorUiState? state,
    String title = 'Traffic & Signals',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? TrafficMonitorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final sigCtrl =
        signal?.controller ??
        (network.solver.signals.isNotEmpty
            ? network.solver.signals.values.first
            : null);
    final phaseLabel = sigCtrl?.currentPhase?.name ?? 'None';
    final sigGroup = signal?.activeGroupName ?? 'ns';
    final lamp =
        sigCtrl?.colorForGroup(sigGroup) ?? traffic.TrafficSignalColor.green;

    ui.labelValue(
      'Vehicles / Stopped',
      '${network.vehicleCount} / ${network.stoppedCount}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Avg Speed',
      '${network.averageSpeedMps.toStringAsFixed(1)} m/s',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Signal Phase',
      '$phaseLabel (${lamp.name.toUpperCase()})',
      valueColor: lamp == traffic.TrafficSignalColor.green
          ? VoxColor.green
          : (lamp == traffic.TrafficSignalColor.yellow
                ? VoxColor.yellow
                : VoxColor.red),
    );
    ui.labelValue(
      'Cycles / State',
      '${sigCtrl?.cycleCount ?? 0} / ${network.paused ? "PAUSED" : "LIVE"}',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final nextPhaseRect = VoxRect(x + pad, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'trf_phase', 'Next Phase', nextPhaseRect)) {
      if (signal != null) {
        signal.forceNextPhase();
      } else {
        sigCtrl?.forceNextPhase();
      }
    }

    final stepRect = VoxRect(nextPhaseRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'trf_step', 'Step +2s', stepRect)) {
      network.stepTraffic(2.0);
    }

    final pauseRect = VoxRect(stepRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'trf_pause',
      network.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      network.paused = !network.paused;
    }

    ui.endWindow();
  }
}
