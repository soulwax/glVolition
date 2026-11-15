part of '../../engine.dart';

/// Convenience alias matching Wave 12 subsystem contract.
typedef SoftBodyXpbd = SoftBodyXpbdComponent;

/// Extended Position-Based Dynamics soft-body component backed by `voxverlet` (E94-2).
final class SoftBodyXpbdComponent extends Behaviour {
  double compliance;
  double volumeCompliance;
  double floorY;
  int substeps;
  bool paused;
  double halfExtent;

  MeshHandle? meshHandle;
  MeshData? currentMeshData;
  int meshUploadCount = 0;

  late xpbd.VerletSoftBodySolver solver;
  Vec3 _initialCenter = Vec3.zero;

  SoftBodyXpbdComponent({
    this.compliance = 0.001,
    this.volumeCompliance = 0.0005,
    this.floorY = -1.0,
    this.substeps = 8,
    this.paused = false,
    this.halfExtent = 0.5,
  }) {
    resetRig();
  }

  static final spec = ComponentSpec<SoftBodyXpbdComponent>(
    'SoftBodyXpbdComponent',
    SoftBodyXpbdComponent.new,
    [
      Field.number(
        'compliance',
        (c) => c.compliance,
        (c, v) => c.compliance = v,
      ),
      Field.number(
        'volumeCompliance',
        (c) => c.volumeCompliance,
        (c, v) => c.volumeCompliance = v,
      ),
      Field.number('floorY', (c) => c.floorY, (c, v) => c.floorY = v),
      Field.integer('substeps', (c) => c.substeps, (c, v) => c.substeps = v),
      Field.boolean('paused', (c) => c.paused, (c, v) => c.paused = v),
      Field.number(
        'halfExtent',
        (c) => c.halfExtent,
        (c, v) => c.halfExtent = v,
      ),
    ],
  );

  int get nodeCount => solver.nodes.length;
  double get totalConstraintError => solver.totalConstraintError();
  double get averageStrain => solver.averageStrain();

  Vec3 get centerOfMass {
    final c = solver.centerOfMass();
    return Vec3(c.x, c.y, c.z);
  }

  @override
  void awake() {
    _initialCenter = transform.position;
    resetRig();
  }

  /// Rebuilds the tetrahedral soft-body cube rig around its initial center.
  void resetRig() {
    solver = xpbd.VerletSoftBodySolver.createCubeRig(
      center: xpbd.VerletVec3(
        _initialCenter.x,
        _initialCenter.y,
        _initialCenter.z,
      ),
      halfExtent: math.max(0.05, halfExtent),
      distanceCompliance: math.max(0.0, compliance),
      volumeCompliance: math.max(0.0, volumeCompliance),
      floorY: floorY,
      substeps: math.max(1, substeps),
    );
    if (isAttached) {
      transform.position = centerOfMass;
    }
  }

  /// Advances the XPBD solver by [dt] seconds and syncs [transform.position].
  void stepPhysics(double dt) {
    solver
      ..floorY = floorY
      ..substeps = math.max(1, substeps);
    solver.step(dt);
    if (isAttached) {
      transform.position = centerOfMass;
    }
  }

  /// Applies a linear velocity impulse to all unpinned soft-body nodes.
  void applyImpulse(Vec3 impulse) {
    solver.applyImpulse(xpbd.VerletVec3(impulse.x, impulse.y, impulse.z));
  }

  @override
  void fixedUpdate() {
    if (paused) return;
    stepPhysics(time.fixedDeltaTime);
  }

  /// Recomputes deformed vertex positions and face normals from solver nodes into [MeshData].
  MeshData recomputeMeshData() {
    final nodes = solver.nodes;
    final com = centerOfMass;
    final invWorldPos = isAttached ? transform.position : com;

    final int vertexCount;
    final Float32List vertices;
    final Uint16List indices;

    if (nodes.length >= 8) {
      // 6 quad faces * 4 vertices = 24 vertices
      const stride = 14;
      vertexCount = 24;
      vertices = Float32List(vertexCount * stride);
      indices = Uint16List(36);

      const faces = <(int, int, int, int)>[
        (4, 5, 7, 6), // Front (+Z)
        (1, 0, 2, 3), // Back (-Z)
        (2, 6, 7, 3), // Top (+Y)
        (0, 1, 5, 4), // Bottom (-Y)
        (1, 5, 7, 3), // Right (+X)
        (4, 0, 2, 6), // Left (-X)
      ];

      const uvs = <(double, double)>[
        (0.0, 0.0),
        (1.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
      ];

      for (var f = 0; f < 6; f++) {
        final (i0, i1, i2, i3) = faces[f];
        final p0 = nodes[i0].position;
        final p1 = nodes[i1].position;
        final p2 = nodes[i2].position;
        final p3 = nodes[i3].position;

        final e1x = p1.x - p0.x;
        final e1y = p1.y - p0.y;
        final e1z = p1.z - p0.z;
        final e2x = p2.x - p0.x;
        final e2y = p2.y - p0.y;
        final e2z = p2.z - p0.z;
        var nx = e1y * e2z - e1z * e2y;
        var ny = e1z * e2x - e1x * e2z;
        var nz = e1x * e2y - e1y * e2x;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (len > 1e-8) {
          nx /= len;
          ny /= len;
          nz /= len;
        } else {
          nx = 0.0;
          ny = 1.0;
          nz = 0.0;
        }

        final facePoints = [p0, p1, p2, p3];
        final baseVertex = f * 4;

        for (var v = 0; v < 4; v++) {
          final pt = facePoints[v];
          final lx = pt.x - invWorldPos.x;
          final ly = pt.y - invWorldPos.y;
          final lz = pt.z - invWorldPos.z;
          final (u, uvV) = uvs[v];
          final base = (baseVertex + v) * stride;

          vertices[base + 0] = lx;
          vertices[base + 1] = ly;
          vertices[base + 2] = lz;
          vertices[base + 3] = nx;
          vertices[base + 4] = ny;
          vertices[base + 5] = nz;
          vertices[base + 6] = 1.0;
          vertices[base + 7] = 1.0;
          vertices[base + 8] = 1.0;
          vertices[base + 9] = 1.0;
          vertices[base + 10] = 1.0;
          vertices[base + 11] = u;
          vertices[base + 12] = uvV;
          vertices[base + 13] = 0.0;
        }

        final idxBase = f * 6;
        indices[idxBase + 0] = baseVertex + 0;
        indices[idxBase + 1] = baseVertex + 1;
        indices[idxBase + 2] = baseVertex + 2;
        indices[idxBase + 3] = baseVertex + 0;
        indices[idxBase + 4] = baseVertex + 2;
        indices[idxBase + 5] = baseVertex + 3;
      }
    } else {
      const stride = 14;
      vertexCount = nodes.length;
      vertices = Float32List(vertexCount * stride);
      indices = Uint16List(math.max(1, (vertexCount - 2) * 3));
      for (var i = 0; i < vertexCount; i++) {
        final pt = nodes[i].position;
        final base = i * stride;
        vertices[base + 0] = pt.x - invWorldPos.x;
        vertices[base + 1] = pt.y - invWorldPos.y;
        vertices[base + 2] = pt.z - invWorldPos.z;
        vertices[base + 3] = 0.0;
        vertices[base + 4] = 1.0;
        vertices[base + 5] = 0.0;
        vertices[base + 6] = 1.0;
        vertices[base + 7] = 1.0;
        vertices[base + 8] = 1.0;
        vertices[base + 9] = 1.0;
        vertices[base + 10] = 1.0;
        vertices[base + 11] = 0.0;
        vertices[base + 12] = 0.0;
        vertices[base + 13] = 0.0;
      }
      for (var i = 0; i < vertexCount - 2; i++) {
        indices[i * 3 + 0] = 0;
        indices[i * 3 + 1] = i + 1;
        indices[i * 3 + 2] = i + 2;
      }
    }

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    const stride = 14;
    for (var i = 0; i < vertexCount; i++) {
      final base = i * stride;
      final x = vertices[base + 0];
      final y = vertices[base + 1];
      final z = vertices[base + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }

    if (minX == double.infinity) {
      minX = -0.5;
      minY = -0.5;
      minZ = -0.5;
      maxX = 0.5;
      maxY = 0.5;
      maxZ = 0.5;
    }
    if ((maxX - minX).abs() < 1e-4) {
      minX -= 0.01;
      maxX += 0.01;
    }
    if ((maxY - minY).abs() < 1e-4) {
      minY -= 0.01;
      maxY += 0.01;
    }
    if ((maxZ - minZ).abs() < 1e-4) {
      minZ -= 0.01;
      maxZ += 0.01;
    }

    final data = MeshData(
      layout: VertexLayoutDescriptor.compatibility14,
      vertices: vertices,
      indices: indices,
      localBounds: Aabb(Vec3(minX, minY, minZ), Vec3(maxX, maxY, maxZ)),
    );
    currentMeshData = data;
    return data;
  }

  /// Recomputes deformed vertex positions & normals and uploads dynamic vertices
  /// to [gfx] via [Graphics.updateMeshVertices].
  void syncToRenderer(Graphics gfx, [MeshHandle? overrideMesh]) {
    final data = recomputeMeshData();
    if (overrideMesh != null) {
      meshHandle = overrideMesh;
    }
    if (meshHandle == null) {
      if (isAttached) {
        final mr = getComponent<MeshRenderer>();
        if (mr != null) {
          meshHandle ??= mr.mesh;
        }
      }
      meshHandle ??= gfx.createMesh(
        data,
        debugLabel: '${isAttached ? gameObject.name : "softbody"}#xpbd',
      );
      if (isAttached) {
        final mr = getComponent<MeshRenderer>();
        if (mr != null) {
          mr.mesh = meshHandle;
        }
      }
    }
    gfx.updateMeshVertices(meshHandle!, data);
    meshUploadCount++;
  }
}

/// Persistent UI state for [XpbdSolverInspectorUI.render].
final class SoftBodyXpbdUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` XPBD soft-body solver inspector (E94-2).
final class XpbdSolverInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    SoftBodyXpbdUiState state,
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
    SoftBodyXpbdComponent comp, {
    SoftBodyXpbdUiState? state,
    String title = 'XPBD Soft Body',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? SoftBodyXpbdUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final com = comp.centerOfMass;
    ui.labelValue(
      'Nodes / Substeps',
      '${comp.nodeCount} nodes | ${comp.substeps} substeps',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Error / Strain',
      'err ${comp.totalConstraintError.toStringAsFixed(4)} | strain ${comp.averageStrain.toStringAsFixed(4)}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Center of Mass',
      '(${com.x.toStringAsFixed(2)}, ${com.y.toStringAsFixed(2)}, ${com.z.toStringAsFixed(2)}) | floor ${comp.floorY.toStringAsFixed(1)}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Compliance / Status',
      'dist ${comp.compliance.toStringAsFixed(4)} | ${comp.paused ? 'Paused' : 'Active'}',
      valueColor: comp.paused ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final pauseRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'xpbd_pause',
      comp.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      comp.paused = !comp.paused;
    }

    final substepRect = VoxRect(pauseRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'xpbd_step', 'Substep +1', substepRect)) {
      comp.stepPhysics(0.016);
    }

    final dropRect = VoxRect(substepRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'xpbd_drop', 'Drop', dropRect)) {
      comp.applyImpulse(const Vec3(0.0, -2.5, 0.0));
    }

    final resetRect = VoxRect(dropRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'xpbd_reset', 'Reset', resetRect)) {
      comp.resetRig();
    }

    ui.endWindow();
  }
}
