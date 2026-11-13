part of '../../engine.dart';

/// Deterministic curl-advected particle stream & Catmull-Rom ribbon trail (`voxribbon`) (E81-2).
final class ParticleRibbonComponent extends Behaviour {
  double startWidth;
  double endWidth;
  double trailLifetimeSeconds;
  double minVertexDistance;
  double emissionRate;
  double curlAmplitude;
  double curlFrequency;
  bool emitting;
  bool syncRibbonMesh;

  MeshRenderer? targetMeshRenderer;

  late ribbon.RibbonTrailBuffer trailBuffer;
  late ribbon.ParticleStreamEmitter emitter;

  MeshData? _lastMeshData;
  MeshHandle? _meshHandle;

  ParticleRibbonComponent({
    this.startWidth = 0.6,
    this.endWidth = 0.05,
    this.trailLifetimeSeconds = 1.2,
    this.minVertexDistance = 0.2,
    this.emissionRate = 24.0,
    this.curlAmplitude = 2.8,
    this.curlFrequency = 0.7,
    this.emitting = true,
    this.syncRibbonMesh = true,
    this.targetMeshRenderer,
    int seed = 1337,
  }) {
    trailBuffer = ribbon.RibbonTrailBuffer(
      startWidth: startWidth,
      endWidth: endWidth,
      lifetimeSeconds: trailLifetimeSeconds,
      minVertexDistance: minVertexDistance,
    );
    emitter = ribbon.ParticleStreamEmitter(
      emissionRate: emissionRate,
      curlField: ribbon.CurlTurbulenceField(
        amplitude: curlAmplitude,
        frequency: curlFrequency,
      ),
      seed: seed,
    );
  }

  static final spec = ComponentSpec<ParticleRibbonComponent>(
    'ParticleRibbonComponent',
    ParticleRibbonComponent.new,
    [
      Field.number(
        'startWidth',
        (c) => c.startWidth,
        (c, v) => c.startWidth = v,
      ),
      Field.number('endWidth', (c) => c.endWidth, (c, v) => c.endWidth = v),
      Field.number(
        'trailLifetimeSeconds',
        (c) => c.trailLifetimeSeconds,
        (c, v) => c.trailLifetimeSeconds = v,
      ),
      Field.number(
        'minVertexDistance',
        (c) => c.minVertexDistance,
        (c, v) => c.minVertexDistance = v,
      ),
      Field.number(
        'emissionRate',
        (c) => c.emissionRate,
        (c, v) => c.emissionRate = v,
      ),
      Field.number(
        'curlAmplitude',
        (c) => c.curlAmplitude,
        (c, v) => c.curlAmplitude = v,
      ),
      Field.number(
        'curlFrequency',
        (c) => c.curlFrequency,
        (c, v) => c.curlFrequency = v,
      ),
      Field.boolean('emitting', (c) => c.emitting, (c, v) => c.emitting = v),
      Field.boolean(
        'syncRibbonMesh',
        (c) => c.syncRibbonMesh,
        (c, v) => c.syncRibbonMesh = v,
      ),
    ],
  );

  int get ribbonPointCount => trailBuffer.pointCount;
  int get particleCount => emitter.particleCount;
  MeshData? get lastMeshData => _lastMeshData;

  void burst(int count) {
    final pos = isAttached ? transform.position : Vec3.zero;
    final dir = isAttached ? transform.forward : kForward;
    emitter.burst(
      count,
      origin: ribbon.RibbonVec3(pos.x, pos.y, pos.z),
      direction: ribbon.RibbonVec3(dir.x, dir.y, dir.z),
    );
  }

  void clear() {
    trailBuffer.clear();
    emitter.clear();
    _lastMeshData = null;
  }

  /// Advances both the ribbon spine buffer and curl-advected particle stream by [dt] seconds.
  void stepEffect(double dt) {
    trailBuffer.startWidth = math.max(0.01, startWidth);
    trailBuffer.endWidth = math.max(0.0, endWidth);
    trailBuffer.lifetimeSeconds = math.max(0.05, trailLifetimeSeconds);
    trailBuffer.minVertexDistance = math.max(0.01, minVertexDistance);

    emitter.emissionRate = math.max(0.0, emissionRate);
    emitter.curlField = ribbon.CurlTurbulenceField(
      amplitude: curlAmplitude,
      frequency: math.max(0.05, curlFrequency),
    );

    final pos = isAttached ? transform.position : Vec3.zero;
    final dir = isAttached ? transform.forward : kForward;
    final rOrigin = ribbon.RibbonVec3(pos.x, pos.y, pos.z);
    final rDir = ribbon.RibbonVec3(dir.x, dir.y, dir.z);

    trailBuffer.advanceTime(dt);
    if (emitting) {
      trailBuffer.recordSample(rOrigin);
    }

    emitter.step(dt, origin: rOrigin, direction: rDir, emit: emitting);

    if (syncRibbonMesh) {
      _rebuildRibbonMesh();
    }
  }

  MeshData? _rebuildRibbonMesh() {
    final geom = trailBuffer.buildMesh();
    if (geom.vertices.isEmpty || geom.indices.isEmpty) {
      _lastMeshData = null;
      return null;
    }

    const stride = 14;
    final verts = Float32List(geom.vertices.length * stride);
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;

    for (var i = 0; i < geom.vertices.length; i++) {
      final v = geom.vertices[i];
      final b = i * stride;
      verts[b + 0] = v.position.x;
      verts[b + 1] = v.position.y;
      verts[b + 2] = v.position.z;
      verts[b + 3] = v.normal.x;
      verts[b + 4] = v.normal.y;
      verts[b + 5] = v.normal.z;
      verts[b + 6] = v.color.r;
      verts[b + 7] = v.color.g;
      verts[b + 8] = v.color.b;
      verts[b + 9] = v.color.a;
      verts[b + 10] = 1.0;
      verts[b + 11] = v.u;
      verts[b + 12] = v.v;
      verts[b + 13] = 0.0;

      if (v.position.x < minX) minX = v.position.x;
      if (v.position.y < minY) minY = v.position.y;
      if (v.position.z < minZ) minZ = v.position.z;
      if (v.position.x > maxX) maxX = v.position.x;
      if (v.position.y > maxY) maxY = v.position.y;
      if (v.position.z > maxZ) maxZ = v.position.z;
    }

    final indices = Uint32List.fromList(geom.indices);
    final data = MeshData(
      vertices: verts,
      indices: indices,
      layout: VertexLayoutDescriptor.compatibility14,
      localBounds: Aabb(
        Vec3(minX - 0.01, minY - 0.01, minZ - 0.01),
        Vec3(maxX + 0.01, maxY + 0.01, maxZ + 0.01),
      ),
    );
    _lastMeshData = data;

    if (isAttached && scene.isLoaded) {
      final mr = targetMeshRenderer ?? getComponent<MeshRenderer>();
      if (mr != null) {
        if (_meshHandle != null) {
          engine.graphics.releaseMesh(_meshHandle!);
        }
        _meshHandle = engine.graphics.createMesh(
          data,
          debugLabel: 'voxribbon_mesh',
        );
        mr.mesh = _meshHandle;
      }
    }
    return data;
  }

  @override
  void update() {
    stepEffect(time.deltaTime);
  }
}

/// Persistent UI state for [RibbonInspectorUI.render].
final class RibbonInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` ribbon trail & curl turbulence stream inspector (E81-2).
final class RibbonInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    RibbonInspectorUiState state,
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
    ParticleRibbonComponent ribbonComp, {
    RibbonInspectorUiState? state,
    String title = 'Particle Ribbon FX',
    double x = 20.0,
    double y = 20.0,
    double width = 395.0,
    double height = 245.0,
  }) {
    final uiState = state ?? RibbonInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Emitter State',
      '${ribbonComp.emitting ? 'Emitting' : 'Paused'} | ${ribbonComp.emissionRate.toStringAsFixed(0)} /s',
      valueColor: ribbonComp.emitting ? VoxColor.green : VoxColor.yellow,
    );
    ui.labelValue(
      'Particles / Spine',
      '${ribbonComp.particleCount} active | ${ribbonComp.ribbonPointCount} trail pts',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Curl Turbulence',
      'amp ${ribbonComp.curlAmplitude.toStringAsFixed(1)} | freq ${ribbonComp.curlFrequency.toStringAsFixed(2)}',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Ribbon Taper',
      '${ribbonComp.startWidth.toStringAsFixed(2)}m -> ${ribbonComp.endWidth.toStringAsFixed(2)}m',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final emitRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'rib_emit',
      ribbonComp.emitting ? 'Pause' : 'Emit',
      emitRect,
    )) {
      ribbonComp.emitting = !ribbonComp.emitting;
    }

    final burstRect = VoxRect(emitRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'rib_burst', 'Burst +12', burstRect)) {
      ribbonComp.burst(12);
    }

    final curlRect = VoxRect(burstRect.right + 8.0, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'rib_curl', 'Curl +1', curlRect)) {
      ribbonComp.curlAmplitude += 1.0;
    }

    final clearRect = VoxRect(curlRect.right + 8.0, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'rib_clear', 'Clear', clearRect)) {
      ribbonComp.clear();
    }

    ui.endWindow();
  }
}
