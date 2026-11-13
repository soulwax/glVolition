part of '../../engine.dart';

/// Sparse 8x8x8 greedy-meshed voxel brick component with per-vertex AO (`voxgreedy`) (E95-2).
final class GreedyVoxelBrickComponent extends Behaviour {
  int brickSize;
  double voxelSize;
  bool bakeAo;
  bool autoSyncMeshRenderer;
  bool paused;

  late greedy.VoxelBrick8 brick;
  greedy.GreedyMeshBuffer? lastBuffer;
  MeshData? _currentMeshData;
  MeshHandle? _dynamicMeshHandle;
  bool _dirty = false;

  GreedyVoxelBrickComponent({
    this.brickSize = 8,
    this.voxelSize = 0.5,
    this.bakeAo = true,
    this.autoSyncMeshRenderer = true,
    this.paused = false,
  }) {
    _initDefaultBrick();
    rebuildMesh();
  }

  static final spec = ComponentSpec<GreedyVoxelBrickComponent>(
    'GreedyVoxelBrickComponent',
    GreedyVoxelBrickComponent.new,
    [
      Field.integer('brickSize', (c) => c.brickSize, (c, v) => c.brickSize = v),
      Field.number('voxelSize', (c) => c.voxelSize, (c, v) => c.voxelSize = v),
      Field.boolean('bakeAo', (c) => c.bakeAo, (c, v) => c.bakeAo = v),
      Field.boolean(
        'autoSyncMeshRenderer',
        (c) => c.autoSyncMeshRenderer,
        (c, v) => c.autoSyncMeshRenderer = v,
      ),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
    ],
  );

  void _initDefaultBrick() {
    brick = greedy.VoxelBrick8(size: brickSize.clamp(2, 32));
    // Default 6x2x6 slab + 2x2x2 raised corner turret so solidCount > 0 out of the box.
    brick.fillBox(1, 0, 1, 6, 1, 6, 1);
    brick.fillBox(1, 2, 1, 2, 3, 2, 2);
  }

  int get quadCount => lastBuffer?.quadCount ?? 0;
  int get triangleCount => lastBuffer?.triangleCount ?? 0;
  int get solidCount => brick.solidCount;
  MeshData? get currentMeshData => _currentMeshData;

  /// Sets a single voxel material ID (`0` for air) at `(x, y, z)`.
  void setVoxel(int x, int y, int z, int materialId) {
    brick.set(x, y, z, materialId);
    _dirty = true;
  }

  /// Fills an inclusive axis-aligned slab `[minX..maxX, minY..maxY, minZ..maxZ]` with [materialId].
  void fillSlab(
    int minX,
    int minY,
    int minZ,
    int maxX,
    int maxY,
    int maxZ, [
    int materialId = 1,
  ]) {
    brick.fillBox(minX, minY, minZ, maxX, maxY, maxZ, materialId);
    _dirty = true;
  }

  /// Rebuilds the greedy mesh and optionally syncs a sibling [MeshRenderer.mesh].
  void rebuildMesh() {
    final buf = greedy.GreedyBrickMesher.buildMesh(
      brick,
      voxelSize: voxelSize,
      enableAo: bakeAo,
    );
    lastBuffer = buf;
    _dirty = false;

    if (autoSyncMeshRenderer && isAttached && scene.isLoaded) {
      final meshData = _buildMeshData(buf);
      _currentMeshData = meshData;
      final mr = getComponent<MeshRenderer>();
      if (mr != null) {
        final nextHandle = engine.graphics.createMesh(
          meshData,
          debugLabel: '${gameObject.name}#greedyBrick',
        );
        final old = _dynamicMeshHandle;
        _dynamicMeshHandle = nextHandle;
        mr.mesh = nextHandle;
        if (old != null) {
          engine.graphics.releaseMesh(old);
        }
      }
    }
  }

  MeshData _buildMeshData(greedy.GreedyMeshBuffer buf) {
    const stride = 14;
    final vCount = buf.vertexCount;
    final vertices = Float32List(vCount * stride);

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var maxZ = double.negativeInfinity;

    for (var i = 0; i < vCount; i++) {
      final p3 = i * 3;
      final px = buf.positions[p3 + 0];
      final py = buf.positions[p3 + 1];
      final pz = buf.positions[p3 + 2];

      if (px < minX) minX = px;
      if (py < minY) minY = py;
      if (pz < minZ) minZ = pz;
      if (px > maxX) maxX = px;
      if (py > maxY) maxY = py;
      if (pz > maxZ) maxZ = pz;

      final nx = buf.normals[p3 + 0];
      final ny = buf.normals[p3 + 1];
      final nz = buf.normals[p3 + 2];

      final u = buf.uvAndAo[p3 + 0];
      final v = buf.uvAndAo[p3 + 1];
      final aoShade = buf.uvAndAo[p3 + 2];

      final base = i * stride;
      vertices[base + 0] = px;
      vertices[base + 1] = py;
      vertices[base + 2] = pz;
      vertices[base + 3] = nx;
      vertices[base + 4] = ny;
      vertices[base + 5] = nz;
      vertices[base + 6] = aoShade;
      vertices[base + 7] = aoShade;
      vertices[base + 8] = aoShade;
      vertices[base + 9] = 1.0;
      vertices[base + 10] = 1.0;
      vertices[base + 11] = u;
      vertices[base + 12] = v;
      vertices[base + 13] = 0.0;
    }

    final Aabb bounds;
    if (vCount == 0) {
      bounds = const Aabb(Vec3.zero, Vec3(0.01, 0.01, 0.01));
    } else {
      bounds = Aabb(
        Vec3(minX, minY, minZ),
        Vec3(
          math.max(minX + 0.01, maxX),
          math.max(minY + 0.01, maxY),
          math.max(minZ + 0.01, maxZ),
        ),
      );
    }

    return MeshData(
      layout: VertexLayoutDescriptor.compatibility14,
      vertices: vertices,
      indices: Uint32List.fromList(buf.indices),
      localBounds: bounds,
    );
  }

  @override
  void awake() {
    final targetSize = brickSize.clamp(2, 32);
    if (brick.size != targetSize) {
      _initDefaultBrick();
      rebuildMesh();
    }
  }

  @override
  void start() {
    if (autoSyncMeshRenderer) {
      rebuildMesh();
    }
  }

  @override
  void update() {
    if (paused || !_dirty) return;
    rebuildMesh();
  }

  @override
  void onDestroy() {
    if (_dynamicMeshHandle != null && isAttached && scene.isLoaded) {
      engine.graphics.releaseMesh(_dynamicMeshHandle!);
      _dynamicMeshHandle = null;
    }
  }
}

/// Persistent UI state for [GreedyMesherInspectorUI.render].
final class GreedyMesherInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` greedy voxel brick & AO inspector (E95-2).
final class GreedyMesherInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    GreedyMesherInspectorUiState state,
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

  static void _carveCenterCore(GreedyVoxelBrickComponent comp) {
    final size = comp.brick.size;
    final hi = size ~/ 2;
    final lo = math.max(0, hi - 1);

    var hitSlab = false;
    for (var z = lo; z <= hi && !hitSlab; z++) {
      for (var y = 0; y <= 1 && y < size && !hitSlab; y++) {
        for (var x = lo; x <= hi; x++) {
          if (comp.brick.isSolid(x, y, z)) {
            hitSlab = true;
            break;
          }
        }
      }
    }

    if (hitSlab) {
      comp.brick.fillBox(lo, 0, lo, hi, math.min(1, size - 1), hi, 0);
    } else {
      comp.brick.fillBox(lo, lo, lo, hi, hi, hi, 0);
    }
    comp.rebuildMesh();
  }

  static void render(
    VoxUiContext ui,
    GreedyVoxelBrickComponent comp, {
    GreedyMesherInspectorUiState? state,
    String title = 'Greedy Voxel Brick',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? GreedyMesherInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Brick / Voxel',
      '${comp.brick.size}^3 | ${comp.voxelSize.toStringAsFixed(2)}m | solid ${comp.solidCount}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Quads / Tris',
      '${comp.quadCount} quads | ${comp.triangleCount} tris',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'AO / AutoSync',
      'AO ${comp.bakeAo ? 'On' : 'Off'} | Sync ${comp.autoSyncMeshRenderer ? 'On' : 'Off'}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Status',
      comp.paused ? 'Paused' : 'Active',
      valueColor: comp.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'gv_pause',
      comp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      comp.paused = !comp.paused;
    }

    final aoRect = VoxRect(pauseRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'gv_ao', 'Toggle AO', aoRect)) {
      comp.bakeAo = !comp.bakeAo;
      comp.rebuildMesh();
    }

    final carveRect = VoxRect(aoRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'gv_carve', 'Carve Core', carveRect)) {
      _carveCenterCore(comp);
    }

    final rebuildRect = VoxRect(carveRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'gv_rebuild', 'Rebuild', rebuildRect)) {
      comp.rebuildMesh();
    }

    ui.endWindow();
  }
}
