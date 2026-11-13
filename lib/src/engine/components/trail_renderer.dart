part of '../../engine.dart';

MeshData _buildRibbonMeshData(
  List<Vec3> points, {
  required double startWidth,
  required double endWidth,
  LinearColor color = const LinearColor(1.0, 1.0, 1.0),
  Vec3 upHint = Vec3.unitY,
}) {
  final n = points.length;
  const stride = 14;
  final vertices = Float32List(n * 2 * stride);
  final indices = Uint32List((n - 1) * 6);

  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;

  void includePoint(Vec3 v) {
    if (v.x < minX) minX = v.x;
    if (v.y < minY) minY = v.y;
    if (v.z < minZ) minZ = v.z;
    if (v.x > maxX) maxX = v.x;
    if (v.y > maxY) maxY = v.y;
    if (v.z > maxZ) maxZ = v.z;
  }

  for (var i = 0; i < n; i++) {
    final t = n > 1 ? i / (n - 1) : 0.0;
    final halfW = (startWidth + (endWidth - startWidth) * t) * 0.5;
    final p = points[i];

    final Vec3 tangent;
    if (i == 0) {
      tangent = (points[1] - points[0]).normalized;
    } else if (i == n - 1) {
      tangent = (points[n - 1] - points[n - 2]).normalized;
    } else {
      tangent = (points[i + 1] - points[i - 1]).normalized;
    }

    var side = tangent.cross(upHint);
    if (side.lengthSquared < 1e-6) {
      side = tangent.cross(Vec3.unitX);
      if (side.lengthSquared < 1e-6) side = Vec3.unitZ;
    }
    side = side.normalized;
    final normal = side.cross(tangent).normalized;

    final left = p - side * halfW;
    final right = p + side * halfW;
    includePoint(left);
    includePoint(right);

    void writeVertex(int vIndex, Vec3 pos, double u, double v) {
      final base = vIndex * stride;
      vertices[base + 0] = pos.x;
      vertices[base + 1] = pos.y;
      vertices[base + 2] = pos.z;
      vertices[base + 3] = normal.x;
      vertices[base + 4] = normal.y;
      vertices[base + 5] = normal.z;
      vertices[base + 6] = color.r;
      vertices[base + 7] = color.g;
      vertices[base + 8] = color.b;
      vertices[base + 9] = 1.0;
      vertices[base + 10] = 1.0;
      vertices[base + 11] = u;
      vertices[base + 12] = v;
      vertices[base + 13] = 0.0;
    }

    writeVertex(i * 2, left, t, 0.0);
    writeVertex(i * 2 + 1, right, t, 1.0);

    if (i < n - 1) {
      final v0 = i * 2;
      final v1 = v0 + 1;
      final v2 = v0 + 2;
      final v3 = v0 + 3;
      final idxBase = i * 6;
      indices[idxBase + 0] = v0;
      indices[idxBase + 1] = v2;
      indices[idxBase + 2] = v1;
      indices[idxBase + 3] = v1;
      indices[idxBase + 4] = v2;
      indices[idxBase + 5] = v3;
    }
  }

  return MeshData(
    vertices: vertices,
    indices: indices,
    layout: VertexLayoutDescriptor.compatibility14,
    localBounds: Aabb(
      Vec3(minX - 0.01, minY - 0.01, minZ - 0.01),
      Vec3(maxX + 0.01, maxY + 0.01, maxZ + 0.01),
    ),
  );
}

/// Renders a 3D ribbon polyline through a list of [positions] with tapered
/// width from [startWidth] to [endWidth] (E10-3).
final class LineRenderer extends Component {
  final List<Vec3> _positions;
  double _startWidth = 0.15;
  double _endWidth = 0.15;
  LinearColor _color = const LinearColor(0.3, 0.85, 1.0);
  bool useWorldSpace;
  MaterialHandle? material;

  SceneNode? _node;
  MeshHandle? _mesh;
  MeshData? _meshData;
  bool _dirty = true;

  LineRenderer({
    Iterable<Vec3> positions = const [],
    double startWidth = 0.15,
    double endWidth = 0.15,
    LinearColor color = const LinearColor(0.3, 0.85, 1.0),
    this.useWorldSpace = true,
    this.material,
  }) : _positions = List.of(positions) {
    _startWidth = startWidth;
    _endWidth = endWidth;
    _color = color;
  }

  List<Vec3> get positions => List.unmodifiable(_positions);
  int get positionCount => _positions.length;
  MeshData? get meshData => _meshData;

  double get startWidth => _startWidth;
  set startWidth(double value) {
    _startWidth = value;
    _dirty = true;
  }

  double get endWidth => _endWidth;
  set endWidth(double value) {
    _endWidth = value;
    _dirty = true;
  }

  LinearColor get color => _color;
  set color(LinearColor value) {
    _color = value;
    if (isAttached && scene.isLoaded) {
      material = _createDefaultMaterial();
      _node?.material = material;
    }
  }

  void setPositions(Iterable<Vec3> nextPositions) {
    _positions
      ..clear()
      ..addAll(nextPositions);
    _dirty = true;
  }

  void setPosition(int index, Vec3 position) {
    _positions[index] = position;
    _dirty = true;
  }

  MaterialHandle _createDefaultMaterial() => engine.graphics.createMaterial(
    MaterialDefinition(
      key: 'line_${gameObject.name}_${identityHashCode(this)}',
      tintR: _color.r,
      tintG: _color.g,
      tintB: _color.b,
      emissiveStrength: 1.5,
      roughness: 0.9,
      metallic: 0.0,
    ),
  );

  void _syncRibbon() {
    final n = _node;
    if (n == null || !scene.isLoaded) return;
    if (!_dirty) return;
    _dirty = false;

    if (_positions.length < 2) {
      n.visible = false;
      return;
    }

    final pts = useWorldSpace
        ? _positions.map((p) => p - transform.position).toList(growable: false)
        : _positions;

    final data = _buildRibbonMeshData(
      pts,
      startWidth: _startWidth,
      endWidth: _endWidth,
    );
    _meshData = data;
    if (_mesh != null) {
      engine.graphics.releaseMesh(_mesh!);
    }
    _mesh = engine.graphics.createMesh(
      data,
      debugLabel: '${gameObject.name}#line_ribbon',
    );
    material ??= _createDefaultMaterial();
    n
      ..mesh = _mesh
      ..meshData = data
      ..bounds = data.bounds
      ..material = material
      ..visible = _active;
  }

  @override
  void _onAttach() {
    final node = SceneNode(
      name: '${gameObject.name}#line',
      castsShadow: false,
      receivesShadow: false,
    )..visible = false;
    gameObject.node.addChild(node);
    _node = node;
  }

  @override
  void _onEnableInternal() {
    scene._lines.add(this);
    _dirty = true;
    _syncRibbon();
  }

  @override
  void _onDisableInternal() {
    scene._lines.remove(this);
    _node?.visible = false;
  }

  @override
  void _onDestroyInternal() {
    scene._lines.remove(this);
    if (_mesh != null && scene.isLoaded) {
      engine.graphics.releaseMesh(_mesh!);
      _mesh = null;
    }
    _node?.removeFromParent();
    _node = null;
  }
}

final class _TrailSample {
  final Vec3 position;
  final double timestamp;
  const _TrailSample(this.position, this.timestamp);
}

/// Automatically records its [GameObject]'s movement over [time] seconds and
/// generates a tapered 3D ribbon mesh behind it (E10-3).
final class TrailRenderer extends Behaviour {
  double timeLength;
  double minVertexDistance;
  double startWidth;
  double endWidth;
  LinearColor color;
  bool emitting;
  MaterialHandle? material;

  final List<_TrailSample> _samples = [];
  SceneNode? _node;
  MeshHandle? _mesh;
  MeshData? _meshData;

  TrailRenderer({
    this.timeLength = 0.5,
    this.minVertexDistance = 0.1,
    this.startWidth = 0.25,
    this.endWidth = 0.02,
    this.color = const LinearColor(1.0, 0.65, 0.2),
    this.emitting = true,
    this.material,
  });

  static final spec =
      ComponentSpec<TrailRenderer>('TrailRenderer', TrailRenderer.new, [
        Field.number(
          'timeLength',
          (t) => t.timeLength,
          (t, v) => t.timeLength = v,
        ),
        Field.number(
          'minVertexDistance',
          (t) => t.minVertexDistance,
          (t, v) => t.minVertexDistance = v,
        ),
        Field.number(
          'startWidth',
          (t) => t.startWidth,
          (t, v) => t.startWidth = v,
        ),
        Field.number('endWidth', (t) => t.endWidth, (t, v) => t.endWidth = v),
        Field.color('color', (t) => t.color, (t, v) => t.color = v),
        Field.boolean('emitting', (t) => t.emitting, (t, v) => t.emitting = v),
      ]);

  int get sampleCount => _samples.length;
  MeshData? get meshData => _meshData;

  void clear() {
    _samples.clear();
    _node?.visible = false;
  }

  @override
  void _onAttach() {
    final node = SceneNode(
      name: '${gameObject.name}#trail',
      castsShadow: false,
      receivesShadow: false,
    )..visible = false;
    gameObject.node.addChild(node);
    _node = node;
  }

  @override
  void lateUpdate() {
    final now = time.time;
    final pos = transform.position;

    if (emitting) {
      if (_samples.isEmpty ||
          (pos - _samples.last.position).length >= minVertexDistance) {
        _samples.add(_TrailSample(pos, now));
      }
    }

    _samples.removeWhere((s) => now - s.timestamp > timeLength);

    final n = _node;
    if (n == null || !scene.isLoaded) return;

    if (_samples.length < 2) {
      n.visible = false;
      return;
    }

    // Build ribbon from newest (head = startWidth) to oldest (tail = endWidth)
    // in the GameObject's local coordinate space.
    final localPts = <Vec3>[
      for (var i = _samples.length - 1; i >= 0; i--) _samples[i].position - pos,
    ];

    final data = _buildRibbonMeshData(
      localPts,
      startWidth: startWidth,
      endWidth: endWidth,
    );
    _meshData = data;
    if (_mesh != null) {
      engine.graphics.releaseMesh(_mesh!);
    }
    _mesh = engine.graphics.createMesh(
      data,
      debugLabel: '${gameObject.name}#trail_ribbon',
    );
    material ??= engine.graphics.createMaterial(
      MaterialDefinition(
        key: 'trail_${gameObject.name}_${identityHashCode(this)}',
        tintR: color.r,
        tintG: color.g,
        tintB: color.b,
        emissiveStrength: 1.8,
        roughness: 0.9,
        metallic: 0.0,
      ),
    );
    n
      ..mesh = _mesh
      ..meshData = data
      ..bounds = data.bounds
      ..material = material
      ..visible = _active;
  }

  @override
  void _onDisableInternal() {
    _node?.visible = false;
  }

  @override
  void _onDestroyInternal() {
    if (_mesh != null && scene.isLoaded) {
      engine.graphics.releaseMesh(_mesh!);
      _mesh = null;
    }
    _node?.removeFromParent();
    _node = null;
  }
}
