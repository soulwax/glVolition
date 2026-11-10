part of '../../engine.dart';

enum LightType { directional, point, spot }

/// A scene light. Its position and direction come from its [GameObject]'s
/// transform (`transform.position`, `transform.forward`).
///
/// The active lights are gathered each frame into [FrameEnvironment] up to
/// [RuntimeLightBudget].
final class Light extends Component {
  LightType type;
  LinearColor color;
  double intensity;

  /// Point light radius or spot light range.
  double range;

  double innerSpotAngle;
  double spotAngle;
  bool castsShadow;

  Light({
    this.type = LightType.point,
    this.color = LinearColor.white,
    this.intensity = 1.0,
    this.range = 10.0,
    this.innerSpotAngle = 0.3,
    this.spotAngle = 0.5,
    this.castsShadow = false,
  });

  factory Light.directional({
    LinearColor color = LinearColor.white,
    double intensity = 1.0,
  }) =>
      Light(type: LightType.directional, color: color, intensity: intensity);

  factory Light.point({
    LinearColor color = LinearColor.white,
    double intensity = 1.0,
    double range = 8.0,
    bool castsShadow = false,
  }) =>
      Light(
        type: LightType.point,
        color: color,
        intensity: intensity,
        range: range,
        castsShadow: castsShadow,
      );

  factory Light.spot({
    LinearColor color = LinearColor.white,
    double intensity = 1.0,
    double range = 12.0,
    double innerSpotAngle = 0.3,
    double spotAngle = 0.5,
    bool castsShadow = false,
  }) =>
      Light(
        type: LightType.spot,
        color: color,
        intensity: intensity,
        range: range,
        innerSpotAngle: innerSpotAngle,
        spotAngle: spotAngle,
        castsShadow: castsShadow,
      );

  @override
  void _onEnableInternal() => scene._lights.add(this);

  @override
  void _onDisableInternal() => scene._lights.remove(this);
}
