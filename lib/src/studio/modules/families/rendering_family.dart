/// S6-A: Rendering & Visuals Family Studio Integration (17 packages):
/// `pixeldart`, `voxvfx`, `voxribbon`, `voxdecal`, `voxlight`, `voxshadow`,
/// `voxsky`, `voxcolor`, `voxlens`, `voxcam`, `voxprobe`, `voxatlas`,
/// `voxbatch`, `voxoctree`, `voxsdf`, `voxgreedy`, `voxvox`.
library;

import '../../../engine.dart';
import '../../commands/menu_registry.dart';

abstract final class RenderingFamilyModule {
  static const List<String> packages = [
    'pixeldart',
    'voxvfx',
    'voxribbon',
    'voxdecal',
    'voxlight',
    'voxshadow',
    'voxsky',
    'voxcolor',
    'voxlens',
    'voxcam',
    'voxprobe',
    'voxatlas',
    'voxbatch',
    'voxoctree',
    'voxsdf',
    'voxgreedy',
    'voxvox',
  ];

  static const List<String> createMenus = [
    'GameObject/Create/Rendering/Directional Light',
    'GameObject/Create/Rendering/Point Light',
    'GameObject/Create/Rendering/Spot Light',
    'GameObject/Create/Rendering/Reflection Probe',
    'GameObject/Create/Rendering/Post Process Volume',
    'GameObject/Create/Rendering/Cascaded Shadow Rig',
    'GameObject/Create/Rendering/Particle System',
  ];

  static void registerMenus(StudioMenuRegistry menus, Scene Function() scene) {
    menus.register(
      StudioMenuItem(
        id: 'create.rendering.dir_light',
        menuPath: 'GameObject/Create/Rendering/Directional Light',
        action: () =>
            scene().createGameObject('Directional Light')
              ..addComponent(Light.directional()),
      ),
    );
    menus.register(
      StudioMenuItem(
        id: 'create.rendering.reflection_probe',
        menuPath: 'GameObject/Create/Rendering/Reflection Probe',
        action: () =>
            scene().createGameObject('Reflection Probe')
              ..addComponent(ReflectionProbeComponent()),
      ),
    );
    menus.register(
      StudioMenuItem(
        id: 'create.rendering.post_volume',
        menuPath: 'GameObject/Create/Rendering/Post Process Volume',
        action: () =>
            scene().createGameObject('Post Process Volume')
              ..addComponent(PostProcessVolumeComponent()),
      ),
    );
    menus.register(
      StudioMenuItem(
        id: 'create.rendering.csm_rig',
        menuPath: 'GameObject/Create/Rendering/Cascaded Shadow Rig',
        action: () =>
            scene().createGameObject('CSM Rig')
              ..addComponent(CascadedShadowRigComponent()),
      ),
    );
  }

  static Scene buildSampleScene() {
    final scene = Scene('RenderingSample');
    scene.createGameObject('MainCamera').addComponent(Camera());
    scene.createGameObject('Sun')
      ..addComponent(Light.directional(intensity: 2.0))
      ..addComponent(CascadedShadowRigComponent());
    scene
        .createGameObject('RoomProbe')
        .addComponent(ReflectionProbeComponent());
    scene
        .createGameObject('GlobalPost')
        .addComponent(PostProcessVolumeComponent());
    return scene;
  }
}
