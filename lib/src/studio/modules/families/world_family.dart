/// S6-E: World & Procedural Family Studio Integration (10 packages):
/// `voxbiome`, `voxnoise3d`, `voxproc`, `voxarch`, `voxbuild`, `voxgrid`,
/// `voxhex`, `voxsnap`, `voxgeom`, `voxfoliage`.
library;

import '../../../engine.dart';
import '../../commands/menu_registry.dart';

abstract final class WorldFamilyModule {
  static const List<String> packages = [
    'voxbiome',
    'voxnoise3d',
    'voxproc',
    'voxarch',
    'voxbuild',
    'voxgrid',
    'voxhex',
    'voxsnap',
    'voxgeom',
    'voxfoliage',
  ];

  static const List<String> createMenus = [
    'GameObject/Create/World/Biome Terrain',
    'GameObject/Create/World/Foliage Scatter',
    'GameObject/Create/World/Noise Field Volume',
  ];

  static void registerMenus(StudioMenuRegistry menus, Scene Function() scene) {
    menus.register(
      StudioMenuItem(
        id: 'create.world.foliage',
        menuPath: 'GameObject/Create/World/Foliage Scatter',
        action: () =>
            scene().createGameObject('Foliage')
              ..addComponent(FoliageScatterComponent()),
      ),
    );
    menus.register(
      StudioMenuItem(
        id: 'create.world.noise_volume',
        menuPath: 'GameObject/Create/World/Noise Field Volume',
        action: () =>
            scene().createGameObject('Noise Volume')
              ..addComponent(NoiseFieldVolumeComponent()),
      ),
    );
  }

  static Scene buildSampleScene() {
    final scene = Scene('WorldSample');
    scene.createGameObject('Foliage').addComponent(FoliageScatterComponent());
    scene
        .createGameObject('NoiseField')
        .addComponent(NoiseFieldVolumeComponent());
    return scene;
  }
}
