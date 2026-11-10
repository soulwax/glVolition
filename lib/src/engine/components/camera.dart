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

  void shake({double trauma = 0.5, double? rotation}) =>
      engine.graphics.shakeCamera(trauma: trauma, rotation: rotation);

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

  CameraView toCameraView([double? aspect]) =>
      controller.toCameraView(aspect ?? engine.graphics.aspect);

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
