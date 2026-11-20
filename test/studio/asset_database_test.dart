/// S1-C tests: AssetDatabase GUID allocation, deterministic seeded GUIDs,
/// rename/move preservation, incremental import cache hits, transitive
/// dependency invalidation, orphan-meta detection, and Memory vs IO FS parity.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

import '../../tool/studio/io_project_fs.dart';

void main() {
  group('S1-C — AssetDatabase & .vmeta GUID System', () {
    Future<void> runFixtureScenario(ProjectFileSystem fs) async {
      await fs.writeString('assets/textures/albedo.png', 'PNGDATA-v1');
      final db = AssetDatabase(
        fs,
        guidGenerator: AssetGuidGenerator(Random(42)),
      );

      await db.refresh();
      final tex = db.getByPath('assets/textures/albedo.png')!;
      expect(tex.guid.length, equals(32));
      expect(db.importCount, equals(1));

      // Create material depending on texture GUID and scene depending on material
      await fs.writeString(
        'assets/materials/hero.vmat',
        jsonEncode({
          'shader': 'lit',
          'dependencyGuids': [tex.guid],
        }),
      );
      await db.refresh();
      final mat = db.getByPath('assets/materials/hero.vmat')!;
      // Texture was unchanged -> cache hit! Only material imported (+1 => 2)
      expect(db.importCount, equals(2));

      await fs.writeString(
        'assets/scenes/main.scene.json',
        jsonEncode({
          'name': 'Main',
          'dependencyGuids': [mat.guid],
        }),
      );
      await db.refresh();
      final scene = db.getByPath('assets/scenes/main.scene.json')!;
      expect(db.importCount, equals(3));

      // Unchanged refresh -> zero additional imports!
      await db.refresh();
      expect(db.importCount, equals(3));

      // Moving/renaming texture preserves GUID
      await db.moveAsset(
        'assets/textures/albedo.png',
        'assets/textures/hero_albedo.png',
      );
      expect(
        db.resolvePath(tex.guid),
        equals('assets/textures/hero_albedo.png'),
      );
      expect(
        db.resolveGuid('assets/textures/hero_albedo.png'),
        equals(tex.guid),
      );

      // Updating texture import settings invalidates texture -> material -> scene transitively
      final invalidated = await db.updateImportSettings(tex.guid, {
        'srgb': true,
        'generateMips': true,
      });
      expect(invalidated, equals([tex.guid, mat.guid, scene.guid]));
      expect(db.importCount, equals(6));

      // Orphan .vmeta detection
      await fs.writeString(
        'assets/textures/ghost.png.vmeta',
        const AssetMeta(
          guid: '00000000000040008000000000000001',
          importerId: 'texture',
          importerVersion: 1,
          contentHash: 'deadbeefdeadbeef',
        ).toJsonString(),
      );
      await db.refresh();
      expect(db.orphanMetas, contains('assets/textures/ghost.png.vmeta'));
    }

    test(
      'produces identical GUIDs and behavior on MemoryProjectFileSystem and IoProjectFileSystem',
      () async {
        final memFs = MemoryProjectFileSystem();
        await runFixtureScenario(memFs);
        final memGuids = (await memFs.list(
          'assets',
          recursive: true,
        )).where((e) => e.path.endsWith('.vmeta')).map((e) => e.path).toList();
        await memFs.close();

        final tmp = Directory.systemTemp.createTempSync('volition_assetdb_');
        try {
          final ioFs = IoProjectFileSystem(tmp);
          await runFixtureScenario(ioFs);
          final ioGuids = (await ioFs.list('assets', recursive: true))
              .where((e) => e.path.endsWith('.vmeta'))
              .map((e) => e.path)
              .toList();
          expect(ioGuids, equals(memGuids));
        } finally {
          tmp.deleteSync(recursive: true);
        }
      },
    );

    test('generates deterministic GUIDs with a seeded RNG', () {
      final g1 = AssetGuidGenerator(Random(1337));
      final g2 = AssetGuidGenerator(Random(1337));
      expect(g1.nextGuid(), equals(g2.nextGuid()));
      expect(g1.nextGuid(), equals(g2.nextGuid()));
    });
  });
}
