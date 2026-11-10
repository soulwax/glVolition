part of '../../engine.dart';

/// Drives the renderer's view from its [GameObject]'s transform, or delegates
/// to one of pixeldart's [CameraController]s (orbit, fly, smooth-follow, or a
/// custom controller).
final class Camera extends Component {
  double fovYRadians;
  double near;
  double far;
  bool orthographic;
  double orthoHeight;

  /// Optional controller. When null the camera looks along its transform's
  /// `forward` (-Z) from `transform.position`.
  CameraController? customController;

  /// Deterministic trauma-based camera shake evaluator (E12-1).
  final CameraShakeEngine shakeEngine = CameraShakeEngine();

  late final _TransformCameraController _transformController = _TransformCameraController(this);

  Camera({
    this.fovYRadians = 1.0,
    this.near = 0.1,
    this.far = 200,
    this.orthographic = false,
    this.orthoHeight = 12.0,
    this.customController,
  });

  factory Camera.ortho({
    double orthoHeight = 12.0,
    double near = 0.1,
    double far = 200,
    CameraController? customController,
  }) =>
      Camera(
        orthographic: true,
        orthoHeight: orthoHeight,
        near: near,
        far: far,
        customController: customController,
      );

  CameraController get controller => customController ?? _transformController;

  /// The most recently enabled camera in the active scene.
  static Camera? of(Scene scene) => scene._cameras.lastOrNull;

  void shake({double trauma = 0.5, double? rotation}) {
    if (rotation != null) shakeEngine.rotationScale = rotation;
    shakeEngine.addTrauma(trauma);
    if (isAttached && scene.isLoaded) {
      engine.graphics.shakeCamera(trauma: trauma, rotation: rotation);
    }
  }

  Ray? screenPointToRay(double x, double y) {
    final hostRay = engine.graphics.screenRay(x, y);
    if (hostRay != null) return hostRay;
    final vw = engine.graphics.viewportWidth;
    final vh = engine.graphics.viewportHeight;
    if (vw <= 0 || vh <= 0) return null;
    return toCameraView(vw / vh).screenPointToRay(x, y, vw, vh);
  }

  /// Intersects the ray through drawing-buffer pixel ([x], [y]) with the
  /// horizontal plane `y == groundHeight` (E4-1).
  Vec3? screenToGroundPlane(double x, double y, [double groundHeight = 0]) =>
      screenPointToRay(x, y)?.intersectGround(groundHeight);

  /// Projects a 3D world-space [worldPoint] into drawing-buffer pixel
  /// coordinates `(x, y)` (top-left origin) and clip-space `depth` (`w`), or
  /// returns `null` when the point is behind the camera (`w <= 0`) (E11-3).
  ({double x, double y, double depth})? worldToScreenPoint(Vec3 worldPoint) {
    final vw = engine.graphics.viewportWidth;
    final vh = engine.graphics.viewportHeight;
    if (vw <= 0 || vh <= 0) return null;
    final vp = toCameraView(vw / vh).viewProjection.m;
    final cx = vp[0] * worldPoint.x + vp[4] * worldPoint.y + vp[8] * worldPoint.z + vp[12];
    final cy = vp[1] * worldPoint.x + vp[5] * worldPoint.y + vp[9] * worldPoint.z + vp[13];
    final cw = vp[3] * worldPoint.x + vp[7] * worldPoint.y + vp[11] * worldPoint.z + vp[15];
    if (cw <= 1e-5) return null;
    final ndcX = cx / cw;
    final ndcY = cy / cw;
    final sx = (ndcX * 0.5 + 0.5) * vw;
    final sy = (1.0 - (ndcY * 0.5 + 0.5)) * vh;
    return (x: sx, y: sy, depth: cw);
  }

  CameraView toCameraView([double? aspect]) {
    _sync();
    final base = controller.toCameraView(aspect ?? engine.graphics.aspect);
    return shakeEngine.applyTo(base);
  }

  void _sync() {
    if (customController == null) _transformController._capture();
  }

  @override
  void _onEnableInternal() => scene._cameras.add(this);

  @override
  void _onDisableInternal() => scene._cameras.remove(this);
}

final class _TransformCameraController implements CameraController {
  final Camera _camera;
  Vec3 _eye = const Vec3(0, 1.6, 5);
  Vec3 _forward = kForward;
  Vec3 _up = kUp;

  _TransformCameraController(this._camera);

  void _capture() {
    final t = _camera.transform;
    _eye = t.position;
    _forward = t.forward;
    _up = t.up;
  }

  @override
  Vec3 get eye => _eye;

  @override
  Vec3 get forward => _forward;

  @override
  void update(double deltaTime) => _capture();

  @override
  CameraView toCameraView(double aspect) {
    if (_camera.orthographic) {
      final halfH = _camera.orthoHeight * 0.5;
      return CameraView.orthographic(
        eye: _eye,
        forward: _forward,
        up: _up,
        halfWidth: halfH * aspect,
        halfHeight: halfH,
        near: _camera.near,
        far: _camera.far,
      );
    }
    return CameraView.look(
      eye: _eye,
      forward: _forward,
      up: _up,
      fovYRadians: _camera.fovYRadians,
      aspect: aspect,
      near: _camera.near,
      far: _camera.far,
    );
  }
}
