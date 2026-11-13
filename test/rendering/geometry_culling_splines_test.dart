/// Instancing, batching, render graph, octree culling, gizmos, foliage, decals & splines.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('E5 — SplinePath & SplineFollower', () {
    test(
      'SplinePath and SplineFollower move along arc length and align rotation',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final path = SplinePath.fromPoints(const [
          Vec3(0, 0, 0),
          Vec3(0, 0, -10),
          Vec3(0, 0, -20),
        ]);
        var finished = false;
        final follower = SplineFollower(
          path: path,
          speed: 10.0,
          loopMode: LoopMode.once,
          onReachedEnd: () => finished = true,
        );
        final cart = engine.scene.createGameObject(
          'Cart',
          components: [path, follower],
        );

        for (var i = 0; i < 10; i++) {
          engine.step(0.1);
        }
        expect(cart.transform.position.z, closeTo(-10.0, 0.25));
        expect(finished, isFalse);

        for (var i = 0; i < 15; i++) {
          engine.step(0.1);
        }
        expect(cart.transform.position.z, closeTo(-20.0, 0.1));
        expect(finished, isTrue);
      },
    );
  });

  group('E9 — InstancedMeshRenderer Batching & Picking', () {
    test(
      'InstancedMeshRenderer batches multiple instances and supports per-instance raycast picking',
      () async {
        final device = GlesDevice();
        final runner = await NativeEngineHost.boot(
          device: device,
          width: 640,
          height: 360,
        );
        final scene = runner.scene;
        scene.createGameObject(
          'Cam',
          position: const Vec3(0, 2, 12),
          components: [Camera()],
        );

        final instanced = InstancedMeshRenderer(
          meshData: Primitives.cube(size: 1.0),
          materialDefinition: const MaterialDefinition(key: 'inst_cube'),
          transforms: [
            Transform.at(const Vec3(-3, 0, 0)),
            Transform.at(const Vec3(0, 0, 0)),
            Transform.at(const Vec3(3, 0, 0)),
          ],
        );
        final go = scene.createGameObject(
          'CubeCluster',
          components: [instanced],
        );

        final stats = runner.renderFrame(1 / 60);
        expect(stats.instancesSubmitted, greaterThanOrEqualTo(3));

        // Raycast straight at the third instance at (3, 0, 0)
        final ray = const Ray(origin: Vec3(3, 0, 5), direction: Vec3(0, 0, -1));
        final pick = scene.raycastVisuals(ray);
        expect(pick, isNotNull);
        expect(pick!.$1, same(go));
        expect(pick.$2.instanceIndex, 2);

        runner.dispose();
        expect(device.liveObjectCount, 0);
      },
    );
  });

  group('E10 — LineRenderer & TrailRenderer Ribbons', () {
    test(
      'LineRenderer and TrailRenderer build ribbon MeshData as GameObjects move',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final line = LineRenderer(
          positions: const [Vec3(0, 0, 0), Vec3(0, 2, -4), Vec3(2, 3, -8)],
          startWidth: 0.4,
          endWidth: 0.1,
        );
        engine.scene.createGameObject('Beam', components: [line]);

        final trail = TrailRenderer(
          timeLength: 1.0,
          minVertexDistance: 0.2,
          startWidth: 0.3,
          endWidth: 0.05,
        );
        final missile = engine.scene.createGameObject(
          'Missile',
          components: [trail],
        );

        engine.step(0.05);
        expect(line.meshData, isNotNull);
        expect(line.meshData!.vertexCount, 6); // 3 points * 2 vertices

        missile.transform.position = const Vec3(0, 0, -1.0);
        engine.step(0.05);
        missile.transform.position = const Vec3(0, 0.5, -2.5);
        engine.step(0.05);

        expect(trail.sampleCount, 3);
        expect(trail.meshData, isNotNull);
        expect(trail.meshData!.vertexCount, 6);
      },
    );
  });

  group('E11 — LodGroup & Billboard', () {
    test(
      'LodGroup switches active child by camera distance and Billboard faces camera',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final camGo = engine.scene.createGameObject(
          'Cam',
          position: const Vec3(0, 0, 5),
          components: [Camera()],
        );

        final tree = engine.scene.createGameObject('Tree', position: Vec3.zero);
        final lod0 = engine.scene.createGameObject('LOD0', parent: tree);
        final lod1 = engine.scene.createGameObject('LOD1', parent: tree);
        final lodGroup = LodGroup(
          levels: [
            LodLevel(maxDistance: 10.0, target: lod0),
            LodLevel(maxDistance: 30.0, target: lod1),
          ],
          cullDistance: 50.0,
        );
        tree.addComponent(lodGroup);

        final banner = engine.scene.createGameObject(
          'Banner',
          position: const Vec3(5, 0, 0),
          components: [Billboard(cylindrical: true)],
        );

        // Distance = 5 -> LOD0 active
        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, 0);
        expect(lod0.activeSelf, isTrue);
        expect(lod1.activeSelf, isFalse);
        // Banner at (5,0,0) facing Cam at (0,0,5) -> forward points along (-1, 0, 1).normalized
        expect(banner.transform.forward.x, closeTo(-0.70710678, 1e-3));
        expect(banner.transform.forward.z, closeTo(0.70710678, 1e-3));

        // Move camera to z = 20 -> LOD1 active
        camGo.transform.position = const Vec3(0, 0, 20);
        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, 1);
        expect(lod0.activeSelf, isFalse);
        expect(lod1.activeSelf, isTrue);

        // Move camera to z = 60 -> culled (-1)
        camGo.transform.position = const Vec3(0, 0, 60);
        engine.step(0.016);
        expect(lodGroup.activeLevelIndex, -1);
        expect(lod0.activeSelf, isFalse);
        expect(lod1.activeSelf, isFalse);
      },
    );
  });

  group('E15 — Gizmos Wireframes & Projection', () {
    test(
      'Gizmos collect collider wireframes, contacts and selection, project to screen, and clear after encode',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = engine.scene;

        scene.createGameObject(
          'Cam',
          position: const Vec3(0, 2, 10),
          components: [Camera()],
        );
        final box = scene.createGameObject(
          'Box',
          components: [BoxCollider(size: const Vec3(2, 2, 2), isTrigger: true)],
        );
        scene.createGameObject(
          'Ball',
          position: const Vec3(0.8, 0, 0),
          components: [SphereCollider(radius: 0.5, isTrigger: true)],
        );
        scene.createGameObject(
          'Pill',
          position: const Vec3(-4, 0, 0),
          components: [CapsuleCollider(radius: 0.3, height: 1.5)],
        );

        // Disabled by default: nothing is queued.
        scene.gizmos.line(Vec3.zero, const Vec3(1, 0, 0));
        expect(scene.gizmos.lineCount, 0);

        engine.step(0.05);
        expect(scene.physics.contactPairs.length, 1);

        scene.gizmos
          ..enabled = true
          ..showContacts = false
          ..showSelection = false;
        scene.gizmos.collectAuto();
        final boxLines = 12;
        final sphereLines = 3 * scene.gizmos.circleSegments;
        final collidersOnly = scene.gizmos.lineCount;
        expect(collidersOnly, greaterThan(boxLines + sphereLines));

        scene.gizmos
          ..clear()
          ..showContacts = true;
        scene.gizmos.collectAuto();
        expect(
          scene.gizmos.lineCount,
          collidersOnly + 4,
        ); // cross (3) + normal ray (1)
        expect(
          scene.gizmos.lines
              .where((l) => l.color == scene.gizmos.contactColor)
              .length,
          4,
        );

        scene.gizmos
          ..clear()
          ..showColliders = false
          ..showContacts = false
          ..showSelection = true;
        engine.editor.selected = box;
        scene.gizmos.collectAuto();
        // 3 axis rays + the selected box's 12 edges in selection colour.
        expect(scene.gizmos.lineCount, 15);
        expect(
          scene.gizmos.lines
              .where((l) => l.color == scene.gizmos.selectionColor)
              .length,
          12,
        );

        // Projection lands on-screen around the viewport centre.
        final projected = scene.gizmos.project(Camera.of(scene)!);
        expect(projected.length, 15);
        for (final s in projected) {
          expect(s.x0, inInclusiveRange(0, 1280));
          expect(s.y0, inInclusiveRange(0, 720));
        }

        // A segment crossing behind the camera is clipped, not dropped or flipped.
        scene.gizmos
          ..clear()
          ..line(Vec3.zero, const Vec3(0, 2, 20));
        final clipped = scene.gizmos.project(Camera.of(scene)!);
        expect(clipped.length, 1);
      },
    );
  });

  group('E16 — Gizmos Arrow & WireDisc Extensions', () {
    test(
      'Gizmos.arrow and Gizmos.wireDisc queue segments and project properly',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final cam = engine.scene
            .createGameObject(
              'Cam',
              position: const Vec3(0, 0, 5),
              components: [Camera()],
            )
            .getComponent<Camera>()!;

        engine.scene.gizmos.enabled = true;
        engine.scene.gizmos.arrow(
          const Vec3(0, 0, 0),
          const Vec3(0, 1, 0),
          headSize: 0.2,
        );
        // Shaft (1) + 4 head base lines = 5 lines
        expect(engine.scene.gizmos.lineCount, 5);

        engine.scene.gizmos.wireDisc(
          const Vec3(0, 0, 0),
          1.0,
          const Vec3(0, 1, 0),
        );
        expect(
          engine.scene.gizmos.lineCount,
          5 + engine.scene.gizmos.circleSegments,
        );

        final projected = engine.scene.gizmos.project(cam);
        expect(projected.length, 5 + engine.scene.gizmos.circleSegments);
      },
    );
  });

  group('E22 — SplineMeshRenderer Ribbon', () {
    test(
      'SplineMeshRenderer samples SplinePath and generates ribbon mesh via LineRenderer',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // Create a 3D curved spline with 4 control points
        final splineObj = engine.scene.createGameObject('SplineCable');
        final path = splineObj.addComponent(
          SplinePath.fromPoints([
            const Vec3(0, 0, 0),
            const Vec3(2, 4, 1),
            const Vec3(6, 3, 2),
            const Vec3(10, 0, 0),
          ]),
        );

        final smr = splineObj.addComponent(
          SplineMeshRenderer(
            path: path,
            sampleCount: 16,
            startWidth: 0.3,
            endWidth: 0.1,
            color: const LinearColor(0.2, 0.9, 0.4),
          ),
        );

        engine.step(0.016);

        final line = splineObj.getComponent<LineRenderer>();
        expect(line, isNotNull);
        expect(line!.positionCount, 16);
        expect(line.startWidth, closeTo(0.3, 1e-4));
        expect(line.endWidth, closeTo(0.1, 1e-4));
        expect(line.color.g, closeTo(0.9, 1e-4));

        // Rebuild with different widths
        smr.startWidth = 0.5;
        smr.endWidth = 0.5;
        smr.rebuild();
        expect(line.startWidth, closeTo(0.5, 1e-4));
        expect(line.endWidth, closeTo(0.5, 1e-4));
      },
    );
  });

  group('E29 — Camera Frustum Extraction & Culling (voxgeom)', () {
    test(
      'E29: Camera frustum extraction and visibility culling with voxgeom',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final camGo = engine.scene.createGameObject('MainCamera');
        camGo.transform.position = const Vec3(0, 0, 10);
        camGo.transform.lookAt(Vec3.zero);
        final cam = camGo.addComponent(
          Camera(fovYRadians: 1.0, near: 0.1, far: 50.0),
        );

        final visibleGo = engine.scene.createGameObject('VisibleCube');
        visibleGo.transform.position = const Vec3(0, 0, 0);
        final visibleMesh = visibleGo.addComponent(MeshRenderer());

        final behindGo = engine.scene.createGameObject('BehindCube');
        behindGo.transform.position = const Vec3(0, 0, 20);
        final behindMesh = behindGo.addComponent(MeshRenderer());

        final farAwayGo = engine.scene.createGameObject('FarAwayCube');
        farAwayGo.transform.position = const Vec3(100, 0, 0);
        final farMesh = farAwayGo.addComponent(MeshRenderer());

        engine.step(0.016);

        final frustum = cam.calculateFrustum();
        expect(frustum.planes, hasLength(6));

        expect(cam.isMeshVisible(visibleMesh), isTrue);
        expect(cam.isMeshVisible(behindMesh), isFalse);
        expect(cam.isMeshVisible(farMesh), isFalse);
      },
    );
  });

  group('E54 — Procedural Spline Extrusion & Intersections (voxextrude)', () {
    test(
      'SplineExtrudeComponent builds swept road mesh, updates MeshRenderer, and rebuilds via ExtrusionInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final roadGo = scene.createGameObject(
          'HighwaySpline',
          components: [
            SplinePath.fromPoints(const [
              Vec3(0.0, 0.0, 0.0),
              Vec3(0.0, 0.5, -6.0),
              Vec3(4.0, 1.0, -12.0),
              Vec3(8.0, 1.2, -18.0),
            ]),
          ],
        );

        final extrude = roadGo.addComponent(
          SplineExtrudeComponent(
            profilePreset: ExtrudeProfilePreset.road,
            subdivisionsPerSegment: 6,
            width: 6.0,
            upLocked: true,
          ),
        );
        engine.step(0.016);

        final mr = roadGo.getComponent<MeshRenderer>();
        expect(mr, isNotNull);
        expect(mr!.mesh, isNotNull);
        expect(extrude.vertexCount, greaterThan(90));
        expect(extrude.triangleCount, greaterThan(100));
        expect(extrude.totalArcLength, greaterThan(18.0));
        expect(extrude.currentMeshData, isNotNull);
        extrude.currentMeshData!.validate();

        // Switch to pipe preset, toggle UpLock via UI click, and verify mesh rebuilds cleanly.
        extrude.profilePreset = ExtrudeProfilePreset.circle;
        extrude.radius = 0.75;

        final ui = VoxUiContext();
        final uiState = ExtrusionInspectorUiState();
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
        ExtrusionInspectorUI.render(ui, extrude, state: uiState);
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: btnX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        ExtrusionInspectorUI.render(ui, extrude, state: uiState);
        ui.endFrame();

        ui.beginFrame(VoxInput());
        ExtrusionInspectorUI.render(ui, extrude, state: uiState);
        final drawList = ui.endFrame();

        expect(extrude.upLocked, isFalse);
        expect(extrude.vertexCount, greaterThan(200));
        expect(drawList.commands.any((c) => c.text == 'circle / OFF'), isTrue);

        // Verify intersection hub + ComponentRegistry round-trip.
        final junction = RoadIntersectionMeshBuilder.build(
          hubRadius: 5.0,
          arms: [
            RoadArm(id: 'n', direction: const ExtVec3(0, 0, -1), width: 6.0),
            RoadArm(id: 'e', direction: const ExtVec3(1, 0, 0), width: 6.0),
            RoadArm(id: 's', direction: const ExtVec3(0, 0, 1), width: 6.0),
          ],
        );
        expect(junction.portals.length, 3);
        expect(junction.mesh.triangleCount, greaterThanOrEqualTo(6));

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('SplineExtrudeComponent'), isNotNull);
        final json = reg.specFor(extrude)!.toJson(extrude);
        expect(json['profilePreset'], 'circle');
        expect(json['upLocked'], false);
      },
    );
  });

  group('E60 — Projective 3D Decals, Skid Ribbons & Decal Pools (voxdecal)', () {
    test(
      'DecalProjectorComponent, DecalPoolComponent, SurfaceSkidTrailComponent & DecalPoolInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        // Ground target mesh
        final floorGo = scene.createGameObject(
          'DecalFloor',
          position: const Vec3(0.0, 0.0, 0.0),
          components: [
            MeshRenderer(
              meshData: Primitives.plane(
                width: 10.0,
                depth: 10.0,
                subdivisionsX: 4,
                subdivisionsZ: 4,
              ),
            ),
          ],
        );

        // Oriented box decal projecting straight downward (-Y -> lookRotation(0,-1,0)) onto floor.
        final projGo = scene.createGameObject(
          'ScorchProjector',
          position: const Vec3(0.5, 0.0, -0.5),
          rotation: lookRotation(const Vec3(0.0, -1.0, 0.0), Vec3.unitZ),
        );
        final projector = projGo.addComponent(
          DecalProjectorComponent(size: const Vec3(2.0, 2.0, 1.0)),
        );
        final clipped = projector.projectOntoTarget(floorGo);
        expect(clipped.isEmpty, isFalse);
        expect(projector.triangleCount, greaterThanOrEqualTo(2));
        projector.currentMeshData!.validate();

        // Ring-buffer pool + skid trail
        final pool = scene
            .createGameObject('DecalCoordinator')
            .addComponent(
              DecalPoolComponent(
                maxCapacity: 3,
                mergeCullRadius: 0.15,
                defaultLifetimeSeconds: 8.0,
              ),
            );
        pool.stampDecal(
          worldPosition: const Vec3(0.0, 0.0, 0.0),
          worldNormal: Vec3.unitY,
          target: floorGo,
        );
        // Duplicate inside mergeCullRadius is dropped
        final dup = pool.stampDecal(
          worldPosition: const Vec3(0.05, 0.0, 0.0),
          worldNormal: Vec3.unitY,
          target: floorGo,
        );
        expect(dup, isNull);
        expect(pool.mergeCulledCount, 1);

        final skidGo = scene.createGameObject('LeftTireSkid');
        final skid = skidGo.addComponent(
          SurfaceSkidTrailComponent(
            ribbonWidth: 0.35,
            minSegmentDistance: 0.25,
          ),
        );
        for (var i = 0; i < 6; i++) {
          skid.addStamp(Vec3(0.0, 0.0, -i * 0.6));
        }
        engine.step(0.05);
        expect(skid.sampleCount, 6);
        expect(skid.triangleCount, 10);
        skid.currentMeshData!.validate();

        // Click 'Stamp' button at x=70, y=156 in DecalPoolInspectorUI.
        final ui = VoxUiContext();
        final uiState = DecalPoolInspectorUiState();
        const stampX = 70.0;
        const btnY = 156.0;
        ui.beginFrame(
          VoxInput(
            mouseX: stampX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        DecalPoolInspectorUI.render(ui, pool, skidTrail: skid, state: uiState);
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: stampX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        DecalPoolInspectorUI.render(ui, pool, skidTrail: skid, state: uiState);
        ui.endFrame();

        ui.beginFrame(VoxInput());
        DecalPoolInspectorUI.render(ui, pool, skidTrail: skid, state: uiState);
        final drawList = ui.endFrame();

        expect(pool.activeCount, 2);
        expect(drawList.commands.any((c) => c.text == '2 / 3'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('DecalPoolComponent'), isNotNull);
        expect(reg.specByName('DecalProjectorComponent'), isNotNull);
        expect(reg.specByName('SurfaceSkidTrailComponent'), isNotNull);
        final json = reg.specFor(pool)!.toJson(pool);
        expect(json['maxCapacity'], 3);
      },
    );
  });

  group('E63 — Poisson-Disk Foliage Scattering & Wind Sway (voxfoliage)', () {
    test(
      'FoliageScatterComponent scatters TerrainComponent heightfield, culls LOD clusters, sways in wind & renders FoliageInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        // Ground terrain sloped gentle meadow
        final terrainGen = TerrainGenerator(
          width: 64.0,
          depth: 64.0,
          subdivisionsX: 32,
          subdivisionsZ: 32,
          maxHeight: 4.0,
          islandRadius: 28.0,
          seed: 7,
        );
        scene.createGameObject(
          'MeadowTerrain',
          components: [TerrainComponent(terrainGen)],
        );

        final cam = scene
            .createGameObject(
              'MainCam',
              position: const Vec3(0.0, 4.0, 0.0),
              components: [Camera()],
            )
            .getComponent<Camera>()!;

        final scatterGo = scene.createGameObject('ForestFoliage');
        final foli =
            scatterGo.addComponent(
              FoliageScatterComponent(
                originX: -24.0,
                originZ: -24.0,
                areaWidth: 48.0,
                areaDepth: 48.0,
                clusterCellSize: 12.0,
                lodFullDistance: 12.0,
                lodMidDistance: 24.0,
                maxDrawDistance: 40.0,
                windSpeed: 5.0,
              ),
            )..addSpecies(
              const FoliageSpeciesDef(
                id: 'spruce',
                name: 'Spruce',
                minSpacing: 3.2,
                minElevation: -10.0,
                maxElevation: 20.0,
                maxSlopeDegrees: 45.0,
              ),
            );

        final count = foli.scatter();
        expect(count, greaterThan(40));
        expect(foli.instancedRenderer, isNotNull);

        engine.step(0.05);
        final nearVisible = foli.visibleCount;
        expect(nearVisible, greaterThan(0));
        expect(foli.lastSwayPoses.first.totalBendRadians, greaterThan(0.005));

        // Moving camera outside draw distance culls all distant foliage clusters
        cam.transform.position = const Vec3(200.0, 10.0, 200.0);
        engine.step(0.05);
        expect(foli.visibleCount, 0);

        // Restore camera & click 'Gust +2' (x=170, y=156) in FoliageInspectorUI
        cam.transform.position = const Vec3(0.0, 4.0, 0.0);
        engine.step(0.05);

        final ui = VoxUiContext();
        final uiState = FoliageInspectorUiState();
        const gustX = 170.0;
        const btnY = 156.0;
        ui.beginFrame(
          VoxInput(
            mouseX: gustX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        FoliageInspectorUI.render(ui, foli, state: uiState);
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: gustX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        FoliageInspectorUI.render(ui, foli, state: uiState);
        ui.endFrame();

        ui.beginFrame(VoxInput());
        FoliageInspectorUI.render(ui, foli, state: uiState);
        final drawList = ui.endFrame();

        expect(foli.windSpeed, closeTo(7.0, 1e-6));
        expect(
          drawList.commands.any(
            (c) => (c.text?.startsWith('7.0 m/s') ?? false),
          ),
          isTrue,
        );

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('FoliageScatterComponent'), isNotNull);
        final json = reg.specFor(foli)!.toJson(foli);
        expect(json['windSpeed'], closeTo(7.0, 1e-6));
      },
    );
  });

  group(
    'E83 — Render/Compute Pass DAG, Barriers & Transient Aliasing (voxgraph)',
    () {
      test(
        'RenderGraphComponent compiles pass DAG, culls dead passes, aliases transient targets & drives RenderGraphInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final rgGo = engine.scene.createGameObject('PipelineGraph');
          final rgComp = rgGo.addComponent(
            RenderGraphComponent(
              viewportWidth: 1280,
              viewportHeight: 720,
              enableTransientAliasing: true,
              includePostProcessPass: true,
              includeUnusedDebugPass: true,
            ),
          );

          final compiled = rgComp.rebuildStandardPipeline();
          expect(compiled.culledPassNames, ['UnusedHeatmap']);
          expect(compiled.executionOrderNames, [
            'DepthPrePass',
            'OpaqueLighting',
            'BloomExtract',
            'ToneMapPresent',
          ]);
          expect(compiled.barrierCount, greaterThanOrEqualTo(5));
          expect(rgComp.aliasingPlan, isNotNull);
          expect(rgComp.aliasingPlan!.slots.length, lessThanOrEqualTo(3));

          // Test RenderGraphInspectorUI: click Post: On/Off toggle (x=150, y=159)
          final ui = VoxUiContext();
          final uiState = RenderGraphInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 150.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          RenderGraphInspectorUI.render(ui, rgComp, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 150.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          RenderGraphInspectorUI.render(ui, rgComp, state: uiState);
          final dl = ui.endFrame();
          expect(rgComp.includePostProcessPass, isFalse);
          expect(rgComp.compiled.executionOrderNames.last, 'DirectPresent');
          expect(dl.commands.any((c) => c.text == 'Render Graph DAG'), isTrue);

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('RenderGraphComponent'), isNotNull);
          final json = reg.specFor(rgComp)!.toJson(rgComp);
          expect(json['includePostProcessPass'], isFalse);
          expect(json['viewportWidth'], 1280);
        },
      );
    },
  );

  group(
    'E86 — Cubic Hermite Splines, Bishop Frames & Track Lofts (voxspline3d)',
    () {
      test(
        'SplineTrackLoftComponent builds MeshRenderer track geometry & drives SplineTrackInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final trackGo = engine.scene.createGameObject('CircuitTrack');
          final loft = trackGo.addComponent(
            SplineTrackLoftComponent(
              trackWidth: 6.0,
              curbHeight: 0.35,
              sampleCount: 16,
              closedLoop: false,
            ),
          );

          engine.step(0.016);
          expect(trackGo.getComponent<MeshRenderer>(), isNotNull);
          expect(loft.vertexCount, 16 * 4);
          expect(loft.triangleCount, 15 * 3 * 2);
          expect(loft.totalArcLength, greaterThan(30.0));

          // Test SplineTrackInspectorUI: click Width +1.0 (x=160, y=159)
          final ui = VoxUiContext();
          final uiState = SplineTrackInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 160.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          SplineTrackInspectorUI.render(ui, loft, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 160.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          SplineTrackInspectorUI.render(ui, loft, state: uiState);
          final dl = ui.endFrame();

          expect(loft.trackWidth, closeTo(7.0, 1e-6));
          expect(dl.commands.any((c) => c.text == 'Spline Track Loft'), isTrue);

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('SplineTrackLoftComponent'), isNotNull);
          final json = reg.specFor(loft)!.toJson(loft);
          expect(json['trackWidth'], closeTo(7.0, 1e-6));
          expect(json['sampleCount'], 16);
        },
      );
    },
  );

  group(
    'E88 — Static/Instanced Draw-Call Batching & Spatial Cell Clustering (voxbatch)',
    () {
      test(
        'DrawBatcherComponent batches shared MeshRenderers into indirect draw commands & drives DrawBatchInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final sharedMesh = host.graphics.createMesh(
            Primitives.cube(size: 1.0),
            debugLabel: 'SharedCube',
          );
          final sharedMat = host.graphics.createMaterial(
            MaterialDefinition.dielectric(
              key: 'SharedMat',
              color: const LinearColor(0.8, 0.5, 0.3),
            ),
          );

          for (var i = 0; i < 6; i++) {
            final go = engine.scene.createGameObject(
              'Prop_$i',
              position: Vec3(i * 1.5, 0.0, 0.0),
            );
            go.addComponent(
              MeshRenderer(mesh: sharedMesh, material: sharedMat),
            );
          }

          final batchGo = engine.scene.createGameObject('BatchManager');
          final batcher = batchGo.addComponent(
            DrawBatcherComponent(cellSize: 20.0, maxInstancesPerCluster: 32),
          );

          engine.step(0.016);
          expect(batcher.inputObjectCount, 6);
          expect(batcher.drawCallCount, 1);
          expect(batcher.reductionRatio, closeTo(5.0 / 6.0, 1e-6));

          // Test DrawBatchInspectorUI: click Cell +8m (x=156, y=159)
          final ui = VoxUiContext();
          final uiState = DrawBatchInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 156.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          DrawBatchInspectorUI.render(ui, batcher, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 156.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          DrawBatchInspectorUI.render(ui, batcher, state: uiState);
          final dl = ui.endFrame();

          expect(batcher.cellSize, closeTo(28.0, 1e-6));
          expect(dl.commands.any((c) => c.text == 'Draw Batcher'), isTrue);

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('DrawBatcherComponent'), isNotNull);
          final json = reg.specFor(batcher)!.toJson(batcher);
          expect(json['cellSize'], closeTo(28.0, 1e-6));
          expect(json['maxInstancesPerCluster'], 32);
        },
      );
    },
  );

  group(
    'E91 — Dynamic Loose 3D Octree, Frustum Culling & Ray Queries (voxoctree)',
    () {
      test(
        'OctreeCullerComponent indexes MeshRenderers, culls frustum, raycasts closest & drives OctreeStatsInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final camGo = engine.scene.createGameObject(
            'MainCamera',
            position: const Vec3(0.0, 0.0, 10.0),
          );
          camGo.transform.lookAt(Vec3.zero);
          final cam = camGo.addComponent(
            Camera(fovYRadians: 1.0, near: 0.5, far: 100.0),
          );

          final cubeMesh = host.graphics.createMesh(
            Primitives.cube(size: 1.0),
            debugLabel: 'OctreeCube',
          );
          final mat = host.graphics.createMaterial(
            MaterialDefinition.dielectric(
              key: 'OctreeMat',
              color: const LinearColor(0.4, 0.8, 0.9),
            ),
          );

          final inFront = engine.scene.createGameObject(
            'InFront',
            position: const Vec3(0.0, 0.0, 0.0),
          );
          inFront.addComponent(MeshRenderer(mesh: cubeMesh, material: mat));

          final behind = engine.scene.createGameObject(
            'Behind',
            position: const Vec3(0.0, 0.0, 25.0),
          );
          behind.addComponent(MeshRenderer(mesh: cubeMesh, material: mat));

          final cullerGo = engine.scene.createGameObject('OctreeCuller');
          final culler = cullerGo.addComponent(
            OctreeCullerComponent(
              worldHalfExtent: 64.0,
              maxDepth: 4,
              targetCamera: cam,
            ),
          );

          engine.step(0.016);
          expect(culler.indexedObjectCount, 2);
          expect(culler.visibleCount, 1);
          expect(culler.visibleEntries.first.item, equals(inFront));

          final hit = culler.raycastClosest(
            const Vec3(0.0, 0.0, 10.0),
            const Vec3(0.0, 0.0, -1.0),
          );
          expect(hit, isNotNull);
          expect(hit!.entry.item, equals(inFront));

          // Test OctreeStatsInspectorUI: click Depth +1 (x=156, y=159)
          final ui = VoxUiContext();
          final uiState = OctreeStatsInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 156.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          OctreeStatsInspectorUI.render(ui, culler, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 156.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          OctreeStatsInspectorUI.render(ui, culler, state: uiState);
          final dl = ui.endFrame();
          expect(culler.maxDepth, 5);
          expect(
            dl.commands.any((c) => c.text == 'Loose Octree Culler'),
            isTrue,
          );

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('OctreeCullerComponent'), isNotNull);
          final json = reg.specFor(culler)!.toJson(culler);
          expect(json['maxDepth'], 5);
          expect(json['worldHalfExtent'], closeTo(64.0, 1e-6));
        },
      );
    },
  );

  group('E97 — Active Runtime Octree Frustum Culling', () {
    test(
      'OctreeCullerComponent(applyFrustumCulling: true) hides off-frustum MeshRenderers & restores on disable',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final camGo = engine.scene.createGameObject(
          'MainCamera',
          position: const Vec3(0.0, 0.0, 10.0),
        );
        camGo.transform.lookAt(Vec3.zero);
        camGo.addComponent(Camera(fovYRadians: 1.0, near: 0.5, far: 100.0));

        final cubeMesh = host.graphics.createMesh(Primitives.cube(size: 1.0));
        final mat = host.graphics.createMaterial(
          MaterialDefinition.dielectric(
            key: 'CullMat',
            color: const LinearColor(0.5, 0.7, 0.9),
          ),
        );

        final frontGo = engine.scene.createGameObject(
          'InFront',
          position: Vec3.zero,
        );
        frontGo.addComponent(MeshRenderer(mesh: cubeMesh, material: mat));
        final backGo = engine.scene.createGameObject(
          'Behind',
          position: const Vec3(0.0, 0.0, 25.0),
        );
        backGo.addComponent(MeshRenderer(mesh: cubeMesh, material: mat));

        final culler = engine.scene
            .createGameObject('Culler')
            .addComponent(
              OctreeCullerComponent(applyFrustumCulling: true, maxDepth: 4),
            );

        engine.step(0.016);
        expect(culler.culledCount, 1);
        expect(frontGo.node.children.first.visible, isTrue);
        expect(backGo.node.children.first.visible, isFalse);

        // Disabling culler restores all hidden nodes
        culler.enabled = false;
        expect(culler.culledCount, 0);
        expect(backGo.node.children.first.visible, isTrue);
      },
    );
  });
}
