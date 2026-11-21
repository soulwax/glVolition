/// Volition Studio Project Templates & Flagship Showcase Generator (`[S8-D]`):
/// Creates GUID-backed starter projects (`empty`, `2d`, `3d`, `multiplayer`,
/// `showcase`) on `ProjectFileSystem`.
library;

import 'dart:convert';

import '../../engine.dart';
import '../assets/asset_database.dart';
import '../modules/families/animation_family.dart';
import '../modules/families/gameplay_family.dart';
import '../modules/families/infra_family.dart';
import '../modules/families/physics_family.dart';
import '../modules/families/rendering_family.dart';
import '../modules/families/world_family.dart';
import 'project_config.dart';
import 'project_fs.dart';

enum StudioProjectTemplate {
  empty,
  template2d,
  template3d,
  multiplayer,
  showcase,
}

abstract final class StudioProjectTemplateGenerator {
  /// Scaffolds a complete Volition project in [fs] for [template] and refreshes
  /// its [AssetDatabase] so every scene/asset has a valid `.vmeta` GUID.
  static Future<AssetDatabase> generate({
    required ProjectFileSystem fs,
    required String projectName,
    required StudioProjectTemplate template,
  }) async {
    const scenePath = 'assets/scenes/main.scene.json';
    final config = VolitionProjectConfig(
      name: projectName,
      scenesInBuild: const [scenePath],
    );
    await fs.writeString(
      kProjectManifestFilename,
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );

    final scene = _buildTemplateScene(projectName, template);
    await fs.writeString(
      scenePath,
      const JsonEncoder.withIndent('  ').convert(SceneSerializer.toJson(scene)),
    );

    final db = AssetDatabase(fs);
    await db.refresh();
    return db;
  }

  static Scene _buildTemplateScene(
    String name,
    StudioProjectTemplate template,
  ) {
    final scene = Scene(name);
    scene.createGameObject('MainCamera').addComponent(Camera());

    switch (template) {
      case StudioProjectTemplate.empty:
        return scene;
      case StudioProjectTemplate.template2d:
        scene.createGameObject('Player2D').addComponent(BoxCollider());
        return scene;
      case StudioProjectTemplate.template3d:
        scene.createGameObject('Sun')
          ..addComponent(Light.directional(intensity: 2.0))
          ..addComponent(CascadedShadowRigComponent());
        scene.createGameObject('Ground').addComponent(BoxCollider());
        return scene;
      case StudioProjectTemplate.multiplayer:
        scene
            .createGameObject('NetworkPlayer')
            .addComponent(NetworkIdentity(netId: 1));
        scene.createGameObject('Sun').addComponent(Light.directional());
        return scene;
      case StudioProjectTemplate.showcase:
        // Flagship Showcase: VRP + at least one component from all 6 families!
        // S6-A Rendering
        scene.createGameObject('Sun')
          ..addComponent(Light.directional(intensity: 2.5))
          ..addComponent(CascadedShadowRigComponent());
        scene
            .createGameObject('RoomProbe')
            .addComponent(ReflectionProbeComponent());
        scene
            .createGameObject('GlobalPost')
            .addComponent(PostProcessVolumeComponent());
        // S6-B Physics
        scene.createGameObject('DynamicCrate')
          ..addComponent(BoxCollider())
          ..addComponent(RigidBody());
        // S6-C Animation
        scene.createGameObject('HeroAnimator').addComponent(Animator());
        // S6-D Gameplay
        scene
            .createGameObject('NavAgent')
            .addComponent(NavMeshAgent3DComponent());
        // S6-E World
        scene
            .createGameObject('Foliage')
            .addComponent(FoliageScatterComponent());
        // S6-F Infra (Audio + Net)
        scene.createGameObject('AmbientAudio').addComponent(AudioSource());
        scene
            .createGameObject('NetHost')
            .addComponent(NetworkIdentity(netId: 1));
        return scene;
    }
  }

  /// Families represented by the flagship showcase (all 6).
  static const List<List<String>> showcaseFamilyCoverage = [
    RenderingFamilyModule.packages,
    PhysicsFamilyModule.packages,
    AnimationFamilyModule.packages,
    GameplayFamilyModule.packages,
    WorldFamilyModule.packages,
    InfraFamilyModule.packages,
  ];
}
