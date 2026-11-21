/// S6-A..S6-F & S6-M test: Verifies all 74 `vendor/*` packages across all 6
/// Studio families meet `inspectable` maturity, register `GameObject > Create`
/// menus, round-trip family sample scenes through `SceneSerializer`, and power
/// family tools (`PhysicsProjectSettingsModel`, `CurveFieldEditorModel`,
/// `ItemDataAsset`/`QuestDataAsset`, `AudioMixerWindowModel`, `ModulesWindowModel`).
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S6 — 74-Module Studio Integration Sweep (S6-A..S6-F, S6-M)', () {
    test(
      'all 6 family package lists partition the 74 registered vendor packages cleanly',
      () {
        final allFamilyPkgs = <String>[
          ...RenderingFamilyModule.packages,
          ...PhysicsFamilyModule.packages,
          ...AnimationFamilyModule.packages,
          ...GameplayFamilyModule.packages,
          ...WorldFamilyModule.packages,
          ...InfraFamilyModule.packages,
        ];
        expect(allFamilyPkgs, hasLength(74));
        expect(allFamilyPkgs.toSet(), hasLength(74));

        final registry = StudioModuleRegistry(kStudioModuleInventory);
        final report = registry.checkCoverage(
          allFamilyPkgs,
          minMaturity: StudioModuleMaturity.inspectable,
        );
        expect(report.passed, isTrue, reason: '${report.toJson()}');
        expect(report.totalRegistered, equals(74));
        expect(report.belowMinMaturity, isEmpty);
      },
    );

    test(
      'every family registers GameObject > Create menus and serializes its sample scene',
      () {
        final menus = StudioMenuRegistry();
        var activeScene = Scene('MenuTarget');

        RenderingFamilyModule.registerMenus(menus, () => activeScene);
        PhysicsFamilyModule.registerMenus(menus, () => activeScene);
        AnimationFamilyModule.registerMenus(menus, () => activeScene);
        GameplayFamilyModule.registerMenus(menus, () => activeScene);
        WorldFamilyModule.registerMenus(menus, () => activeScene);
        InfraFamilyModule.registerMenus(menus, () => activeScene);

        expect(menus.all.length, greaterThanOrEqualTo(12));
        for (final item in menus.all) {
          expect(menus.trigger(item.id), isTrue);
        }
        expect(activeScene.rootGameObjects.length, equals(menus.all.length));

        final samples = <Scene>[
          RenderingFamilyModule.buildSampleScene(),
          PhysicsFamilyModule.buildSampleScene(),
          AnimationFamilyModule.buildSampleScene(),
          GameplayFamilyModule.buildSampleScene(),
          WorldFamilyModule.buildSampleScene(),
          InfraFamilyModule.buildSampleScene(),
        ];
        for (final s in samples) {
          final json = SceneSerializer.toJson(s);
          final restored = SceneSerializer.fromJson(json);
          expect(restored.name, equals(s.name));
          expect(
            restored.rootGameObjects.length,
            equals(s.rootGameObjects.length),
          );
        }
      },
    );

    test(
      'family tools (Physics settings, Curve editor, DataAssets, Audio Mixer, Modules window) work',
      () {
        // S6-B: Physics project settings
        final phys = PhysicsProjectSettingsModel();
        expect(phys.layersCollide(1, 2), isTrue);
        phys.setLayersCollide(1, 2, false);
        expect(phys.layersCollide(1, 2), isFalse);
        expect(phys.layersCollide(2, 1), isFalse);

        // S6-C: Curve field editor
        final curve = CurveFieldEditorModel(const [
          StudioCurveKeyframe(time: 0.0, value: 0.0),
          StudioCurveKeyframe(time: 1.0, value: 1.0),
        ]);
        expect(curve.evaluate(0.0), closeTo(0.0, 1e-6));
        expect(curve.evaluate(0.5), closeTo(0.5, 1e-6));
        expect(curve.evaluate(1.0), closeTo(1.0, 1e-6));

        // S6-D: DataAsset round-trip
        final dataReg = DataAssetRegistry();
        GameplayFamilyModule.registerDataAssets(dataReg);
        final sword = ItemDataAsset(
          guid: 'item-001',
          name: 'IronSword',
          itemId: 'sword_iron',
          maxStack: 1,
          weight: 3.5,
        );
        final restoredItem =
            dataReg.deserialize(sword.toJson()) as ItemDataAsset?;
        expect(restoredItem, isNotNull);
        expect(restoredItem!.itemId, equals('sword_iron'));
        expect(restoredItem.weight, closeTo(3.5, 1e-6));

        // S6-F: Audio Mixer mute/solo
        final mixer = AudioMixerWindowModel();
        mixer.busByName('SFX')!.volume = 0.8;
        mixer.busByName('Master')!.volume = 0.5;
        expect(mixer.effectiveGain('SFX'), closeTo(0.4, 1e-6));
        mixer.busByName('Music')!.solo = true;
        expect(mixer.effectiveGain('SFX'), equals(0.0));
        expect(mixer.effectiveGain('Music'), closeTo(0.5, 1e-6));

        // S6-M: Modules Window package manager
        final registry = StudioModuleRegistry(kStudioModuleInventory);
        final modulesWin = ModulesWindowModel(registry);
        expect(modulesWin.filteredModules, hasLength(74));
        modulesWin.familyFilter = StudioModuleFamily.physicsSimulation;
        expect(modulesWin.filteredModules, hasLength(11));
        modulesWin.setEnabled('voxcloth', false);
        expect(modulesWin.isEnabled('voxcloth'), isFalse);
      },
    );
  });
}
