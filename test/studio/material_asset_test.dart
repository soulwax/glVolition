/// S4-E test: Verifies `.vmat` import/save round-trip, live hot-update fan-out
/// across multiple subscribers, `MaterialPropertyBlock` override precedence,
/// `MaterialInspectorModel`, and `RenderQueueSorter` opaque/transparent order.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S4-E — .vmat Material Assets, Hot-Update, MPB & Render Queues', () {
    test(
      'VmatImporter & MaterialInspectorModel fan out live edits to all subscribers',
      () async {
        final fs = MemoryProjectFileSystem();
        final importer = VmatImporter(fs);

        const initial = VmatAsset(
          guid: 'mat-hero-001',
          name: 'HeroArmor',
          keywords: {ShaderKeyword.normalMap, ShaderKeyword.ormMap},
          properties: {'roughness': 0.35, 'metallic': 0.85},
          textureGuids: {'albedo': 'tex-001'},
          renderQueue: RenderQueue.geometry,
        );
        await importer.saveToPath('assets/materials/hero.vmat', initial);

        // Re-import round-trip from VFS
        final reloaded = await importer.importFromPath(
          'assets/materials/hero.vmat',
        );
        expect(reloaded.guid, equals('mat-hero-001'));
        expect(reloaded.keywords, contains(ShaderKeyword.normalMap));

        // Subscribe two independent consumers (simulating 2 MeshRenderers)
        final receivedA = <double>[];
        final receivedB = <double>[];
        final unsubA = importer.subscribe(
          'mat-hero-001',
          (_, compiled) => receivedA.add(compiled.roughness),
        );
        importer.subscribe(
          'mat-hero-001',
          (_, compiled) => receivedB.add(compiled.roughness),
        );

        final inspector = MaterialInspectorModel(
          importer: importer,
          initialAsset: reloaded,
        );
        inspector.setProperty('roughness', 0.15);
        inspector.setKeyword(ShaderKeyword.emissiveMap, true);
        inspector.setTextureGuid('emissive', 'tex-emissive-002');

        expect(receivedA.last, closeTo(0.15, 1e-6));
        expect(receivedB.last, closeTo(0.15, 1e-6));
        expect(inspector.asset.keywords, contains(ShaderKeyword.emissiveMap));
        expect(
          inspector.asset.textureGuids['emissive'],
          equals('tex-emissive-002'),
        );

        unsubA();
        inspector.setProperty('roughness', 0.65);
        expect(receivedA.last, closeTo(0.15, 1e-6));
        expect(receivedB.last, closeTo(0.65, 1e-6));
      },
    );

    test(
      'MaterialPropertyBlock overrides base MaterialDefinition without mutating it',
      () {
        const base = MaterialDefinition(
          key: 'crate',
          roughness: 0.7,
          metallic: 0.0,
          tintR: 1.0,
          tintG: 1.0,
          tintB: 1.0,
        );
        final mpb = MaterialPropertyBlock()
          ..setFloat('roughness', 0.2)
          ..setFloat('metallic', 1.0)
          ..setColor('albedoColor', const LinearColor(0.9, 0.2, 0.1));

        final effective = mpb.applyTo(base);
        expect(effective.roughness, closeTo(0.2, 1e-6));
        expect(effective.metallic, closeTo(1.0, 1e-6));
        expect(effective.tintR, closeTo(0.9, 1e-6));
        // Base remains untouched
        expect(base.roughness, closeTo(0.7, 1e-6));
        expect(base.metallic, closeTo(0.0, 1e-6));
      },
    );

    test(
      'RenderQueueSorter sorts opaque front-to-back and transparent back-to-front',
      () {
        final sorted = RenderQueueSorter.sort(const [
          RenderQueueDrawItem(
            id: 'glass_near',
            renderQueue: RenderQueue.transparent,
            cameraDistance: 3.0,
          ),
          RenderQueueDrawItem(
            id: 'glass_far',
            renderQueue: RenderQueue.transparent,
            cameraDistance: 12.0,
          ),
          RenderQueueDrawItem(
            id: 'wall_far',
            renderQueue: RenderQueue.geometry,
            cameraDistance: 20.0,
          ),
          RenderQueueDrawItem(
            id: 'wall_near',
            renderQueue: RenderQueue.geometry,
            cameraDistance: 4.0,
          ),
          RenderQueueDrawItem(
            id: 'sky',
            renderQueue: RenderQueue.background,
            cameraDistance: 100.0,
          ),
          RenderQueueDrawItem(
            id: 'hud_overlay',
            renderQueue: RenderQueue.overlay,
            cameraDistance: 1.0,
          ),
        ]);

        expect(
          [for (final i in sorted) i.id],
          equals([
            'sky',
            'wall_near',
            'wall_far',
            'glass_far',
            'glass_near',
            'hud_overlay',
          ]),
        );
      },
    );
  });
}
