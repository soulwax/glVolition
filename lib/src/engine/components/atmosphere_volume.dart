part of '../../engine.dart';

/// Drives the scene's sun [DirectionalLight], skybox, and horizon fog from
/// pixeldart's [SolarCycleEngine], and manages active
/// [AtmosphericParticleField]s and [FlowParticleField]s (E5-4).
final class AtmosphereVolume extends Behaviour {
  double timeOfDayHours;

  /// Rate at which [timeOfDayHours] advances per scaled game second.
  double hoursPerSecond;

  double latitudeRadians;
  double solarDeclinationRadians;
  double cloudCoverage;
  double cloudDensity;
  double aerosolTurbidity;
  double fogStart;
  double fogEnd;
  bool coherentHorizon;

  final List<AtmosphericParticleField> particleFields = [];
  final List<FlowParticleField> flowFields = [];

  SolarLightingState? _lastState;

  AtmosphereVolume({
    this.timeOfDayHours = 12.0,
    this.hoursPerSecond = 0.0,
    this.latitudeRadians = 0.65,
    this.solarDeclinationRadians = 0.2,
    this.cloudCoverage = 0.25,
    this.cloudDensity = 0.45,
    this.aerosolTurbidity = 2.0,
    this.fogStart = 45.0,
    this.fogEnd = 210.0,
    this.coherentHorizon = true,
  });

  static final spec = ComponentSpec<AtmosphereVolume>(
    'AtmosphereVolume',
    AtmosphereVolume.new,
    [
      Field.number(
        'timeOfDayHours',
        (a) => a.timeOfDayHours,
        (a, v) => a.timeOfDayHours = v,
      ),
      Field.number(
        'hoursPerSecond',
        (a) => a.hoursPerSecond,
        (a, v) => a.hoursPerSecond = v,
      ),
      Field.number(
        'latitudeRadians',
        (a) => a.latitudeRadians,
        (a, v) => a.latitudeRadians = v,
      ),
      Field.number(
        'solarDeclinationRadians',
        (a) => a.solarDeclinationRadians,
        (a, v) => a.solarDeclinationRadians = v,
      ),
      Field.number(
        'cloudCoverage',
        (a) => a.cloudCoverage,
        (a, v) => a.cloudCoverage = v,
      ),
      Field.number(
        'cloudDensity',
        (a) => a.cloudDensity,
        (a, v) => a.cloudDensity = v,
      ),
      Field.number(
        'aerosolTurbidity',
        (a) => a.aerosolTurbidity,
        (a, v) => a.aerosolTurbidity = v,
      ),
      Field.number('fogStart', (a) => a.fogStart, (a, v) => a.fogStart = v),
      Field.number('fogEnd', (a) => a.fogEnd, (a, v) => a.fogEnd = v),
      Field.boolean(
        'coherentHorizon',
        (a) => a.coherentHorizon,
        (a, v) => a.coherentHorizon = v,
      ),
    ],
  );

  SolarLightingState? get currentSolarState => _lastState;

  @override
  void _onEnableInternal() {
    scene._atmospheres.add(this);
    _applySolar();
  }

  @override
  void _onDisableInternal() {
    scene._atmospheres.remove(this);
  }

  @override
  void update() {
    if (hoursPerSecond != 0) {
      timeOfDayHours =
          ((timeOfDayHours + hoursPerSecond * time.deltaTime) % 24 + 24) % 24;
    }
    _applySolar();
  }

  void _applySolar() {
    final state = SolarCycleEngine.evaluate(
      SolarCycleInput(
        timeHours: timeOfDayHours,
        latitudeRadians: latitudeRadians,
        solarDeclinationRadians: solarDeclinationRadians,
        cloudCover01: cloudCoverage.clamp(0.0, 1.0),
        aerosolTurbidity: math.max(1.0, aerosolTurbidity),
      ),
    );
    _lastState = state;

    final twilight = state.twilightFactor01;
    final computedHorizon = LinearColor(
      0.04 + state.sunColor.r * 0.35 * twilight,
      0.06 + state.sunColor.g * 0.38 * twilight,
      0.10 + state.sunColor.b * 0.45 * twilight,
    );
    final zenith = LinearColor(
      0.01 + 0.16 * twilight,
      0.02 + 0.34 * twilight,
      0.05 + 0.68 * twilight,
    );
    final horizon = coherentHorizon ? state.fogColor : computedHorizon;
    final starVis = (1.0 - twilight).clamp(0.0, 1.0);
    final rs = scene.renderSettings;
    rs
      ..clearColor = state.fogColor
      ..ambientColor = state.ambientColor
      ..ambientIntensity = state.ambientIntensity
      ..fogEnabled = true
      ..fogColor = state.fogColor
      ..fogStart = fogStart
      ..fogEnd = fogEnd
      ..fogDensity = state.fogDensity
      ..fogHeightFalloff = state.fogHeightFalloff
      ..skybox = SkyboxDeclaration(
        assetId: 'solar_sky',
        horizon: horizon,
        zenith: zenith,
        ground: state.fogColor,
        horizonGlow: state.horizonVisibility01 * 0.35,
        starDensity: starVis * 0.04,
        cloudCoverage: cloudCoverage.clamp(0.0, 1.0),
        cloudDensity: cloudDensity.clamp(0.0, 1.0),
      );

    // Also update or provide a sun directional light if the scene has one
    // attached to this GameObject.
    final sun = getComponent<Light>();
    if (sun != null && sun.type == LightType.directional) {
      sun
        ..color = state.sunColor
        ..intensity = state.directionalIntensity;
      transform.rotation = lookRotation(state.sunDirection);
    }
  }

  void _encode(RenderEncoder encoder, FrameInput frame) {
    for (final f in particleFields) {
      f.submit(encoder, frame);
    }
    for (final flow in flowFields) {
      flow.submit(encoder, frame);
    }
  }
}

/// Emits volumetric light scattering ([VolumetricSource]) into the scene's
/// [FrameEnvironment] (E13-3).
final class VolumetricLightSource extends Component {
  LinearColor color;
  double luminousIntensity;
  double referenceDistance;
  double cutoffDistance;

  VolumetricLightSource({
    this.color = const LinearColor(1.0, 0.85, 0.6),
    this.luminousIntensity = 2.0,
    this.referenceDistance = 1.0,
    this.cutoffDistance = 40.0,
  });

  static final spec = ComponentSpec<VolumetricLightSource>(
    'VolumetricLightSource',
    VolumetricLightSource.new,
    [
      Field.color('color', (v) => v.color, (v, c) => v.color = c),
      Field.number(
        'luminousIntensity',
        (v) => v.luminousIntensity,
        (v, n) => v.luminousIntensity = n,
      ),
      Field.number(
        'referenceDistance',
        (v) => v.referenceDistance,
        (v, n) => v.referenceDistance = n,
      ),
      Field.number(
        'cutoffDistance',
        (v) => v.cutoffDistance,
        (v, n) => v.cutoffDistance = n,
      ),
    ],
  );

  VolumetricSource toVolumetricSource() => VolumetricSource(
    id: 'vol_${gameObject.name}_$instanceId',
    position: transform.position,
    color: Vec3(color.r, color.g, color.b),
    luminousIntensity: math.max(0.0, luminousIntensity),
    referenceDistance: math.max(0.01, referenceDistance),
    cutoffDistance: math.max(0.1, cutoffDistance),
  );

  @override
  void _onEnableInternal() => scene._volumetricSources.add(this);

  @override
  void _onDisableInternal() => scene._volumetricSources.remove(this);
}

/// Emits a spherical thermal conduction field ([ThermalSource]) into the
/// scene's [FrameEnvironment] and [Scene.sampleThermalDissolution] queries
/// (E13-3).
final class ThermalSourceComponent extends Component {
  double radiusMeters;
  double dissolution01;

  ThermalSourceComponent({this.radiusMeters = 4.0, this.dissolution01 = 1.0});

  static final spec = ComponentSpec<ThermalSourceComponent>(
    'ThermalSourceComponent',
    ThermalSourceComponent.new,
    [
      Field.number(
        'radiusMeters',
        (t) => t.radiusMeters,
        (t, v) => t.radiusMeters = v,
      ),
      Field.number(
        'dissolution01',
        (t) => t.dissolution01,
        (t, v) => t.dissolution01 = v,
      ),
    ],
  );

  ThermalSource toThermalSource() => ThermalSource(
    id: 'therm_${gameObject.name}_$instanceId',
    position: transform.position,
    radiusMeters: math.max(0.05, radiusMeters),
    dissolution01: dissolution01.clamp(0.0, 1.0),
  );

  @override
  void _onEnableInternal() => scene._thermalSources.add(this);

  @override
  void _onDisableInternal() => scene._thermalSources.remove(this);
}
