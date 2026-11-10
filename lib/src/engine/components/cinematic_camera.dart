part of '../../engine.dart';

/// Smoothly follows a [target] [GameObject] using pixeldart's
/// [SmoothFollowCameraController] and drives a sibling [Camera] (E12-1).
final class SmoothFollowCamera extends Behaviour {
  GameObject? target;
  Vec3 targetOffset;
  double distance;
  double height;
  double positionDamping;
  double rotationDamping;
  double azimuthOffset;
  double elevationOffset;

  late final SmoothFollowCameraController controller = SmoothFollowCameraController(
    targetOffset: targetOffset,
    distance: distance,
    height: height,
    positionDamping: positionDamping,
    rotationDamping: rotationDamping,
  )
    ..azimuthOffset = azimuthOffset
    ..elevationOffset = elevationOffset;

  SmoothFollowCamera({
    this.target,
    this.targetOffset = const Vec3(0, 0.8, 0),
    this.distance = 5.5,
    this.height = 1.8,
    this.positionDamping = 6.0,
    this.rotationDamping = 8.0,
    this.azimuthOffset = 0.0,
    this.elevationOffset = 0.25,
  });

  static final spec = ComponentSpec<SmoothFollowCamera>(
    'SmoothFollowCamera',
    SmoothFollowCamera.new,
    [
      Field.vec3('targetOffset', (c) => c.targetOffset, (c, v) => c.targetOffset = v),
      Field.number('distance', (c) => c.distance, (c, v) => c.distance = v),
      Field.number('height', (c) => c.height, (c, v) => c.height = v),
      Field.number('positionDamping', (c) => c.positionDamping, (c, v) => c.positionDamping = v),
      Field.number('rotationDamping', (c) => c.rotationDamping, (c, v) => c.rotationDamping = v),
      Field.number('azimuthOffset', (c) => c.azimuthOffset, (c, v) => c.azimuthOffset = v),
      Field.number('elevationOffset', (c) => c.elevationOffset, (c, v) => c.elevationOffset = v),
    ],
  );

  @override
  void onEnable() {
    getComponent<Camera>()?.customController = controller;
    _syncParameters();
    controller.update(0.0);
  }

  @override
  void lateUpdate() {
    final cam = getComponent<Camera>();
    if (cam != null && cam.customController == null) {
      cam.customController = controller;
    }
    _syncParameters();
    controller.update(time.deltaTime);
    transform.position = controller.eye;
  }

  void _syncParameters() {
    controller
      ..targetNode = target?.node
      ..targetPosition = target?.transform.position ?? controller.targetPosition
      ..targetOffset = targetOffset
      ..distance = distance
      ..height = height
      ..positionDamping = positionDamping
      ..rotationDamping = rotationDamping
      ..azimuthOffset = azimuthOffset
      ..elevationOffset = elevationOffset;
  }
}

/// Drives a sibling [Camera] along a keyframed Catmull-Rom spline tour using
/// pixeldart's [CinematicTourCameraController] (E12-1).
final class CinematicTourCamera extends Behaviour {
  final CinematicTourCameraController controller;
  void Function()? onCompleted;
  bool _completedFired = false;

  CinematicTourCamera({
    required List<CameraWaypoint> waypoints,
    double duration = 12.0,
    bool loop = false,
    double breathingAmplitude = 0.0,
    double breathingSpeed = 1.2,
    this.onCompleted,
  }) : controller = CinematicTourCameraController(
          waypoints: waypoints,
          duration: duration,
          loop: loop,
          breathingAmplitude: breathingAmplitude,
          breathingSpeed: breathingSpeed,
        );

  static final spec = ComponentSpec<CinematicTourCamera>(
    'CinematicTourCamera',
    () => CinematicTourCamera(
      waypoints: const [
        CameraWaypoint(eye: Vec3(0, 2, 8), target: Vec3.zero),
        CameraWaypoint(eye: Vec3(6, 3, 6), target: Vec3.zero),
      ],
    ),
    const [],
  );

  double get progress => controller.progress;
  bool get isPlaying => controller.isPlaying;

  void play() {
    _completedFired = false;
    controller.play();
  }

  void pause() => controller.pause();

  void reset() {
    _completedFired = false;
    controller.reset();
  }

  void seek(double normalizedProgress) => controller.seek(normalizedProgress);

  @override
  void onEnable() {
    getComponent<Camera>()?.customController = controller;
  }

  @override
  void update() {
    final cam = getComponent<Camera>();
    if (cam != null && cam.customController == null) {
      cam.customController = controller;
    }
    controller.update(time.deltaTime);
    transform.position = controller.eye;
    if (!controller.loop && !controller.isPlaying && controller.progress >= 1.0 && !_completedFired) {
      _completedFired = true;
      onCompleted?.call();
    }
  }
}
