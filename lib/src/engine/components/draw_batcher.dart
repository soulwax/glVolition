part of '../../engine.dart';

/// Draw-call state sorter, spatial cell cluster builder & indirect draw table component (`voxbatch`) (E88-2).
final class DrawBatcherComponent extends Behaviour {
  double cellSize;
  int maxInstancesPerCluster;
  bool autoRebuildOnUpdate;
  bool paused;

  batch.BatchSortResult sortResult = const batch.BatchSortResult(
    sortedItems: [],
    stateSwitchesBefore: 0,
    stateSwitchesAfter: 0,
  );
  List<batch.CellCluster> clusters = const [];
  batch.IndirectDrawTable drawTable = batch.IndirectDrawTable.build(const []);

  DrawBatcherComponent({
    this.cellSize = 16.0,
    this.maxInstancesPerCluster = 256,
    this.autoRebuildOnUpdate = true,
    this.paused = false,
  });

  static final spec = ComponentSpec<DrawBatcherComponent>(
    'DrawBatcherComponent',
    DrawBatcherComponent.new,
    [
      Field.number('cellSize', (c) => c.cellSize, (c, v) => c.cellSize = v),
      Field.integer(
        'maxInstancesPerCluster',
        (c) => c.maxInstancesPerCluster,
        (c, v) => c.maxInstancesPerCluster = v,
      ),
      Field.boolean(
        'autoRebuildOnUpdate',
        (c) => c.autoRebuildOnUpdate,
        (c, v) => c.autoRebuildOnUpdate = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  int get drawCallCount => drawTable.stats.drawCommandCount;
  int get inputObjectCount => drawTable.stats.totalInputObjects;
  double get reductionRatio => drawTable.stats.drawCallReductionRatio;

  /// Gathers active [MeshRenderer] instances from the scene, sorts & clusters them into indirect draw commands.
  batch.IndirectDrawTable rebuildFromScene({
    List<batch.RenderBatchItem>? customItems,
  }) {
    final items = <batch.RenderBatchItem>[];
    if (customItems != null) {
      items.addAll(customItems);
    } else if (isAttached && scene.isLoaded) {
      final camPos = Camera.of(scene)?.transform.position ?? Vec3.zero;
      for (final mr in scene.findObjectsOfType<MeshRenderer>()) {
        if (!mr.isActiveAndEnabled) continue;
        final pos = mr.transform.position;
        final dist = (pos - camPos).length;
        final idxCount = mr.meshData?.indices?.length ?? 36;
        final radius = mr.meshData != null
            ? (mr.meshData!.bounds.max - mr.meshData!.bounds.min).length * 0.5
            : 0.5;
        items.add(
          batch.RenderBatchItem(
            entityId: mr.instanceId,
            shaderId: 1,
            materialId: mr.material?.hashCode ?? 0,
            meshId: mr.mesh?.hashCode ?? (mr.meshData?.hashCode ?? 0),
            indexCount: idxCount,
            boundingRadius: radius,
            worldPosition: batch.BatchVec3(pos.x, pos.y, pos.z),
            viewDistance: dist,
            transparent: mr.drawMode != DrawMode.opaque,
          ),
        );
      }
    }

    sortResult = batch.RenderBatchSorter.sort(items);
    clusters = batch.InstanceClusterBuilder.buildClusters(
      sortResult.sortedItems,
      cellSize: cellSize,
      maxInstancesPerCluster: maxInstancesPerCluster,
    );
    drawTable = batch.IndirectDrawTable.build(clusters);
    return drawTable;
  }

  @override
  void update() {
    if (paused || !autoRebuildOnUpdate) return;
    rebuildFromScene();
  }
}

/// Persistent UI state for [DrawBatchInspectorUI.render].
final class DrawBatchInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` draw-call batcher & spatial cell cluster inspector (E88-2).
final class DrawBatchInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    DrawBatchInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked =
        hovered && state.activeButtonId == id && inp.wasMouseReleased;
    if (inp.wasMouseReleased && state.activeButtonId == id) {
      state.activeButtonId = null;
    }

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      bg,
      cornerRadius: ui.style.frameRounding,
    );
    dl.addRectOutline(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      ui.style.windowBorder,
      cornerRadius: ui.style.frameRounding,
    );
    final textW = label.length * (ui.style.fontSize * 0.6);
    dl.addText(
      label,
      rect.x + math.max(4.0, (rect.width - textW) * 0.5),
      rect.y + (rect.height - ui.style.fontSize) * 0.5,
      color: ui.style.text,
      size: ui.style.fontSize,
    );
    return clicked;
  }

  static void render(
    VoxUiContext ui,
    DrawBatcherComponent batcher, {
    DrawBatchInspectorUiState? state,
    String title = 'Draw Batcher',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? DrawBatchInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Draws / Objects',
      '${batcher.drawCallCount} cmds <- ${batcher.inputObjectCount} objs',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Batch Savings',
      '${(batcher.reductionRatio * 100.0).toStringAsFixed(1)}% | -${batcher.sortResult.switchesEliminated} switches',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Cell Size / Cap',
      '${batcher.cellSize.toStringAsFixed(1)}m | max ${batcher.maxInstancesPerCluster}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Status / Auto',
      '${batcher.paused ? 'Paused' : 'Active'} | Auto ${batcher.autoRebuildOnUpdate ? 'On' : 'Off'}',
      valueColor: batcher.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'db_pause',
      batcher.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      batcher.paused = !batcher.paused;
    }

    final cellRect = VoxRect(pauseRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'db_cell', 'Cell +8m', cellRect)) {
      batcher.cellSize += 8.0;
      batcher.rebuildFromScene();
    }

    final maxRect = VoxRect(cellRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'db_max', 'Batch +64', maxRect)) {
      batcher.maxInstancesPerCluster += 64;
      batcher.rebuildFromScene();
    }

    final rebRect = VoxRect(maxRect.right + 8.0, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'db_reb', 'Rebuild', rebRect)) {
      batcher.rebuildFromScene();
    }

    ui.endWindow();
  }
}
