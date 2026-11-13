/// Terrain, water, atmosphere, weather, particles/VFX, dungeons, hex grids, fluids & SDF.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('E5 — Terrain, Water, Buoyancy & AtmosphereVolume', () {
    test(
      'TerrainComponent, WaterSurfaceComponent, and BuoyantBody update height and vessel pose',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final terrain = TerrainComponent(
          TerrainGenerator(
            subdivisionsX: 16,
            subdivisionsZ: 16,
            width: 40,
            depth: 40,
            maxHeight: 8,
            seed: 7,
          ),
          biomeTextureSize: 32,
        );
        engine.scene.createGameObject('Island', components: [terrain]);
        expect(terrain.sampleHeight(0, 0).isFinite, isTrue);

        final water = WaterSurfaceComponent(
          surface: WaterSurfaceMesh(
            subdivisionsX: 8,
            subdivisionsZ: 8,
            width: 30,
            depth: 30,
          ),
          waves: GerstnerWaveEvaluator.ocean(),
        );
        engine.scene.createGameObject('Ocean', components: [water]);

        final boat = engine.scene.createGameObject(
          'Boat',
          position: const Vec3(0, 2, 0),
          components: [BuoyantBody()],
        );

        for (var i = 0; i < 10; i++) {
          engine.step(0.05);
        }
        expect(boat.transform.position.y.isFinite, isTrue);
        expect(boat.getComponent<BuoyantBody>()!.roll.isFinite, isTrue);
      },
    );

    test(
      'AtmosphereVolume advances solar cycle and updates scene RenderSettings & sun Light',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final sunLight = Light.directional(intensity: 1.0);
        final atm = AtmosphereVolume(timeOfDayHours: 6.5, hoursPerSecond: 2.0);
        engine.scene.createGameObject('Sky', components: [sunLight, atm]);

        for (var i = 0; i < 10; i++) {
          engine.step(0.1);
        } // advances 1.0s -> from 6.5h (sunrise) to 8.5h (morning)
        expect(atm.timeOfDayHours, closeTo(8.5, 1e-5));
        expect(atm.currentSolarState, isNotNull);
        expect(engine.scene.renderSettings.skybox, isNotNull);
        expect(engine.scene.renderSettings.fogEnabled, isTrue);
        expect(sunLight.intensity, greaterThan(0));
      },
    );
  });

  group('E18 — ParticleSystem Preset Factories', () {
    test(
      'ParticleSystem preset factories instantiate emitters, burst, and reset active counts',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final mesh = host.graphics.createMesh(Primitives.cube());
        final mat = host.graphics.createMaterial(
          MaterialDefinition(key: 'fire'),
        );

        final campfire = ParticleSystem.campfire(mesh: mesh, material: mat);
        final explosion = ParticleSystem.explosion(mesh: mesh, material: mat);
        final fireflies = ParticleSystem.fireflies(mesh: mesh, material: mat);

        final go = engine.scene.createGameObject('VFX', components: [campfire]);

        expect(campfire.activeParticleCount, 0);
        final spawned = campfire.burst(25);
        expect(spawned, 25);
        expect(campfire.activeParticleCount, 25);

        campfire.reset();
        expect(campfire.activeParticleCount, 0);

        // Verify explosion and fireflies can burst
        go.addComponent(explosion);
        final expSpawned = explosion.burst(50);
        expect(expSpawned, 50);
        expect(explosion.activeParticleCount, 50);
        explosion.clear();
        expect(explosion.activeParticleCount, 0);

        go.addComponent(fireflies);
        final ffSpawned = fireflies.burst(10);
        expect(ffSpawned, 10);
        expect(fireflies.activeParticleCount, 10);
        fireflies.clear();
        expect(fireflies.activeParticleCount, 0);
      },
    );
  });

  group('E19 — TilemapComponent Spatial & Raycast Queries', () {
    test('TilemapComponent cellToWorld, raycast, and hasLineOfSight', () {
      final layer = TileLayer(
        columns: 10,
        rows: 10,
        tileWidth: 16,
        tileHeight: 16,
        originX: 0,
        originY: 0,
        tileset: [SpriteRegion.white, SpriteRegion.white],
      );
      // Place a wall at column 5, row 2
      layer.setTile(5, 2, 1);

      final tilemap = TilemapComponent(layer, solidTiles: [1]);

      // cellToWorld check
      final originCorner = tilemap.cellToWorld(2, 3);
      expect(originCorner.x, 32.0);
      expect(originCorner.y, 48.0);

      final centerPt = tilemap.cellToWorld(2, 3, center: true);
      expect(centerPt.x, 40.0);
      expect(centerPt.y, 56.0);

      // Line of sight horizontally across row 2 (from col 1 to col 8) -> hits wall at col 5
      final startBlocked = tilemap.cellToWorld(1, 2, center: true);
      final endBlocked = tilemap.cellToWorld(8, 2, center: true);
      final hit = tilemap.raycast(startBlocked, endBlocked);

      expect(hit, isNotNull);
      expect(hit!.column, 5);
      expect(hit.row, 2);
      expect(tilemap.hasLineOfSight(startBlocked, endBlocked), isFalse);

      // Line of sight horizontally across row 3 (from col 1 to col 8) -> completely clear
      final startClear = tilemap.cellToWorld(1, 3, center: true);
      final endClear = tilemap.cellToWorld(8, 3, center: true);
      final hitClear = tilemap.raycast(startClear, endClear);

      expect(hitClear, isNull);
      expect(tilemap.hasLineOfSight(startClear, endClear), isTrue);
    });
  });

  group('E31 — ProceduralDungeon & PoissonScatter', () {
    test(
      'E31: ProceduralDungeonComponent generates BSP rooms, corridors, and NavGrid',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final dungeonGo = engine.scene.createGameObject('Dungeon');
        final layer = TileLayer(
          columns: 40,
          rows: 40,
          tileWidth: 16,
          tileHeight: 16,
          tileset: [SpriteRegion.white, SpriteRegion.white],
        );
        final tilemap = dungeonGo.addComponent(
          TilemapComponent(layer, solidTiles: [1]),
        );
        final dungeon = dungeonGo.addComponent(
          ProceduralDungeonComponent(
            width: 40,
            height: 40,
            minRoomSize: 4,
            maxRoomSize: 10,
            tileSize: 2.0,
          ),
        );

        final result = dungeon.generate(customSeed: 42, targetTilemap: tilemap);

        expect(result.rooms, isNotEmpty);
        expect(dungeon.rooms, equals(result.rooms));
        expect(dungeon.roomCenters, hasLength(dungeon.rooms.length));
        expect(dungeon.navGrid, isNotNull);

        // Verify player spawn is within bounds and on a walkable floor
        final spawn = dungeon.playerSpawn;
        expect(spawn.x, greaterThan(0.0));
        expect(spawn.z, greaterThan(0.0));

        final spawnTileX = (spawn.x / 2.0).floor();
        final spawnTileZ = (spawn.z / 2.0).floor();
        expect(dungeon.navGrid!.isWalkable(spawnTileX, spawnTileZ), isTrue);
        expect(tilemap.layer.tileAt(spawnTileX, spawnTileZ), equals(1));
      },
    );

    test(
      'E31: PoissonScatterComponent distributes non-overlapping prefabs',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final scatterGo = engine.scene.createGameObject('ScatterZone');
        final scatter = scatterGo.addComponent(
          PoissonScatterComponent(
            areaWidth: 50.0,
            areaHeight: 50.0,
            minDistance: 8.0,
            seed: 999,
          ),
        );

        final positions = scatter.sampleWorldPositions();
        expect(positions, isNotEmpty);

        // Verify minimum clearance between all sampled points
        for (var i = 0; i < positions.length; i++) {
          for (var j = i + 1; j < positions.length; j++) {
            final dx = positions[i].x - positions[j].x;
            final dz = positions[i].z - positions[j].z;
            final distSq = dx * dx + dz * dz;
            expect(distSq, greaterThanOrEqualTo(7.99 * 7.99));
          }
        }

        // Instantiate prefabs into scene
        final treePrefab = Prefab('TreePrefab', (root) {
          root.addComponent(MeshRenderer());
        });

        final spawned = scatter.spawnPrefabs(treePrefab);
        expect(spawned, hasLength(positions.length));
        expect(scatterGo.children, hasLength(positions.length));
      },
    );
  });

  group('E38 — VisualEffectComponent & Explosion Forces', () {
    test(
      'E38: VisualEffectComponent integrates voxvfx simulation with GameObject transform',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final fireVfx = VisualEffectComponent.fire(maxParticles: 100);
        final go = engine.scene.createGameObject(
          'Torch',
          components: [fireVfx],
        );
        go.transform.position = const Vec3(10.0, 5.0, -2.0);

        expect(fireVfx.simulation.activeParticleCount, 0);

        // Step engine -> should update emitter position and spawn particles
        engine.step(0.1);

        expect(fireVfx.simulation.emitterPosition.x, closeTo(10.0, 1e-4));
        expect(fireVfx.simulation.emitterPosition.y, closeTo(5.0, 1e-4));
        expect(fireVfx.simulation.emitterPosition.z, closeTo(-2.0, 1e-4));
        expect(fireVfx.simulation.activeParticleCount, greaterThan(0));

        // Test manual burst and clear
        fireVfx.burst(15);
        final countAfterBurst = fireVfx.simulation.activeParticleCount;
        expect(countAfterBurst, greaterThanOrEqualTo(15));

        fireVfx.clear();
        expect(fireVfx.simulation.activeParticleCount, 0);
      },
    );

    test('E38: VisualEffectComponent.explosion triggers burst forces', () {
      final explosion = VisualEffectComponent.explosion(particleCount: 50);
      expect(explosion.simulation.activeParticleCount, 0);

      // Advance simulation step -> burst triggered at time 0
      explosion.step(0.016);
      expect(explosion.simulation.activeParticleCount, 50);

      for (final p in explosion.simulation.activeParticles) {
        expect(p.velocity.length, greaterThan(0.0));
      }
    });
  });

  group('E39 — VoxelTerrainComponent DDA & Carving', () {
    test(
      'E39: VoxelTerrainComponent builds terrain, performs 3D DDA raycasts, and carves cavities',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final terrain = VoxelTerrainComponent();
        final go = engine.scene.createGameObject(
          'VoxelWorld',
          components: [terrain],
        );
        go.transform.position = const Vec3(0, 0, 0);

        // Fill a solid 4x4x4 block of stone
        terrain.fillBox(
          const VoxelCoord(0, 0, 0),
          const VoxelCoord(3, 3, 3),
          1, // Stone
        );

        // Verify voxel data
        expect(terrain.getVoxel(1, 1, 1), equals(1));
        expect(terrain.getVoxel(5, 5, 5), equals(0));

        // Raycast from (1.5, 10.0, 1.5) downward (0, -1, 0)
        final hit = terrain.raycastVoxel(
          const Vec3(1.5, 10.0, 1.5),
          const Vec3(0.0, -1.0, 0.0),
          maxDistance: 20.0,
        );

        expect(hit, isNotNull);
        expect(hit!.hitVoxel, equals(const VoxelCoord(1, 3, 1)));
        expect(hit.normal.y, closeTo(1.0, 1e-4)); // hit top face pointing +Y
        expect(
          hit.adjacentEmptyVoxel,
          equals(const VoxelCoord(1, 4, 1)),
        ); // block above

        // Rebuild greedy meshes
        final meshes = terrain.rebuildAllMeshes();
        expect(meshes, isNotEmpty);
        final mesh = meshes.values.first;
        // 4x4x4 cube faces merged into 6 quads
        expect(mesh.quadCount, equals(6));

        // Carve sphere at (1, 1, 1)
        final carved = terrain.carveSphere(const VoxelCoord(1, 1, 1), 1.5);
        expect(carved, greaterThan(0));
        expect(terrain.getVoxel(1, 1, 1), equals(0));
      },
    );
  });

  group('E44 — HexGrid, WFC Biomes & WfcTilemapGenerator', () {
    test(
      'E44: HexGridComponent projects world coords, runs WFC biomes, paths, reachability & FOV',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final grid = HexGridComponent.radial(radius: 3, hexSize: 2.0);
        engine.scene.createGameObject(
          'TacticalBoard',
          position: const Vec3(10, 0, -5),
          components: [grid],
        );

        const targetHex = HexCoord(1, -1);
        final worldPos = grid.hexToWorld(targetHex);
        expect(grid.worldToHex(worldPos), targetHex);

        final rules = WfcRuleSet<String>.hex()
          ..addTile('grass', weight: 4.0)
          ..addTile('hills', weight: 2.0)
          ..addTile('mountain', weight: 1.0);
        for (int d = 0; d < 6; d++) {
          rules.allow('grass', d, 'grass');
          rules.allow('grass', d, 'hills');
          rules.allow('hills', d, 'hills');
          rules.allow('hills', d, 'mountain');
          rules.allow('mountain', d, 'mountain');
        }

        final ok = grid.generateWfcBiomes(
          rules: rules,
          seed: 42,
          preplaced: {HexCoord.zero: 'hills', const HexCoord(1, 0): 'mountain'},
          terrainCatalog: const {
            'grass': (moveCost: 1.0, passable: true, blocksSight: false),
            'hills': (moveCost: 2.0, passable: true, blocksSight: false),
            'mountain': (moveCost: 99.0, passable: false, blocksSight: true),
          },
        );
        expect(ok, isTrue);
        expect(grid.map[HexCoord.zero]!.terrain, 'hills');
        expect(grid.map[const HexCoord(1, 0)]!.passable, isFalse);

        // Visibility blocked directly behind mountain at (1, 0)
        final visible = grid.computeVisible(HexCoord.zero, radius: 3);
        expect(visible.contains(const HexCoord(1, 0)), isTrue);
        expect(visible.contains(const HexCoord(2, 0)), isFalse);

        // Reachability respects movement budget and avoids mountain
        final reach = grid.reachableFrom(HexCoord.zero, 2.0);
        expect(reach.canReach(const HexCoord(1, 0)), isFalse);
        expect(reach.canReach(HexCoord.zero), isTrue);
      },
    );

    test(
      'E44: WfcTilemapGenerator populates TileLayer and HexGridUI renders & picks hovered hex',
      () {
        final layer = TileLayer(
          columns: 6,
          rows: 5,
          tileWidth: 16,
          tileHeight: 16,
          tileset: [SpriteRegion.white, SpriteRegion.white, SpriteRegion.white],
        );
        final rules = WfcRuleSet<int>.grid2d()
          ..addSocketTile(0, ['g', 'g', 'g', 'g'], weight: 3.0)
          ..addSocketTile(1, ['g', 'r', 'g', 'r'], weight: 1.0)
          ..addSocketTile(2, ['r', 'g', 'r', 'g'], weight: 1.0);

        final filled = WfcTilemapGenerator.populate(
          layer: layer,
          rules: rules,
          seed: 9,
          preplaced: {(2, 2): 1},
        );
        expect(filled, isTrue);
        expect(layer.tileAt(2, 2), 1);

        final grid = HexGridComponent.radial(radius: 2, hexSize: 1.0);
        grid.map[const HexCoord(1, 0)]!.passable = false;

        final ui = VoxUiContext();
        // Window at (20, 20, 360, 340) places center at (200, 20 + 26 + 314*0.5 = 203)
        final centerX = 20.0 + 360.0 * 0.5;
        final centerY =
            20.0 +
            ui.style.titleBarHeight +
            (340.0 - ui.style.titleBarHeight) * 0.5;
        ui.beginFrame(VoxInput(mouseX: centerX, mouseY: centerY));
        final hovered = HexGridUI.render(
          ui,
          grid,
          x: 20,
          y: 20,
          width: 360,
          height: 340,
          selectedHex: HexCoord.zero,
          reachable: {const HexCoord(-1, 0), const HexCoord(0, -1)},
          path: const [HexCoord.zero, HexCoord(-1, 0)],
        );
        final cmds = ui.endFrame();

        expect(hovered, HexCoord.zero);
        expect(
          cmds.commands.where((c) => c.type == DrawCmdType.line).length,
          greaterThan(100),
        );
      },
    );
  });

  group('E55 — Terrain Noise Graph, Hydraulic Erosion & Biomes (voxbiome)', () {
    test(
      'BiomeTerrainGeneratorComponent synthesizes eroded heightfield, RGBA splat texture, and responds to NoiseErosionUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final terrainGo = scene.createGameObject('IslandBiomeTerrain');
        final terrain = terrainGo.addComponent(
          BiomeTerrainGeneratorComponent(
            seed: 404,
            gridWidth: 24,
            gridHeight: 24,
            worldWidth: 24.0,
            worldDepth: 24.0,
            amplitude: 6.5,
            initialErosionDroplets: 300,
            initialThermalIterations: 4,
          ),
        );
        engine.step(0.016);

        final mr = terrainGo.getComponent<MeshRenderer>();
        expect(mr, isNotNull);
        expect(mr!.mesh, isNotNull);
        expect(terrain.currentMaterial, isNotNull);
        expect(terrain.vertexCount, 24 * 24);
        expect(terrain.triangleCount, 23 * 23 * 2);
        expect(terrain.albedoPixels!.length, 24 * 24 * 4);
        expect(terrain.splatMaskPixels!.length, 24 * 24 * 4);
        expect(terrain.lastErosionStats!.dropletsSimulated, 300);
        expect(terrain.lastErosionStats!.totalErodedVolume, greaterThan(0.0));
        terrain.currentMeshData!.validate();

        final sampledH = terrain.sampleHeight(0.0, 0.0);
        final sampledN = terrain.sampleNormal(0.0, 0.0);
        expect(sampledH.isFinite, isTrue);
        expect(sampledN.y, greaterThan(0.2));
        expect(terrain.classifyAt(0.0, 0.0).r, inInclusiveRange(0, 255));

        // Click 'Erode +250' button in NoiseErosionUI at (60, 156).
        final ui = VoxUiContext();
        final uiState = NoiseErosionUiState();
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
        NoiseErosionUI.render(ui, terrain, state: uiState);
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: btnX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        NoiseErosionUI.render(ui, terrain, state: uiState);
        final drawList = ui.endFrame();

        expect(terrain.lastErosionStats!.dropletsSimulated, 550);
        expect(drawList.commands.any((c) => c.text == '404 / 24x24'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('BiomeTerrainGeneratorComponent'), isNotNull);
        final json = reg.specFor(terrain)!.toJson(terrain);
        expect(json['seed'], 404);
        expect(json['gridWidth'], 24);
      },
    );
  });

  group('E57 — Astronomical Day/Night Cycle, Weather & Wind Zones (voxsky)', () {
    test(
      'DayNightSkyComponent, WeatherVolumeComponent, WindZoneComponent & WeatherInspectorUI drive lighting, fog & wind',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final sun = Light.directional(intensity: 1.0);
        final weather = WeatherVolumeComponent(
          initialWeather: WeatherKind.clear,
          transitionDurationSeconds: 1.0,
        );
        final skyComp = DayNightSkyComponent(
          initialHours: 12.0,
          dayLengthSeconds: 24.0,
          sunLight: sun,
          weatherVolume: weather,
        );
        scene.createGameObject(
          'AtmosphereController',
          components: [sun, weather, skyComp],
        );

        final windZoneGo = scene.createGameObject(
          'WindTurbine',
          position: const Vec3(10.0, 0.0, 0.0),
          components: [
            WindZoneComponent(
              shape: WindZoneShape.sphericalRadial,
              radius: 6.0,
              strength: 12.0,
            ),
          ],
        );
        expect(windZoneGo.activeInHierarchy, isTrue);

        engine.step(0.05);
        final noonIntensity = sun.intensity;
        expect(noonIntensity, greaterThan(2.0));
        expect(scene.renderSettings.skybox, isNotNull);
        expect(scene.renderSettings.fogEnabled, isTrue);

        final zoneWind = weather.sampleWindAt(const Vec3(11.5, 0.0, 0.0));
        final farWind = weather.sampleWindAt(const Vec3(40.0, 0.0, 0.0));
        expect(zoneWind.length, greaterThan(farWind.length + 4.0));

        // Click 'Storm' button in WeatherInspectorUI at x=198, y=156.
        final ui = VoxUiContext();
        final uiState = WeatherInspectorUiState();
        const stormX = 198.0;
        const btnY = 156.0;
        ui.beginFrame(
          VoxInput(
            mouseX: stormX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        WeatherInspectorUI.render(
          ui,
          skyComp,
          weather: weather,
          state: uiState,
        );
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: stormX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        WeatherInspectorUI.render(
          ui,
          skyComp,
          weather: weather,
          state: uiState,
        );
        ui.endFrame();

        for (var i = 0; i < 30; i++) {
          engine.step(0.05);
        }

        expect(weather.weatherKind, WeatherKind.storm);
        expect(weather.wetness01, greaterThan(0.15));
        expect(weather.currentSnapshot.cloudCoverage01, greaterThan(0.9));

        ui.beginFrame(VoxInput());
        WeatherInspectorUI.render(
          ui,
          skyComp,
          weather: weather,
          state: uiState,
        );
        final drawList = ui.endFrame();
        expect(drawList.commands.any((c) => c.text == 'storm / 100%'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('DayNightSkyComponent'), isNotNull);
        expect(reg.specByName('WeatherVolumeComponent'), isNotNull);
        expect(reg.specByName('WindZoneComponent'), isNotNull);
        final json = reg.specFor(weather)!.toJson(weather);
        expect(json['weatherKind'], 'storm');
      },
    );
  });

  group('E67 — Eulerian Shallow-Water & Cellular Fire Grids (voxfluid)', () {
    test(
      'FluidSurfaceComponent conserves water across terrain, quenches fire, builds MeshData & renders FluidInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        scene.createGameObject(
          'BasinTerrain',
          components: [
            TerrainComponent(
              TerrainGenerator(
                width: 24,
                depth: 24,
                subdivisionsX: 16,
                subdivisionsZ: 16,
                maxHeight: 0.4,
                seed: 3,
              ),
            ),
          ],
        );

        final fluidGo = scene.createGameObject('BasinFluid');
        final fluidSim = fluidGo.addComponent(
          FluidSurfaceComponent(
            gridWidth: 10,
            gridDepth: 10,
            cellSize: 1.0,
            autoSyncTerrain: true,
            generateMesh: true,
          ),
        );

        fluidSim.addWaterVolume(2, 5, 16.0);
        fluidSim.igniteFire(6, 5, heat: 2.4);
        expect(fluidSim.currentWaterMeshData, isNotNull);
        expect(fluidGo.getComponent<MeshRenderer>(), isNotNull);
        expect(fluidSim.burningCellCount, greaterThanOrEqualTo(1));

        for (var i = 0; i < 40; i++) {
          engine.step(0.1);
        }

        expect(fluidSim.totalWaterVolume, closeTo(16.0, 1e-2));
        expect(fluidSim.floodedCellCount, greaterThan(15));
        expect(fluidSim.water.waterDepthAt(6, 5), greaterThan(0.02));
        expect(fluidSim.fire.burnAt(6, 5), closeTo(0.0, 1e-6));

        // Clear center cell to test UI 'Ignite' (x=158, y=156), 'Rain +2m3' (x=72, y=156) & 'Pause' (x=240, y=156)
        fluidSim.water.clearWater();
        fluidSim.fillFireFuelUniform(1.0);

        final ui = VoxUiContext();
        final uiState = FluidInspectorUiState();
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: 158.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        FluidInspectorUI.render(ui, fluidSim, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 158.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        FluidInspectorUI.render(ui, fluidSim, state: uiState);
        ui.endFrame();
        expect(fluidSim.burningCellCount, greaterThanOrEqualTo(1));

        ui.beginFrame(
          VoxInput(
            mouseX: 72.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        FluidInspectorUI.render(ui, fluidSim, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 72.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        FluidInspectorUI.render(ui, fluidSim, state: uiState);
        ui.endFrame();
        expect(fluidSim.totalWaterVolume, closeTo(2.0, 1e-5));

        ui.beginFrame(
          VoxInput(
            mouseX: 240.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        FluidInspectorUI.render(ui, fluidSim, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 240.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        FluidInspectorUI.render(ui, fluidSim, state: uiState);
        ui.endFrame();

        ui.beginFrame(VoxInput());
        FluidInspectorUI.render(ui, fluidSim, state: uiState);
        final drawList = ui.endFrame();

        expect(fluidSim.paused, isTrue);
        expect(drawList.commands.any((c) => c.text == 'PAUSED'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('FluidSurfaceComponent'), isNotNull);
        final json = reg.specFor(fluidSim)!.toJson(fluidSim);
        expect(json['gridWidth'], 10);
        expect(json['paused'], isTrue);
      },
    );
  });

  group('E72 — Procedural Floorplan Split-Grammar & Connectivity (voxarch)', () {
    test(
      'FloorplanGeneratorComponent subdivides specs, builds doorway-cut geometry & NavGrid and responds to FloorplanInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final gen = scene
            .createGameObject('BuildingGen')
            .addComponent(
              FloorplanGeneratorComponent(
                boundsWidth: 16.0,
                boundsDepth: 12.0,
                wallHeight: 3.0,
                seed: 101,
                carveCentralCorridor: false,
                spawnGeometry: true,
              ),
            );

        engine.step(0.016);
        final initial = gen.lastResult!;
        expect(initial.rooms.length, 5);
        expect(initial.isFullyConnected, isTrue);
        expect(gen.spawnedObjectCount, greaterThan(10));

        final nav = gen.toNavGrid(cellSize: 1.0);
        expect(nav.width, 16);
        expect(nav.height, 12);

        final ui = VoxUiContext();
        final uiState = FloorplanInspectorUiState();
        const btnY = 156.0;

        // Click 'Seed +1' (x=150) then 'Corridor' (x=237)
        ui.beginFrame(
          VoxInput(
            mouseX: 150.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        FloorplanInspectorUI.render(ui, gen, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 150.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        FloorplanInspectorUI.render(ui, gen, state: uiState);
        ui.endFrame();
        expect(gen.seed, 102);

        ui.beginFrame(
          VoxInput(
            mouseX: 237.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        FloorplanInspectorUI.render(ui, gen, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 237.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        FloorplanInspectorUI.render(ui, gen, state: uiState);
        ui.endFrame();
        expect(gen.carveCentralCorridor, isTrue);
        expect(gen.lastResult!.rooms.any((r) => r.isCorridor), isTrue);
        expect(gen.lastResult!.isFullyConnected, isTrue);

        ui.beginFrame(VoxInput());
        FloorplanInspectorUI.render(ui, gen, state: uiState);
        final drawList = ui.endFrame();
        expect(drawList.commands.any((c) => c.text == 'CONNECTED'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('FloorplanGeneratorComponent'), isNotNull);
        final json = reg.specFor(gen)!.toJson(gen);
        expect(json['seed'], 102);
      },
    );
  });

  group('E74 — Signed Distance Field CSG Sculpting & Surface Nets (voxsdf)', () {
    test(
      'SdfVolumeComponent builds Surface Nets MeshRenderer, raymarches CSG ops & handles SdfSculptInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final go = engine.scene.createGameObject(
          'SculptVolume',
          position: const Vec3(2.0, 0.0, 0.0),
        );
        final vol = go.addComponent(
          SdfVolumeComponent(
            nx: 18,
            ny: 18,
            nz: 18,
            voxelSize: 0.25,
            brushRadius: 1.1,
            brushSmoothness: 0.25,
          ),
        );

        vol.addSphere(Vec3.zero, 1.1);
        expect(vol.brushCount, 1);
        expect(vol.vertexCount, greaterThan(40));
        expect(vol.triangleCount, greaterThan(60));
        expect(vol.currentMeshData, isNotNull);

        final mr = go.getComponent<MeshRenderer>();
        expect(mr, isNotNull);
        expect(mr!.mesh, isNotNull);

        final hit = vol.raymarchWorld(
          const Vec3(6.0, 0.0, 0.0),
          const Vec3(-1.0, 0.0, 0.0),
        );
        expect(hit, isNotNull);
        expect(hit!.point.x, closeTo(3.1, 0.18));
        expect(hit.normal.x, greaterThan(0.8));

        final ui = VoxUiContext();
        final uiState = SdfSculptInspectorUiState();
        const btnY = 156.0;

        // Click 'Carve' (x=149) -> carves sphere at (0.495, 0.495, 0)
        ui.beginFrame(
          VoxInput(
            mouseX: 149.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        SdfSculptInspectorUI.render(ui, vol, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 149.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        SdfSculptInspectorUI.render(ui, vol, state: uiState);
        ui.endFrame();

        expect(vol.brushCount, 2);
        expect(vol.triangleCount, greaterThan(0));
        expect(
          vol.field.sampleTrilinear(const SdfVec3(0.495, 0.495, 0.0)),
          greaterThan(0.0),
        );

        // Undo carve returns cavity back to solid interior
        expect(vol.undoLastBrush(), isTrue);
        expect(vol.brushCount, 1);
        expect(
          vol.field.sampleTrilinear(const SdfVec3(0.495, 0.495, 0.0)),
          lessThan(0.0),
        );

        // Click 'Rad +0.2' (x=318) -> 1.1 + 0.2 = 1.3
        ui.beginFrame(
          VoxInput(
            mouseX: 318.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        SdfSculptInspectorUI.render(ui, vol, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 318.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        SdfSculptInspectorUI.render(ui, vol, state: uiState);
        ui.endFrame();
        expect(vol.brushRadius, closeTo(1.3, 1e-6));

        ui.beginFrame(VoxInput());
        SdfSculptInspectorUI.render(ui, vol, state: uiState);
        final drawList = ui.endFrame();
        expect(
          drawList.commands.any((c) => c.text == '1 ops / k=0.25'),
          isTrue,
        );

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('SdfVolumeComponent'), isNotNull);
        final json = reg.specFor(vol)!.toJson(vol);
        expect(json['brushRadius'], closeTo(1.3, 1e-6));
      },
    );
  });

  group(
    'E81 — Particle Ribbons & Divergence-Free Curl Turbulence (voxribbon)',
    () {
      test(
        'ParticleRibbonComponent builds Catmull-Rom ribbon MeshRenderer, emits curl particles & drives RibbonInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final mr = MeshRenderer();
          final rib = ParticleRibbonComponent(
            emissionRate: 30.0,
            curlAmplitude: 3.5,
            startWidth: 0.8,
            endWidth: 0.1,
            minVertexDistance: 0.25,
          );
          final go = engine.scene.createGameObject(
            'Comet',
            position: const Vec3(0.0, 0.0, 0.0),
            components: [mr, rib],
          );

          for (var i = 0; i < 6; i++) {
            go.transform.position = Vec3(i * 0.6, (i * 0.2), 0.0);
            engine.step(0.05);
          }

          expect(rib.ribbonPointCount, greaterThanOrEqualTo(5));
          expect(rib.particleCount, greaterThan(0));
          expect(rib.lastMeshData, isNotNull);
          expect(mr.mesh, isNotNull);

          // Test RibbonInspectorUI: click Burst +12 (x=140, y=159)
          final beforeCount = rib.particleCount;
          final ui = VoxUiContext();
          final uiState = RibbonInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 140.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          RibbonInspectorUI.render(ui, rib, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 140.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          RibbonInspectorUI.render(ui, rib, state: uiState);
          final dl = ui.endFrame();
          expect(rib.particleCount, greaterThanOrEqualTo(beforeCount + 12));
          expect(
            dl.commands.any((c) => c.text == 'Particle Ribbon FX'),
            isTrue,
          );

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('ParticleRibbonComponent'), isNotNull);
          final json = reg.specFor(rib)!.toJson(rib);
          expect(json['curlAmplitude'], closeTo(3.5, 1e-6));
          expect(json['emitting'], isTrue);
        },
      );
    },
  );
}
