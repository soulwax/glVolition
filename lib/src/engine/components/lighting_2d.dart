part of '../../engine.dart';

vlight.LightVec2 _toLightVec2(Vec2 v) => vlight.LightVec2(v.x, v.y);

/// 2D dynamic point, spot or directional light component (E35).
class Light2DComponent extends Component {
  vlight.Light2DType type;
  LinearColor color;
  double intensity;
  double radius;
  double innerRadius;
  double spotAngle;
  double innerSpotAngle;
  bool castsShadows;

  /// Custom 2D direction for spot lights. If null, uses the GameObject's 2D orientation.
  Vec2? customDirection;

  Light2DComponent({
    this.type = vlight.Light2DType.point,
    this.color = LinearColor.white,
    this.intensity = 1.0,
    this.radius = 10.0,
    this.innerRadius = 0.0,
    this.spotAngle = math.pi * 0.5,
    this.innerSpotAngle = math.pi * 0.25,
    this.castsShadows = true,
    this.customDirection,
  });

  Vec2 get position2D => Vec2(transform.position.x, transform.position.y);

  Vec2 get direction2D {
    if (customDirection != null) return customDirection!;
    // In 2D xy plane, rotate (1, 0, 0) by transform rotation
    final dir = transform.rotation.rotate(const Vec3(1.0, 0.0, 0.0));
    return Vec2(dir.x, dir.y);
  }

  /// Builds a pure voxlight Light2D instance representing this component.
  vlight.Light2D toVoxLight() {
    return vlight.Light2D(
      type: type,
      position: _toLightVec2(position2D),
      radius: radius,
      innerRadius: innerRadius,
      intensity: intensity,
      r: color.r,
      g: color.g,
      b: color.b,
      direction: _toLightVec2(direction2D),
      spotAngle: spotAngle,
      innerSpotAngle: innerSpotAngle,
      castsShadows: castsShadows,
    );
  }

  /// Evaluates lighting contribution at [target] in 2D space.
  vlight.Illumination2D evaluate(Vec2 target, [List<vlight.Segment2D>? occluders]) {
    final light = toVoxLight();
    return light.evaluate(_toLightVec2(target), occluders);
  }

  /// Computes the 2D visibility polygon from this light's position against active shadow casters in the scene.
  vlight.VisibilityPolygon computeVisibilityPolygon({double? customRadius}) {
    final r = customRadius ?? radius;
    final occluders = scene.gatherShadowSegments2D();
    return vlight.VisibilityPolygon.compute(
      origin: _toLightVec2(position2D),
      segments: occluders,
      maxRadius: r,
    );
  }

  @override
  void _onEnableInternal() {
    scene._registerLight2D(this);
  }

  @override
  void _onDisableInternal() {
    scene._unregisterLight2D(this);
  }
}

/// 2D Shadow Caster component that generates occluding segments for 2D lighting and visibility polygons (E35).
class ShadowCaster2DComponent extends Component {
  /// Custom occluder segments relative to this GameObject's local origin.
  final List<vlight.Segment2D> localSegments = [];

  /// If true, automatically extracts occluding boundary segments from a sibling [Collider2D].
  bool useCollider;

  /// Cached half-extents if defining an axis-aligned box caster.
  Vec2? boxHalfExtents;

  ShadowCaster2DComponent({
    List<vlight.Segment2D>? segments,
    this.useCollider = true,
    this.boxHalfExtents,
  }) {
    if (segments != null) {
      localSegments.addAll(segments);
    }
  }

  factory ShadowCaster2DComponent.box(Vec2 halfExtents) {
    return ShadowCaster2DComponent(boxHalfExtents: halfExtents, useCollider: false);
  }

  /// Returns world-space occluding segments for this caster.
  List<vlight.Segment2D> getWorldSegments() {
    final segments = <vlight.Segment2D>[];
    final pos = Vec2(transform.position.x, transform.position.y);

    // 1. Box half extents
    final box = boxHalfExtents;
    if (box != null) {
      final caster = vlight.ShadowCaster2D.fromBox(_toLightVec2(pos), _toLightVec2(box));
      segments.addAll(caster.segments);
    }

    // 2. Local custom segments transformed to world
    for (final seg in localSegments) {
      final worldA = vlight.LightVec2(seg.a.x + pos.x, seg.a.y + pos.y);
      final worldB = vlight.LightVec2(seg.b.x + pos.x, seg.b.y + pos.y);
      segments.add(vlight.Segment2D(worldA, worldB));
    }

    // 3. Auto-extract from sibling Collider2D
    if (useCollider) {
      final boxCol = getComponent<BoxCollider2D>();
      if (boxCol != null) {
        final center = Vec2(pos.x + boxCol.offset.x, pos.y + boxCol.offset.y);
        final halfSize = Vec2(boxCol.size.x * 0.5, boxCol.size.y * 0.5);
        final caster = vlight.ShadowCaster2D.fromBox(_toLightVec2(center), _toLightVec2(halfSize));
        segments.addAll(caster.segments);
      }

      final polyCol = getComponent<PolygonCollider2D>();
      if (polyCol != null && polyCol.points.length >= 3) {
        final worldPts = polyCol.points.map((p) => vlight.LightVec2(p.x + pos.x, p.y + pos.y)).toList();
        final caster = vlight.ShadowCaster2D.fromPolygon(worldPts);
        segments.addAll(caster.segments);
      }
    }

    return segments;
  }

  @override
  void _onEnableInternal() {
    scene._registerShadowCaster2D(this);
  }

  @override
  void _onDisableInternal() {
    scene._unregisterShadowCaster2D(this);
  }
}

/// 2D tile-grid Fog of War exploration component (E35).
class FogOfWar2DComponent extends Component {
  final vlight.FogOfWar _fog;

  vlight.FogOfWar get rawFog => _fog;

  FogOfWar2DComponent({
    required int width,
    required int height,
    double cellSize = 1.0,
    Vec2 origin = Vec2.zero,
  }) : _fog = vlight.FogOfWar(
          width: width,
          height: height,
          cellSize: cellSize,
          origin: _toLightVec2(origin),
        );

  int get width => _fog.width;
  int get height => _fog.height;
  double get cellSize => _fog.cellSize;

  /// Reveals a circle of sight around [center] up to [radius].
  /// If [testOcclusion] is true, shadows from scene occluders block sight.
  void reveal(Vec2 center, double radius, {bool testOcclusion = true}) {
    List<vlight.Segment2D>? occluders;
    if (testOcclusion) {
      occluders = scene.gatherShadowSegments2D();
    }
    _fog.reveal(_toLightVec2(center), radius, occluders);
  }

  /// Resets currently visible tiles to explored state.
  void clearVisibility() => _fog.clearVisibility();

  bool isVisible(Vec2 worldPos) => _fog.isVisible(_toLightVec2(worldPos));

  bool isExplored(Vec2 worldPos) => _fog.isExplored(_toLightVec2(worldPos));
}
