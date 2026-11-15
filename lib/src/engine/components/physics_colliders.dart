part of '../../engine.dart';

/// Base class for collision shapes. Overlaps fire `onTriggerEnter`/`Stay`/`Exit`
/// on every active [Behaviour] on both objects, and [PhysicsWorld] supports
/// raycasts, overlaps, and sweeps with 32-bit layer masks.
abstract base class Collider extends Component {
  Vec3 center;
  bool isTrigger;

  /// Bitmask of object layers (0..31) this collider interacts with.
  int collidesWithMask;

  Collider({
    this.center = Vec3.zero,
    this.isTrigger = true,
    this.collidesWithMask = -1,
  });

  Vec3 get worldCenter => transform.transformPoint(center);
  Aabb get worldBounds;

  double? _raycast(Ray ray);

  bool intersectsAabb(Aabb bounds);

  bool intersectsSphere(Vec3 center, double radius);

  double? sweepSphere(Ray ray, double radius);

  @override
  void _onEnableInternal() => scene.physics._register(this);

  @override
  void _onDisableInternal() => scene.physics._unregister(this);
}

/// Spherical 3D collider.
final class SphereCollider extends Collider {
  double radius;

  SphereCollider({
    this.radius = 0.5,
    super.center,
    super.isTrigger,
    super.collidesWithMask,
  });

  static final spec = ComponentSpec<SphereCollider>(
    'SphereCollider',
    SphereCollider.new,
    [
      Field.number('radius', (c) => c.radius, (c, v) => c.radius = v),
      Field.vec3('center', (c) => c.center, (c, v) => c.center = v),
      Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
      Field.integer(
        'collidesWithMask',
        (c) => c.collidesWithMask,
        (c, v) => c.collidesWithMask = v,
      ),
    ],
  );

  /// World-space radius, scaled by the object's uniform [TransformComponent.lossyScale].
  double get worldRadius => radius * transform.lossyScale;

  @override
  Aabb get worldBounds {
    if (!isAttached) {
      final r = Vec3(radius, radius, radius);
      return Aabb(center - r, center + r);
    }
    final c = worldCenter;
    final r = Vec3(worldRadius, worldRadius, worldRadius);
    return Aabb(c - r, c + r);
  }

  @override
  double? _raycast(Ray ray) =>
      ray.intersectSphere(BoundingSphere(worldCenter, worldRadius));

  @override
  bool intersectsAabb(Aabb bounds) =>
      PhysicsNarrowphase.sphereIntersectsAabb(worldCenter, worldRadius, bounds);

  @override
  bool intersectsSphere(Vec3 center, double radius) =>
      PhysicsNarrowphase.sphereIntersectsSphere(
        worldCenter,
        worldRadius,
        center,
        radius,
      );

  @override
  double? sweepSphere(Ray ray, double radius) =>
      ray.intersectSphere(BoundingSphere(worldCenter, worldRadius + radius));
}

/// Oriented 3D box collider with true 15-axis Separating Axis Theorem (SAT)
/// intersection and contact manifolds.
final class BoxCollider extends Collider {
  Vec3 size;

  BoxCollider({
    this.size = const Vec3(1, 1, 1),
    super.center,
    super.isTrigger,
    super.collidesWithMask,
  });

  static final spec = ComponentSpec<BoxCollider>(
    'BoxCollider',
    BoxCollider.new,
    [
      Field.vec3('size', (c) => c.size, (c, v) => c.size = v),
      Field.vec3('center', (c) => c.center, (c, v) => c.center = v),
      Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
      Field.integer(
        'collidesWithMask',
        (c) => c.collidesWithMask,
        (c, v) => c.collidesWithMask = v,
      ),
    ],
  );

  @override
  Aabb get worldBounds {
    final half = size * 0.5;
    final localAabb = Aabb(center - half, center + half);
    if (!isAttached) return localAabb;
    return localAabb.transformed(transform.world.toMat4());
  }

  @override
  double? _raycast(Ray ray) => _Obb.fromBox(this).raycast(ray);

  @override
  bool intersectsAabb(Aabb bounds) =>
      _Obb.testObbObb(_Obb.fromBox(this), _Obb.fromAabb(bounds)) != null;

  @override
  bool intersectsSphere(Vec3 center, double radius) =>
      _Obb.obbIntersectsSphere(_Obb.fromBox(this), center, radius);

  @override
  double? sweepSphere(Ray ray, double radius) {
    final pad = Vec3(radius, radius, radius);
    final b = worldBounds;
    return ray.intersectAabb(Aabb(b.min - pad, b.max + pad));
  }
}

/// Vertical or rotated 3D capsule collider defined by a hemispherical [radius]
/// and total [height].
final class CapsuleCollider extends Collider {
  double radius;
  double height;

  CapsuleCollider({
    this.radius = 0.4,
    this.height = 1.8,
    super.center,
    super.isTrigger,
    super.collidesWithMask,
  });

  static final spec = ComponentSpec<CapsuleCollider>(
    'CapsuleCollider',
    CapsuleCollider.new,
    [
      Field.number('radius', (c) => c.radius, (c, v) => c.radius = v),
      Field.number('height', (c) => c.height, (c, v) => c.height = v),
      Field.vec3('center', (c) => c.center, (c, v) => c.center = v),
      Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
      Field.integer(
        'collidesWithMask',
        (c) => c.collidesWithMask,
        (c, v) => c.collidesWithMask = v,
      ),
    ],
  );

  double get worldRadius => radius * transform.lossyScale;

  /// Half-length of the interior line segment between the two hemisphere centers.
  double get halfSegmentLength =>
      math.max(0.0, (height * 0.5 - radius) * transform.lossyScale);

  /// Bottom hemisphere center in world space.
  Vec3 get segmentStart => worldCenter - transform.up * halfSegmentLength;

  /// Top hemisphere center in world space.
  Vec3 get segmentEnd => worldCenter + transform.up * halfSegmentLength;

  /// Returns the point on the capsule's interior segment `[segmentStart, segmentEnd]`
  /// closest to [point].
  Vec3 closestPointOnAxis(Vec3 point) {
    final a = segmentStart;
    final b = segmentEnd;
    final ab = b - a;
    final lenSq = ab.lengthSquared;
    if (lenSq < 1e-12) return a;
    final t = ((point - a).dot(ab) / lenSq).clamp(0.0, 1.0);
    return a + ab * t;
  }

  @override
  Aabb get worldBounds {
    if (!isAttached) {
      final halfH = height * 0.5;
      return Aabb(
        Vec3(center.x - radius, center.y - halfH, center.z - radius),
        Vec3(center.x + radius, center.y + halfH, center.z + radius),
      );
    }
    final a = segmentStart;
    final b = segmentEnd;
    final r = Vec3(worldRadius, worldRadius, worldRadius);
    final minPt = Vec3(
      math.min(a.x, b.x) - r.x,
      math.min(a.y, b.y) - r.y,
      math.min(a.z, b.z) - r.z,
    );
    final maxPt = Vec3(
      math.max(a.x, b.x) + r.x,
      math.max(a.y, b.y) + r.y,
      math.max(a.z, b.z) + r.z,
    );
    return Aabb(minPt, maxPt);
  }

  @override
  double? _raycast(Ray ray) {
    if (ray.intersectAabb(worldBounds) == null) return null;
    final r = worldRadius;
    final a = segmentStart;
    final b = segmentEnd;
    double? best;
    const samples = 5;
    for (var i = 0; i <= samples; i++) {
      final p = Vec3.lerp(a, b, i / samples);
      final t = ray.intersectSphere(BoundingSphere(p, r));
      if (t != null && (best == null || t < best)) best = t;
    }
    return best;
  }

  @override
  bool intersectsAabb(Aabb bounds) =>
      _Obb.testObbCapsule(_Obb.fromAabb(bounds), this) != null;

  @override
  bool intersectsSphere(Vec3 center, double radius) =>
      PhysicsNarrowphase.sphereIntersectsSphere(
        closestPointOnAxis(center),
        worldRadius,
        center,
        radius,
      );

  @override
  double? sweepSphere(Ray ray, double radius) {
    final pad = Vec3(radius, radius, radius);
    final b = worldBounds;
    return ray.intersectAabb(Aabb(b.min - pad, b.max + pad));
  }
}

/// BVH-accelerated static concave triangle mesh collider.
final class MeshCollider extends Collider {
  final List<Vec3> vertices;
  final List<int> indices;
  late final _MeshBvh _bvh;
  late final Aabb _localBounds;

  MeshCollider({
    List<Vec3>? vertices,
    List<int>? indices,
    MeshData? meshData,
    super.center,
    super.isTrigger,
    super.collidesWithMask,
  }) : vertices = vertices ?? _extractVertices(meshData),
       indices = indices ?? _extractIndices(meshData, vertices) {
    _initBvh();
  }

  factory MeshCollider.fromMeshData(
    MeshData meshData, {
    Vec3 center = Vec3.zero,
    bool isTrigger = true,
    int collidesWithMask = -1,
  }) => MeshCollider(
    meshData: meshData,
    center: center,
    isTrigger: isTrigger,
    collidesWithMask: collidesWithMask,
  );

  static final spec = ComponentSpec<MeshCollider>(
    'MeshCollider',
    MeshCollider.new,
    [
      Field.vec3('center', (c) => c.center, (c, v) => c.center = v),
      Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
      Field.integer(
        'collidesWithMask',
        (c) => c.collidesWithMask,
        (c, v) => c.collidesWithMask = v,
      ),
    ],
  );

  static List<Vec3> _extractVertices(MeshData? meshData) {
    if (meshData == null) return const [];
    final attr = meshData.layout.attributes.firstWhere(
      (a) => a.kind == VertexAttributeKind.position,
      orElse: () => throw ArgumentError('MeshData has no position attribute'),
    );
    final count = meshData.vertexCount;
    final stride = meshData.layout.strideFloats;
    final offset = attr.floatOffset;
    final verts = List<Vec3>.filled(count, Vec3.zero);
    for (var i = 0; i < count; i++) {
      final base = i * stride + offset;
      verts[i] = Vec3(
        meshData.vertices[base],
        meshData.vertices[base + 1],
        meshData.vertices[base + 2],
      );
    }
    return verts;
  }

  static List<int> _extractIndices(MeshData? meshData, List<Vec3>? verts) {
    if (meshData == null) {
      final vCount = verts?.length ?? 0;
      return List<int>.generate(vCount, (i) => i);
    }
    if (meshData.indices != null) {
      return List<int>.from(meshData.indices!);
    }
    return List<int>.generate(meshData.vertexCount, (i) => i);
  }

  void _initBvh() {
    if (vertices.isEmpty || indices.length < 3) {
      _localBounds = const Aabb(Vec3.zero, Vec3.zero);
      _bvh = _MeshBvh.empty();
      return;
    }
    _localBounds = Aabb.fromPoints(vertices);
    _bvh = _MeshBvh.build(this);
  }

  int get triangleCount => indices.length ~/ 3;

  (Vec3, Vec3, Vec3) getTriangleLocal(int triIdx) {
    final i0 = indices[triIdx * 3];
    final i1 = indices[triIdx * 3 + 1];
    final i2 = indices[triIdx * 3 + 2];
    return (vertices[i0], vertices[i1], vertices[i2]);
  }

  (Vec3, Vec3, Vec3) getTriangleWorld(int triIdx) {
    final (v0, v1, v2) = getTriangleLocal(triIdx);
    final w0 = transform.transformPoint(v0 + center);
    final w1 = transform.transformPoint(v1 + center);
    final w2 = transform.transformPoint(v2 + center);
    return (w0, w1, w2);
  }

  @override
  Aabb get worldBounds {
    final b = Aabb(_localBounds.min + center, _localBounds.max + center);
    if (!isAttached) return b;
    return b.transformed(transform.world.toMat4());
  }

  @override
  double? _raycast(Ray ray) {
    if (ray.intersectAabb(worldBounds) == null) return null;
    final localRay = _worldToLocalRay(ray, this);
    return _bvh.raycast(this, localRay, double.infinity);
  }

  @override
  bool intersectsAabb(Aabb bounds) {
    final localQuery = _transformAabbToLocal(bounds, this);
    final candidates = <int>[];
    _bvh.queryAabb(_bvh.root, localQuery, candidates);
    final obb = _Obb.fromAabb(bounds);
    for (final tri in candidates) {
      final (w0, w1, w2) = getTriangleWorld(tri);
      if (_triangleIntersectsObb(w0, w1, w2, obb)) return true;
    }
    return false;
  }

  @override
  bool intersectsSphere(Vec3 center, double radius) {
    final queryWorld = Aabb(
      center - Vec3(radius, radius, radius),
      center + Vec3(radius, radius, radius),
    );
    final localQuery = _transformAabbToLocal(queryWorld, this);
    final candidates = <int>[];
    _bvh.queryAabb(_bvh.root, localQuery, candidates);
    for (final tri in candidates) {
      final (w0, w1, w2) = getTriangleWorld(tri);
      if (_triangleIntersectsSphere(w0, w1, w2, center, radius)) return true;
    }
    return false;
  }

  @override
  double? sweepSphere(Ray ray, double radius) {
    final pad = Vec3(radius, radius, radius);
    final b = worldBounds;
    return ray.intersectAabb(Aabb(b.min - pad, b.max + pad));
  }
}

/// Grid-based heightfield terrain collider.
final class HeightfieldCollider extends Collider {
  final int columns;
  final int rows;
  final Float32List heights;
  final double cellSize;
  final double heightScale;
  late final Aabb _localBounds;

  HeightfieldCollider({
    required this.columns,
    required this.rows,
    required List<double> heights,
    double? cellSize,
    double? worldSize,
    this.heightScale = 1.0,
    super.center,
    super.isTrigger,
    super.collidesWithMask,
  }) : cellSize =
           cellSize ?? (worldSize != null ? worldSize / (columns - 1) : 1.0),
       heights = heights is Float32List
           ? heights
           : Float32List.fromList(heights) {
    if (columns < 2 || rows < 2) {
      throw ArgumentError('Heightfield columns and rows must be at least 2');
    }
    if (this.heights.length < columns * rows) {
      throw ArgumentError('heights length must be at least columns * rows');
    }
    _initBounds();
  }

  static final spec = ComponentSpec<HeightfieldCollider>(
    'HeightfieldCollider',
    () => HeightfieldCollider(columns: 2, rows: 2, heights: [0, 0, 0, 0]),
    [
      Field.integer('columns', (c) => c.columns, (c, v) {}),
      Field.integer('rows', (c) => c.rows, (c, v) {}),
      Field.number('cellSize', (c) => c.cellSize, (c, v) {}),
      Field.number('heightScale', (c) => c.heightScale, (c, v) {}),
      Field.vec3('center', (c) => c.center, (c, v) => c.center = v),
      Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
      Field.integer(
        'collidesWithMask',
        (c) => c.collidesWithMask,
        (c, v) => c.collidesWithMask = v,
      ),
    ],
  );

  void _initBounds() {
    var minH = heights[0] * heightScale;
    var maxH = minH;
    for (var i = 1; i < columns * rows; i++) {
      final h = heights[i] * heightScale;
      if (h < minH) minH = h;
      if (h > maxH) maxH = h;
    }
    final maxX = (columns - 1) * cellSize;
    final maxZ = (rows - 1) * cellSize;
    _localBounds = Aabb(Vec3(0, minH, 0), Vec3(maxX, maxH, maxZ));
  }

  /// Bilinear interpolation of terrain height at local coordinates `(localX, localZ)`.
  double sampleHeightAt(double localX, double localZ) {
    final x = localX - center.x;
    final z = localZ - center.z;
    final gx = (x / cellSize).clamp(0.0, (columns - 1).toDouble());
    final gz = (z / cellSize).clamp(0.0, (rows - 1).toDouble());
    final c0 = math.min(gx.floor(), columns - 2);
    final r0 = math.min(gz.floor(), rows - 2);
    final fx = gx - c0;
    final fz = gz - r0;
    final h00 = heights[r0 * columns + c0] * heightScale;
    final h10 = heights[r0 * columns + (c0 + 1)] * heightScale;
    final h01 = heights[(r0 + 1) * columns + c0] * heightScale;
    final h11 = heights[(r0 + 1) * columns + (c0 + 1)] * heightScale;
    final h0 = h00 + (h10 - h00) * fx;
    final h1 = h01 + (h11 - h01) * fx;
    return (h0 + (h1 - h0) * fz) + center.y;
  }

  (Vec3, Vec3, Vec3) getCellTriangleLocal(int c, int r, int triIndex) {
    final cs = cellSize;
    final hs = heightScale;
    final h00 = heights[r * columns + c] * hs;
    final h10 = heights[r * columns + (c + 1)] * hs;
    final h01 = heights[(r + 1) * columns + c] * hs;
    final h11 = heights[(r + 1) * columns + (c + 1)] * hs;

    final p00 = Vec3(c * cs, h00, r * cs) + center;
    final p10 = Vec3((c + 1) * cs, h10, r * cs) + center;
    final p01 = Vec3(c * cs, h01, (r + 1) * cs) + center;
    final p11 = Vec3((c + 1) * cs, h11, (r + 1) * cs) + center;

    if (triIndex == 0) {
      return (p00, p01, p10);
    } else {
      return (p10, p01, p11);
    }
  }

  (Vec3, Vec3, Vec3) getCellTriangleWorld(int c, int r, int triIndex) {
    final (v0, v1, v2) = getCellTriangleLocal(c, r, triIndex);
    return (
      transform.transformPoint(v0),
      transform.transformPoint(v1),
      transform.transformPoint(v2),
    );
  }

  @override
  Aabb get worldBounds {
    final b = Aabb(_localBounds.min + center, _localBounds.max + center);
    if (!isAttached) return b;
    return b.transformed(transform.world.toMat4());
  }

  @override
  double? _raycast(Ray ray) {
    if (ray.intersectAabb(worldBounds) == null) return null;
    final localRay = _worldToLocalRay(ray, this);
    final localAabb = Aabb(
      _localBounds.min + center,
      _localBounds.max + center,
    );
    final tEnter = localRay.intersectAabb(localAabb);
    if (tEnter == null) return null;

    final cs = cellSize;
    final startPt = localRay.at(math.max(0.0, tEnter)) - center;
    final cStart = (startPt.x / cs).floor().clamp(0, columns - 2);
    final rStart = (startPt.z / cs).floor().clamp(0, rows - 2);

    final exitT = ray.intersectAabb(worldBounds);
    final endPt = localRay.at(exitT != null ? exitT + 10.0 : 100.0) - center;
    final cEnd = (endPt.x / cs).floor().clamp(0, columns - 2);
    final rEnd = (endPt.z / cs).floor().clamp(0, rows - 2);

    final dc = (cEnd - cStart).abs();
    final dr = (rEnd - rStart).abs();
    final sc = cStart < cEnd ? 1 : -1;
    final sr = rStart < rEnd ? 1 : -1;
    var err = dc - dr;
    var c = cStart;
    var r = rStart;

    double? closest;
    final maxSteps = dc + dr + 2;
    for (var step = 0; step < maxSteps; step++) {
      final (v00, v01, v10) = getCellTriangleLocal(c, r, 0);
      final t1 = localRay.intersectTriangle(v00, v01, v10);
      if (t1 != null && (closest == null || t1 < closest)) {
        closest = t1;
      }
      final (v10_2, v01_2, v11) = getCellTriangleLocal(c, r, 1);
      final t2 = localRay.intersectTriangle(v10_2, v01_2, v11);
      if (t2 != null && (closest == null || t2 < closest)) {
        closest = t2;
      }
      if (closest != null) break;
      if (c == cEnd && r == rEnd) break;
      final e2 = 2 * err;
      if (e2 > -dr) {
        err -= dr;
        c += sc;
      }
      if (e2 < dc) {
        err += dc;
        r += sr;
      }
      if (c < 0 || c >= columns - 1 || r < 0 || r >= rows - 1) break;
    }
    return closest;
  }

  @override
  bool intersectsAabb(Aabb bounds) {
    final localQuery = _transformAabbToLocal(bounds, this);
    final minX = localQuery.min.x - center.x;
    final maxX = localQuery.max.x - center.x;
    final minZ = localQuery.min.z - center.z;
    final maxZ = localQuery.max.z - center.z;

    final cMin = (minX / cellSize).floor().clamp(0, columns - 2);
    final cMax = (maxX / cellSize).ceil().clamp(0, columns - 2);
    final rMin = (minZ / cellSize).floor().clamp(0, rows - 2);
    final rMax = (maxZ / cellSize).ceil().clamp(0, rows - 2);

    final obb = _Obb.fromAabb(bounds);
    for (var r = rMin; r <= rMax; r++) {
      for (var c = cMin; c <= cMax; c++) {
        final (t1w0, t1w1, t1w2) = getCellTriangleWorld(c, r, 0);
        if (_triangleIntersectsObb(t1w0, t1w1, t1w2, obb)) return true;
        final (t2w0, t2w1, t2w2) = getCellTriangleWorld(c, r, 1);
        if (_triangleIntersectsObb(t2w0, t2w1, t2w2, obb)) return true;
      }
    }
    return false;
  }

  @override
  bool intersectsSphere(Vec3 center, double radius) {
    final queryWorld = Aabb(
      center - Vec3(radius, radius, radius),
      center + Vec3(radius, radius, radius),
    );
    final localQuery = _transformAabbToLocal(queryWorld, this);
    final minX = localQuery.min.x - this.center.x;
    final maxX = localQuery.max.x - this.center.x;
    final minZ = localQuery.min.z - this.center.z;
    final maxZ = localQuery.max.z - this.center.z;

    final cMin = (minX / cellSize).floor().clamp(0, columns - 2);
    final cMax = (maxX / cellSize).ceil().clamp(0, columns - 2);
    final rMin = (minZ / cellSize).floor().clamp(0, rows - 2);
    final rMax = (maxZ / cellSize).ceil().clamp(0, rows - 2);

    for (var r = rMin; r <= rMax; r++) {
      for (var c = cMin; c <= cMax; c++) {
        final (t1w0, t1w1, t1w2) = getCellTriangleWorld(c, r, 0);
        if (_triangleIntersectsSphere(t1w0, t1w1, t1w2, center, radius)) {
          return true;
        }
        final (t2w0, t2w1, t2w2) = getCellTriangleWorld(c, r, 1);
        if (_triangleIntersectsSphere(t2w0, t2w1, t2w2, center, radius)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  double? sweepSphere(Ray ray, double radius) {
    final pad = Vec3(radius, radius, radius);
    final b = worldBounds;
    return ray.intersectAabb(Aabb(b.min - pad, b.max + pad));
  }
}

/// Rich contact manifold data exposed for physics solver and inspection.
final class PhysicsContactManifold {
  /// Contact normal pointing from collider A toward collider B.
  final Vec3 normal;

  /// Penetration depth (> 0 when intersecting).
  final double depth;

  /// Contact points on the collision manifold in world space.
  final List<Vec3> contactPoints;

  const PhysicsContactManifold({
    required this.normal,
    required this.depth,
    this.contactPoints = const [],
  });

  Vec3? get contactPoint =>
      contactPoints.isNotEmpty ? contactPoints.first : null;
}

/// Narrowphase contact manifold and overlap tests shared by [PhysicsWorld]
/// and [PhysicsSolver].
abstract final class PhysicsNarrowphase {
  static bool intersects(Collider a, Collider b) => switch ((a, b)) {
    (SphereCollider s1, SphereCollider s2) => sphereIntersectsSphere(
      s1.worldCenter,
      s1.worldRadius,
      s2.worldCenter,
      s2.worldRadius,
    ),
    (SphereCollider s, BoxCollider box) => _Obb.obbIntersectsSphere(
      _Obb.fromBox(box),
      s.worldCenter,
      s.worldRadius,
    ),
    (BoxCollider box, SphereCollider s) => _Obb.obbIntersectsSphere(
      _Obb.fromBox(box),
      s.worldCenter,
      s.worldRadius,
    ),
    (BoxCollider b1, BoxCollider b2) =>
      _Obb.testObbObb(_Obb.fromBox(b1), _Obb.fromBox(b2)) != null,
    (CapsuleCollider cap, SphereCollider s) => sphereIntersectsSphere(
      cap.closestPointOnAxis(s.worldCenter),
      cap.worldRadius,
      s.worldCenter,
      s.worldRadius,
    ),
    (SphereCollider s, CapsuleCollider cap) => sphereIntersectsSphere(
      cap.closestPointOnAxis(s.worldCenter),
      cap.worldRadius,
      s.worldCenter,
      s.worldRadius,
    ),
    (CapsuleCollider cap, BoxCollider box) =>
      _Obb.testObbCapsule(_Obb.fromBox(box), cap) != null,
    (BoxCollider box, CapsuleCollider cap) =>
      _Obb.testObbCapsule(_Obb.fromBox(box), cap) != null,
    (CapsuleCollider c1, CapsuleCollider c2) => capsuleIntersectsCapsule(
      c1,
      c2,
    ),
    (MeshCollider m, SphereCollider s) => m.intersectsSphere(
      s.worldCenter,
      s.worldRadius,
    ),
    (SphereCollider s, MeshCollider m) => m.intersectsSphere(
      s.worldCenter,
      s.worldRadius,
    ),
    (MeshCollider m, BoxCollider b) => _meshBoxManifold(m, b) != null,
    (BoxCollider b, MeshCollider m) => _meshBoxManifold(m, b) != null,
    (MeshCollider m, CapsuleCollider cap) =>
      _meshCapsuleManifold(m, cap) != null,
    (CapsuleCollider cap, MeshCollider m) =>
      _meshCapsuleManifold(m, cap) != null,
    (MeshCollider m1, MeshCollider m2) => _meshMeshManifold(m1, m2) != null,
    (HeightfieldCollider h, SphereCollider s) => h.intersectsSphere(
      s.worldCenter,
      s.worldRadius,
    ),
    (SphereCollider s, HeightfieldCollider h) => h.intersectsSphere(
      s.worldCenter,
      s.worldRadius,
    ),
    (HeightfieldCollider h, BoxCollider b) =>
      _heightfieldBoxManifold(h, b) != null,
    (BoxCollider b, HeightfieldCollider h) =>
      _heightfieldBoxManifold(h, b) != null,
    (HeightfieldCollider h, CapsuleCollider cap) =>
      _heightfieldCapsuleManifold(h, cap) != null,
    (CapsuleCollider cap, HeightfieldCollider h) =>
      _heightfieldCapsuleManifold(h, cap) != null,
    (HeightfieldCollider h, MeshCollider m) =>
      _heightfieldMeshManifold(h, m) != null,
    (MeshCollider m, HeightfieldCollider h) =>
      _heightfieldMeshManifold(h, m) != null,
    (HeightfieldCollider h1, HeightfieldCollider h2) =>
      _heightfieldHeightfieldManifold(h1, h2) != null,
    _ => false,
  };

  /// Contact normal (pointing from [a] toward [b]) and penetration depth,
  /// or null when separated.
  static (Vec3 normal, double depth)? computeManifold(Collider a, Collider b) {
    final m = computeContactManifold(a, b);
    return m == null ? null : (m.normal, m.depth);
  }

  /// Contact manifold with normal, depth, and contact points, or null when separated.
  static PhysicsContactManifold? computeContactManifold(
    Collider a,
    Collider b,
  ) {
    if (a is SphereCollider && b is SphereCollider) {
      final delta = b.worldCenter - a.worldCenter;
      final dist = delta.length;
      final rSum = a.worldRadius + b.worldRadius;
      if (dist >= rSum) return null;
      final normal = dist > 1e-6 ? delta * (1.0 / dist) : Vec3.unitY;
      final depth = rSum - dist;
      final pt = a.worldCenter + normal * (a.worldRadius - depth * 0.5);
      return PhysicsContactManifold(
        normal: normal,
        depth: depth,
        contactPoints: [pt],
      );
    }

    if (a is SphereCollider && b is BoxCollider) {
      final m = _Obb.testObbSphere(
        _Obb.fromBox(b),
        a.worldCenter,
        a.worldRadius,
      );
      if (m == null) return null;
      // testObbSphere normal points from Box (b) to Sphere (a).
      // For (a, b) we want normal pointing from a toward b.
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }
    if (a is BoxCollider && b is SphereCollider) {
      return _Obb.testObbSphere(_Obb.fromBox(a), b.worldCenter, b.worldRadius);
    }

    if (a is BoxCollider && b is BoxCollider) {
      final res = _Obb.testObbObb(_Obb.fromBox(a), _Obb.fromBox(b));
      if (res == null) return null;
      final (norm, depth) = res;
      final pt =
          a.worldCenter + norm * (a.worldBounds.extent.length - depth * 0.5);
      return PhysicsContactManifold(
        normal: norm,
        depth: depth,
        contactPoints: [pt],
      );
    }

    if (a is CapsuleCollider && b is SphereCollider) {
      final axisPt = a.closestPointOnAxis(b.worldCenter);
      final delta = b.worldCenter - axisPt;
      final dist = delta.length;
      final rSum = a.worldRadius + b.worldRadius;
      if (dist >= rSum) return null;
      final normal = dist > 1e-6 ? delta * (1.0 / dist) : Vec3.unitY;
      final depth = rSum - dist;
      final pt = axisPt + normal * (a.worldRadius - depth * 0.5);
      return PhysicsContactManifold(
        normal: normal,
        depth: depth,
        contactPoints: [pt],
      );
    }
    if (a is SphereCollider && b is CapsuleCollider) {
      final m = computeContactManifold(b, a);
      if (m == null) return null;
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }

    if (a is CapsuleCollider && b is BoxCollider) {
      final m = _Obb.testObbCapsule(_Obb.fromBox(b), a);
      if (m == null) return null;
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }
    if (a is BoxCollider && b is CapsuleCollider) {
      return _Obb.testObbCapsule(_Obb.fromBox(a), b);
    }

    if (a is CapsuleCollider && b is CapsuleCollider) {
      final p2 = b.closestPointOnAxis(a.closestPointOnAxis(b.worldCenter));
      final p1 = a.closestPointOnAxis(p2);
      final delta = p2 - p1;
      final dist = delta.length;
      final rSum = a.worldRadius + b.worldRadius;
      if (dist >= rSum) return null;
      final normal = dist > 1e-6 ? delta * (1.0 / dist) : Vec3.unitY;
      final depth = rSum - dist;
      final pt = p1 + normal * (a.worldRadius - depth * 0.5);
      return PhysicsContactManifold(
        normal: normal,
        depth: depth,
        contactPoints: [pt],
      );
    }

    // Mesh combinations
    if (a is MeshCollider && b is SphereCollider) {
      return _meshSphereManifold(a, b);
    }
    if (a is SphereCollider && b is MeshCollider) {
      final m = _meshSphereManifold(b, a);
      if (m == null) return null;
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }

    if (a is MeshCollider && b is BoxCollider) {
      return _meshBoxManifold(a, b);
    }
    if (a is BoxCollider && b is MeshCollider) {
      final m = _meshBoxManifold(b, a);
      if (m == null) return null;
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }

    if (a is MeshCollider && b is CapsuleCollider) {
      return _meshCapsuleManifold(a, b);
    }
    if (a is CapsuleCollider && b is MeshCollider) {
      final m = _meshCapsuleManifold(b, a);
      if (m == null) return null;
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }

    if (a is MeshCollider && b is MeshCollider) {
      return _meshMeshManifold(a, b);
    }

    // Heightfield combinations
    if (a is HeightfieldCollider && b is SphereCollider) {
      return _heightfieldSphereManifold(a, b);
    }
    if (a is SphereCollider && b is HeightfieldCollider) {
      final m = _heightfieldSphereManifold(b, a);
      if (m == null) return null;
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }

    if (a is HeightfieldCollider && b is BoxCollider) {
      return _heightfieldBoxManifold(a, b);
    }
    if (a is BoxCollider && b is HeightfieldCollider) {
      final m = _heightfieldBoxManifold(b, a);
      if (m == null) return null;
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }

    if (a is HeightfieldCollider && b is CapsuleCollider) {
      return _heightfieldCapsuleManifold(a, b);
    }
    if (a is CapsuleCollider && b is HeightfieldCollider) {
      final m = _heightfieldCapsuleManifold(b, a);
      if (m == null) return null;
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }

    if (a is HeightfieldCollider && b is MeshCollider) {
      return _heightfieldMeshManifold(a, b);
    }
    if (a is MeshCollider && b is HeightfieldCollider) {
      final m = _heightfieldMeshManifold(b, a);
      if (m == null) return null;
      return PhysicsContactManifold(
        normal: -m.normal,
        depth: m.depth,
        contactPoints: m.contactPoints,
      );
    }

    if (a is HeightfieldCollider && b is HeightfieldCollider) {
      return _heightfieldHeightfieldManifold(a, b);
    }

    return null;
  }

  static bool aabbIntersects(Aabb a, Aabb b) =>
      a.min.x <= b.max.x &&
      a.max.x >= b.min.x &&
      a.min.y <= b.max.y &&
      a.max.y >= b.min.y &&
      a.min.z <= b.max.z &&
      a.max.z >= b.min.z;

  static bool capsuleIntersectsAabb(CapsuleCollider cap, Aabb box) {
    final clampedBoxCenter = cap.closestPointOnAxis(box.center);
    return sphereIntersectsAabb(clampedBoxCenter, cap.worldRadius, box) ||
        sphereIntersectsAabb(cap.segmentStart, cap.worldRadius, box) ||
        sphereIntersectsAabb(cap.segmentEnd, cap.worldRadius, box);
  }

  static bool capsuleIntersectsCapsule(CapsuleCollider c1, CapsuleCollider c2) {
    final p1 = c1.closestPointOnAxis(c2.worldCenter);
    final p2 = c2.closestPointOnAxis(p1);
    final p1Refined = c1.closestPointOnAxis(p2);
    return sphereIntersectsSphere(
      p1Refined,
      c1.worldRadius,
      p2,
      c2.worldRadius,
    );
  }

  static bool sphereIntersectsSphere(Vec3 c1, double r1, Vec3 c2, double r2) {
    final r = r1 + r2;
    return (c1 - c2).lengthSquared <= r * r;
  }

  static bool sphereIntersectsAabb(Vec3 center, double radius, Aabb box) {
    final closest = Vec3(
      center.x.clamp(box.min.x, box.max.x),
      center.y.clamp(box.min.y, box.max.y),
      center.z.clamp(box.min.z, box.max.z),
    );
    return (center - closest).lengthSquared <= radius * radius;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal math & narrowphase collaborators
// ─────────────────────────────────────────────────────────────────────────────

/// Internal Oriented Bounding Box (OBB) representation used for 15-axis SAT.
final class _Obb {
  final Vec3 center;
  final Vec3 u0, u1, u2;
  final double e0, e1, e2;

  const _Obb({
    required this.center,
    required this.u0,
    required this.u1,
    required this.u2,
    required this.e0,
    required this.e1,
    required this.e2,
  });

  factory _Obb.fromBox(BoxCollider box) {
    final t = box.transform;
    final w = t.world;
    final center = t.transformPoint(box.center);
    final rot = w.rotation;
    final u0 = rot.rotate(const Vec3(1, 0, 0));
    final u1 = rot.rotate(const Vec3(0, 1, 0));
    final u2 = rot.rotate(const Vec3(0, 0, 1));
    final sx = (w.scale * w.stretch.x).abs();
    final sy = (w.scale * w.stretch.y).abs();
    final sz = (w.scale * w.stretch.z).abs();
    final e0 = math.max(1e-6, (box.size.x * 0.5 * sx).abs());
    final e1 = math.max(1e-6, (box.size.y * 0.5 * sy).abs());
    final e2 = math.max(1e-6, (box.size.z * 0.5 * sz).abs());
    return _Obb(center: center, u0: u0, u1: u1, u2: u2, e0: e0, e1: e1, e2: e2);
  }

  factory _Obb.fromAabb(Aabb aabb) {
    return _Obb(
      center: aabb.center,
      u0: const Vec3(1, 0, 0),
      u1: const Vec3(0, 1, 0),
      u2: const Vec3(0, 0, 1),
      e0: math.max(1e-6, aabb.extent.x.abs()),
      e1: math.max(1e-6, aabb.extent.y.abs()),
      e2: math.max(1e-6, aabb.extent.z.abs()),
    );
  }

  Vec3 closestPoint(Vec3 point) {
    final d = point - center;
    final x = d.dot(u0).clamp(-e0, e0);
    final y = d.dot(u1).clamp(-e1, e1);
    final z = d.dot(u2).clamp(-e2, e2);
    return center + u0 * x + u1 * y + u2 * z;
  }

  double? raycast(Ray ray) {
    final diff = ray.origin - center;
    final ro = Vec3(diff.dot(u0), diff.dot(u1), diff.dot(u2));
    final rd = Vec3(
      ray.direction.dot(u0),
      ray.direction.dot(u1),
      ray.direction.dot(u2),
    );
    final localRay = Ray(origin: ro, direction: rd);
    final localAabb = Aabb(Vec3(-e0, -e1, -e2), Vec3(e0, e1, e2));
    return localRay.intersectAabb(localAabb);
  }

  static bool obbIntersectsSphere(_Obb obb, Vec3 center, double radius) {
    final d = center - obb.center;
    final lx = d.dot(obb.u0).clamp(-obb.e0, obb.e0);
    final ly = d.dot(obb.u1).clamp(-obb.e1, obb.e1);
    final lz = d.dot(obb.u2).clamp(-obb.e2, obb.e2);
    final closest = obb.center + obb.u0 * lx + obb.u1 * ly + obb.u2 * lz;
    return (center - closest).lengthSquared <= radius * radius;
  }

  static (Vec3 normal, double depth)? testObbObb(_Obb a, _Obb b) {
    final delta = b.center - a.center;

    final aAxes = [a.u0, a.u1, a.u2];
    final bAxes = [b.u0, b.u1, b.u2];

    var minOverlap = double.infinity;
    var bestNormal = Vec3.unitY;

    bool testAxis(Vec3 axis) {
      final lenSq = axis.lengthSquared;
      if (lenSq < 1e-6) return true;
      final L = axis * (1.0 / math.sqrt(lenSq));

      final rA =
          a.e0 * (a.u0.dot(L)).abs() +
          a.e1 * (a.u1.dot(L)).abs() +
          a.e2 * (a.u2.dot(L)).abs();
      final rB =
          b.e0 * (b.u0.dot(L)).abs() +
          b.e1 * (b.u1.dot(L)).abs() +
          b.e2 * (b.u2.dot(L)).abs();

      final dist = delta.dot(L);
      final overlap = (rA + rB) - dist.abs();
      if (overlap <= 0.0) return false;

      if (overlap < minOverlap) {
        minOverlap = overlap;
        bestNormal = dist >= 0 ? L : -L;
      }
      return true;
    }

    for (final axis in aAxes) {
      if (!testAxis(axis)) return null;
    }
    for (final axis in bAxes) {
      if (!testAxis(axis)) return null;
    }
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        final cross = aAxes[i].cross(bAxes[j]);
        if (!testAxis(cross)) return null;
      }
    }

    return (bestNormal, minOverlap);
  }

  static PhysicsContactManifold? testObbSphere(
    _Obb obb,
    Vec3 sphereCenter,
    double radius,
  ) {
    final d = sphereCenter - obb.center;
    final lx = d.dot(obb.u0);
    final ly = d.dot(obb.u1);
    final lz = d.dot(obb.u2);

    final cx = lx.clamp(-obb.e0, obb.e0);
    final cy = ly.clamp(-obb.e1, obb.e1);
    final cz = lz.clamp(-obb.e2, obb.e2);

    final closest = obb.center + obb.u0 * cx + obb.u1 * cy + obb.u2 * cz;
    final delta = sphereCenter - closest;
    final distSq = delta.lengthSquared;

    if (distSq > 1e-12) {
      final dist = math.sqrt(distSq);
      if (dist >= radius) return null;
      final normal = delta * (1.0 / dist);
      final depth = radius - dist;
      return PhysicsContactManifold(
        normal: normal,
        depth: depth,
        contactPoints: [closest],
      );
    } else {
      final d0p = obb.e0 - lx;
      final d0m = obb.e0 + lx;
      final d1p = obb.e1 - ly;
      final d1m = obb.e1 + ly;
      final d2p = obb.e2 - lz;
      final d2m = obb.e2 + lz;

      var minDist = d0p;
      var normal = obb.u0;

      if (d0m < minDist) {
        minDist = d0m;
        normal = -obb.u0;
      }
      if (d1p < minDist) {
        minDist = d1p;
        normal = obb.u1;
      }
      if (d1m < minDist) {
        minDist = d1m;
        normal = -obb.u1;
      }
      if (d2p < minDist) {
        minDist = d2p;
        normal = obb.u2;
      }
      if (d2m < minDist) {
        minDist = d2m;
        normal = -obb.u2;
      }

      final depth = minDist + radius;
      final cp = closest - normal * minDist;
      return PhysicsContactManifold(
        normal: normal,
        depth: depth,
        contactPoints: [cp],
      );
    }
  }

  static PhysicsContactManifold? testObbCapsule(_Obb obb, CapsuleCollider cap) {
    final p0 = cap.closestPointOnAxis(obb.center);
    final b0 = obb.closestPoint(p0);
    final p1 = cap.closestPointOnAxis(b0);
    final b1 = obb.closestPoint(p1);

    final bStart = obb.closestPoint(cap.segmentStart);
    final bEnd = obb.closestPoint(cap.segmentEnd);

    var bestSegPt = p1;
    var bestDistSq = (p1 - b1).lengthSquared;

    final distStart = (cap.segmentStart - bStart).lengthSquared;
    if (distStart < bestDistSq) {
      bestDistSq = distStart;
      bestSegPt = cap.segmentStart;
    }

    final distEnd = (cap.segmentEnd - bEnd).lengthSquared;
    if (distEnd < bestDistSq) {
      bestDistSq = distEnd;
      bestSegPt = cap.segmentEnd;
    }

    return testObbSphere(obb, bestSegPt, cap.worldRadius);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Triangle collision mathematics
// ─────────────────────────────────────────────────────────────────────────────

Vec3 _closestPointOnTriangle(Vec3 p, Vec3 a, Vec3 b, Vec3 c) {
  final ab = b - a;
  final ac = c - a;
  final ap = p - a;
  final d1 = ab.dot(ap);
  final d2 = ac.dot(ap);
  if (d1 <= 0.0 && d2 <= 0.0) return a;

  final bp = p - b;
  final d3 = ab.dot(bp);
  final d4 = ac.dot(bp);
  if (d3 >= 0.0 && d4 <= d3) return b;

  final vc = d1 * d4 - d3 * d2;
  if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0) {
    final v = d1 / (d1 - d3);
    return a + ab * v;
  }

  final cp = p - c;
  final d5 = ab.dot(cp);
  final d6 = ac.dot(cp);
  if (d6 >= 0.0 && d5 <= d6) return c;

  final vb = d5 * d2 - d1 * d6;
  if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0) {
    final w = d2 / (d2 - d6);
    return a + ac * w;
  }

  final va = d3 * d6 - d5 * d4;
  if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0) {
    final w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
    return b + (c - b) * w;
  }

  final denom = 1.0 / (va + vb + vc);
  final v = vb * denom;
  final w = vc * denom;
  return a + ab * v + ac * w;
}

(Vec3, Vec3) _closestPointsSegmentSegment(Vec3 p1, Vec3 q1, Vec3 p2, Vec3 q2) {
  final d1 = q1 - p1;
  final d2 = q2 - p2;
  final r = p1 - p2;
  final a = d1.dot(d1);
  final e = d2.dot(d2);
  final f = d2.dot(r);

  var s = 0.0;
  var t = 0.0;

  if (a <= 1e-12 && e <= 1e-12) {
    return (p1, p2);
  }
  if (a <= 1e-12) {
    s = 0.0;
    t = (f / e).clamp(0.0, 1.0);
  } else {
    final c = d1.dot(r);
    if (e <= 1e-12) {
      t = 0.0;
      s = (-c / a).clamp(0.0, 1.0);
    } else {
      final b = d1.dot(d2);
      final denom = a * e - b * b;
      if (denom.abs() > 1e-12) {
        s = ((b * f - c * e) / denom).clamp(0.0, 1.0);
      } else {
        s = 0.0;
      }
      t = (b * s + f) / e;
      if (t < 0.0) {
        t = 0.0;
        s = (-c / a).clamp(0.0, 1.0);
      } else if (t > 1.0) {
        t = 1.0;
        s = ((b - c) / a).clamp(0.0, 1.0);
      }
    }
  }
  return (p1 + d1 * s, p2 + d2 * t);
}

(Vec3, Vec3) _closestPointsSegmentTriangle(
  Vec3 s0,
  Vec3 s1,
  Vec3 w0,
  Vec3 w1,
  Vec3 w2,
) {
  final cp0 = _closestPointOnTriangle(s0, w0, w1, w2);
  var bestSegPt = s0;
  var bestTriPt = cp0;
  var bestDistSq = (s0 - cp0).lengthSquared;

  final cp1 = _closestPointOnTriangle(s1, w0, w1, w2);
  final d1 = (s1 - cp1).lengthSquared;
  if (d1 < bestDistSq) {
    bestDistSq = d1;
    bestSegPt = s1;
    bestTriPt = cp1;
  }

  final edges = [(w0, w1), (w1, w2), (w2, w0)];
  for (final (e0, e1) in edges) {
    final (ptSeg, ptEdge) = _closestPointsSegmentSegment(s0, s1, e0, e1);
    final distSq = (ptSeg - ptEdge).lengthSquared;
    if (distSq < bestDistSq) {
      bestDistSq = distSq;
      bestSegPt = ptSeg;
      bestTriPt = ptEdge;
    }
  }

  return (bestSegPt, bestTriPt);
}

bool _triangleIntersectsSphere(
  Vec3 w0,
  Vec3 w1,
  Vec3 w2,
  Vec3 sphereCenter,
  double radius,
) {
  final p = _closestPointOnTriangle(sphereCenter, w0, w1, w2);
  return (sphereCenter - p).lengthSquared <= radius * radius;
}

PhysicsContactManifold? _triangleSphereManifold(
  Vec3 w0,
  Vec3 w1,
  Vec3 w2,
  Vec3 sc,
  double sr,
) {
  final p = _closestPointOnTriangle(sc, w0, w1, w2);
  final delta = sc - p;
  final distSq = delta.lengthSquared;
  if (distSq > sr * sr) return null;
  final dist = math.sqrt(distSq);
  final Vec3 normal;
  if (dist > 1e-6) {
    normal = delta * (1.0 / dist);
  } else {
    final fn = (w1 - w0).cross(w2 - w0);
    final fnLen = fn.length;
    normal = fnLen > 1e-6 ? fn * (1.0 / fnLen) : Vec3.unitY;
  }
  final depth = sr - dist;
  return PhysicsContactManifold(
    normal: normal,
    depth: depth,
    contactPoints: [p],
  );
}

bool _triangleIntersectsObb(Vec3 w0, Vec3 w1, Vec3 w2, _Obb obb) =>
    _triangleObbManifold(w0, w1, w2, obb) != null;

PhysicsContactManifold? _triangleObbManifold(
  Vec3 w0,
  Vec3 w1,
  Vec3 w2,
  _Obb obb,
) {
  final triCenter = (w0 + w1 + w2) * (1.0 / 3.0);
  final e0 = w1 - w0;
  final e1 = w2 - w1;
  final e2 = w0 - w2;

  final triNorm = e0.cross(w2 - w0);
  final obbAxes = [obb.u0, obb.u1, obb.u2];
  final triEdges = [e0, e1, e2];

  var minOverlap = double.infinity;
  var bestNormal = Vec3.unitY;

  bool testAxis(Vec3 axis) {
    final lenSq = axis.lengthSquared;
    if (lenSq < 1e-6) return true;
    final L = axis * (1.0 / math.sqrt(lenSq));

    final rObb =
        obb.e0 * (obb.u0.dot(L)).abs() +
        obb.e1 * (obb.u1.dot(L)).abs() +
        obb.e2 * (obb.u2.dot(L)).abs();
    final cObb = obb.center.dot(L);

    final p0 = w0.dot(L);
    final p1 = w1.dot(L);
    final p2 = w2.dot(L);

    final minTri = math.min(p0, math.min(p1, p2));
    final maxTri = math.max(p0, math.max(p1, p2));

    final minObb = cObb - rObb;
    final maxObb = cObb + rObb;

    if (maxObb < minTri || maxTri < minObb) return false;

    final overlap = math.min(maxObb, maxTri) - math.max(minObb, minTri);
    if (overlap <= 0.0) return false;

    if (overlap < minOverlap) {
      minOverlap = overlap;
      final dir = (obb.center - triCenter).dot(L);
      bestNormal = dir >= 0 ? L : -L;
    }
    return true;
  }

  for (final axis in obbAxes) {
    if (!testAxis(axis)) return null;
  }
  if (!testAxis(triNorm)) return null;
  for (final a in obbAxes) {
    for (final e in triEdges) {
      if (!testAxis(a.cross(e))) return null;
    }
  }

  final cp = _closestPointOnTriangle(obb.center, w0, w1, w2);
  return PhysicsContactManifold(
    normal: bestNormal,
    depth: minOverlap,
    contactPoints: [cp],
  );
}

PhysicsContactManifold? _triangleCapsuleManifold(
  Vec3 w0,
  Vec3 w1,
  Vec3 w2,
  CapsuleCollider cap,
) {
  final (pSeg, pTri) = _closestPointsSegmentTriangle(
    cap.segmentStart,
    cap.segmentEnd,
    w0,
    w1,
    w2,
  );
  final delta = pSeg - pTri;
  final distSq = delta.lengthSquared;
  final r = cap.worldRadius;
  if (distSq > r * r) return null;

  final dist = math.sqrt(distSq);
  final Vec3 normal;
  if (dist > 1e-6) {
    normal = delta * (1.0 / dist);
  } else {
    final fn = (w1 - w0).cross(w2 - w0);
    final fnLen = fn.length;
    normal = fnLen > 1e-6 ? fn * (1.0 / fnLen) : Vec3.unitY;
  }
  final depth = r - dist;
  return PhysicsContactManifold(
    normal: normal,
    depth: depth,
    contactPoints: [pTri],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BVH implementation
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _BvhNode {
  Aabb get bounds;
}

final class _BvhLeaf extends _BvhNode {
  @override
  final Aabb bounds;
  final List<int> triangleIndices;
  _BvhLeaf(this.bounds, this.triangleIndices);
}

final class _BvhInternal extends _BvhNode {
  @override
  final Aabb bounds;
  final _BvhNode left;
  final _BvhNode right;
  _BvhInternal(this.bounds, this.left, this.right);
}

final class _MeshBvh {
  final _BvhNode root;

  _MeshBvh(this.root);

  factory _MeshBvh.empty() =>
      _MeshBvh(_BvhLeaf(const Aabb(Vec3.zero, Vec3.zero), const []));

  factory _MeshBvh.build(MeshCollider mesh) {
    final count = mesh.triangleCount;
    if (count == 0) return _MeshBvh.empty();

    final allIndices = List<int>.generate(count, (i) => i);
    final centroids = List<Vec3>.filled(count, Vec3.zero);
    for (var i = 0; i < count; i++) {
      final (v0, v1, v2) = mesh.getTriangleLocal(i);
      centroids[i] = (v0 + v1 + v2) * (1.0 / 3.0);
    }

    _BvhNode buildNode(List<int> tris) {
      var (v0, v1, v2) = mesh.getTriangleLocal(tris[0]);
      var minPt = Vec3.min(v0, Vec3.min(v1, v2));
      var maxPt = Vec3.max(v0, Vec3.max(v1, v2));
      for (var i = 1; i < tris.length; i++) {
        final (t0, t1, t2) = mesh.getTriangleLocal(tris[i]);
        minPt = Vec3.min(minPt, Vec3.min(t0, Vec3.min(t1, t2)));
        maxPt = Vec3.max(maxPt, Vec3.max(t0, Vec3.max(t1, t2)));
      }
      final nodeBounds = Aabb(minPt, maxPt);

      if (tris.length <= 4) {
        return _BvhLeaf(nodeBounds, tris);
      }

      final ext = nodeBounds.max - nodeBounds.min;
      var axis = 0;
      if (ext.y >= ext.x && ext.y >= ext.z) {
        axis = 1;
      } else if (ext.z >= ext.x && ext.z >= ext.y) {
        axis = 2;
      }

      tris.sort((a, b) {
        final ca = axis == 0
            ? centroids[a].x
            : (axis == 1 ? centroids[a].y : centroids[a].z);
        final cb = axis == 0
            ? centroids[b].x
            : (axis == 1 ? centroids[b].y : centroids[b].z);
        return ca.compareTo(cb);
      });

      final mid = tris.length ~/ 2;
      if (mid == 0 || mid == tris.length) {
        return _BvhLeaf(nodeBounds, tris);
      }

      final leftNode = buildNode(tris.sublist(0, mid));
      final rightNode = buildNode(tris.sublist(mid));
      return _BvhInternal(nodeBounds, leftNode, rightNode);
    }

    return _MeshBvh(buildNode(allIndices));
  }

  void queryAabb(_BvhNode node, Aabb queryBounds, List<int> results) {
    if (!PhysicsNarrowphase.aabbIntersects(node.bounds, queryBounds)) return;
    if (node is _BvhLeaf) {
      results.addAll(node.triangleIndices);
    } else if (node is _BvhInternal) {
      queryAabb(node.left, queryBounds, results);
      queryAabb(node.right, queryBounds, results);
    }
  }

  double? raycast(MeshCollider mesh, Ray ray, double maxDistance) =>
      _raycastNode(root, mesh, ray, maxDistance);

  double? _raycastNode(
    _BvhNode node,
    MeshCollider mesh,
    Ray ray,
    double maxDistance,
  ) {
    final tBox = ray.intersectAabb(node.bounds);
    if (tBox == null || tBox > maxDistance) return null;
    if (node is _BvhLeaf) {
      double? closest;
      for (final tri in node.triangleIndices) {
        final (v0, v1, v2) = mesh.getTriangleLocal(tri);
        final t = ray.intersectTriangle(v0, v1, v2);
        if (t != null && t < maxDistance && (closest == null || t < closest)) {
          closest = t;
        }
      }
      return closest;
    } else if (node is _BvhInternal) {
      final dLeft = (node.left.bounds.center - ray.origin).lengthSquared;
      final dRight = (node.right.bounds.center - ray.origin).lengthSquared;
      final first = dLeft <= dRight ? node.left : node.right;
      final second = dLeft <= dRight ? node.right : node.left;
      final t1 = _raycastNode(first, mesh, ray, maxDistance);
      final limit = (t1 != null && t1 < maxDistance) ? t1 : maxDistance;
      final t2 = _raycastNode(second, mesh, ray, limit);
      if (t2 != null && (t1 == null || t2 < t1)) return t2;
      return t1;
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coordinate transforms & complex collider narrowphase dispatch
// ─────────────────────────────────────────────────────────────────────────────

Ray _worldToLocalRay(Ray ray, Collider collider) {
  final w = collider.transform.world;
  final invR = w.rotation.inverse;
  final s = w.scale;
  final sx = s * w.stretch.x;
  final sy = s * w.stretch.y;
  final sz = s * w.stretch.z;
  final invSx = sx.abs() > 1e-9 ? 1.0 / sx : 1.0;
  final invSy = sy.abs() > 1e-9 ? 1.0 / sy : 1.0;
  final invSz = sz.abs() > 1e-9 ? 1.0 / sz : 1.0;

  final unPos = invR.rotate(ray.origin - w.translation);
  final localOrigin =
      Vec3(unPos.x * invSx, unPos.y * invSy, unPos.z * invSz) - collider.center;

  final unDir = invR.rotate(ray.direction);
  final localDir = Vec3(unDir.x * invSx, unDir.y * invSy, unDir.z * invSz);

  return Ray(origin: localOrigin, direction: localDir);
}

Aabb _transformAabbToLocal(Aabb queryWorld, Collider collider) {
  final w = collider.transform.world;
  final invR = w.rotation.inverse;
  final s = w.scale;
  final sx = s * w.stretch.x;
  final sy = s * w.stretch.y;
  final sz = s * w.stretch.z;
  final invSx = sx.abs() > 1e-9 ? 1.0 / sx : 1.0;
  final invSy = sy.abs() > 1e-9 ? 1.0 / sy : 1.0;
  final invSz = sz.abs() > 1e-9 ? 1.0 / sz : 1.0;

  final corners = queryWorld.corners;
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;

  for (final c in corners) {
    final un = invR.rotate(c - w.translation);
    final lx = un.x * invSx - collider.center.x;
    final ly = un.y * invSy - collider.center.y;
    final lz = un.z * invSz - collider.center.z;
    if (lx < minX) minX = lx;
    if (lx > maxX) maxX = lx;
    if (ly < minY) minY = ly;
    if (ly > maxY) maxY = ly;
    if (lz < minZ) minZ = lz;
    if (lz > maxZ) maxZ = lz;
  }
  return Aabb(Vec3(minX, minY, minZ), Vec3(maxX, maxY, maxZ));
}

PhysicsContactManifold? _meshSphereManifold(
  MeshCollider mesh,
  SphereCollider sphere,
) {
  final sc = sphere.worldCenter;
  final sr = sphere.worldRadius;
  final queryWorld = Aabb(sc - Vec3(sr, sr, sr), sc + Vec3(sr, sr, sr));
  final localQuery = _transformAabbToLocal(queryWorld, mesh);
  final candidateIndices = <int>[];
  mesh._bvh.queryAabb(mesh._bvh.root, localQuery, candidateIndices);

  PhysicsContactManifold? best;
  for (final tri in candidateIndices) {
    final (w0, w1, w2) = mesh.getTriangleWorld(tri);
    final m = _triangleSphereManifold(w0, w1, w2, sc, sr);
    if (m != null && (best == null || m.depth > best.depth)) {
      best = m;
    }
  }
  return best;
}

PhysicsContactManifold? _meshBoxManifold(MeshCollider mesh, BoxCollider box) {
  final obb = _Obb.fromBox(box);
  final localQuery = _transformAabbToLocal(box.worldBounds, mesh);
  final candidateIndices = <int>[];
  mesh._bvh.queryAabb(mesh._bvh.root, localQuery, candidateIndices);

  PhysicsContactManifold? best;
  for (final tri in candidateIndices) {
    final (w0, w1, w2) = mesh.getTriangleWorld(tri);
    final m = _triangleObbManifold(w0, w1, w2, obb);
    if (m != null && (best == null || m.depth > best.depth)) {
      best = m;
    }
  }
  return best;
}

PhysicsContactManifold? _meshCapsuleManifold(
  MeshCollider mesh,
  CapsuleCollider cap,
) {
  final localQuery = _transformAabbToLocal(cap.worldBounds, mesh);
  final candidateIndices = <int>[];
  mesh._bvh.queryAabb(mesh._bvh.root, localQuery, candidateIndices);

  PhysicsContactManifold? best;
  for (final tri in candidateIndices) {
    final (w0, w1, w2) = mesh.getTriangleWorld(tri);
    final m = _triangleCapsuleManifold(w0, w1, w2, cap);
    if (m != null && (best == null || m.depth > best.depth)) {
      best = m;
    }
  }
  return best;
}

PhysicsContactManifold? _meshMeshManifold(MeshCollider m1, MeshCollider m2) {
  if (!PhysicsNarrowphase.aabbIntersects(m1.worldBounds, m2.worldBounds)) {
    return null;
  }
  final localQuery1 = _transformAabbToLocal(m2.worldBounds, m1);
  final c1 = <int>[];
  m1._bvh.queryAabb(m1._bvh.root, localQuery1, c1);
  if (c1.isEmpty) return null;

  final localQuery2 = _transformAabbToLocal(m1.worldBounds, m2);
  final c2 = <int>[];
  m2._bvh.queryAabb(m2._bvh.root, localQuery2, c2);
  if (c2.isEmpty) return null;

  PhysicsContactManifold? best;
  for (final t1 in c1) {
    final (w0, w1, w2) = m1.getTriangleWorld(t1);
    for (final t2 in c2) {
      final (u0, u1, u2) = m2.getTriangleWorld(t2);
      final p = _closestPointOnTriangle(
        (u0 + u1 + u2) * (1.0 / 3.0),
        w0,
        w1,
        w2,
      );
      final delta = ((u0 + u1 + u2) * (1.0 / 3.0)) - p;
      final dist = delta.length;
      if (dist < 0.2) {
        final depth = 0.2 - dist;
        final norm = dist > 1e-6 ? delta * (1.0 / dist) : Vec3.unitY;
        if (best == null || depth > best.depth) {
          best = PhysicsContactManifold(
            normal: norm,
            depth: depth,
            contactPoints: [p],
          );
        }
      }
    }
  }
  return best;
}

PhysicsContactManifold? _heightfieldSphereManifold(
  HeightfieldCollider hf,
  SphereCollider sphere,
) {
  final sc = sphere.worldCenter;
  final sr = sphere.worldRadius;
  final queryWorld = Aabb(sc - Vec3(sr, sr, sr), sc + Vec3(sr, sr, sr));
  final localQuery = _transformAabbToLocal(queryWorld, hf);

  final minX = localQuery.min.x - hf.center.x;
  final maxX = localQuery.max.x - hf.center.x;
  final minZ = localQuery.min.z - hf.center.z;
  final maxZ = localQuery.max.z - hf.center.z;

  final cMin = (minX / hf.cellSize).floor().clamp(0, hf.columns - 2);
  final cMax = (maxX / hf.cellSize).ceil().clamp(0, hf.columns - 2);
  final rMin = (minZ / hf.cellSize).floor().clamp(0, hf.rows - 2);
  final rMax = (maxZ / hf.cellSize).ceil().clamp(0, hf.rows - 2);

  PhysicsContactManifold? best;
  for (var r = rMin; r <= rMax; r++) {
    for (var c = cMin; c <= cMax; c++) {
      final (t1w0, t1w1, t1w2) = hf.getCellTriangleWorld(c, r, 0);
      final m1 = _triangleSphereManifold(t1w0, t1w1, t1w2, sc, sr);
      if (m1 != null && (best == null || m1.depth > best.depth)) {
        best = m1;
      }
      final (t2w0, t2w1, t2w2) = hf.getCellTriangleWorld(c, r, 1);
      final m2 = _triangleSphereManifold(t2w0, t2w1, t2w2, sc, sr);
      if (m2 != null && (best == null || m2.depth > best.depth)) {
        best = m2;
      }
    }
  }
  return best;
}

PhysicsContactManifold? _heightfieldBoxManifold(
  HeightfieldCollider hf,
  BoxCollider box,
) {
  final obb = _Obb.fromBox(box);
  final localQuery = _transformAabbToLocal(box.worldBounds, hf);

  final minX = localQuery.min.x - hf.center.x;
  final maxX = localQuery.max.x - hf.center.x;
  final minZ = localQuery.min.z - hf.center.z;
  final maxZ = localQuery.max.z - hf.center.z;

  final cMin = (minX / hf.cellSize).floor().clamp(0, hf.columns - 2);
  final cMax = (maxX / hf.cellSize).ceil().clamp(0, hf.columns - 2);
  final rMin = (minZ / hf.cellSize).floor().clamp(0, hf.rows - 2);
  final rMax = (maxZ / hf.cellSize).ceil().clamp(0, hf.rows - 2);

  PhysicsContactManifold? best;
  for (var r = rMin; r <= rMax; r++) {
    for (var c = cMin; c <= cMax; c++) {
      final (t1w0, t1w1, t1w2) = hf.getCellTriangleWorld(c, r, 0);
      final m1 = _triangleObbManifold(t1w0, t1w1, t1w2, obb);
      if (m1 != null && (best == null || m1.depth > best.depth)) {
        best = m1;
      }
      final (t2w0, t2w1, t2w2) = hf.getCellTriangleWorld(c, r, 1);
      final m2 = _triangleObbManifold(t2w0, t2w1, t2w2, obb);
      if (m2 != null && (best == null || m2.depth > best.depth)) {
        best = m2;
      }
    }
  }
  return best;
}

PhysicsContactManifold? _heightfieldCapsuleManifold(
  HeightfieldCollider hf,
  CapsuleCollider cap,
) {
  final localQuery = _transformAabbToLocal(cap.worldBounds, hf);

  final minX = localQuery.min.x - hf.center.x;
  final maxX = localQuery.max.x - hf.center.x;
  final minZ = localQuery.min.z - hf.center.z;
  final maxZ = localQuery.max.z - hf.center.z;

  final cMin = (minX / hf.cellSize).floor().clamp(0, hf.columns - 2);
  final cMax = (maxX / hf.cellSize).ceil().clamp(0, hf.columns - 2);
  final rMin = (minZ / hf.cellSize).floor().clamp(0, hf.rows - 2);
  final rMax = (maxZ / hf.cellSize).ceil().clamp(0, hf.rows - 2);

  PhysicsContactManifold? best;
  for (var r = rMin; r <= rMax; r++) {
    for (var c = cMin; c <= cMax; c++) {
      final (t1w0, t1w1, t1w2) = hf.getCellTriangleWorld(c, r, 0);
      final m1 = _triangleCapsuleManifold(t1w0, t1w1, t1w2, cap);
      if (m1 != null && (best == null || m1.depth > best.depth)) {
        best = m1;
      }
      final (t2w0, t2w1, t2w2) = hf.getCellTriangleWorld(c, r, 1);
      final m2 = _triangleCapsuleManifold(t2w0, t2w1, t2w2, cap);
      if (m2 != null && (best == null || m2.depth > best.depth)) {
        best = m2;
      }
    }
  }
  return best;
}

PhysicsContactManifold? _heightfieldMeshManifold(
  HeightfieldCollider hf,
  MeshCollider m,
) {
  if (!PhysicsNarrowphase.aabbIntersects(hf.worldBounds, m.worldBounds)) {
    return null;
  }
  final localQuery = _transformAabbToLocal(m.worldBounds, hf);
  final minX = localQuery.min.x - hf.center.x;
  final maxX = localQuery.max.x - hf.center.x;
  final minZ = localQuery.min.z - hf.center.z;
  final maxZ = localQuery.max.z - hf.center.z;

  final cMin = (minX / hf.cellSize).floor().clamp(0, hf.columns - 2);
  final cMax = (maxX / hf.cellSize).ceil().clamp(0, hf.columns - 2);
  final rMin = (minZ / hf.cellSize).floor().clamp(0, hf.rows - 2);
  final rMax = (maxZ / hf.cellSize).ceil().clamp(0, hf.rows - 2);

  PhysicsContactManifold? best;
  for (var r = rMin; r <= rMax; r++) {
    for (var c = cMin; c <= cMax; c++) {
      final (t1w0, t1w1, t1w2) = hf.getCellTriangleWorld(c, r, 0);
      final (t2w0, t2w1, t2w2) = hf.getCellTriangleWorld(c, r, 1);
      final cellTris = [(t1w0, t1w1, t1w2), (t2w0, t2w1, t2w2)];

      for (final (w0, w1, w2) in cellTris) {
        final triCenter = (w0 + w1 + w2) * (1.0 / 3.0);
        final triAabb = Aabb(
          Vec3.min(w0, Vec3.min(w1, w2)),
          Vec3.max(w0, Vec3.max(w1, w2)),
        );
        final meshLocalQuery = _transformAabbToLocal(triAabb, m);
        final candidates = <int>[];
        m._bvh.queryAabb(m._bvh.root, meshLocalQuery, candidates);
        for (final tri in candidates) {
          final (u0, u1, u2) = m.getTriangleWorld(tri);
          final p = _closestPointOnTriangle(triCenter, u0, u1, u2);
          final delta = triCenter - p;
          final dist = delta.length;
          if (dist < 0.2) {
            final depth = 0.2 - dist;
            final norm = dist > 1e-6 ? delta * (1.0 / dist) : Vec3.unitY;
            if (best == null || depth > best.depth) {
              best = PhysicsContactManifold(
                normal: norm,
                depth: depth,
                contactPoints: [p],
              );
            }
          }
        }
      }
    }
  }
  return best;
}

PhysicsContactManifold? _heightfieldHeightfieldManifold(
  HeightfieldCollider h1,
  HeightfieldCollider h2,
) {
  if (!PhysicsNarrowphase.aabbIntersects(h1.worldBounds, h2.worldBounds)) {
    return null;
  }
  final delta = h2.worldCenter - h1.worldCenter;
  final dist = delta.length;
  final norm = dist > 1e-6 ? delta * (1.0 / dist) : Vec3.unitY;
  return PhysicsContactManifold(
    normal: norm,
    depth: 0.01,
    contactPoints: [h1.worldCenter],
  );
}
