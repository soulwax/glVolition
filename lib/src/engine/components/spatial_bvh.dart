part of '../../engine.dart';

/// Maintains a dynamic SAH [vgrid.DynamicBvh] broad-phase spatial index over
/// active scene [Collider]s and [MeshRenderer]s (E51-2).
final class SpatialIndexComponent extends Behaviour {
  final vgrid.DynamicBvh<Collider> colliderBvh;
  final vgrid.DynamicBvh<MeshRenderer> rendererBvh;

  bool indexColliders;
  bool indexRenderers;
  bool autoSyncOnLateUpdate;

  final Set<Collider> _trackedColliders = {};
  final Set<MeshRenderer> _trackedRenderers = {};

  SpatialIndexComponent({
    double fatMargin = 0.15,
    this.indexColliders = true,
    this.indexRenderers = true,
    this.autoSyncOnLateUpdate = true,
  }) : colliderBvh = vgrid.DynamicBvh<Collider>(fatMargin: fatMargin),
       rendererBvh = vgrid.DynamicBvh<MeshRenderer>(fatMargin: fatMargin);

  static final spec = ComponentSpec<SpatialIndexComponent>(
    'SpatialIndexComponent',
    SpatialIndexComponent.new,
    [
      Field.boolean(
        'indexColliders',
        (s) => s.indexColliders,
        (s, v) => s.indexColliders = v,
      ),
      Field.boolean(
        'indexRenderers',
        (s) => s.indexRenderers,
        (s, v) => s.indexRenderers = v,
      ),
      Field.boolean(
        'autoSyncOnLateUpdate',
        (s) => s.autoSyncOnLateUpdate,
        (s, v) => s.autoSyncOnLateUpdate = v,
      ),
    ],
  );

  static vgrid.GridAabb _toGridAabb(Aabb box) => vgrid.GridAabb(
    vgrid.GridVec3(box.min.x, box.min.y, box.min.z),
    vgrid.GridVec3(box.max.x, box.max.y, box.max.z),
  );

  static vgrid.GridAabb _toGridAabb3(Aabb3 box) => vgrid.GridAabb(
    vgrid.GridVec3(box.min.x, box.min.y, box.min.z),
    vgrid.GridVec3(box.max.x, box.max.y, box.max.z),
  );

  static vgrid.GridRay _toGridRay(Ray ray) => vgrid.GridRay(
    origin: vgrid.GridVec3(ray.origin.x, ray.origin.y, ray.origin.z),
    direction: vgrid.GridVec3(
      ray.direction.x,
      ray.direction.y,
      ray.direction.z,
    ),
  );

  /// Synchronizes tracked scene [Collider]s and [MeshRenderer]s incrementally.
  void syncNow() {
    if (!isAttached) return;

    if (indexColliders) {
      final active = scene.findObjectsOfType<Collider>().toSet();
      for (final col in active) {
        _trackedColliders.add(col);
        colliderBvh.upsert(col, _toGridAabb(col.worldBounds));
      }
      final removed = _trackedColliders
          .where((c) => !active.contains(c) || c.isDestroyed)
          .toList();
      for (final col in removed) {
        _trackedColliders.remove(col);
        colliderBvh.removeItem(col);
      }
    }

    if (indexRenderers) {
      final active = scene.findObjectsOfType<MeshRenderer>().toSet();
      for (final rend in active) {
        _trackedRenderers.add(rend);
        rendererBvh.upsert(rend, _toGridAabb3(rend.worldAabb));
      }
      final removed = _trackedRenderers
          .where((r) => !active.contains(r) || r.isDestroyed)
          .toList();
      for (final rend in removed) {
        _trackedRenderers.remove(rend);
        rendererBvh.removeItem(rend);
      }
    }
  }

  List<Collider> queryAabb(
    Aabb bounds, {
    int layerMask = -1,
    bool includeTriggers = true,
  }) => colliderBvh.queryAabb(
    _toGridAabb(bounds),
    filter: (c) =>
        c._active &&
        (includeTriggers || !c.isTrigger) &&
        (layerMask & (1 << c.gameObject.layer)) != 0,
  );

  List<Collider> querySphere(
    Vec3 center,
    double radius, {
    int layerMask = -1,
    bool includeTriggers = true,
  }) => colliderBvh.querySphere(
    vgrid.GridVec3(center.x, center.y, center.z),
    radius,
    filter: (c) =>
        c._active &&
        (includeTriggers || !c.isTrigger) &&
        (layerMask & (1 << c.gameObject.layer)) != 0,
  );

  List<Collider> queryFrustum(
    Camera camera, {
    double? aspect,
    int layerMask = -1,
    bool includeTriggers = true,
  }) {
    final vp = camera.toCameraView(aspect).viewProjection.m;
    final frustum = vgrid.GridFrustum.fromColumnMajorMatrix(vp);
    return colliderBvh.queryFrustum(
      frustum,
      filter: (c) =>
          c._active &&
          (includeTriggers || !c.isTrigger) &&
          (layerMask & (1 << c.gameObject.layer)) != 0,
    );
  }

  List<MeshRenderer> queryVisibleRenderers(Camera camera, {double? aspect}) {
    final vp = camera.toCameraView(aspect).viewProjection.m;
    final frustum = vgrid.GridFrustum.fromColumnMajorMatrix(vp);
    return rendererBvh.queryFrustum(
      frustum,
      filter: (r) => r.isActiveAndEnabled,
    );
  }

  List<(Collider, Collider)> queryOverlapPairs({bool includeTriggers = true}) {
    final raw = colliderBvh.queryOverlapPairs();
    if (includeTriggers) return raw;
    return raw.where((p) => !p.$1.isTrigger && !p.$2.isTrigger).toList();
  }

  /// Finds the closest hit collider along [ray] using branch-and-bound BVH pruning
  /// paired with exact collider narrow-phase testing.
  PhysicsHit? raycastClosest(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = -1,
    bool includeTriggers = true,
  }) {
    final gRay = _toGridRay(ray);
    final hit = colliderBvh.raycastClosest(
      gRay,
      maxDistance: maxDistance,
      filter: (c) =>
          c._active &&
          (includeTriggers || !c.isTrigger) &&
          (layerMask & (1 << c.gameObject.layer)) != 0,
      narrowPhase: (col, _, bestDist) {
        final t = col._raycast(ray);
        if (t == null || t > bestDist) return null;
        return t;
      },
    );
    if (hit == null) return null;
    return PhysicsHit(
      collider: hit.item,
      point: ray.at(hit.distance),
      distance: hit.distance,
    );
  }

  @override
  void start() {
    syncNow();
  }

  @override
  void lateUpdate() {
    if (autoSyncOnLateUpdate) {
      syncNow();
    }
  }
}

/// Immediate-mode `voxui` BVH spatial broadphase inspector (E51-2).
final class SpatialBroadphaseUI {
  static void render(
    VoxUiContext ui,
    SpatialIndexComponent index, {
    String title = 'Spatial BVH Broadphase',
    double x = 20.0,
    double y = 20.0,
    double width = 350.0,
    double height = 240.0,
  }) {
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final cb = index.colliderBvh;
    final rb = index.rendererBvh;

    ui.labelValue(
      'Collider Proxies',
      '${cb.count} (nodes ${cb.nodeCount})',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Collider Tree Height',
      '${cb.height}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Move / Reinsert',
      '${cb.moveCallCount} / ${cb.reinsertionCount}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Surface Area Cost',
      cb.computeSurfaceAreaSum().toStringAsFixed(1),
      valueColor: VoxColor.yellow,
    );
    ui.separator();
    ui.labelValue(
      'Renderer Proxies',
      '${rb.count} (nodes ${rb.nodeCount})',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Renderer Tree Height',
      '${rb.height}',
      valueColor: VoxColor.lightGray,
    );

    if (ui.button('Rebuild / Sync Now', height: 22.0)) {
      index.syncNow();
    }

    ui.endWindow();
  }
}
