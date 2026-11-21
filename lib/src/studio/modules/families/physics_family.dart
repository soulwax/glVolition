/// S6-B: Physics & Simulation Family Studio Integration (11 packages):
/// `voxphys`, `voxbroad`, `voxcloth`, `voxfluid`, `voxfracture`, `voxragdoll`,
/// `voxverlet`, `voxwheel`, `voxtraffic`, `voxcrowd`, `voxsteer`.
library;

import 'package:pixeldart/rendering/math/vec.dart';

import '../../../engine.dart';
import '../../commands/menu_registry.dart';

/// Studio Physics project settings model (gravity, fixed step, layer collision
/// matrix, `[S6-B]`).
final class PhysicsProjectSettingsModel {
  Vec3 gravity;
  double fixedDeltaTime;
  int maxSubsteps;
  final List<String> layerNames;
  final List<int> _layerMasks;

  PhysicsProjectSettingsModel({
    this.gravity = const Vec3(0, -9.81, 0),
    this.fixedDeltaTime = 1.0 / 60.0,
    this.maxSubsteps = 4,
    List<String>? layerNames,
  }) : layerNames =
           layerNames ??
           const ['Default', 'Player', 'Enemy', 'Environment', 'Trigger'],
       _layerMasks = List<int>.filled((layerNames?.length ?? 5), 0xFFFFFFFF);

  bool layersCollide(int a, int b) => (_layerMasks[a] & (1 << b)) != 0;

  void setLayersCollide(int a, int b, bool collide) {
    if (collide) {
      _layerMasks[a] |= (1 << b);
      _layerMasks[b] |= (1 << a);
    } else {
      _layerMasks[a] &= ~(1 << b);
      _layerMasks[b] &= ~(1 << a);
    }
  }
}

abstract final class PhysicsFamilyModule {
  static const List<String> packages = [
    'voxphys',
    'voxbroad',
    'voxcloth',
    'voxfluid',
    'voxfracture',
    'voxragdoll',
    'voxverlet',
    'voxwheel',
    'voxtraffic',
    'voxcrowd',
    'voxsteer',
  ];

  static const List<String> createMenus = [
    'GameObject/Create/Physics/Box Collider',
    'GameObject/Create/Physics/Sphere Collider',
    'GameObject/Create/Physics/RigidBody',
  ];

  static void registerMenus(StudioMenuRegistry menus, Scene Function() scene) {
    menus.register(
      StudioMenuItem(
        id: 'create.physics.box_collider',
        menuPath: 'GameObject/Create/Physics/Box Collider',
        action: () =>
            scene().createGameObject('Box Collider')
              ..addComponent(BoxCollider()),
      ),
    );
    menus.register(
      StudioMenuItem(
        id: 'create.physics.sphere_collider',
        menuPath: 'GameObject/Create/Physics/Sphere Collider',
        action: () =>
            scene().createGameObject('Sphere Collider')
              ..addComponent(SphereCollider()),
      ),
    );
    menus.register(
      StudioMenuItem(
        id: 'create.physics.rigidbody',
        menuPath: 'GameObject/Create/Physics/RigidBody',
        action: () =>
            scene().createGameObject('RigidBody')..addComponent(RigidBody()),
      ),
    );
  }

  static Scene buildSampleScene() {
    final scene = Scene('PhysicsSample');
    scene.createGameObject('Ground').addComponent(BoxCollider());
    scene.createGameObject('DynamicCrate')
      ..addComponent(BoxCollider())
      ..addComponent(RigidBody());
    return scene;
  }
}
