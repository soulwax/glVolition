/// S5-A test: Verifies `volition codegen` (`SpecCodeGenerator`) generates
/// deterministic `ComponentSpec` / `DataAsset` specs from annotations, rejects
/// generics with `file:line` diagnostics, and emits byte-identical output on
/// repeated runs.
library;

import 'package:test/test.dart';

import '../../tool/codegen/spec_codegen.dart';

void main() {
  group('S5-A — volition codegen (SpecCodeGenerator)', () {
    test(
      'generates ComponentSpec with all annotation metadata and is byte-identical across runs',
      () {
        const sample = '''
@RequireComponent(RigidBody)
@AddComponentMenu('Gameplay/PlayerController')
@ExecuteInEditMode()
class PlayerController extends Behaviour {
  @Serialized()
  @Header('Movement')
  @Range(0, 10)
  @Tooltip('Max run speed in m/s')
  double speed = 5.0;

  @serialized
  @Min(1)
  int maxJumps = 2;

  @Serialized()
  @Multiline(4)
  String bio = '';

  @Serialized()
  @HideInInspector()
  bool internalFlag = false;

  @Serialized()
  Vec3 spawnOffset = Vec3.zero;
}
''';

        final res1 = SpecCodeGenerator.generateForSource(
          sample,
          filePath: 'lib/player_controller.dart',
        );
        final res2 = SpecCodeGenerator.generateForSource(
          sample,
          filePath: 'lib/player_controller.dart',
        );

        expect(res1.hasErrors, isFalse);
        expect(res1.classCount, equals(1));
        expect(res1.fieldCount, equals(5));
        expect(res1.generatedCode, equals(res2.generatedCode));
        expect(res1.generatedCode, contains('PlayerControllerGeneratedSpec'));
        expect(res1.generatedCode, contains('min: 0, max: 10'));
        expect(res1.generatedCode, contains("header: 'Movement'"));
        expect(res1.generatedCode, contains("tooltip: 'Max run speed in m/s'"));
        expect(res1.generatedCode, contains('hidden: true'));
        expect(res1.generatedCode, contains('multiline: true'));
        expect(
          res1.generatedCode,
          contains('PlayerControllerRequiredComponents = [RigidBody]'),
        );
        expect(
          res1.generatedCode,
          contains(
            "PlayerControllerComponentMenuPath = 'Gameplay/PlayerController'",
          ),
        );
      },
    );

    test('rejects generic field types with exact file:line diagnostics', () {
      const badSource = '''
class InventoryComp extends Component {
  @Serialized()
  List<int> items = [];
}
''';
      final res = SpecCodeGenerator.generateForSource(
        badSource,
        filePath: 'lib/inventory.dart',
      );
      expect(res.hasErrors, isTrue);
      expect(res.diagnostics.single.filePath, equals('lib/inventory.dart'));
      expect(res.diagnostics.single.line, equals(3));
      expect(res.diagnostics.single.message, contains('Generic field type'));
    });

    test('supports single-line annotation + field syntax', () {
      const inlineSource = '''
class Mover extends Behaviour {
  @Serialized @Range(0, 10) double speed = 3.0;
}
''';
      final res = SpecCodeGenerator.generateForSource(
        inlineSource,
        filePath: 'lib/mover.dart',
      );
      expect(res.hasErrors, isFalse);
      expect(res.fieldCount, equals(1));
      expect(res.generatedCode, contains("Field.number('speed'"));
      expect(res.generatedCode, contains('min: 0, max: 10'));
    });
  });
}
