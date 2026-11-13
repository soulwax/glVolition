/// Spatial BVH, XPBD cloth/rope/softbody, crowd avoidance, vehicles, fracture & ragdolls.
library;

import 'dart:math' as math;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('E51 — SpatialIndexComponent DynamicBvh', () {
    test(
      'E51: SpatialIndexComponent maintains DynamicBvh over Colliders & MeshRenderers, culls frustum & renders UI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final cam = Camera(fovYRadians: math.pi / 3.0, near: 0.5, far: 40.0);
        engine.scene.createGameObject(
          'Camera',
          position: Vec3.zero,
          components: [cam],
        );

        final nearBoxCol = BoxCollider(size: const Vec3(2, 2, 2));
        final nearBoxRend = MeshRenderer(meshData: Primitives.cube());
        engine.scene.createGameObject(
          'NearBox',
          position: const Vec3(0, 0, -6),
          components: [nearBoxCol, nearBoxRend],
        );

        final nearSphereCol = SphereCollider(radius: 1.0);
        final nearSphereRend = MeshRenderer(
          meshData: Primitives.sphere(radius: 1.0),
        );
        final nearSphereGo = engine.scene.createGameObject(
          'NearSphere',
          position: const Vec3(0.8, 0, -6),
          components: [nearSphereCol, nearSphereRend],
        );

        final behindBoxCol = BoxCollider(size: const Vec3(2, 2, 2));
        final behindBoxRend = MeshRenderer(meshData: Primitives.cube());
        engine.scene.createGameObject(
          'BehindBox',
          position: const Vec3(0, 0, 8),
          components: [behindBoxCol, behindBoxRend],
        );

        final spatial = SpatialIndexComponent(fatMargin: 0.4);
        engine.scene.createGameObject('SpatialIndex', components: [spatial]);

        engine.step(0.016);
        expect(spatial.colliderBvh.count, 3);
        expect(spatial.rendererBvh.count, 3);

        // Overlap pairs identify overlapping NearBox & NearSphere cleanly.
        final pairs = spatial.queryOverlapPairs();
        expect(pairs.length, 1);
        expect({pairs.single.$1, pairs.single.$2}, {nearBoxCol, nearSphereCol});

        // Closest-hit raycast along -Z hits NearBox front face at z = -5 (distance 5.0).
        final hit = spatial.raycastClosest(
          const Ray(origin: Vec3.zero, direction: kForward),
        );
        expect(hit, isNotNull);
        expect(hit!.collider, nearBoxCol);
        expect(hit.distance, closeTo(5.0, 1e-4));

        // Frustum culling keeps forward objects and rejects BehindBox.
        final visibleRenderers = spatial.queryVisibleRenderers(
          cam,
          aspect: 1.5,
        );
        expect(visibleRenderers, containsAll([nearBoxRend, nearSphereRend]));
        expect(visibleRenderers, isNot(contains(behindBoxRend)));

        // Small move stays inside fatMargin (zero reinserts!); large move reinserts and separates pair.
        final baselineReinserts = spatial.colliderBvh.reinsertionCount;
        nearSphereGo.transform.position = const Vec3(0.85, 0, -6);
        engine.step(0.016);
        expect(spatial.colliderBvh.reinsertionCount, baselineReinserts);

        nearSphereGo.transform.position = const Vec3(6.0, 0, -6);
        engine.step(0.016);
        expect(
          spatial.colliderBvh.reinsertionCount,
          greaterThan(baselineReinserts),
        );
        expect(spatial.queryOverlapPairs(), isEmpty);

        // Render SpatialBroadphaseUI via voxui.
        final ui = VoxUiContext();
        ui.beginFrame(VoxInput());
        SpatialBroadphaseUI.render(ui, spatial);
        final drawList = ui.endFrame();
        expect(drawList.commands.any((c) => c.text == '3 (nodes 5)'), isTrue);
      },
    );
  });

  group('E53 — Cloth & Rope XPBD Simulation', () {
    test(
      'E53: ClothSimulationComponent & RopeSimulationComponent solve XPBD physics, update renderers & render UI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final anchor = engine.scene.createGameObject(
          'RopeAnchor',
          position: const Vec3(-4, 3, 0),
        );
        final ropeLine = LineRenderer(startWidth: 0.08, endWidth: 0.08);
        final ropeComp = RopeSimulationComponent(
          startAnchor: anchor,
          endOffset: const Vec3(2.5, 3, 0),
          segments: 8,
          pinStart: true,
          pinEnd: false,
        );
        engine.scene.createGameObject(
          'Cable',
          components: [ropeComp, ropeLine],
        );

        final blockerCol = SphereCollider(radius: 0.65);
        engine.scene.createGameObject(
          'ShieldSphere',
          position: const Vec3(0, 1.8, 0.15),
          components: [blockerCol],
        );

        final clothRend = MeshRenderer();
        final clothComp = ClothSimulationComponent(
          columns: 5,
          rows: 5,
          width: 2.0,
          height: 2.0,
          wind: const Vec3(0, 0, 5.0),
          pinTopCorners: true,
        )..trackedColliders.add(blockerCol);
        engine.scene.createGameObject(
          'Banner',
          position: const Vec3(0, 3.0, 0),
          components: [clothComp, clothRend],
        );

        for (int i = 0; i < 30; i++) {
          engine.step(0.05);
        }

        expect(ropeLine.positionCount, 9);
        expect(ropeComp.world.averageStretchError, lessThan(0.03));
        expect(ropeComp.nodes.last.position.y, lessThan(2.0));

        expect(clothComp.currentMeshData, isNotNull);
        expect(clothRend.mesh, isNotNull);
        expect(clothComp.world.averageStretchError, lessThan(0.04));
        // Wind & blocker push center-bottom banner vertex toward +Z.
        expect(clothComp.patch!.at(2, 4).position.z, greaterThan(0.2));

        // Render XpbdDebuggerUI and click '+Wind +Z' button at x=60, y=156.
        final ui = VoxUiContext();
        final uiState = XpbdDebuggerUiState();
        const btnX = 60.0;
        const btnY = 156.0;
        ui.beginFrame(
          VoxInput(
            mouseX: btnX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        XpbdDebuggerUI.render(ui, clothComp.world, state: uiState);
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: btnX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        XpbdDebuggerUI.render(ui, clothComp.world, state: uiState);
        final drawList = ui.endFrame();

        expect(drawList.commands.any((c) => c.text == '25 / 88'), isTrue);
        expect(clothComp.world.wind.z, closeTo(7.0, 1e-4));
      },
    );
  });

  group('E56 — Reciprocal Crowd Avoidance & Formations (voxcrowd)', () {
    test(
      'CrowdManagerComponent, CrowdAgentComponent, FormationLeaderComponent & CrowdInspectorUI drive collision-free squads',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final manager = CrowdManagerComponent(autoDiscoverAgents: true)
          ..addCircleObstacle(const Vec3(0.0, 0.0, -3.0), 0.9);
        scene.createGameObject('CrowdCoordinator', components: [manager]);

        final leaderGo = scene.createGameObject(
          'SquadLeader',
          position: const Vec3(0.0, 0.0, -6.0),
        );
        final agents = <CrowdAgentComponent>[];
        for (var i = 0; i < 4; i++) {
          final go = scene.createGameObject(
            'Trooper_$i',
            position: Vec3(-3.0 + i * 2.0, 0.0, 4.0),
          );
          final comp = go.addComponent(
            CrowdAgentComponent(radius: 0.45, maxSpeed: 4.5),
          );
          agents.add(comp);
        }

        final formation = leaderGo.addComponent(
          FormationLeaderComponent(
            pattern: FormationKind.wedge,
            spacing: 2.0,
            offsetBehind: 1.5,
            followers: agents,
          ),
        );

        for (var i = 0; i < 65; i++) {
          engine.step(0.05);
        }

        expect(manager.agents.length, 4);
        expect(formation.lastSlots.length, 4);
        expect(manager.lastStats.minPairwiseClearance, greaterThan(-0.08));
        for (var i = 0; i < agents.length; i++) {
          final pos = agents[i].transform.position;
          final goal = formation.lastSlots[i];
          // Note assignNearestSlots may permute indices, so check distance to any slot or agent goal.
          expect(agents[i].goal, isNotNull);
          final distToOwnGoal =
              (Vec3(pos.x, 0.0, pos.z) -
                      Vec3(agents[i].goal!.x, 0.0, agents[i].goal!.z))
                  .length;
          expect(distToOwnGoal, lessThan(1.0));
          expect(goal.y, closeTo(0.0, 1e-6));
        }

        // Click 'Cycle Form' button in CrowdInspectorUI at x=260, y=156.
        final ui = VoxUiContext();
        final uiState = CrowdInspectorUiState();
        const btnX = 260.0;
        const btnY = 156.0;
        ui.beginFrame(
          VoxInput(
            mouseX: btnX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        CrowdInspectorUI.render(
          ui,
          manager,
          formation: formation,
          state: uiState,
        );
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: btnX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        CrowdInspectorUI.render(
          ui,
          manager,
          formation: formation,
          state: uiState,
        );
        ui.endFrame();

        ui.beginFrame(VoxInput());
        CrowdInspectorUI.render(
          ui,
          manager,
          formation: formation,
          state: uiState,
        );
        final drawList = ui.endFrame();

        expect(formation.pattern, FormationKind.line);
        expect(drawList.commands.any((c) => c.text == 'ORCA / line'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('CrowdAgentComponent'), isNotNull);
        expect(reg.specByName('FormationLeaderComponent'), isNotNull);
        final json = reg.specFor(formation)!.toJson(formation);
        expect(json['pattern'], 'line');
      },
    );
  });

  group('E58 — Raycast Vehicle Dynamics & Wheel Suspension (voxwheel)', () {
    test(
      'VehicleChassisComponent, WheelSuspensionComponent & VehicleTelemetryUI drive on scene collider',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        // Solid road box top at y = 0.0 (center y = -0.5, height 1.0).
        scene.createGameObject(
          'RoadDeck',
          position: const Vec3(0.0, -0.5, -40.0),
          components: [
            BoxCollider(size: const Vec3(40.0, 1.0, 160.0), isTrigger: false),
          ],
        );

        final carGo = scene.createGameObject(
          'SportsCar',
          position: const Vec3(0.0, 0.70, 0.0),
        );
        final chassis = carGo.addComponent(
          VehicleChassisComponent(
            driveLayout: DriveLayout.rwd,
            useScenePhysicsRaycasts: true,
            useFlatGroundFallback: false,
          ),
        );
        final wheelNodes = <GameObject>[];
        for (var i = 0; i < 4; i++) {
          wheelNodes.add(
            scene.createGameObject(
              'Wheel_$i',
              parent: carGo,
              components: [WheelSuspensionComponent(wheelIndex: i)],
            ),
          );
        }

        chassis.setInputs(throttle: 1.0, steer: 0.0);
        for (var i = 0; i < 190; i++) {
          engine.step(1.0 / 60.0);
        }

        expect(chassis.groundedWheels, 4);
        expect(chassis.forwardSpeedMps, greaterThan(12.5));
        expect(carGo.transform.position.z, lessThan(-15.0));
        expect(wheelNodes.first.transform.localPosition.y, lessThan(0.0));

        // Turn right smoothly while cruising.
        chassis.setInputs(throttle: 0.5, steer: 0.65);
        for (var i = 0; i < 60; i++) {
          engine.step(1.0 / 60.0);
        }
        expect(carGo.transform.position.x, greaterThan(1.5));

        // Click 'Shift -' button in VehicleTelemetryUI at x=68, y=156.
        final ui = VoxUiContext();
        final uiState = VehicleTelemetryUiState();
        final gearBeforeClick = chassis.currentGear;
        expect(gearBeforeClick, greaterThanOrEqualTo(2));
        const shiftDownX = 68.0;
        const btnY = 156.0;
        ui.beginFrame(
          VoxInput(
            mouseX: shiftDownX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        VehicleTelemetryUI.render(ui, chassis, state: uiState);
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: shiftDownX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        VehicleTelemetryUI.render(ui, chassis, state: uiState);
        ui.endFrame();

        ui.beginFrame(VoxInput());
        VehicleTelemetryUI.render(ui, chassis, state: uiState);
        final drawList = ui.endFrame();

        expect(chassis.currentGear, gearBeforeClick - 1);
        expect(
          drawList.commands.any(
            (c) => c.text?.endsWith('G${chassis.currentGear}') ?? false,
          ),
          isTrue,
        );

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('VehicleChassisComponent'), isNotNull);
        expect(reg.specByName('WheelSuspensionComponent'), isNotNull);
        final json = reg.specFor(chassis)!.toJson(chassis);
        expect(json['driveLayout'], 'rwd');
      },
    );
  });

  group(
    'E59 — 3D Mesh Plane Slicing, Voronoi Shatter & Structural Support (voxfracture)',
    () {
      test(
        'FracturableMeshComponent, StructuralSupportComponent & DestructionInspectorUI slice, shatter & collapse',
        () {
          final engine = Engine(HeadlessHost());
          final scene = engine.scene;

          // Test converting a Primitives.cube() (`surfaceV2`) -> FractureMesh -> plane slice -> shards -> Reset.
          final crateGo = scene.createGameObject(
            'DestructibleCrate',
            position: const Vec3(0.0, 2.0, 0.0),
            components: [MeshRenderer(meshData: Primitives.cube(size: 2.0))],
          );
          final fracturable = crateGo.addComponent(
            FracturableMeshComponent(
              voronoiCellCount: 6,
              seed: 77,
              debrisMass: 12.0,
            ),
          );

          final sliceRes = fracturable.sliceAlongPlane(
            const Vec3(0.0, 2.2, 0.0),
            const Vec3(0.2, 1.0, 0.0),
          );
          expect(sliceRes.hadCut, isTrue);
          expect(sliceRes.positive, isNotNull);
          expect(sliceRes.negative, isNotNull);
          expect(fracturable.isFractured, isTrue);
          expect(fracturable.shardCount, 2);
          expect(fracturable.lastTotalVolume, closeTo(8.0, 0.05));
          expect(crateGo.node.children.every((n) => !n.visible), isTrue);

          // Click 'Voronoi' button at x=164, y=156 in DestructionInspectorUI.
          final ui = VoxUiContext();
          final uiState = DestructionInspectorUiState();
          const voroX = 164.0;
          const btnY = 156.0;
          ui.beginFrame(
            VoxInput(
              mouseX: voroX,
              mouseY: btnY,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          DestructionInspectorUI.render(ui, fracturable, state: uiState);
          ui.endFrame();

          ui.beginFrame(
            VoxInput(
              mouseX: voroX,
              mouseY: btnY,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          DestructionInspectorUI.render(ui, fracturable, state: uiState);
          ui.endFrame();

          ui.beginFrame(VoxInput());
          DestructionInspectorUI.render(ui, fracturable, state: uiState);
          final drawList = ui.endFrame();

          expect(fracturable.shardCount, greaterThanOrEqualTo(5));
          expect(fracturable.lastTotalVolume, closeTo(8.0, 0.1));
          expect(
            drawList.commands.any(
              (c) => c.text == 'SHATTERED / ${fracturable.shardCount}',
            ),
            isTrue,
          );

          // Structural support tower collapse drops upper unsupported blocks as dynamic RigidBodies.
          final base = scene.createGameObject(
            'AnchorBlock',
            position: const Vec3(10, 0, 0),
          );
          final mid = scene.createGameObject(
            'MidBlock',
            position: const Vec3(10, 1, 0),
          );
          final roof = scene.createGameObject(
            'RoofBlock',
            position: const Vec3(10, 2, 0),
          );
          final tower = scene.createGameObject('TowerController');
          final support = tower.addComponent(StructuralSupportComponent());
          support
            ..linkPiece(base, isAnchor: true, mass: 5.0)
            ..linkPiece(mid, mass: 2.0, maxHitPoints: 50.0)
            ..linkPiece(roof, mass: 2.0)
            ..connectPieces(base, mid, bondStrength: 80.0)
            ..connectPieces(mid, roof, bondStrength: 80.0);

          final collapse = support.applyBlastDamage(
            const Vec3(10, 1, 0),
            radius: 0.9,
            damage: 100.0,
          );
          expect(collapse.detachedNodeIds.length, 2);
          expect(roof.getComponent<RigidBody>(), isNotNull);
          expect(roof.getComponent<RigidBody>()!.isKinematic, isFalse);

          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('FracturableMeshComponent'), isNotNull);
          expect(reg.specByName('StructuralSupportComponent'), isNotNull);
          final json = reg.specFor(fracturable)!.toJson(fracturable);
          expect(json['voronoiCellCount'], 6);
        },
      );
    },
  );

  group('E64 — Articulated Ragdoll Constraints & Active Balance (voxragdoll)', () {
    test(
      'ArticulatedRagdollComponent syncs limb GameObjects, handles hit flinch, recovers & renders RagdollInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final ragGo = scene.createGameObject(
          'HeroRagdoll',
          position: const Vec3(0, 0, 0),
        );
        final rag = ragGo.addComponent(
          ArticulatedRagdollComponent(
            floorY: 0.0,
            activeBalanceStrength: 0.9,
            flinchRecoveryRate: 3.0,
          ),
        );

        final limbs = rag.spawnDebugLimbs();
        expect(limbs.length, rag.skeleton.limbs.length);
        rag.pinLimb('pelvis', true);

        rag.applyHitImpulse(
          'torso',
          const Vec3(140.0, 20.0, 60.0),
          localHitOffset: const Vec3(0.0, 0.2, 0.0),
          flinchStrength: 0.85,
          durationSeconds: 0.25,
        );
        expect(rag.mode, RagdollMode.hitReactionFlinch);
        expect(rag.motorBlend, lessThan(0.3));

        engine.step(0.05);
        engine.step(0.05);
        final torsoPos = limbs['torso']!.transform.position;
        expect(torsoPos.x.abs() + torsoPos.z.abs(), greaterThan(0.02));
        expect(rag.maxJointViolationMeters, lessThan(0.05));

        for (var i = 0; i < 40; i++) {
          engine.step(0.05);
        }
        expect(rag.mode, RagdollMode.activeBalanced);
        expect(rag.motorBlend, greaterThan(0.8));

        // Click 'Punch Torso' (x=72, y=156) and 'Go Limp' (x=168, y=156) in RagdollInspectorUI
        final ui = VoxUiContext();
        final uiState = RagdollInspectorUiState();
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: 72.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        RagdollInspectorUI.render(ui, rag, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 72.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        RagdollInspectorUI.render(ui, rag, state: uiState);
        ui.endFrame();
        expect(rag.mode, RagdollMode.hitReactionFlinch);

        ui.beginFrame(
          VoxInput(
            mouseX: 168.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        RagdollInspectorUI.render(ui, rag, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 168.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        RagdollInspectorUI.render(ui, rag, state: uiState);
        ui.endFrame();

        ui.beginFrame(VoxInput());
        RagdollInspectorUI.render(ui, rag, state: uiState);
        final drawList = ui.endFrame();

        expect(rag.isLimp, isTrue);
        expect(rag.mode, RagdollMode.fullLimp);
        expect(drawList.commands.any((c) => c.text == 'fullLimp / 0%'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('ArticulatedRagdollComponent'), isNotNull);
        final json = reg.specFor(rag)!.toJson(rag);
        expect(json['isLimp'], isTrue);
        expect(json['activeBalanceStrength'], closeTo(0.9, 1e-6));
      },
    );
  });

  group('E80 — Spatial Hash Grids, SAP Broadphase & Swept-AABB TOI (voxbroad)', () {
    test(
      'BroadphaseWorldComponent syncs scene colliders, queries neighborhoods, solves swept TOI & drives BroadphaseStatsUI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final bpGo = engine.scene.createGameObject('Broadphase');
        final bp = bpGo.addComponent(
          BroadphaseWorldComponent(cellSize: 3.0, useSapBroadphase: false),
        );

        final a = engine.scene.createGameObject(
          'BoxA',
          position: const Vec3(0.0, 0.0, 0.0),
          components: [BoxCollider(size: const Vec3(2.0, 2.0, 2.0))],
        );
        engine.scene.createGameObject(
          'BoxB',
          position: const Vec3(1.4, 0.0, 0.0),
          components: [BoxCollider(size: const Vec3(2.0, 2.0, 2.0))],
        );
        engine.scene.createGameObject(
          'Wall',
          position: const Vec3(10.0, 0.0, 0.0),
          components: [BoxCollider(size: const Vec3(2.0, 4.0, 4.0))],
        );

        engine.step(0.02);
        expect(bp.trackedCount, 3);
        expect(bp.overlapPairCount, 1);

        final nearHits = bp.queryAabb(
          Aabb(const Vec3(-1.5, -1.5, -1.5), const Vec3(0.5, 1.5, 1.5)),
          exclude: a.getComponent<BoxCollider>(),
        );
        expect(nearHits.map((c) => c.gameObject.name).toList(), ['BoxB']);

        // Sweep mover box from x=4 to x=19 -> hits Wall (min x=9.0, mover half=0.5 -> contact x=8.5, dist=4.5, toi=0.3)
        final toiHit = bp.sweepAabbToi(
          Aabb(const Vec3(3.5, -0.5, -0.5), const Vec3(4.5, 0.5, 0.5)),
          const Vec3(15.0, 0.0, 0.0),
        );
        expect(toiHit, isNotNull);
        expect(
          bp.colliderByEntryId(toiHit!.targetId!)?.gameObject.name,
          'Wall',
        );
        expect(toiHit.toi, closeTo(4.5 / 15.0, 1e-4));
        expect(toiHit.normal.x, closeTo(-1.0, 1e-5));

        // Test BroadphaseStatsUI: click Toggle SAP (x=144, y=159)
        final ui = VoxUiContext();
        final uiState = BroadphaseStatsUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 144.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        BroadphaseStatsUI.render(ui, bp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 144.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        BroadphaseStatsUI.render(ui, bp, state: uiState);
        final dl = ui.endFrame();
        expect(bp.useSapBroadphase, isTrue);
        expect(bp.overlapPairCount, 1);
        expect(dl.commands.any((c) => c.text == 'Broadphase World'), isTrue);

        // Verify ComponentRegistry serialization
        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('BroadphaseWorldComponent'), isNotNull);
        final json = reg.specFor(bp)!.toJson(bp);
        expect(json['useSapBroadphase'], isTrue);
        expect(json['cellSize'], closeTo(3.0, 1e-6));
      },
    );
  });

  group('E94 — XPBD Constraints & Soft Body Solver (voxverlet)', () {
    test(
      'SoftBodyXpbdComponent steps Verlet cube rig, handles XpbdSolverInspectorUI & serializes',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final bodyGo = engine.scene.createGameObject(
          'SoftCube',
          position: const Vec3(0.0, 2.0, 0.0),
        );
        final comp = bodyGo.addComponent(
          SoftBodyXpbdComponent(
            compliance: 0.001,
            volumeCompliance: 0.0005,
            floorY: -1.0,
            substeps: 8,
            halfExtent: 0.5,
          ),
        );

        final startY = comp.centerOfMass.y;
        engine.step(0.04);
        expect(comp.nodeCount, 8);
        expect(comp.centerOfMass.y, lessThan(startY));
        expect(comp.totalConstraintError.isFinite, isTrue);

        // Test XpbdSolverInspectorUI: click Substep +1 at (156.0, 159.0) & Drop at (252.0, 159.0)
        final ui = VoxUiContext();
        final uiState = SoftBodyXpbdUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 252.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        XpbdSolverInspectorUI.render(ui, comp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 252.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        XpbdSolverInspectorUI.render(ui, comp, state: uiState);
        ui.endFrame();

        final beforeSubstepY = comp.centerOfMass.y;
        ui.beginFrame(
          VoxInput(
            mouseX: 156.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        XpbdSolverInspectorUI.render(ui, comp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 156.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        XpbdSolverInspectorUI.render(ui, comp, state: uiState);
        final dl = ui.endFrame();
        expect(comp.centerOfMass.y, lessThan(beforeSubstepY));
        expect(dl.commands.any((c) => c.text == 'XPBD Soft Body'), isTrue);

        // Verify ComponentRegistry serialization
        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('SoftBodyXpbdComponent'), isNotNull);
        final json = reg.specFor(comp)!.toJson(comp);
        expect(json['substeps'], 8);
        expect(json['floorY'], closeTo(-1.0, 1e-6));
      },
    );
  });
}
