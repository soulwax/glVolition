/// S6-D: AI, Gameplay & Narrative Family Studio Integration (15 packages):
/// `voxai`, `voxhtn`, `voxnav3d`, `voxpath`, `voxflow`, `voxgraph`,
/// `voxcircuit`, `voxrule`, `voxitem`, `voxcraft`, `voxquest`, `voxtalk`,
/// `voxstat`, `voxscore`, `voxloc`.
library;

import '../../../engine.dart';
import '../../commands/menu_registry.dart';

/// GUID-referenced `.vasset` Item definition (`[S6-D]`).
@CreateAssetMenu(menuName: 'Gameplay/Item', fileName: 'NewItem')
final class ItemDataAsset extends DataAsset {
  String itemId;
  int maxStack;
  double weight;

  ItemDataAsset({
    super.guid,
    super.name = 'Item',
    this.itemId = 'item_default',
    this.maxStack = 99,
    this.weight = 1.0,
  });

  @override
  String get assetType => 'volition.item';

  @override
  Map<String, Object?> serializeFields() => {
    'itemId': itemId,
    'maxStack': maxStack,
    'weight': weight,
  };

  @override
  void deserializeFields(Map<String, Object?> data) {
    itemId = data['itemId'] as String? ?? itemId;
    maxStack = (data['maxStack'] as num?)?.toInt() ?? maxStack;
    weight = (data['weight'] as num?)?.toDouble() ?? weight;
  }
}

/// GUID-referenced `.vasset` Quest definition (`[S6-D]`).
@CreateAssetMenu(menuName: 'Gameplay/Quest', fileName: 'NewQuest')
final class QuestDataAsset extends DataAsset {
  String questId;
  String title;
  int rewardXp;

  QuestDataAsset({
    super.guid,
    super.name = 'Quest',
    this.questId = 'quest_01',
    this.title = 'Untitled Quest',
    this.rewardXp = 100,
  });

  @override
  String get assetType => 'volition.quest';

  @override
  Map<String, Object?> serializeFields() => {
    'questId': questId,
    'title': title,
    'rewardXp': rewardXp,
  };

  @override
  void deserializeFields(Map<String, Object?> data) {
    questId = data['questId'] as String? ?? questId;
    title = data['title'] as String? ?? title;
    rewardXp = (data['rewardXp'] as num?)?.toInt() ?? rewardXp;
  }
}

abstract final class GameplayFamilyModule {
  static const List<String> packages = [
    'voxai',
    'voxhtn',
    'voxnav3d',
    'voxpath',
    'voxflow',
    'voxgraph',
    'voxcircuit',
    'voxrule',
    'voxitem',
    'voxcraft',
    'voxquest',
    'voxtalk',
    'voxstat',
    'voxscore',
    'voxloc',
  ];

  static const List<String> createMenus = [
    'GameObject/Create/Gameplay/NavMesh Agent 3D',
    'GameObject/Create/Gameplay/Quest Journal',
  ];

  static void registerDataAssets(DataAssetRegistry registry) {
    registry.register('volition.item', ItemDataAsset.new);
    registry.register('volition.quest', QuestDataAsset.new);
  }

  static void registerMenus(StudioMenuRegistry menus, Scene Function() scene) {
    menus.register(
      StudioMenuItem(
        id: 'create.gameplay.nav_agent',
        menuPath: 'GameObject/Create/Gameplay/NavMesh Agent 3D',
        action: () =>
            scene().createGameObject('NavAgent')
              ..addComponent(NavMeshAgent3DComponent()),
      ),
    );
    menus.register(
      StudioMenuItem(
        id: 'create.gameplay.nav_surface',
        menuPath: 'GameObject/Create/Gameplay/NavMesh Surface 3D',
        action: () =>
            scene().createGameObject('NavSurface')
              ..addComponent(NavMeshSurfaceComponent()),
      ),
    );
  }

  static Scene buildSampleScene() {
    final scene = Scene('GameplaySample');
    scene.createGameObject('Agent').addComponent(NavMeshAgent3DComponent());
    scene
        .createGameObject('NavSurface')
        .addComponent(NavMeshSurfaceComponent());
    return scene;
  }
}
