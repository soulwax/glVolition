part of '../../engine.dart';

/// 2D orthographic pixel/design-space camera component wrapping pixeldart's
/// [Camera2D] (E4-2).
final class Camera2DComponent extends Component {
  final Camera2D raw;

  /// When true, copies `transform.position.x/y` and `transform.localScale`
  /// into [raw] before each frame.
  bool followTransform;

  Camera2DComponent({
    double designWidth = 400,
    double designHeight = 225,
    this.followTransform = true,
  }) : raw = Camera2D(designWidth: designWidth, designHeight: designHeight);

  double get x => raw.x;
  set x(double value) {
    raw.x = value;
    if (followTransform && isAttached) {
      final p = transform.localPosition;
      transform.localPosition = Vec3(value, p.y, p.z);
    }
  }

  double get y => raw.y;
  set y(double value) {
    raw.y = value;
    if (followTransform && isAttached) {
      final p = transform.localPosition;
      transform.localPosition = Vec3(p.x, value, p.z);
    }
  }

  double get zoom => raw.zoom;
  set zoom(double value) => raw.zoom = value;

  double get rotation => raw.rotation;
  set rotation(double value) => raw.rotation = value;

  Vec2 screenToWorld(double screenX, double screenY) => raw.screenToWorld(screenX, screenY);
  Vec2 worldToScreen(double worldX, double worldY) => raw.worldToScreen(worldX, worldY);

  /// Smoothly interpolates the camera's 2D position towards [target] using exponential decay.
  void smoothFollow(Vec2 target, {double smoothing = 10.0, double dt = 1 / 60}) {
    final factor = 1.0 - math.exp(-smoothing * dt);
    final curX = x;
    final curY = y;
    x = curX + (target.x - curX) * factor;
    y = curY + (target.y - curY) * factor;
  }

  /// Clamps the 2D camera coordinates within the given world bounding rectangle `[minX..maxX, minY..maxY]`.
  void clampToBounds({
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
  }) {
    x = x.clamp(minX, maxX);
    y = y.clamp(minY, maxY);
  }

  void _sync(int viewportWidth, int viewportHeight) {
    if (viewportWidth > 0 && viewportHeight > 0) {
      raw.setViewport(viewportWidth, viewportHeight);
    }
    if (followTransform) {
      final p = transform.position;
      raw.x = p.x;
      raw.y = p.y;
    }
  }

  @override
  void _onEnableInternal() => scene._cameras2d.add(this);

  @override
  void _onDisableInternal() => scene._cameras2d.remove(this);
}

/// Renders a 2D [SpriteRegion] at this [GameObject]'s `(x, y)` world position,
/// batched automatically by `(layer, y)` in [Scene._encode] (E4-2).
final class SpriteRenderer extends Component {
  SpriteRegion region;
  double? width;
  double? height;
  double originX;
  double originY;
  double rotation;
  bool flipX;
  bool flipY;
  int color;
  double additive;
  double glow;
  double flash;
  int layer;
  SpriteBlend blend;

  SpriteRenderer({
    required this.region,
    this.width,
    this.height,
    this.originX = 0.5,
    this.originY = 0.5,
    this.rotation = 0,
    this.flipX = false,
    this.flipY = false,
    this.color = 0xFFFFFFFF,
    this.additive = 0,
    this.glow = 0,
    this.flash = 0,
    this.layer = 0,
    this.blend = SpriteBlend.alpha,
  });

  void _drawInto(SpriteBatch batch) {
    final pos = transform.position;
    final s = transform.lossyScale;
    final stretch = transform.localStretch;
    batch.draw(
      region,
      pos.x,
      pos.y,
      width: width,
      height: height,
      scaleX: s * stretch.x,
      scaleY: s * stretch.y,
      originX: originX,
      originY: originY,
      rotation: rotation,
      flipX: flipX,
      flipY: flipY,
      color: color,
      additive: additive,
      glow: glow,
      flash: flash,
      z: pos.z,
      layer: layer,
      blend: blend,
    );
  }

  @override
  void _onEnableInternal() => scene._sprites.add(this);

  @override
  void _onDisableInternal() => scene._sprites.remove(this);
}

/// Frame-by-frame sprite animation behaviour that drives a sibling
/// [SpriteRenderer] (E4-2).
final class SpriteAnimator extends Behaviour {
  final Map<String, List<SpriteRegion>> clips;
  double fps;
  bool loop;

  String? _currentClip;
  double _frameCursor = 0;

  SpriteAnimator({
    required this.clips,
    this.fps = 10,
    this.loop = true,
    String? initialClip,
  }) : _currentClip = initialClip;

  static final spec = ComponentSpec<SpriteAnimator>(
    'SpriteAnimator',
    () => SpriteAnimator(clips: {'idle': [SpriteRegion.white]}, initialClip: 'idle'),
    [
      Field.number('fps', (s) => s.fps, (s, v) => s.fps = v),
      Field.boolean('loop', (s) => s.loop, (s, v) => s.loop = v),
    ],
  );

  String? get currentClip => _currentClip;
  int get currentFrameIndex => _frameCursor.floor();

  void play(String clipName, {bool restart = false}) {
    if (!clips.containsKey(clipName)) {
      throw ArgumentError.value(clipName, 'clipName', 'unknown sprite animation clip');
    }
    if (_currentClip != clipName || restart) {
      _currentClip = clipName;
      _frameCursor = 0;
      _applyFrame();
    }
  }

  @override
  void start() {
    if (_currentClip != null) _applyFrame();
  }

  @override
  void update() {
    final name = _currentClip;
    if (name == null) return;
    final frames = clips[name];
    if (frames == null || frames.isEmpty) return;

    _frameCursor += time.deltaTime * fps;
    if (_frameCursor >= frames.length) {
      if (loop) {
        _frameCursor %= frames.length;
      } else {
        _frameCursor = (frames.length - 1).toDouble();
      }
    }
    _applyFrame();
  }

  void _applyFrame() {
    final name = _currentClip;
    if (name == null) return;
    final frames = clips[name];
    if (frames == null || frames.isEmpty) return;
    final renderer = getComponent<SpriteRenderer>();
    if (renderer == null) return;
    final idx = _frameCursor.floor().clamp(0, frames.length - 1);
    renderer.region = frames[idx];
  }
}
