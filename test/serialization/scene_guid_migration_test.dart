/// S1-M tests: AssetRef serialization and v1/v2 -> v3 GUID scene migration via
/// injectable AssetGuidResolver.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('S1-M — AssetRef & v2->v3 GUID Scene Migration', () {
    test('AssetRef round-trips JSON cleanly', () {
      const ref = AssetRef(
        'aabbccdd0011223344556677889900ff',
        subAssetId: 'mesh0',
      );
      final json = ref.toJson();
      expect(
        json[AssetRef.guidJsonKey],
        equals('aabbccdd0011223344556677889900ff'),
      );
      expect(json[AssetRef.subAssetJsonKey], equals('mesh0'));
      expect(AssetRef.fromJson(json), equals(ref));
      expect(AssetRef.tryFromJson({'other': 1}), isNull);
    });

    test(
      'migrates v1/v2 scene asset paths to v3 AssetRef GUIDs via resolver',
      () {
        final legacyV1Scene = <String, Object?>{
          'schemaVersion': 1,
          'name': 'LegacyLevel',
          'objects': [
            {
              'name': 'Hero',
              'transform': {
                'pos': [1, 2, 3],
              },
              'components': [
                {
                  'type': 'MeshRenderer',
                  'enabled': true,
                  'data': {
                    'mesh': 'assets/meshes/hero.glb',
                    'material': 'assets/materials/hero.vmat',
                    'castShadows': true,
                  },
                },
              ],
            },
          ],
        };

        const guidMap = {
          'assets/meshes/hero.glb': '11111111222243338444555555555555',
          'assets/materials/hero.vmat': 'aaaaaaaa222243338444bbbbbbbbbbbb',
        };

        final migrator = SceneMigrator.withGuidResolver(
          (path) => guidMap[path],
        );
        final result = migrator.migrate(
          legacyV1Scene,
          kind: ScenePayloadKind.scene,
        );

        expect(result.fromVersion, equals(1));
        expect(result.toVersion, equals(SceneSerializer.schemaVersion));
        expect(result.appliedSteps, equals(['v1->v2', 'v2->v3']));

        final objects = result.data['objects']! as List<Object?>;
        final hero = objects.first! as Map<String, Object?>;
        final comps = hero['components']! as List<Object?>;
        final meshComp = comps.first! as Map<String, Object?>;
        final compData = meshComp['data']! as Map<String, Object?>;

        expect(
          AssetRef.tryFromJson(compData['mesh']),
          equals(const AssetRef('11111111222243338444555555555555')),
        );
        expect(
          AssetRef.tryFromJson(compData['material']),
          equals(const AssetRef('aaaaaaaa222243338444bbbbbbbbbbbb')),
        );
        expect(compData['castShadows'], isTrue);
      },
    );
  });
}
