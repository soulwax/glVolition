part of '../../engine.dart';

/// Holds a 3D Catmull-Rom spline path in world space (E5-2).
final class SplinePath extends Component {
  CatmullRomSpline3D spline;

  SplinePath(this.spline);

  factory SplinePath.fromPoints(List<Vec3> controlPoints, {bool closed = false}) =>
      SplinePath(CatmullRomSpline3D(points: controlPoints, closed: closed));

  double get totalLength => spline.totalLength;

  Vec3 sampleAtDistance(double distance) => spline.sampleAtDistance(distance);

  Vec3 tangentAtDistance(double distance) => spline.tangentAtDistance(distance);

  /// Finds the arc-length distance along the spline closest to [point].
  double closestDistance(Vec3 point, {int samples = 64}) {
    final len = spline.totalLength;
    if (len <= 0 || samples <= 1) return 0;
    var bestS = 0.0;
    var bestD2 = double.infinity;
    for (var i = 0; i <= samples; i++) {
      final s = (i / samples) * len;
      final p = spline.sampleAtDistance(s);
      final d2 = (p - point).lengthSquared;
      if (d2 < bestD2) {
        bestD2 = d2;
        bestS = s;
      }
    }
    return bestS;
  }
}

/// Moves its [GameObject] along a [SplinePath] at arc-length [speed] (E5-2).
final class SplineFollower extends Behaviour {
  SplinePath path;
  double speed;
  double distance;
  LoopMode loopMode;
  bool alignToTangent;
  Vec3 localOffset;
  void Function()? onReachedEnd;

  int _direction = 1;
  bool _completed = false;

  SplineFollower({
    required this.path,
    this.speed = 5.0,
    this.distance = 0.0,
    this.loopMode = LoopMode.once,
    this.alignToTangent = true,
    this.localOffset = Vec3.zero,
    this.onReachedEnd,
  });

  bool get isCompleted => _completed;

  @override
  void start() => _applyPose();

  @override
  void update() {
    if (_completed) return;
    final len = path.totalLength;
    if (len <= 0) return;

    distance += speed * _direction * time.deltaTime;
    switch (loopMode) {
      case LoopMode.once:
        if (distance >= len) {
          distance = len;
          _completed = true;
          _applyPose();
          onReachedEnd?.call();
          return;
        } else if (distance < 0) {
          distance = 0;
        }
      case LoopMode.loop:
        distance = ((distance % len) + len) % len;
      case LoopMode.pingPong:
        if (distance >= len) {
          distance = len - (distance - len);
          _direction = -1;
        } else if (distance <= 0) {
          distance = -distance;
          _direction = 1;
        }
        distance = distance.clamp(0.0, len);
    }
    _applyPose();
  }

  void _applyPose() {
    final pos = path.sampleAtDistance(distance) + localOffset;
    transform.position = pos;
    if (alignToTangent) {
      final tan = path.tangentAtDistance(distance) * _direction.toDouble();
      if (tan.lengthSquared > 1e-8) {
        transform.rotation = lookRotation(tan);
      }
    }
  }
}
