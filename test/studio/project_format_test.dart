/// S1-C tests: volition.project.json manifest round-trip & schema validation.
library;

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S1-C — VolitionProjectConfig (volition.project.json)', () {
    test(
      'saves and loads complete manifest cleanly via ProjectFileSystem',
      () async {
        final fs = MemoryProjectFileSystem();
        const config = VolitionProjectConfig(
          name: 'StarlightDemo',
          version: '1.2.0',
          enabledModules: ['pixeldart', 'voxanim', 'voxnet'],
          scenesInBuild: ['guid-scene-main', 'guid-scene-level2'],
          tags: ['Untagged', 'Player', 'Boss'],
          layers: ['Default', 'World', 'UI'],
          physicsLayerMatrix: {
            'Default': ['Default', 'World'],
            'UI': [],
          },
          inputActionsAssetGuid: 'guid-input-actions',
          renderPipelineSettingsAssetGuid: 'guid-vrp-settings',
          buildProfiles: {
            'web-release': {'target': 'js', 'minify': true},
          },
        );

        await config.save(fs);
        expect(await fs.exists(kProjectManifestFilename), isTrue);

        final loaded = await VolitionProjectConfig.load(fs);
        expect(loaded.name, equals('StarlightDemo'));
        expect(loaded.version, equals('1.2.0'));
        expect(
          loaded.enabledModules,
          equals(['pixeldart', 'voxanim', 'voxnet']),
        );
        expect(
          loaded.scenesInBuild,
          equals(['guid-scene-main', 'guid-scene-level2']),
        );
        expect(
          loaded.physicsLayerMatrix['Default'],
          equals(['Default', 'World']),
        );
        expect(loaded.inputActionsAssetGuid, equals('guid-input-actions'));
        expect(
          loaded.renderPipelineSettingsAssetGuid,
          equals('guid-vrp-settings'),
        );
        expect(loaded.qualityTiers.length, equals(3));
        expect(loaded.buildProfiles['web-release']?['minify'], isTrue);
        await fs.close();
      },
    );
  });
}
