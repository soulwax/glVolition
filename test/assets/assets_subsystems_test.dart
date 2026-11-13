/// Asset catalog, VFS bundles, model packages, atlases, greedy voxel & LUT tests.
library;

import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../support/subsystems_test_helpers.dart';

void main() {
  group('E3 — AssetCatalog Preload & Cleanup', () {
    test(
      'AssetCatalog preloads procedural textures/audio and releases GPU handles on clear()',
      () async {
        final host = HeadlessHost();
        final engine = Engine(host);
        final progressLog = <(int, int)>[];

        await engine.catalog.load({
          'beep': const AudioEntry('sfx/beep.wav', volume: 0.7),
          'checker': ProceduralTextureEntry(
            width: 4,
            height: 4,
            generatePixels: () => Uint8List(4 * 4 * 4),
          ),
        }, onProgress: (loaded, total) => progressLog.add((loaded, total)));

        expect(progressLog.first, (0, 2));
        expect(progressLog.last, (2, 2));

        engine.catalog.registerMesh('cube', Primitives.cube());
        engine.catalog.registerMaterial(
          'mat',
          const MaterialDefinition(key: 'mat'),
        );

        expect(engine.catalog.clip('beep').path, 'sfx/beep.wav');
        expect(engine.catalog.texture('checker'), isNotNull);
        expect(engine.catalog.mesh('cube'), isNotNull);
        expect(engine.catalog.material('mat'), isNotNull);
        expect(host.graphics.liveMeshes.length, 1);
        expect(host.graphics.liveMaterials.length, 1);
        expect(host.graphics.liveTextures.length, 1);

        engine.catalog.clear();
        expect(host.graphics.liveMeshes, isEmpty);
        expect(host.graphics.liveMaterials, isEmpty);
        expect(host.graphics.liveTextures, isEmpty);
      },
    );
  });

  group('E14 — Model Prefabs (GlbResult)', () {
    test(
      'Prefab.fromGlbResult builds GameObject hierarchy with MeshRenderers and shared GPU handles',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final cube = Primitives.cube();
        final root = SceneNode.group(name: 'Ship');
        final hull = SceneNode(
          name: 'Hull',
          meshData: cube,
          transform: const Transform(translation: Vec3(0, 1, 0)),
        );
        final fin = SceneNode(name: 'Fin', meshData: cube);
        root.addChild(hull);
        hull.addChild(fin);
        final glb = GlbResult(
          rootNode: root,
          meshes: [cube],
          materials: [MaterialDefinition(key: 'paint')],
          nodeMaterials: {hull: 0, fin: 0},
        );

        final meshesBefore = host.graphics.liveMeshes.length;
        final prefab = Prefab.fromGlbResult('Ship', glb, engine);
        // Shared MeshData is uploaded exactly once.
        expect(host.graphics.liveMeshes.length - meshesBefore, 1);

        final a = engine.scene.instantiate(
          prefab,
          position: const Vec3(5, 0, 0),
        );
        final b = engine.scene.instantiate(
          prefab,
          position: const Vec3(-5, 0, 0),
        );
        for (final ship in [a, b]) {
          final hullGo = ship.children.single;
          expect(hullGo.name, 'Hull');
          expect(hullGo.transform.localPosition.y, closeTo(1.0, 1e-6));
          expect(hullGo.getComponent<MeshRenderer>()?.mesh, isNotNull);
          expect(
            hullGo.children.single.getComponent<MeshRenderer>(),
            isNotNull,
          );
        }
        expect(a.transform.position.x, closeTo(5, 1e-6));
        expect(
          a.children.single.getComponent<MeshRenderer>()!.mesh,
          same(b.children.single.getComponent<MeshRenderer>()!.mesh),
        );
        expect(host.graphics.liveMeshes.length - meshesBefore, 1);
      },
    );
  });

  group('E15 — Catalog Prefab Shortcut', () {
    test(
      'AssetCatalog.prefab lazily wraps ModelAssets and spawn instantiates them',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final cube = Primitives.cube();
        final root = SceneNode.group(name: 'Crate');
        root.addChild(SceneNode(name: 'Body', meshData: cube));
        final glb = GlbResult(
          rootNode: root,
          meshes: [cube],
          materials: [MaterialDefinition(key: 'wood')],
        );
        final asset = ModelAsset.fromGlb(
          glb,
          HeadlessResources(host.graphics),
          name: 'crate',
        );
        engine.catalog.putModel('crate', asset);

        expect(engine.catalog.hasPrefab('crate'), isTrue);
        final p1 = engine.catalog.prefab('crate');
        expect(engine.catalog.prefab('crate'), same(p1));

        final go = engine.catalog.spawn('crate', position: const Vec3(3, 0, 0));
        expect(go.name, 'crate');
        expect(go.transform.position.x, closeTo(3, 1e-6));
        expect(
          go.children.single.getComponent<MeshRenderer>()?.mesh,
          isNotNull,
        );
        expect(() => engine.catalog.prefab('missing'), throwsArgumentError);

        engine.catalog.clear();
        expect(engine.catalog.hasPrefab('crate'), isFalse);
      },
    );
  });

  group('E21 — SpriteSheet Grid Slicing', () {
    test(
      'SpriteSheet slices uniform grid cells and slices sub-ranges for animation clips',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // 4 columns x 2 rows of 16x16 tiles (total 64x32)
        final dummyTex = host.graphics.createTexture(
          width: 64,
          height: 32,
          pixels: Uint8List(64 * 32 * 4),
        );

        final sheet = engine.catalog.registerSpriteSheet(
          'hero_sheet',
          texture: dummyTex,
          cellWidth: 16,
          cellHeight: 16,
          columns: 4,
          rows: 2,
        );

        expect(sheet.count, 8);
        expect(sheet.all.length, 8);

        final first = sheet.cell(0, 0);
        expect(first.width, 16.0);
        expect(first.height, 16.0);

        final bottomCorner = sheet.cell(3, 1);
        expect(bottomCorner, isNotNull);

        // Slicing animation clip [0..4]
        final walkClip = sheet.slice(0, 4);
        expect(walkClip.length, 4);

        // Create SpriteRenderer from region
        final renderer = SpriteRenderer.fromRegion(
          first,
          color: 0xFF5566FF,
          layer: 2,
        );
        expect(renderer.layer, 2);
        expect(renderer.color, 0xFF5566FF);
        expect(renderer.region, first);

        // Look up from catalog
        expect(engine.catalog.spriteSheet('hero_sheet'), same(sheet));
      },
    );
  });

  group('E48 — VfsAssetLoader & MigratedSaveStore', () {
    test(
      'E48: VfsAssetLoader resolves layered VPAK bundles, MigratedSaveStore upgrades schemas & AssetBrowserUI renders',
      () async {
        final host = HeadlessHost();
        final engine = Engine(host);

        final basePak = PakBuilder()
          ..addText('data/config.json', '{"difficulty":"normal"}', xorKey: 0x77)
          ..addText('levels/arena.lvl', 'ARENA_V1', xorKey: 0x77);
        final dlcPak = PakBuilder()
          ..addText('data/config.json', '{"difficulty":"hardcore"}');

        final vfsLoader = VfsAssetLoader(fallback: host.assets)
          ..mountPakBytes(
            'base.pak',
            basePak.build(),
            priority: 0,
            xorKey: 0x77,
          )
          ..mountPakBytes('dlc.pak', dlcPak.build(), priority: 10);

        expect(
          await vfsLoader.loadText('data/config.json'),
          '{"difficulty":"hardcore"}',
        );
        expect(await vfsLoader.loadText('levels/arena.lvl'), 'ARENA_V1');

        final migrator = SaveMigrator(targetVersion: 2)
          ..addStep(1, 2, (data) {
            data['credits'] = ((data['gold'] as num?)?.toInt() ?? 0) * 10;
            data.remove('gold');
            return data;
          });

        host.storage.write('slot_1', '{"schemaVersion":1,"gold":45}');
        final saveStore = MigratedSaveStore(
          storage: host.storage,
          migrator: migrator,
        );
        final migrated = saveStore.load('slot_1');
        expect(migrated, isNotNull);
        expect(migrated!.didMigrate, isTrue);
        expect(migrated.data['credits'], 450);

        // Re-reading after auto-persist is now already v2 (didMigrate == false)
        final reloaded = saveStore.load('slot_1')!;
        expect(reloaded.didMigrate, isFalse);
        expect(reloaded.data['credits'], 450);

        // Render AssetBrowserUI via voxui
        final ui = VoxUiContext();
        ui.beginFrame(VoxInput());
        AssetBrowserUI.render(ui, vfsLoader.vfs, globFilter: '**/*.lvl');
        final drawList = ui.endFrame();
        expect(
          drawList.commands.any((c) => c.text == 'levels/arena.lvl'),
          isTrue,
        );
        expect(engine.scene.isLoaded, isTrue);
      },
    );
  });

  group('E49 — LocalizationComponent & VFS Tables', () {
    test(
      'E49: LocalizationComponent loads VFS CSV/JSON tables, persists locale & renders LocalizationDebuggerUI',
      () async {
        final host = HeadlessHost();
        final engine = Engine(host);

        final pak = PakBuilder()
          ..addText(
            'i18n/strings.csv',
            'key,en,de,ja\nmenu.start,Start Game,Spiel starten,ゲーム開始\nhp.low[one],{count} HP left,{count} TP übrig,{count} HP残り\nhp.low[other],{count} HP left,{count} TP übrig,{count} HP残り',
          );
        final vfsLoader = VfsAssetLoader()
          ..mountPakBytes('loc.pak', pak.build());

        final events = <String>[];
        final l10n = LocalizationComponent(onLocaleChanged: events.add);
        engine.scene.createGameObject('Localization', components: [l10n]);

        await l10n.loadCsvAsset('i18n/strings.csv', loader: vfsLoader);
        expect(l10n.tr('menu.start'), 'Start Game');

        l10n.setLocale('de');
        expect(l10n.tr('menu.start'), 'Spiel starten');
        expect(l10n.trPlural('hp.low', 1), '1 TP übrig');
        l10n.saveLocalePreference('user_lang');

        // Reload into a new Engine sharing host storage
        final engine2 = Engine(host);
        final l10n2 = LocalizationComponent()
          ..loadCsv('key,en,de\nmenu.start,Start Game,Spiel starten');
        engine2.scene.createGameObject('Localization2', components: [l10n2]);
        expect(l10n2.loadLocalePreference('user_lang'), isTrue);
        expect(l10n2.activeLocale, 'de');
        expect(events, ['de']);

        // Render LocalizationDebuggerUI via voxui
        final ui = VoxUiContext();
        ui.beginFrame(VoxInput());
        LocalizationDebuggerUI.render(
          ui,
          l10n.manager,
          previewKeys: const ['menu.start'],
        );
        final drawList = ui.endFrame();
        expect(drawList.commands.any((c) => c.text == 'Spiel starten'), isTrue);
      },
    );
  });

  group(
    'E78 — Texture Atlas Packing, 9-Slice Sprites & Bitmap/SDF Font Metrics (voxatlas)',
    () {
      test(
        'TextureAtlasComponent packs 9-slice UI & glyph sprites, shapes bitmap font & drives AtlasPackerInspectorUI',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final tex0 = host.graphics.createTexture(
            width: 128,
            height: 128,
            pixels: Uint8List(128 * 128 * 4),
          );
          final atlasGo = engine.scene.createGameObject('UIAtlas');
          final atlasComp = atlasGo.addComponent(
            TextureAtlasComponent(pageWidth: 128, pageHeight: 128, padding: 2),
          );
          atlasComp.bindPageTexture(0, tex0);
          atlasComp.registerSprite(
            const AtlasSpriteInput(
              id: 'panel_bg',
              width: 48,
              height: 48,
              nineSlice: NineSliceInsets.all(12.0),
            ),
          );
          atlasComp.registerSprite(
            const AtlasSpriteInput(id: 'glyph_A', width: 20, height: 24),
          );
          atlasComp.registerSprite(
            const AtlasSpriteInput(id: 'glyph_V', width: 20, height: 24),
          );

          atlasComp.registerFont(
            BitmapFontLayout(
              fontFamily: 'VoxSansSDF',
              lineHeight: 28.0,
              baseLine: 22.0,
              glyphs: const {
                65: BitmapGlyphMetrics(
                  codePoint: 65,
                  atlasEntryId: 'glyph_A',
                  width: 20.0,
                  height: 24.0,
                  xAdvance: 18.0,
                  sdfSpread: 4.0,
                ),
                86: BitmapGlyphMetrics(
                  codePoint: 86,
                  atlasEntryId: 'glyph_V',
                  width: 20.0,
                  height: 24.0,
                  xAdvance: 18.0,
                  sdfSpread: 4.0,
                ),
              },
              kerningPairs: const {(65, 86): -2.5},
            ),
          );

          final region = atlasComp.spriteRegionFor('panel_bg');
          expect(region, isNotNull);
          expect(region!.texture, same(tex0));
          expect(region.width, closeTo(48.0, 1e-6));

          final slices = atlasComp.sliceQuadsFor(
            'panel_bg',
            destX: 10.0,
            destY: 20.0,
            destW: 200.0,
            destH: 100.0,
          );
          expect(slices.length, 9);

          final glyphs = atlasComp.layoutFontText('VoxSansSDF', 'AV');
          expect(glyphs.length, 2);
          expect(glyphs[1].x - glyphs[0].x, closeTo(15.5, 1e-5));

          // Test AtlasPackerInspectorUI: click Heuristic (x=153, y=159) -> bestAreaFit
          final ui = VoxUiContext();
          final uiState = AtlasPackerInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 153.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          AtlasPackerInspectorUI.render(ui, atlasComp, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 153.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          AtlasPackerInspectorUI.render(ui, atlasComp, state: uiState);
          final dl = ui.endFrame();
          expect(atlasComp.heuristic, MaxRectsHeuristic.bestAreaFit);
          expect(
            dl.commands.any((c) => c.text == 'Texture Atlas Packer'),
            isTrue,
          );

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('TextureAtlasComponent'), isNotNull);
          final json = reg.specFor(atlasComp)!.toJson(atlasComp);
          expect(json['pageWidth'], 128);
          expect(json['heuristic'], 'bestAreaFit');
        },
      );
    },
  );

  group('E92 — 3D Coherent Noise, Worley Cellular & Curl Fields (voxnoise3d)', () {
    test(
      'NoiseFieldVolumeComponent samples scalar & curl velocity, cycles mode via NoiseFieldInspectorUI & serializes',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final noiseGo = engine.scene.createGameObject(
          'NoiseField',
          position: const Vec3(2.4, -1.3, 4.1),
        );
        final field = noiseGo.addComponent(
          NoiseFieldVolumeComponent(
            seed: 4242,
            frequency: 0.35,
            warpAmplitude: 1.5,
            octaves: 4,
            mode: NoiseFieldMode.domainWarp,
          ),
        );

        engine.step(0.016);
        expect(field.lastSampleScalar.isFinite, isTrue);
        expect(field.lastCurlVelocity.length, greaterThan(0.0));

        // Test NoiseFieldInspectorUI: click Mode (x=156, y=159) -> cycles to simplexFbm
        final ui = VoxUiContext();
        final uiState = NoiseFieldInspectorUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 156.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        NoiseFieldInspectorUI.render(ui, field, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 156.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        NoiseFieldInspectorUI.render(ui, field, state: uiState);
        final dl = ui.endFrame();
        expect(field.mode, NoiseFieldMode.simplexFbm);
        expect(dl.commands.any((c) => c.text == '3D Noise & Curl'), isTrue);

        // Verify ComponentRegistry serialization
        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('NoiseFieldVolumeComponent'), isNotNull);
        final json = reg.specFor(field)!.toJson(field);
        expect(json['mode'], 'simplexFbm');
        expect(json['seed'], 4242);
      },
    );
  });

  group(
    'E93 — Perceptual OKLab/OKLCH Gradients & 3D LUT Color Grading (voxcolor)',
    () {
      test(
        'ColorGradingLutComponent evaluates OKLab gradient & 3D LUT, boosts Temp +0.2 via ColorGradingInspectorUI & serializes',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final colorGo = engine.scene.createGameObject('ColorGradeRig');
          final comp = colorGo.addComponent(
            ColorGradingLutComponent(
              lutSize: 16,
              temperature: 0.1,
              contrast: 1.1,
              saturation: 1.05,
            ),
          );

          engine.step(0.016);
          final graded = comp.gradeLinearColor(
            const LinearColor(0.25, 0.45, 0.75),
          );
          expect(
            graded.r.isFinite && graded.g.isFinite && graded.b.isFinite,
            isTrue,
          );
          expect(comp.lastDeltaE, greaterThanOrEqualTo(0.0));

          // Test ColorGradingInspectorUI: click Temp +0.2 (x=152, y=159)
          final ui = VoxUiContext();
          final uiState = ColorGradingInspectorUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 152.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          ColorGradingInspectorUI.render(ui, comp, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 152.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          ColorGradingInspectorUI.render(ui, comp, state: uiState);
          final dl = ui.endFrame();
          expect(comp.temperature, closeTo(0.3, 1e-6));
          expect(dl.commands.any((c) => c.text == 'OKLab Color LUT'), isTrue);

          // Verify ComponentRegistry serialization
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('ColorGradingLutComponent'), isNotNull);
          final json = reg.specFor(comp)!.toJson(comp);
          expect(json['lutSize'], 16);
          expect(json['temperature'], closeTo(0.3, 1e-6));
        },
      );
    },
  );

  group('E95 — Sparse 8x8x8 Voxel Brick Greedy Meshing & AO Baker (voxgreedy)', () {
    test(
      'GreedyVoxelBrickComponent generates MeshData for MeshRenderer, toggles AO via GreedyMesherInspectorUI & serializes',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final mat = host.graphics.createMaterial(
          MaterialDefinition.dielectric(
            key: 'VoxelBrickMat',
            color: const LinearColor(0.3, 0.8, 0.7),
          ),
        );
        final brickGo = engine.scene.createGameObject('GreedyBrick');
        final mr = brickGo.addComponent(MeshRenderer(material: mat));
        final comp = brickGo.addComponent(
          GreedyVoxelBrickComponent(
            brickSize: 8,
            voxelSize: 0.5,
            bakeAo: true,
            autoSyncMeshRenderer: true,
          ),
        );

        engine.step(0.016);
        expect(comp.solidCount, 80);
        expect(comp.quadCount, greaterThan(0));
        expect(comp.triangleCount, comp.quadCount * 2);
        expect(mr.mesh, isNotNull);
        expect(comp.currentMeshData, isNotNull);

        final aoQuadCount = comp.quadCount;

        // Test GreedyMesherInspectorUI: click Toggle AO at (156.0, 159.0) -> bakeAo = false
        final ui = VoxUiContext();
        final uiState = GreedyMesherInspectorUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 156.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        GreedyMesherInspectorUI.render(ui, comp, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 156.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        GreedyMesherInspectorUI.render(ui, comp, state: uiState);
        final dl = ui.endFrame();
        expect(comp.bakeAo, isFalse);
        expect(comp.quadCount, lessThanOrEqualTo(aoQuadCount));
        expect(dl.commands.any((c) => c.text == 'Greedy Voxel Brick'), isTrue);

        // Verify ComponentRegistry serialization
        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('GreedyVoxelBrickComponent'), isNotNull);
        final json = reg.specFor(comp)!.toJson(comp);
        expect(json['brickSize'], 8);
        expect(json['bakeAo'], isFalse);
      },
    );
  });

  group('E101 — Prefab.fromModelPackage (QMSH)', () {
    test(
      'E101: Prefab.fromModelPackage decodes QMSH parts, registers materials & instantiates child MeshRenderers',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final cube = Primitives.cube(size: 1.0);
        final stride = cube.layout.strideFloats; // 18 (surfaceV2)
        final expanded = <double>[];
        if (cube.indices != null) {
          for (final idx in cube.indices!) {
            final base = idx * stride;
            for (var k = 0; k < stride; k++) {
              expanded.add(cube.vertices[base + k]);
            }
          }
        } else {
          expanded.addAll(cube.vertices);
        }
        final vCount = expanded.length ~/ stride;
        const headerBytes = 36;
        final payload = Uint8List(headerBytes + expanded.length * 4);
        final bd = ByteData.sublistView(payload)
          ..setUint8(0, 0x51) // 'Q'
          ..setUint8(1, 0x4D) // 'M'
          ..setUint8(2, 0x53) // 'S'
          ..setUint8(3, 0x48) // 'H'
          ..setUint16(4, stride == 14 ? 1 : 2, Endian.little)
          ..setUint16(6, stride, Endian.little)
          ..setUint32(8, vCount, Endian.little)
          ..setFloat32(12, cube.localBounds.min.x, Endian.little)
          ..setFloat32(16, cube.localBounds.min.y, Endian.little)
          ..setFloat32(20, cube.localBounds.min.z, Endian.little)
          ..setFloat32(24, cube.localBounds.max.x, Endian.little)
          ..setFloat32(28, cube.localBounds.max.y, Endian.little)
          ..setFloat32(32, cube.localBounds.max.z, Endian.little);
        for (var i = 0; i < expanded.length; i++) {
          bd.setFloat32(headerBytes + i * 4, expanded[i], Endian.little);
        }

        final manifest = ModelPackageManifest(
          assetId: 'crate-prop',
          packageHash: '0' * 64,
          sourceFormat: 'glb',
          materials: const ['crate_mat'],
          lods: const ['LOD0'],
          parts: const [
            ModelPackagePart(
              id: 'hull',
              materialSlot: 0,
              lodFiles: {'LOD0': 'hull_lod0.qmesh'},
            ),
          ],
        );
        final pkg = ValidatedModelPackage(
          manifest: manifest,
          payloads: {'hull_lod0.qmesh': payload},
        );

        final cache = ModelCache();
        final prefab = Prefab.fromModelPackage(pkg, engine, cache: cache);
        final instance = prefab.instantiate(
          engine.scene,
          position: const Vec3(2, 0, -4),
        );

        expect(instance.name, 'crate-prop');
        expect(instance.children.length, 1);
        final partGo = instance.children.first;
        expect(partGo.name, 'hull');
        final mr = partGo.getComponent<MeshRenderer>();
        expect(mr, isNotNull);
        expect(mr!.mesh, isNotNull);
        expect(mr.material, isNotNull);
        expect(mr.meshData!.vertices.length, greaterThan(0));
        // Local acquisition inside Prefab.fromModelPackage releases back cleanly to 0.
        expect(cache.cachedCount, 0);
      },
    );
  });
}
