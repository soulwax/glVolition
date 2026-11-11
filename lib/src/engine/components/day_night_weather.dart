part of '../../engine.dart';

/// Spatially weighted wind volume evaluated alongside global gusts by [WindZoneComponent.sampleAt] (E57-2).
final class WindZoneComponent extends Component {
  sky.WindZoneShape shape;
  double radius;
  double strength;
  double turbulence;
  Vec3 direction;

  WindZoneComponent({
    this.shape = sky.WindZoneShape.directional,
    this.radius = 12.0,
    this.strength = 8.0,
    this.turbulence = 0.5,
    this.direction = const Vec3(1.0, 0.0, 0.25),
  });

  static final spec = ComponentSpec<WindZoneComponent>(
    'WindZoneComponent',
    WindZoneComponent.new,
    [
      Field.enumValue<WindZoneComponent, sky.WindZoneShape>(
        'shape',
        sky.WindZoneShape.values,
        (w) => w.shape,
        (w, v) => w.shape = v,
      ),
      Field.number('radius', (w) => w.radius, (w, v) => w.radius = v),
      Field.number('strength', (w) => w.strength, (w, v) => w.strength = v),
      Field.number('turbulence', (w) => w.turbulence, (w, v) => w.turbulence = v),
      Field.vec3('direction', (w) => w.direction, (w, v) => w.direction = v),
    ],
  );

  sky.WindZoneDef toWindZoneDef() {
    final pos = isAttached ? transform.position : Vec3.zero;
    final worldDir = isAttached ? transform.rotation.rotate(direction) : direction;
    return sky.WindZoneDef(
      id: 'wz_$instanceId',
      position: sky.SkyVec3(pos.x, pos.y, pos.z),
      direction: sky.SkyVec3(worldDir.x, worldDir.y, worldDir.z),
      radius: radius,
      strength: strength,
      turbulence: turbulence,
      shape: shape,
      enabled: _active,
    );
  }
}

/// Manages weather transitions (clear, overcast, rain, storm, snow), wetness/snow accumulation,
/// lightning flash impulses, and harmonic global/zoned wind sampling (E57-2).
final class WeatherVolumeComponent extends Behaviour {
  final sky.WeatherController controller;
  final sky.WindFieldSampler windSampler;
  sky.WeatherKind initialWeather;
  double transitionDurationSeconds;
  Vec3 windDirection;

  WeatherVolumeComponent({
    this.initialWeather = sky.WeatherKind.clear,
    this.transitionDurationSeconds = 5.0,
    this.windDirection = const Vec3(1.0, 0.0, 0.25),
    int seed = 1080,
  })  : controller = sky.WeatherController(
          initialKind: initialWeather,
          transitionDurationSeconds: transitionDurationSeconds,
          seed: seed,
        ),
        windSampler = sky.WindFieldSampler(
          baseDirection: sky.SkyVec3(windDirection.x, windDirection.y, windDirection.z),
        );

  static final spec = ComponentSpec<WeatherVolumeComponent>(
    'WeatherVolumeComponent',
    WeatherVolumeComponent.new,
    [
      Field.enumValue<WeatherVolumeComponent, sky.WeatherKind>(
        'weatherKind',
        sky.WeatherKind.values,
        (w) => w.weatherKind,
        (w, v) => w.setWeather(v, immediate: true),
      ),
      Field.number(
        'transitionDurationSeconds',
        (w) => w.transitionDurationSeconds,
        (w, v) {
          w.transitionDurationSeconds = v;
          w.controller.transitionDurationSeconds = v;
        },
      ),
      Field.vec3('windDirection', (w) => w.windDirection, (w, v) {
        w.windDirection = v;
        w.windSampler.baseDirection = sky.SkyVec3(v.x, v.y, v.z);
      }),
    ],
  );

  sky.WeatherKind get weatherKind => controller.targetKind;
  sky.WeatherSnapshot get currentSnapshot => controller.currentSnapshot;
  double get wetness01 => controller.wetness01;
  double get snowAccumulation01 => controller.snowAccumulation01;
  double get lightningFlash01 => controller.lightningFlash01;

  void setWeather(sky.WeatherKind kind, {bool immediate = false}) =>
      controller.setWeather(kind, immediate: immediate);

  void triggerLightning([double strength = 1.0]) =>
      controller.triggerLightningFlash(strength);

  /// Samples total wind vector (`m/s`) at [worldPosition], folding in scene [WindZoneComponent]s.
  Vec3 sampleWindAt(Vec3 worldPosition) {
    windSampler.zones.clear();
    if (isAttached) {
      void collectZones(GameObject go) {
        final wz = go.getComponent<WindZoneComponent>();
        if (wz != null && wz._active && go.activeInHierarchy) {
          windSampler.zones.add(wz.toWindZoneDef());
        }
        for (final c in go.children) {
          collectZones(c);
        }
      }

      for (final root in scene.rootGameObjects) {
        collectZones(root);
      }
    }
    final res = windSampler.sampleWind(
      sky.SkyVec3(worldPosition.x, worldPosition.y, worldPosition.z),
    );
    return Vec3(res.x, res.y, res.z);
  }

  @override
  void update() {
    controller.transitionDurationSeconds = transitionDurationSeconds;
    final snap = controller.update(time.deltaTime);
    windSampler.baseDirection = sky.SkyVec3(windDirection.x, windDirection.y, windDirection.z);
    windSampler.baseSpeed = snap.windSpeed;
    windSampler.gustStrength = snap.windGustiness;
    windSampler.advance(time.deltaTime);
  }
}

/// Drives 24-hour astronomical solar/lunar sky rendering, scene [RenderSettings],
/// directional sun/moon [Light], and weather modulation from `voxsky` (E57-2).
final class DayNightSkyComponent extends Behaviour {
  final sky.TimeOfDayClock clock;
  final sky.AtmosphericSkyRamp skyRamp;

  double latitudeDegrees;
  double solarDeclinationDegrees;
  double fogStart;
  double fogEnd;
  bool driveRenderSettings;
  Light? sunLight;
  WeatherVolumeComponent? weatherVolume;

  sky.SolarEphemerisState? _lastEphemeris;
  sky.SkyRampStop? _lastSkyStop;

  DayNightSkyComponent({
    double initialHours = 12.0,
    double dayLengthSeconds = 600.0,
    bool paused = false,
    this.latitudeDegrees = 38.0,
    this.solarDeclinationDegrees = 14.0,
    this.fogStart = 35.0,
    this.fogEnd = 200.0,
    this.driveRenderSettings = true,
    this.sunLight,
    this.weatherVolume,
    sky.AtmosphericSkyRamp? skyRamp,
  })  : clock = sky.TimeOfDayClock(
          initialHours: initialHours,
          dayLengthSeconds: dayLengthSeconds,
          paused: paused,
        ),
        skyRamp = skyRamp ?? sky.AtmosphericSkyRamp.earthDefault();

  static final spec = ComponentSpec<DayNightSkyComponent>(
    'DayNightSkyComponent',
    DayNightSkyComponent.new,
    [
      Field.number('hours', (d) => d.hours, (d, v) => d.hours = v),
      Field.number(
        'dayLengthSeconds',
        (d) => d.clock.dayLengthSeconds,
        (d, v) => d.clock.dayLengthSeconds = v,
      ),
      Field.boolean('paused', (d) => d.clock.paused, (d, v) => d.clock.paused = v),
      Field.number('latitudeDegrees', (d) => d.latitudeDegrees, (d, v) => d.latitudeDegrees = v),
      Field.number('fogStart', (d) => d.fogStart, (d, v) => d.fogStart = v),
      Field.number('fogEnd', (d) => d.fogEnd, (d, v) => d.fogEnd = v),
    ],
  );

  double get hours => clock.hours;
  set hours(double value) {
    clock.hours = value;
    evaluateNow();
  }

  int get dayCount => clock.dayCount;
  String get formattedTime => clock.formattedTime;
  sky.DayPeriod get period => clock.period;
  sky.SolarEphemerisState? get lastEphemeris => _lastEphemeris;
  sky.SkyRampStop? get lastSkyStop => _lastSkyStop;

  WeatherVolumeComponent? _resolveWeather() {
    if (weatherVolume != null && !weatherVolume!.isDestroyed) return weatherVolume;
    if (!isAttached) return null;
    final sibling = getComponent<WeatherVolumeComponent>();
    if (sibling != null) return sibling;
    for (final root in scene.rootGameObjects) {
      final w = _findInTree<WeatherVolumeComponent>(root);
      if (w != null) return w;
    }
    return null;
  }

  /// Evaluates ephemeris, atmospheric color ramp & weather modulation, updating
  /// `scene.renderSettings` and `sunLight` immediately.
  void evaluateNow() {
    final ephemeris = sky.SolarEphemeris(
      latitudeDegrees: latitudeDegrees,
      solarDeclinationDegrees: solarDeclinationDegrees,
    );
    final ephem = ephemeris.evaluate(clock.hours, dayCount: clock.dayCount);
    final stop = skyRamp.evaluate(ephem.sunElevationRadians);
    _lastEphemeris = ephem;
    _lastSkyStop = stop;

    final weather = _resolveWeather()?.currentSnapshot;
    final sunAtten = weather?.sunAttenuation01 ?? 1.0;
    final ambScale = weather?.ambientScale01 ?? 1.0;
    final fogMult = weather?.fogMultiplier ?? 1.0;
    final clouds = weather?.cloudCoverage01 ?? 0.2;
    final flash = weather?.lightningFlash01 ?? 0.0;
    final tint = weather?.skyTint ?? sky.SkyColor.white;

    sky.SkyColor scaleTint(sky.SkyColor c) => sky.SkyColor(
          c.r * tint.r + flash * 0.65,
          c.g * tint.g + flash * 0.72,
          c.b * tint.b + flash * 0.85,
        );

    final horizon = scaleTint(stop.horizonColor);
    final zenith = scaleTint(stop.zenithColor);
    final fogCol = scaleTint(stop.fogColor);
    final sunCol = scaleTint(stop.sunColor);
    final ambCol = scaleTint(stop.ambientColor);

    if (driveRenderSettings && isAttached) {
      final rs = scene.renderSettings;
      rs
        ..clearColor = LinearColor(fogCol.r, fogCol.g, fogCol.b)
        ..ambientColor = LinearColor(ambCol.r, ambCol.g, ambCol.b)
        ..ambientIntensity = stop.ambientIntensity * ambScale + flash * 0.8
        ..fogEnabled = true
        ..fogColor = LinearColor(fogCol.r, fogCol.g, fogCol.b)
        ..fogStart = fogStart / math.max(1.0, fogMult * 0.65)
        ..fogEnd = fogEnd / math.max(1.0, fogMult * 0.5)
        ..fogDensity = stop.fogDensity * fogMult
        ..skybox = SkyboxDeclaration(
          assetId: 'voxsky_dome',
          horizon: LinearColor(horizon.r, horizon.g, horizon.b),
          zenith: LinearColor(zenith.r, zenith.g, zenith.b),
          ground: LinearColor(stop.groundColor.r, stop.groundColor.g, stop.groundColor.b),
          horizonGlow: ephem.twilightFactor * 0.35,
          starDensity: stop.starVisibility01 * (1.0 - clouds) * 0.05,
          cloudCoverage: clouds,
          cloudDensity: 0.4 + clouds * 0.5,
        );
    }

    final light = sunLight ?? (isAttached ? getComponent<Light>() : null);
    if (light != null && light.type == LightType.directional) {
      light
        ..color = LinearColor(sunCol.r, sunCol.g, sunCol.b)
        ..intensity = stop.sunIntensity * sunAtten + flash * 3.5;
      final lightDir = Vec3(
        ephem.primaryLightDirection.x,
        ephem.primaryLightDirection.y,
        ephem.primaryLightDirection.z,
      );
      if (lightDir.lengthSquared > 1e-6 && light.isAttached) {
        light.transform.rotation = lookRotation(lightDir);
      }
    }
  }

  @override
  void onEnable() => evaluateNow();

  @override
  void update() {
    clock.advance(time.deltaTime);
    evaluateNow();
  }
}

/// Persistent UI interaction state for [WeatherInspectorUI.render].
final class WeatherInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` sky clock, weather & wind inspector panel (E57-2).
final class WeatherInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    WeatherInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked = hovered && state.activeButtonId == id && inp.wasMouseReleased;
    if (inp.wasMouseReleased && state.activeButtonId == id) state.activeButtonId = null;

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(rect.x, rect.y, rect.width, rect.height, bg, cornerRadius: ui.style.frameRounding);
    dl.addRectOutline(rect.x, rect.y, rect.width, rect.height, ui.style.windowBorder, cornerRadius: ui.style.frameRounding);
    final textW = label.length * (ui.style.fontSize * 0.6);
    dl.addText(
      label,
      rect.x + math.max(4.0, (rect.width - textW) * 0.5),
      rect.y + (rect.height - ui.style.fontSize) * 0.5,
      color: ui.style.text,
      size: ui.style.fontSize,
    );
    return clicked;
  }

  static void render(
    VoxUiContext ui,
    DayNightSkyComponent dayNight, {
    WeatherVolumeComponent? weather,
    WeatherInspectorUiState? state,
    String title = 'Sky & Weather Inspector',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? WeatherInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final w = weather ?? dayNight._resolveWeather();
    final snap = w?.currentSnapshot;
    final elevDeg = ((dayNight.lastEphemeris?.sunElevationRadians ?? 0.0) * 180.0 / math.pi)
        .toStringAsFixed(1);

    ui.labelValue(
      'Clock / Day',
      '${dayNight.formattedTime} (${dayNight.period.name}) D${dayNight.dayCount}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Weather / Clouds',
      '${snap?.targetKind.name ?? "clear"} / ${((snap?.cloudCoverage01 ?? 0.0) * 100).round()}%',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Wetness / Snow',
      '${((snap?.wetness01 ?? 0.0) * 100).round()}% / ${((snap?.snowAccumulation01 ?? 0.0) * 100).round()}%',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Sun Alt / Wind',
      '$elevDeg° / ${(snap?.windSpeed ?? 0.0).toStringAsFixed(1)} m/s',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final hourRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'sky_hour', '+1 Hour', hourRect)) {
      dayNight.hours = dayNight.hours + 1.0;
    }

    if (w != null) {
      final clearRect = VoxRect(hourRect.right + 6.0, barY, 64.0, 22.0);
      if (_drawButton(ui, uiState, 'sky_clear', 'Clear', clearRect)) {
        w.setWeather(sky.WeatherKind.clear);
      }

      final stormRect = VoxRect(clearRect.right + 6.0, barY, 68.0, 22.0);
      if (_drawButton(ui, uiState, 'sky_storm', 'Storm', stormRect)) {
        w.setWeather(sky.WeatherKind.storm);
      }

      final snowRect = VoxRect(stormRect.right + 6.0, barY, 64.0, 22.0);
      if (_drawButton(ui, uiState, 'sky_snow', 'Snow', snowRect)) {
        w.setWeather(sky.WeatherKind.snow);
      }
    }

    ui.endWindow();
  }
}
