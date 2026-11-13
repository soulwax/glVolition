/// AI behavior trees, FSMs, HTN planners, navigation, steering & traffic tests.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('E9 — StateMachine Transitions', () {
    test('StateMachine transitions between states and tracks stateTime', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final log = <String>[];
      final fsm = StateMachine<String>('idle')
        ..defineState(
          'idle',
          onEnter: () => log.add('enter:idle'),
          onExit: () => log.add('exit:idle'),
        )
        ..defineState(
          'alert',
          onEnter: () => log.add('enter:alert'),
          onUpdate: (dt) => log.add('update:alert:${dt.toStringAsFixed(2)}'),
        );

      engine.scene.createGameObject('Guard', components: [fsm]);
      engine.step(0.05);
      expect(fsm.currentState, 'idle');
      expect(fsm.stateTime, closeTo(0.05, 1e-5));
      expect(log, ['enter:idle']);

      fsm.transitionTo('alert');
      expect(fsm.previousState, 'idle');
      expect(fsm.currentState, 'alert');
      expect(fsm.stateTime, 0.0);

      engine.step(0.05);
      expect(fsm.stateTime, closeTo(0.05, 1e-5));
      expect(log, [
        'enter:idle',
        'exit:idle',
        'enter:alert',
        'update:alert:0.05',
      ]);
    });
  });

  group('E11 — NavGrid2D & NavAgent A* Pathfinding', () {
    test(
      'NavGrid2D A* routes around solid walls without corner-cutting and NavAgent reaches goal',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final grid = NavGrid2D(
          columns: 6,
          rows: 6,
          cellWidth: 1.0,
          cellHeight: 1.0,
        );
        // Vertical wall at col=2, rows 0..3
        for (var r = 0; r <= 3; r++) {
          grid.setWalkable(2, r, false);
        }

        final path = grid.findPath(const Vec2(0.5, 0.5), const Vec2(4.5, 0.5));
        expect(path, isNotEmpty);
        // Every waypoint must be on a walkable cell (never col==2 && row<=3)
        for (final wp in path) {
          final (c, r) = grid.worldToCell(wp.x, wp.y);
          expect(grid.isWalkable(c, r), isTrue);
        }

        final agent = NavAgent(grid: grid, speed: 10.0, stoppingDistance: 0.15);
        final go = engine.scene.createGameObject(
          'Runner',
          position: const Vec3(0.5, 0.5, 0),
          components: [agent],
        );
        expect(agent.setDestination(const Vec3(4.5, 0.5, 0)), isTrue);

        for (var i = 0; i < 60; i++) {
          engine.step(1 / 30);
        }

        expect(agent.hasPath, isFalse);
        expect(
          (go.transform.position - const Vec3(4.5, 0.5, 0)).length,
          lessThan(0.25),
        );
      },
    );
  });

  group('E20 — NavGrid2D Line-of-Sight & Raycast', () {
    test(
      'NavGrid2D hasLineOfSight and raycast verify straight-line traversability',
      () {
        // 10x10 nav grid
        final nav = NavGrid2D(
          columns: 10,
          rows: 10,
          cellWidth: 1.0,
          cellHeight: 1.0,
        );
        // Place a 1-cell pillar obstacle at (5, 5)
        nav.setWalkable(5, 5, false);

        // Line from (1, 5) to (8, 5) crosses (5, 5) => blocked
        final blockedStart = Vec2(1.5, 5.5);
        final blockedEnd = Vec2(8.5, 5.5);
        expect(nav.hasLineOfSight(blockedStart, blockedEnd), isFalse);

        final hit = nav.raycast(blockedStart, blockedEnd);
        expect(hit, isNotNull);
        expect(hit!.column, 5);
        expect(hit.row, 5);
        expect(hit.distance, greaterThan(0));

        // Line from (1, 2) to (8, 2) does not cross row 5 => clear
        final clearStart = Vec2(1.5, 2.5);
        final clearEnd = Vec2(8.5, 2.5);
        expect(nav.hasLineOfSight(clearStart, clearEnd), isTrue);
        expect(nav.raycast(clearStart, clearEnd), isNull);
      },
    );
  });

  group('E28 — AI Components (BehaviorTree & AiFsm / voxai)', () {
    test(
      'BehaviorTreeComponent and AiFsmComponent advance AI states in engine loop',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        var attackTicked = false;
        final tree = BehaviorTree(
          root: SequenceNode([
            ConditionNode((bb) => bb.get<int>('targetDistance') <= 5),
            ActionNode((bb) {
              attackTicked = true;
              return NodeStatus.success;
            }),
          ]),
        );
        tree.blackboard.set('targetDistance', 10);

        final go = engine.scene.createGameObject('Enemy');
        final btComp = go.addComponent(BehaviorTreeComponent(tree: tree));

        // Step 1: Distance = 10 -> condition fails, attackTicked is false
        engine.step(0.016);
        expect(attackTicked, isFalse);
        expect(btComp.lastStatus, equals(NodeStatus.failure));

        // Step 2: Distance = 3 -> condition passes, attackTicked is true
        btComp.blackboard.set('targetDistance', 3);
        engine.step(0.016);
        expect(attackTicked, isTrue);
        expect(btComp.lastStatus, equals(NodeStatus.success));

        // FSM Component test
        var patrolEntered = false;
        var alertEntered = false;

        final fsmComp = go.addComponent(
          AiFsmComponent<String>(initialState: 'patrol'),
        );
        fsmComp.addState(
          'patrol',
          LambdaState(onEnter: (_) => patrolEntered = true),
        );
        fsmComp.addState(
          'alert',
          LambdaState(onEnter: (_) => alertEntered = true),
        );
        fsmComp.addTransition(
          'patrol',
          'alert',
          (targetGo) => targetGo.transform.position.x > 10.0,
        );

        engine.step(0.016);
        expect(fsmComp.currentStateId, equals('patrol'));
        expect(patrolEntered, isTrue);
        expect(alertEntered, isFalse);

        // Move enemy beyond x = 10 -> triggers transition to alert
        go.transform.position = const Vec3(15, 0, 0);
        engine.step(0.016);
        expect(fsmComp.currentStateId, equals('alert'));
        expect(alertEntered, isTrue);
      },
    );
  });

  group('E30 — NavAgent2D & FlowField2D (voxpath)', () {
    test(
      'E30: NavAgent2D pathfinding, waypoint tracking, and arrival events with voxpath',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.time.maximumDeltaTime = 10.0;

        final grid = NavGrid.fromAscii(['.....', '.###.', '.....']);

        final agentGo = engine.scene.createGameObject('Minion');
        agentGo.transform.position = const Vec3(0.5, 0, 0.5);

        final agent = agentGo.addComponent(NavAgent2D(speed: 4.0, grid: grid));
        var reachedDestination = false;
        final visited = <Vec2>[];

        agent.onWaypointReached = (idx, pt) => visited.add(pt);
        agent.onDestinationReached = () => reachedDestination = true;

        // Navigate from (0, 0) around wall to (4, 2)
        final success = agent.setDestination(
          const Vec2(4.5, 2.5),
          tileSize: 1.0,
        );
        expect(success, isTrue);
        expect(agent.isMoving, isTrue);

        // Step simulation
        for (var i = 0; i < 30 && !reachedDestination; i++) {
          engine.step(0.1);
        }

        expect(reachedDestination, isTrue);
        expect(visited, isNotEmpty);
        expect(agentGo.transform.position.x, closeTo(4.5, 0.2));
        expect(agentGo.transform.position.z, closeTo(2.5, 0.2));
      },
    );

    test('E30: FlowField2DComponent crowd vector field evaluation', () {
      final grid = NavGrid.fromAscii([
        '..........',
        '..######..',
        '..........',
      ]);

      final fieldComp = FlowField2DComponent(grid: grid, tileSize: 1.0);
      fieldComp.setTarget(const GridPoint(5, 2));

      // Test steering vector in world space: must steer around the obstacle horizontally
      final steer = fieldComp.getSteeringVector(const Vec3(5.5, 0, 0.5));
      expect(steer.length, closeTo(1.0, 1e-3));
      expect(steer.x.abs(), greaterThan(0.0));
    });
  });

  group('E52 — 3D NavMesh Navigation', () {
    test(
      'E52: NavMeshSurfaceComponent, NavMeshAgent3DComponent & NavMeshDebuggerUI navigate 3D ramps and off-mesh links',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final surface = NavMeshSurfaceComponent(maxStepHeight: 0.8);
        surface.bakeFromPolygons(
          [
            const [Vec3(0, 0, 0), Vec3(4, 0, 0), Vec3(4, 0, 6), Vec3(0, 0, 6)],
            const [Vec3(4, 0, 2), Vec3(8, 2, 2), Vec3(8, 2, 4), Vec3(4, 0, 4)],
            const [
              Vec3(8, 2, 0),
              Vec3(12, 2, 0),
              Vec3(12, 2, 6),
              Vec3(8, 2, 6),
            ],
            const [
              Vec3(15, 3, 0),
              Vec3(18, 3, 0),
              Vec3(18, 3, 6),
              Vec3(15, 3, 6),
            ],
          ],
          offMeshLinks: [
            NavOffMeshLink(
              id: 'rope_swing',
              startPos: const NavVec3(11.8, 2.0, 3.0),
              endPos: const NavVec3(15.2, 3.0, 3.0),
              costMultiplier: 1.1,
            ),
          ],
        );
        engine.scene.createGameObject('NavMesh', components: [surface]);

        final traversedLinks = <String>[];
        var arrived = false;
        final agent = NavMeshAgent3DComponent(
          speed: 10.0,
          onTraverseOffMeshLink: (link) => traversedLinks.add(link.id),
          onDestinationReached: () => arrived = true,
        );
        final agentGo = engine.scene.createGameObject(
          'Runner',
          position: const Vec3(1, 0, 1),
          components: [agent],
        );

        engine.step(0.016);
        expect(agent.setDestination(const Vec3(17, 3, 5)), isTrue);
        expect(agent.hasPath, isTrue);

        final ui = VoxUiContext();
        ui.beginFrame(VoxInput());
        NavMeshDebuggerUI.render(ui, surface, agent: agent);
        final drawList = ui.endFrame();
        expect(drawList.commands.any((c) => c.text == '4'), isTrue);
        expect(drawList.commands.any((c) => c.text == 'Navigating'), isTrue);

        for (int i = 0; i < 40; i++) {
          engine.step(0.1);
        }
        expect(arrived, isTrue);
        expect(agent.hasPath, isFalse);
        expect(traversedLinks, ['rope_swing']);
        expect(agentGo.transform.position.x, closeTo(17.0, 0.2));
        expect(agentGo.transform.position.y, closeTo(3.0, 0.2));
        expect(agentGo.transform.position.z, closeTo(5.0, 0.2));
      },
    );
  });

  group('E65 — Autonomous Traffic Lane Graphs & Signals (voxtraffic)', () {
    test(
      'TrafficNetworkComponent & TrafficSignalComponent brake platoon on red, clear on green & render TrafficMonitorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final sigGo = scene.createGameObject(
          'MainSignal',
          components: [
            MeshRenderer(meshData: Primitives.cube(size: 1.0)),
            Light(),
          ],
        );
        final sig = sigGo.addComponent(
          TrafficSignalComponent(
            signalId: 'sig_main',
            activeGroupName: 'ns',
            customPhases: const [
              TrafficPhaseSpec(
                id: 'p_ew',
                name: 'EW Green',
                greenGroupIds: {'ew'},
                greenDurationSeconds: 10.0,
                yellowDurationSeconds: 2.0,
                allRedClearanceSeconds: 0.5,
              ),
              TrafficPhaseSpec(
                id: 'p_ns',
                name: 'NS Green',
                greenGroupIds: {'ns'},
                greenDurationSeconds: 10.0,
                yellowDurationSeconds: 2.0,
                allRedClearanceSeconds: 0.5,
              ),
            ],
          ),
        );
        expect(sig.currentColor, TrafficSignalColor.red);

        final net =
            scene
                .createGameObject('CityTraffic')
                .addComponent(TrafficNetworkComponent())
              ..addNode(
                const TrafficLaneNode(
                  id: 'a',
                  position: TrafficVec3(0, 0, -60),
                ),
              )
              ..addNode(
                const TrafficLaneNode(
                  id: 'b',
                  position: TrafficVec3(0, 0, 0),
                  signalControllerId: 'sig_main',
                  signalGroupId: 'ns',
                ),
              )
              ..addNode(
                const TrafficLaneNode(id: 'c', position: TrafficVec3(0, 0, 60)),
              )
              ..addEdge(
                TrafficLaneEdge(
                  id: 'in',
                  fromNodeId: 'a',
                  toNodeId: 'b',
                  speedLimitMps: 14.0,
                  nextEdgeIds: ['out'],
                ),
              )
              ..addEdge(
                TrafficLaneEdge(
                  id: 'out',
                  fromNodeId: 'b',
                  toNodeId: 'c',
                  speedLimitMps: 14.0,
                ),
              )
              ..attachSignalComponent(sig);

        final lead = net.spawnVehicle(
          'lead',
          edgeId: 'in',
          distanceAlongEdge: 32.0,
          initialSpeedMps: 10.0,
        );
        final tail = net.spawnVehicle(
          'tail',
          edgeId: 'in',
          distanceAlongEdge: 14.0,
          initialSpeedMps: 10.0,
        );
        expect(net.vehicleObject('lead'), isNotNull);
        expect(
          net.vehicleObject('lead')!.getComponent<BoxCollider>(),
          isNotNull,
        );

        for (var i = 0; i < 110; i++) {
          engine.step(0.05);
        }
        expect(lead.speedMps, lessThan(0.5));
        expect(lead.waitingAtSignal, isTrue);
        expect(lead.currentEdgeId, 'in');
        expect(tail.distanceAlongEdge, lessThan(lead.distanceAlongEdge - 4.0));
        expect(
          net.vehicleObject('lead')!.transform.position.z,
          closeTo(lead.worldPosition.z, 1e-4),
        );

        // Click 'Next Phase' (x=76, y=156) and 'Step +2s' (x=172, y=156) twice in TrafficMonitorUI
        final ui = VoxUiContext();
        final uiState = TrafficMonitorUiState();
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: 76.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        TrafficMonitorUI.render(ui, net, signal: sig, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 76.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        TrafficMonitorUI.render(ui, net, signal: sig, state: uiState);
        ui.endFrame();

        expect(sig.currentColor, TrafficSignalColor.green);
        expect(sigGo.getComponent<Light>()!.color.g, greaterThan(0.8));

        for (var k = 0; k < 2; k++) {
          ui.beginFrame(
            VoxInput(
              mouseX: 172.0,
              mouseY: btnY,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          TrafficMonitorUI.render(ui, net, signal: sig, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 172.0,
              mouseY: btnY,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          TrafficMonitorUI.render(ui, net, signal: sig, state: uiState);
          ui.endFrame();
        }

        ui.beginFrame(VoxInput());
        TrafficMonitorUI.render(ui, net, signal: sig, state: uiState);
        final drawList = ui.endFrame();

        expect(lead.currentEdgeId, 'out');
        expect(lead.speedMps, greaterThan(4.0));
        expect(
          drawList.commands.any((c) => c.text == 'NS Green (GREEN)'),
          isTrue,
        );

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('TrafficSignalComponent'), isNotNull);
        expect(reg.specByName('TrafficNetworkComponent'), isNotNull);
        expect(reg.specFor(sig)!.toJson(sig)['signalId'], 'sig_main');
        expect(reg.specFor(net)!.toJson(net)['timeScale'], 1.0);
      },
    );
  });

  group('E75 — Hierarchical Task Network & Utility AI with Memory Decay (voxhtn)', () {
    test(
      'HtnPlannerComponent executes compound plans, decays facts, replans via HtnDebuggerUI & serializes',
      () {
        final engine = Engine(HeadlessHost());
        final executed = <String>[];

        final domain = HtnDomain(
          name: 'GuardAI',
          rootTaskId: 'root',
          tasks: [
            HtnCompoundTask(
              id: 'root',
              methods: [
                HtnMethod(
                  id: 'm_ambush',
                  preconditions: [(bb) => bb.hasFact('alert_rumor')],
                  considerations: [
                    UtilityConsideration(
                      name: 'alert_conf',
                      inputSampler: (bb) => bb.confidenceOf('alert_rumor'),
                    ),
                  ],
                  subtaskIds: ['sneak_to_cover', 'ambush_strike'],
                ),
                HtnMethod(
                  id: 'm_patrol',
                  basePriority: 0.4,
                  subtaskIds: ['walk_waypoint'],
                ),
              ],
            ),
            HtnPrimitiveTask(
              id: 'sneak_to_cover',
              preconditions: [(bb) => bb.hasFact('alert_rumor')],
              effects: [(bb) => bb.setFact('in_cover', true)],
              onExecute: (bb, dt) {
                executed.add('sneak');
                return HtnExecStatus.succeeded;
              },
            ),
            HtnPrimitiveTask(
              id: 'ambush_strike',
              preconditions: [(bb) => bb.getBool('in_cover')],
              effects: [(bb) => bb.setFact('ambushed', true)],
              onExecute: (bb, dt) {
                executed.add('ambush');
                return HtnExecStatus.succeeded;
              },
            ),
            HtnPrimitiveTask(
              id: 'walk_waypoint',
              effects: [(bb) => bb.setFact('patrolled', true)],
              onExecute: (bb, dt) {
                executed.add('patrol');
                return HtnExecStatus.succeeded;
              },
            ),
          ],
        );

        final go = engine.scene.createGameObject('GuardBot');
        final htnComp = go.addComponent(
          HtnPlannerComponent(
            paused: true,
            autoReplanWhenIdle: true,
            pruneConfidenceThreshold: 0.1,
            domain: domain,
          ),
        );
        htnComp.setFact(
          'alert_rumor',
          'east_wing',
          confidence: 1.0,
          halfLifeSeconds: 1.0,
        );

        final preview = htnComp.replanNow();
        expect(preview.found, isTrue);
        expect(preview.decomposedTrace, ['root:m_ambush']);
        expect(preview.steps.map((s) => s.id).toList(), [
          'sneak_to_cover',
          'ambush_strike',
        ]);

        final ui = VoxUiContext();
        final uiState = HtnDebuggerUiState();
        const btnY = 156.0;

        // Click 'Replan' (x=68) -> builds m_ambush plan and runs step 0 (sneak_to_cover)
        ui.beginFrame(
          VoxInput(
            mouseX: 68.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        HtnDebuggerUI.render(ui, htnComp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 68.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        HtnDebuggerUI.render(ui, htnComp, state: uiState);
        ui.endFrame();

        expect(executed, ['sneak']);
        expect(htnComp.activeTaskName, 'ambush_strike');
        expect(htnComp.remainingSteps, 1);

        // Click 'Step' (x=148) -> runs step 1 (ambush_strike)
        ui.beginFrame(
          VoxInput(
            mouseX: 148.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        HtnDebuggerUI.render(ui, htnComp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 148.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        HtnDebuggerUI.render(ui, htnComp, state: uiState);
        ui.endFrame();
        expect(executed, ['sneak', 'ambush']);

        // Click 'Decay +1s' (x=233) 4 times -> 0.5^4 = 0.0625 < 0.1 threshold -> forgets alert_rumor
        for (var i = 0; i < 4; i++) {
          ui.beginFrame(
            VoxInput(
              mouseX: 233.0,
              mouseY: btnY,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          HtnDebuggerUI.render(ui, htnComp, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 233.0,
              mouseY: btnY,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          HtnDebuggerUI.render(ui, htnComp, state: uiState);
          ui.endFrame();
        }
        expect(htnComp.blackboard.hasFact('alert_rumor'), isFalse);

        // Click 'Resume' (x=322) to unpause, then step engine so update() auto-replans m_patrol!
        ui.beginFrame(
          VoxInput(
            mouseX: 322.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        HtnDebuggerUI.render(ui, htnComp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 322.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        HtnDebuggerUI.render(ui, htnComp, state: uiState);
        ui.endFrame();
        expect(htnComp.paused, isFalse);

        engine.step(0.05);
        expect(executed, ['sneak', 'ambush', 'patrol']);
        expect(htnComp.currentPlan!.decomposedTrace, ['root:m_patrol']);

        ui.beginFrame(VoxInput());
        HtnDebuggerUI.render(ui, htnComp, state: uiState);
        final drawList = ui.endFrame();
        expect(drawList.commands.any((c) => c.text == 'root:m_patrol'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('HtnPlannerComponent'), isNotNull);
        final json = reg.specFor(htnComp)!.toJson(htnComp);
        expect(json['paused'], isFalse);
        expect(json['pruneConfidenceThreshold'], closeTo(0.1, 1e-6));
      },
    );
  });

  group('E82 — Reynolds Steering, Dynamic Flocking & Formation Slots (voxsteer)', () {
    test(
      'SteeringAgentComponent drives arrival, formation slots, obstacle whiskers & SteeringInspectorUI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final leader = engine.scene.createGameObject(
          'SquadLeader',
          position: const Vec3(10.0, 0.0, 0.0),
        );

        final wingman = engine.scene.createGameObject(
          'Wingman',
          position: const Vec3(0.0, 0.0, 0.0),
        );
        final steerComp = wingman.addComponent(
          SteeringAgentComponent(
            mode: SteeringBehaviorMode.formation,
            formationShape: FormationShape.wedge,
            formationSpacing: 2.0,
            formationSlotIndex: 1,
            formationTotalSlots: 3,
            maxSpeed: 8.0,
            maxForce: 24.0,
            target: leader,
          ),
        );
        steerComp.addObstacle(const Vec3(5.0, 0.0, 0.2), 1.0);

        for (var i = 0; i < 60; i++) {
          engine.step(0.05);
        }

        // Moves toward trailing left wedge slot near (10 - 1.7, 0, +2.0) and avoids obstacle at x=5
        expect(wingman.transform.position.x, greaterThan(6.5));
        expect(
          (wingman.transform.position - const Vec3(5.0, 0.0, 0.2)).length,
          greaterThan(0.9),
        );

        // Test SteeringInspectorUI: click Pause (x=66, y=159) -> click Next Mode (x=144, y=159)
        final ui = VoxUiContext();
        final uiState = SteeringInspectorUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 66.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        SteeringInspectorUI.render(ui, steerComp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 66.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        SteeringInspectorUI.render(ui, steerComp, state: uiState);
        ui.endFrame();
        expect(steerComp.paused, isTrue);

        ui.beginFrame(
          VoxInput(
            mouseX: 144.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        SteeringInspectorUI.render(ui, steerComp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 144.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        SteeringInspectorUI.render(ui, steerComp, state: uiState);
        final dl = ui.endFrame();
        expect(steerComp.mode, SteeringBehaviorMode.arrive);
        expect(dl.commands.any((c) => c.text == 'Steering Agent'), isTrue);

        // Verify ComponentRegistry serialization
        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('SteeringAgentComponent'), isNotNull);
        final json = reg.specFor(steerComp)!.toJson(steerComp);
        expect(json['mode'], 'arrive');
        expect(json['paused'], isTrue);
      },
    );
  });
}
