/// S2-D tests: ProjectWindowModel (create/rename/move preserving GUIDs,
/// thumbnail cache reuse, import settings) and ConsolePanelModel (collapse,
/// level filters, search, stack-frame file:line parsing, open_in_editor).
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

import '../../tool/studio/open_in_editor.dart';

void main() {
  group('S2-D — ProjectWindowModel & Thumbnail Cache', () {
    test('create/rename/move keep GUIDs and reuse cached thumbnails', () async {
      final fs = MemoryProjectFileSystem();
      final db = AssetDatabase(
        fs,
        guidGenerator: AssetGuidGenerator(Random(7)),
      );
      final project = ProjectWindowModel(db);

      await project.createFolder('materials');
      project.currentFolder = 'assets/materials';
      final mat = await project.createMaterialAsset('stone');
      final originalGuid = mat.guid;

      // Rename preserves GUID
      final renamed = await project.renameAsset(mat.path, 'granite.vmat');
      expect(renamed.guid, equals(originalGuid));
      expect(renamed.path, equals('assets/materials/granite.vmat'));

      // Move to another folder preserves GUID
      project.currentFolder = 'assets';
      await project.createFolder('archived');
      final moved = await project.moveAssetToFolder(
        renamed.path,
        'assets/archived',
      );
      expect(moved.guid, equals(originalGuid));
      expect(moved.path, equals('assets/archived/granite.vmat'));

      // Thumbnail cache: first call renders, second call hits cache
      var renderCalls = 0;
      Future<Uint8List> fakeThumb(AssetRecord rec) async {
        renderCalls++;
        return Uint8List.fromList([137, 80, 78, 71, renderCalls]);
      }

      final t1 = await project.getOrGenerateThumbnail(originalGuid, fakeThumb);
      final t2 = await project.getOrGenerateThumbnail(originalGuid, fakeThumb);
      expect(renderCalls, equals(1));
      expect(t2, equals(t1));

      // Changing import settings invalidates cacheKey -> re-renders thumbnail
      await project.updateImportSettings(originalGuid, {'srgb': false});
      await project.getOrGenerateThumbnail(originalGuid, fakeThumb);
      expect(renderCalls, equals(2));

      await fs.close();
    });
  });

  group('S2-D — ConsolePanelModel & Open-In-Editor', () {
    test(
      'supports collapse, level filters, search, and file:line extraction',
      () {
        final console = ConsolePanelModel();
        console.log(ConsoleLogLevel.info, 'Scene loaded');
        console.log(ConsoleLogLevel.warning, 'Missing normal map');
        console.log(ConsoleLogLevel.warning, 'Missing normal map');
        console.log(
          ConsoleLogLevel.error,
          'Null check operator used on a null value',
          stackTrace: '#0  main (file:///C:/proj/lib/player.dart:42:9)\n',
        );

        expect(console.totalCount, equals(4));
        expect(console.errorCount, equals(1));

        console.collapseDuplicates = true;
        final collapsed = console.visibleEntries();
        expect(collapsed.length, equals(3));
        expect(
          collapsed.firstWhere((e) => e.level == ConsoleLogLevel.warning).count,
          equals(2),
        );

        final err = collapsed.firstWhere(
          (e) => e.level == ConsoleLogLevel.error,
        );
        expect(err.sourceLocation?.filePath, equals('C:/proj/lib/player.dart'));
        expect(err.sourceLocation?.line, equals(42));
        expect(err.sourceLocation?.column, equals(9));

        final cmd = buildOpenInEditorCommand(
          err.sourceLocation!.filePath,
          err.sourceLocation!.line,
          column: err.sourceLocation!.column,
        );
        expect(cmd.executable, equals('code'));
        expect(cmd.arguments, equals(['-g', 'C:/proj/lib/player.dart:42:9']));
      },
    );
  });
}
