/// S8-B test: Verifies Build Profiles, transitive GUID reachability stripping,
/// module tree-shaken entrypoint generation, and byte-deterministic `.pak`
/// hashes across repeated builds.
library;

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S8-B — Build Profiles, Reachability Stripping & Determinism', () {
    test(
      'strips unreferenced assets and produces identical hash across two builds',
      () {
        const profile = StudioBuildProfile(
          name: 'web-release',
          target: StudioBuildTarget.web,
          scenesInBuild: ['assets/scenes/main.vscene.json'],
          enabledModules: ['pixeldart', 'voxphys', 'voxui'],
          qualityTier: 'high',
        );

        final catalog = <String, BuildAssetRecord>{
          'scene-main': const BuildAssetRecord(
            guid: 'scene-main',
            path: 'assets/scenes/main.vscene.json',
            sizeBytes: 4096,
            dependencyGuids: ['mat-hero', 'mesh-hero'],
          ),
          'mat-hero': const BuildAssetRecord(
            guid: 'mat-hero',
            path: 'assets/materials/hero.vmat',
            sizeBytes: 512,
            dependencyGuids: ['tex-hero'],
          ),
          'tex-hero': const BuildAssetRecord(
            guid: 'tex-hero',
            path: 'assets/textures/hero.png',
            sizeBytes: 65536,
          ),
          'mesh-hero': const BuildAssetRecord(
            guid: 'mesh-hero',
            path: 'assets/models/hero.glb',
            sizeBytes: 32768,
          ),
          'unused-debug-tex': const BuildAssetRecord(
            guid: 'unused-debug-tex',
            path: 'assets/textures/unused.png',
            sizeBytes: 131072,
          ),
        };

        final report1 = StudioBuildPlanner.planBuild(
          profile: profile,
          catalog: catalog,
          rootSceneGuids: const ['scene-main'],
        );
        final report2 = StudioBuildPlanner.planBuild(
          profile: profile,
          catalog: catalog,
          rootSceneGuids: const ['scene-main'],
        );

        expect(report1.includedAssetGuids, hasLength(4));
        expect(report1.strippedAssetGuids, equals(['unused-debug-tex']));
        expect(report1.totalAssetBytes, equals(4096 + 512 + 65536 + 32768));
        expect(
          report1.deterministicPakHash,
          equals(report2.deterministicPakHash),
        );
        expect(
          report1.generatedEntrypointSource,
          contains('// Enabled module: voxphys'),
        );
        expect(report1.generatedEntrypointSource, isNot(contains('voxcloth')));
      },
    );
  });
}
