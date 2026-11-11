part of '../../engine.dart';

enum FieldKind {
  number,
  integer,
  boolean,
  text,
  vec3,
  quat,
  color,
  enumeration,
}

/// Strongly typed, zero-codegen field descriptor for a [Component] subclass [T].
final class Field<T extends Component, V> {
  final String name;
  final FieldKind kind;
  final V Function(T component) getter;
  final void Function(T component, V value) setter;
  final Object? Function(V value) toJson;
  final V Function(Object? raw) fromJson;

  const Field._({
    required this.name,
    required this.kind,
    required this.getter,
    required this.setter,
    required this.toJson,
    required this.fromJson,
  });

  Object? readJson(T component) => toJson(getter(component));

  void writeJson(T component, Object? raw) => setter(component, fromJson(raw));

  static Field<T, double> number<T extends Component>(
    String name,
    double Function(T) get,
    void Function(T, double) set,
  ) =>
      Field._(
        name: name,
        kind: FieldKind.number,
        getter: get,
        setter: set,
        toJson: (v) => v,
        fromJson: (raw) => (raw as num).toDouble(),
      );

  static Field<T, int> integer<T extends Component>(
    String name,
    int Function(T) get,
    void Function(T, int) set,
  ) =>
      Field._(
        name: name,
        kind: FieldKind.integer,
        getter: get,
        setter: set,
        toJson: (v) => v,
        fromJson: (raw) => (raw as num).toInt(),
      );

  static Field<T, bool> boolean<T extends Component>(
    String name,
    bool Function(T) get,
    void Function(T, bool) set,
  ) =>
      Field._(
        name: name,
        kind: FieldKind.boolean,
        getter: get,
        setter: set,
        toJson: (v) => v,
        fromJson: (raw) => raw as bool,
      );

  static Field<T, String> text<T extends Component>(
    String name,
    String Function(T) get,
    void Function(T, String) set,
  ) =>
      Field._(
        name: name,
        kind: FieldKind.text,
        getter: get,
        setter: set,
        toJson: (v) => v,
        fromJson: (raw) => raw as String,
      );

  static Field<T, Vec3> vec3<T extends Component>(
    String name,
    Vec3 Function(T) get,
    void Function(T, Vec3) set,
  ) =>
      Field._(
        name: name,
        kind: FieldKind.vec3,
        getter: get,
        setter: set,
        toJson: _vec3ToJson,
        fromJson: _vec3FromJson,
      );

  static Field<T, Quat> quat<T extends Component>(
    String name,
    Quat Function(T) get,
    void Function(T, Quat) set,
  ) =>
      Field._(
        name: name,
        kind: FieldKind.quat,
        getter: get,
        setter: set,
        toJson: _quatToJson,
        fromJson: _quatFromJson,
      );

  static Field<T, LinearColor> color<T extends Component>(
    String name,
    LinearColor Function(T) get,
    void Function(T, LinearColor) set,
  ) =>
      Field._(
        name: name,
        kind: FieldKind.color,
        getter: get,
        setter: set,
        toJson: _colorToJson,
        fromJson: _colorFromJson,
      );

  static Field<T, E> enumValue<T extends Component, E extends Enum>(
    String name,
    List<E> values,
    E Function(T) get,
    void Function(T, E) set,
  ) =>
      Field._(
        name: name,
        kind: FieldKind.enumeration,
        getter: get,
        setter: set,
        toJson: (v) => v.name,
        fromJson: (raw) => values.firstWhere((e) => e.name == raw),
      );
}

List<double> _vec3ToJson(Vec3 v) => [v.x, v.y, v.z];
Vec3 _vec3FromJson(Object? raw) {
  final list = raw as List<Object?>;
  return Vec3(
    (list[0] as num).toDouble(),
    (list[1] as num).toDouble(),
    (list[2] as num).toDouble(),
  );
}

List<double> _quatToJson(Quat q) => [q.x, q.y, q.z, q.w];
Quat _quatFromJson(Object? raw) {
  final list = raw as List<Object?>;
  return Quat(
    (list[0] as num).toDouble(),
    (list[1] as num).toDouble(),
    (list[2] as num).toDouble(),
    (list[3] as num).toDouble(),
  );
}

List<double> _colorToJson(LinearColor c) => [c.r, c.g, c.b];
LinearColor _colorFromJson(Object? raw) {
  final list = raw as List<Object?>;
  return LinearColor(
    (list[0] as num).toDouble(),
    (list[1] as num).toDouble(),
    (list[2] as num).toDouble(),
  );
}

/// Serialization and inspector schema for a [Component] type [T].
final class ComponentSpec<T extends Component> {
  final String typeName;
  final T Function() create;
  final List<Field<T, dynamic>> fields;

  const ComponentSpec(this.typeName, this.create, [this.fields = const []]);

  Type get componentType => T;

  Map<String, Object?> toJson(Component component) {
    final typed = component as T;
    return {
      'type': typeName,
      for (final f in fields) f.name: f.readJson(typed),
    };
  }

  void applyJson(Component component, Map<String, Object?> data) {
    final typed = component as T;
    for (final f in fields) {
      if (data.containsKey(f.name)) {
        f.writeJson(typed, data[f.name]);
      }
    }
  }
}

/// Maps component runtime types and type names to their [ComponentSpec]s.
final class ComponentRegistry {
  final Map<String, ComponentSpec<dynamic>> _byName = {};
  final Map<Type, ComponentSpec<dynamic>> _byType = {};

  ComponentRegistry({bool includeBuiltIns = true}) {
    if (includeBuiltIns) _registerBuiltIns();
  }

  factory ComponentRegistry.defaults() => ComponentRegistry();

  void register<T extends Component>(ComponentSpec<T> spec) {
    _byName[spec.typeName] = spec;
    _byType[T] = spec;
  }

  ComponentSpec<dynamic>? specByName(String typeName) => _byName[typeName];
  ComponentSpec<dynamic>? specFor(Component component) => _byType[component.runtimeType];

  /// All registered [ComponentSpec]s in registration order.
  Iterable<ComponentSpec<dynamic>> get registeredSpecs => _byName.values;

  void _registerBuiltIns() {
    register<Camera>(
      ComponentSpec<Camera>(
        'Camera',
        Camera.new,
        [
          Field.number('fovYRadians', (c) => c.fovYRadians, (c, v) => c.fovYRadians = v),
          Field.number('near', (c) => c.near, (c, v) => c.near = v),
          Field.number('far', (c) => c.far, (c, v) => c.far = v),
          Field.boolean('orthographic', (c) => c.orthographic, (c, v) => c.orthographic = v),
          Field.number('orthoHeight', (c) => c.orthoHeight, (c, v) => c.orthoHeight = v),
          Field.integer('cullingMask', (c) => c.cullingMask, (c, v) => c.cullingMask = v),
          Field.integer('depth', (c) => c.depth, (c, v) => c.depth = v),
        ],
      ),
    );
    register<Light>(
      ComponentSpec<Light>(
        'Light',
        Light.new,
        [
          Field.enumValue<Light, LightType>('lightType', LightType.values, (l) => l.type, (l, v) => l.type = v),
          Field.color('color', (l) => l.color, (l, v) => l.color = v),
          Field.number('intensity', (l) => l.intensity, (l, v) => l.intensity = v),
          Field.number('range', (l) => l.range, (l, v) => l.range = v),
          Field.number('innerSpotAngle', (l) => l.innerSpotAngle, (l, v) => l.innerSpotAngle = v),
          Field.number('spotAngle', (l) => l.spotAngle, (l, v) => l.spotAngle = v),
          Field.boolean('castsShadow', (l) => l.castsShadow, (l, v) => l.castsShadow = v),
        ],
      ),
    );
    register<SphereCollider>(
      ComponentSpec<SphereCollider>(
        'SphereCollider',
        SphereCollider.new,
        [
          Field.number('radius', (c) => c.radius, (c, v) => c.radius = v),
          Field.vec3('center', (c) => c.center, (c, v) => c.center = v),
          Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
          Field.integer('collidesWithMask', (c) => c.collidesWithMask, (c, v) => c.collidesWithMask = v),
        ],
      ),
    );
    register<BoxCollider>(
      ComponentSpec<BoxCollider>(
        'BoxCollider',
        BoxCollider.new,
        [
          Field.vec3('size', (c) => c.size, (c, v) => c.size = v),
          Field.vec3('center', (c) => c.center, (c, v) => c.center = v),
          Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
          Field.integer('collidesWithMask', (c) => c.collidesWithMask, (c, v) => c.collidesWithMask = v),
        ],
      ),
    );
    register<CapsuleCollider>(
      ComponentSpec<CapsuleCollider>(
        'CapsuleCollider',
        CapsuleCollider.new,
        [
          Field.number('radius', (c) => c.radius, (c, v) => c.radius = v),
          Field.number('height', (c) => c.height, (c, v) => c.height = v),
          Field.vec3('center', (c) => c.center, (c, v) => c.center = v),
          Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
          Field.integer('collidesWithMask', (c) => c.collidesWithMask, (c, v) => c.collidesWithMask = v),
        ],
      ),
    );
    register<AudioSource>(
      ComponentSpec<AudioSource>(
        'AudioSource',
        AudioSource.new,
        [
          Field.number('volume', (a) => a.volume, (a, v) => a.volume = v),
          Field.number('pitch', (a) => a.pitch, (a, v) => a.pitch = v),
          Field.boolean('loop', (a) => a.loop, (a, v) => a.loop = v),
          Field.boolean('playOnAwake', (a) => a.playOnAwake, (a, v) => a.playOnAwake = v),
          Field.text('bus', (a) => a.bus, (a, v) => a.bus = v),
          Field.number('spatialBlend', (a) => a.spatialBlend, (a, v) => a.spatialBlend = v),
          Field.number('minDistance', (a) => a.minDistance, (a, v) => a.minDistance = v),
          Field.number('maxDistance', (a) => a.maxDistance, (a, v) => a.maxDistance = v),
        ],
      ),
    );
    register<AudioListener>(
      ComponentSpec<AudioListener>(
        'AudioListener',
        AudioListener.new,
        [
          Field.number('volume', (a) => a.volume, (a, v) => a.volume = v),
        ],
      ),
    );
    register<AtmosphereVolume>(
      ComponentSpec<AtmosphereVolume>(
        'AtmosphereVolume',
        AtmosphereVolume.new,
        [
          Field.number('timeOfDayHours', (a) => a.timeOfDayHours, (a, v) => a.timeOfDayHours = v),
          Field.number('hoursPerSecond', (a) => a.hoursPerSecond, (a, v) => a.hoursPerSecond = v),
          Field.number('latitudeRadians', (a) => a.latitudeRadians, (a, v) => a.latitudeRadians = v),
          Field.number('solarDeclinationRadians', (a) => a.solarDeclinationRadians, (a, v) => a.solarDeclinationRadians = v),
          Field.number('cloudCoverage', (a) => a.cloudCoverage, (a, v) => a.cloudCoverage = v),
          Field.number('cloudDensity', (a) => a.cloudDensity, (a, v) => a.cloudDensity = v),
          Field.number('aerosolTurbidity', (a) => a.aerosolTurbidity, (a, v) => a.aerosolTurbidity = v),
          Field.number('fogStart', (a) => a.fogStart, (a, v) => a.fogStart = v),
          Field.number('fogEnd', (a) => a.fogEnd, (a, v) => a.fogEnd = v),
          Field.boolean('coherentHorizon', (a) => a.coherentHorizon, (a, v) => a.coherentHorizon = v),
        ],
      ),
    );
    register<Camera2DComponent>(
      ComponentSpec<Camera2DComponent>(
        'Camera2DComponent',
        Camera2DComponent.new,
        [
          Field.number('zoom', (c) => c.zoom, (c, v) => c.zoom = v),
          Field.number('rotation', (c) => c.rotation, (c, v) => c.rotation = v),
          Field.boolean('followTransform', (c) => c.followTransform, (c, v) => c.followTransform = v),
        ],
      ),
    );
    register<SpriteRenderer>(
      ComponentSpec<SpriteRenderer>(
        'SpriteRenderer',
        () => SpriteRenderer(region: SpriteRegion.white),
        [
          Field.number('rotation', (s) => s.rotation, (s, v) => s.rotation = v),
          Field.boolean('flipX', (s) => s.flipX, (s, v) => s.flipX = v),
          Field.boolean('flipY', (s) => s.flipY, (s, v) => s.flipY = v),
          Field.integer('color', (s) => s.color, (s, v) => s.color = v),
          Field.number('additive', (s) => s.additive, (s, v) => s.additive = v),
          Field.number('glow', (s) => s.glow, (s, v) => s.glow = v),
          Field.number('flash', (s) => s.flash, (s, v) => s.flash = v),
          Field.integer('layer', (s) => s.layer, (s, v) => s.layer = v),
        ],
      ),
    );
    register<PostProcessVolume>(PostProcessVolume.spec);
    register<UICanvas>(UICanvas.spec);
    register<DebugController>(DebugController.spec);
    register<SplineFollower>(
      ComponentSpec<SplineFollower>(
        'SplineFollower',
        () => SplineFollower(path: SplinePath.fromPoints(const [Vec3.zero, Vec3(0, 0, -5)])),
        [
          Field.number('speed', (s) => s.speed, (s, v) => s.speed = v),
          Field.number('distance', (s) => s.distance, (s, v) => s.distance = v),
          Field.boolean('alignToTangent', (s) => s.alignToTangent, (s, v) => s.alignToTangent = v),
          Field.vec3('localOffset', (s) => s.localOffset, (s, v) => s.localOffset = v),
        ],
      ),
    );
    register<SpriteAnimator>(
      ComponentSpec<SpriteAnimator>(
        'SpriteAnimator',
        () => SpriteAnimator(clips: {'idle': [SpriteRegion.white]}, initialClip: 'idle'),
        [
          Field.number('fps', (s) => s.fps, (s, v) => s.fps = v),
          Field.boolean('loop', (s) => s.loop, (s, v) => s.loop = v),
        ],
      ),
    );
    register<BuoyantBody>(
      ComponentSpec<BuoyantBody>(
        'BuoyantBody',
        BuoyantBody.new,
        const [],
      ),
    );
    register<RigidBody>(RigidBody.spec);
    register<CharacterController>(
      ComponentSpec<CharacterController>(
        'CharacterController',
        CharacterController.new,
        [
          Field.number('radius', (c) => c.radius, (c, v) => c.radius = v),
          Field.number('height', (c) => c.height, (c, v) => c.height = v),
          Field.vec3('center', (c) => c.center, (c, v) => c.center = v),
          Field.number('stepOffset', (c) => c.stepOffset, (c, v) => c.stepOffset = v),
          Field.number('slopeLimitDegrees', (c) => c.slopeLimitDegrees, (c, v) => c.slopeLimitDegrees = v),
          Field.boolean('useGravity', (c) => c.useGravity, (c, v) => c.useGravity = v),
          Field.vec3('gravity', (c) => c.gravity, (c, v) => c.gravity = v),
        ],
      ),
    );
    register<LineRenderer>(
      ComponentSpec<LineRenderer>(
        'LineRenderer',
        LineRenderer.new,
        [
          Field.number('startWidth', (l) => l.startWidth, (l, v) => l.startWidth = v),
          Field.number('endWidth', (l) => l.endWidth, (l, v) => l.endWidth = v),
          Field.color('color', (l) => l.color, (l, v) => l.color = v),
          Field.boolean('useWorldSpace', (l) => l.useWorldSpace, (l, v) => l.useWorldSpace = v),
        ],
      ),
    );
    register<TrailRenderer>(TrailRenderer.spec);
    register<NavAgent>(NavAgent.spec);
    register<LodGroup>(LodGroup.spec);
    register<Billboard>(Billboard.spec);
    register<Animator>(Animator.spec);
    register<WaterSurfaceComponent>(WaterSurfaceComponent.spec);
    register<SmoothFollowCamera>(SmoothFollowCamera.spec);
    register<CinematicTourCamera>(CinematicTourCamera.spec);
    register<VolumetricLightSource>(VolumetricLightSource.spec);
    register<ThermalSourceComponent>(ThermalSourceComponent.spec);
    register<PhysicsRaycaster>(PhysicsRaycaster.spec);
    register<ParallaxBackground2D>(ParallaxBackground2D.spec);
  }
}
