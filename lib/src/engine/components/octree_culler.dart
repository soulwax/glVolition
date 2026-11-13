part of '../../engine.dart';

/// Loose 3D octree spatial index, frustum visibility culler & ray query component (`voxoctree`) (E91-2).
final class OctreeCullerComponent extends Behaviour {
  double worldHalfExtent;
  int maxDepth;
  int splitThreshold;
  bool autoSyncOnUpdate;
  bool paused;
  bool applyFrustumCulling;

  late oct.DynamicLooseOctree<GameObject> octree;
  List<oct.OctreeEntry<GameObject>> visibleEntries = const [];
  Camera? targetCamera;

  final Set<int> _culledRendererIds = {};
  int _totalTracked = 0;

  OctreeCullerComponent({
    this.worldHalfExtent = 128.0,
    this.maxDepth = 5,
    this.splitThreshold = 8,
    this.autoSyncOnUpdate = true,
    this.paused = false,
    this.applyFrustumCulling = false,
    this.targetCamera,
  }) {
    _resetTree();
  }

  static final spec = ComponentSpec<OctreeCullerComponent>(
    'OctreeCullerComponent',
    OctreeCullerComponent.new,
    [
      Field.number(
        'worldHalfExtent',
        (c) => c.worldHalfExtent,
        (c, v) => c.worldHalfExtent = v,
      ),
      Field.integer('maxDepth', (c) => c.maxDepth, (c, v) => c.maxDepth = v),
      Field.integer(
        'splitThreshold',
        (c) => c.splitThreshold,
        (c, v) => c.splitThreshold = v,
      ),
      Field.boolean(
        'autoSyncOnUpdate',
        (c) => c.autoSyncOnUpdate,
        (c, v) => c.autoSyncOnUpdate = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
      Field.boolean(
        'applyFrustumCulling',
        (c) => c.applyFrustumCulling,
        (c, v) => c.applyFrustumCulling = v,
      ),
    ],
  );

  void _resetTree() {
    octree = oct.DynamicLooseOctree<GameObject>(
      halfExtent: math.max(2.0, worldHalfExtent),
      maxDepth: maxDepth.clamp(1, 8),
      splitThreshold: math.max(1, splitThreshold),
    );
  }

  int get indexedObjectCount => octree.count;
  int get nodeCount => octree.nodeCount;
  int get visibleCount => visibleEntries.length;
  int get culledCount => _culledRendererIds.length;
  int get totalTracked => _totalTracked;

  /// Restores scene-node visibility for any [MeshRenderer]s hidden by frustum culling.
  void restoreAllVisibility() {
    if (_culledRendererIds.isEmpty) return;
    if (isAttached && scene.isLoaded) {
      for (final mr in scene.findObjectsOfType<MeshRenderer>()) {
        if (_culledRendererIds.contains(mr.instanceId)) {
          final leaf = mr._leaf;
          if (leaf != null) leaf.visible = true;
        }
      }
    }
    _culledRendererIds.clear();
  }

  /// Rebuilds loose octree bounds from scene [MeshRenderer]s and queries camera frustum visibility.
  List<oct.OctreeEntry<GameObject>> rebuildFromScene() {
    _resetTree();
    var tracked = 0;
    if (isAttached && scene.isLoaded) {
      for (final mr in scene.findObjectsOfType<MeshRenderer>()) {
        if (!mr.isActiveAndEnabled) continue;
        tracked++;
        final pos = mr.transform.position;
        final localB = mr.meshData?.bounds;
        final minV = localB != null
            ? oct.OctreeVec3(
                pos.x + localB.min.x,
                pos.y + localB.min.y,
                pos.z + localB.min.z,
              )
            : oct.OctreeVec3(pos.x - 0.5, pos.y - 0.5, pos.z - 0.5);
        final maxV = localB != null
            ? oct.OctreeVec3(
                pos.x + localB.max.x,
                pos.y + localB.max.y,
                pos.z + localB.max.z,
              )
            : oct.OctreeVec3(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5);
        octree.insertOrUpdate(
          mr.instanceId,
          mr.gameObject,
          oct.OctreeAabb(minV, maxV),
        );
      }
    }
    _totalTracked = tracked;

    final cam =
        targetCamera ??
        (isAttached && scene.isLoaded ? Camera.of(scene) : null);
    if (cam != null && cam.isAttached) {
      var aspect = 16.0 / 9.0;
      if (isAttached && scene.isLoaded) {
        final vw = engine.graphics.viewportWidth;
        final vh = engine.graphics.viewportHeight;
        if (vw > 0 && vh > 0) aspect = vw / vh;
      }
      final cp = cam.transform.position;
      final cf = cam.transform.forward;
      final cu = cam.transform.up;
      final frustum = oct.FrustumCullSet.perspective(
        eye: oct.OctreeVec3(cp.x, cp.y, cp.z),
        forward: oct.OctreeVec3(cf.x, cf.y, cf.z),
        up: oct.OctreeVec3(cu.x, cu.y, cu.z),
        fovYRadians: cam.fovYRadians,
        aspect: aspect,
        near: cam.near,
        far: cam.far,
      );
      visibleEntries = octree.queryFrustum(frustum);
    } else {
      visibleEntries = octree.queryAabb(octree.rootBounds);
    }

    if (applyFrustumCulling && isAttached && scene.isLoaded) {
      final visibleGos = <GameObject>{
        for (final entry in visibleEntries) entry.item,
      };
      final activeIds = <int>{};
      for (final mr in scene.findObjectsOfType<MeshRenderer>()) {
        if (!mr.isActiveAndEnabled) continue;
        activeIds.add(mr.instanceId);
        final leaf = mr._leaf;
        if (visibleGos.contains(mr.gameObject)) {
          if (_culledRendererIds.remove(mr.instanceId) && leaf != null) {
            leaf.visible = true;
          }
        } else {
          if (leaf != null && leaf.visible) {
            leaf.visible = false;
            _culledRendererIds.add(mr.instanceId);
          }
        }
      }
      _culledRendererIds.retainAll(activeIds);
    } else {
      restoreAllVisibility();
    }

    return visibleEntries;
  }

  oct.OctreeRayHit<GameObject>? raycastClosest(
    Vec3 origin,
    Vec3 direction, {
    double maxDistance = 500.0,
  }) => oct.OctreeRayQuery.raycastClosest(
    octree,
    origin: oct.OctreeVec3(origin.x, origin.y, origin.z),
    direction: oct.OctreeVec3(direction.x, direction.y, direction.z),
    maxDistance: maxDistance,
  );

  @override
  void update() {
    if (paused || !autoSyncOnUpdate) return;
    rebuildFromScene();
  }

  @override
  void _onDisableInternal() {
    restoreAllVisibility();
  }

  @override
  void onDestroy() {
    restoreAllVisibility();
  }
}

/// Persistent UI state for [OctreeStatsInspectorUI.render].
final class OctreeStatsInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` loose 3D octree & frustum culling inspector (E91-2).
final class OctreeStatsInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    OctreeStatsInspectorUiState state,
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
    OctreeCullerComponent culler, {
    OctreeStatsInspectorUiState? state,
    String title = 'Loose Octree Culler',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? OctreeStatsInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Visible / Indexed',
      '${culler.visibleCount} / ${culler.indexedObjectCount} objs',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Octree Nodes / Depth',
      '${culler.nodeCount} nodes | maxDepth ${culler.maxDepth}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Bounds / Split',
      '+/-${culler.worldHalfExtent.toStringAsFixed(0)}m | threshold ${culler.splitThreshold}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Status / Cull',
      '${culler.paused ? 'Paused' : 'Active'} | Auto ${culler.autoSyncOnUpdate ? 'On' : 'Off'} | Culled ${culler.culledCount}/${culler._totalTracked}',
      valueColor: culler.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'oct_pause',
      culler.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      culler.paused = !culler.paused;
    }

    final depthRect = VoxRect(pauseRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'oct_depth', 'Depth +1', depthRect)) {
      culler.maxDepth = culler.maxDepth >= 8 ? 1 : culler.maxDepth + 1;
      culler.rebuildFromScene();
    }

    final splitRect = VoxRect(depthRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'oct_split', 'Split +4', splitRect)) {
      culler.splitThreshold += 4;
      culler.rebuildFromScene();
    }

    final rebRect = VoxRect(splitRect.right + 8.0, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'oct_reb', 'Rebuild', rebRect)) {
      culler.rebuildFromScene();
    }

    final cullRect = VoxRect(x + pad, barY + 28.0, 108.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'oct_cull',
      culler.applyFrustumCulling ? 'Cull: On' : 'Cull: Off',
      cullRect,
    )) {
      culler.applyFrustumCulling = !culler.applyFrustumCulling;
      culler.rebuildFromScene();
    }

    ui.endWindow();
  }
}
