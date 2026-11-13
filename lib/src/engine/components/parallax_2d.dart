part of '../../engine.dart';

/// Single visual layer in a [ParallaxBackground2D] system (E24-2).
final class ParallaxLayer {
  /// Parallax movement multiplier relative to camera translation (`0.0` = static, `1.0` = 1:1 with camera).
  Vec2 factor;

  /// Ambient automatic scroll velocity in world units/sec (e.g. drifting clouds or stars).
  Vec2 autoScroll;

  /// Tiling repeat width and height in world units.
  double width;
  double height;

  /// Current visual scroll offset.
  Vec2 offset;

  /// Texture region slice for rendering this layer.
  SpriteRegion? region;

  /// RGBA tint color for this layer.
  int tintColor;

  /// Whether this layer wraps horizontally.
  bool repeatX;

  /// Whether this layer wraps vertically.
  bool repeatY;

  ParallaxLayer({
    this.factor = const Vec2(0.5, 0.5),
    this.autoScroll = Vec2.zero,
    this.width = 640.0,
    this.height = 360.0,
    Vec2? offset,
    this.region,
    this.tintColor = 0xFFFFFFFF,
    this.repeatX = true,
    this.repeatY = false,
  }) : offset = offset ?? Vec2.zero;

  /// Advances the layer's offset based on [cameraDelta] and elapsed [dt] seconds.
  void advance(Vec2 cameraDelta, double dt) {
    var ox = offset.x + autoScroll.x * dt + cameraDelta.x * factor.x;
    var oy = offset.y + autoScroll.y * dt + cameraDelta.y * factor.y;

    if (repeatX && width > 0.0) {
      ox = Mathfx.repeat(ox, width);
    }
    if (repeatY && height > 0.0) {
      oy = Mathfx.repeat(oy, height);
    }

    offset = Vec2(ox, oy);
  }
}

/// Multi-layered 2D parallax background controller that responds to camera motion (E24-2).
final class ParallaxBackground2D extends Behaviour {
  final List<ParallaxLayer> layers = [];

  /// Optional transform to follow. When null, tracks the scene's [Camera2DComponent] or [Camera].
  TransformComponent? target;

  Vec3? _lastTrackedPosition;

  ParallaxBackground2D({List<ParallaxLayer> layers = const [], this.target}) {
    this.layers.addAll(layers);
  }

  static final spec = ComponentSpec<ParallaxBackground2D>(
    'ParallaxBackground2D',
    ParallaxBackground2D.new,
    const [],
  );

  /// Appends a new [ParallaxLayer] to this background.
  void addLayer(ParallaxLayer layer) => layers.add(layer);

  @override
  void onEnable() {
    _lastTrackedPosition = _resolveTrackedPosition();
  }

  @override
  void lateUpdate() {
    final currentPos = _resolveTrackedPosition();
    final prevPos = _lastTrackedPosition ?? currentPos;
    _lastTrackedPosition = currentPos;

    final cameraDelta = Vec2(
      currentPos.x - prevPos.x,
      currentPos.y - prevPos.y,
    );
    final dt = isAttached ? time.deltaTime : 1 / 60;

    for (final layer in layers) {
      layer.advance(cameraDelta, dt);
    }
  }

  Vec3 _resolveTrackedPosition() {
    if (target != null && target!.isAttached) {
      return target!.position;
    }
    final cam2d = Camera2DComponent.of(scene);
    if (cam2d != null && cam2d.isAttached) {
      return cam2d.transform.position;
    }
    final cam3d = Camera.of(scene);
    if (cam3d != null && cam3d.isAttached) {
      return cam3d.transform.position;
    }
    return Vec3.zero;
  }
}
