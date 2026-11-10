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
    register<AudioSource>(
      ComponentSpec<AudioSource>(
        'AudioSource',
        AudioSource.new,
        [
          Field.number('volume', (a) => a.volume, (a, v) => a.volume = v),
          Field.number('pitch', (a) => a.pitch, (a, v) => a.pitch = v),
          Field.boolean('loop', (a) => a.loop, (a, v) => a.loop = v),
          Field.boolean('playOnAwake', (a) => a.playOnAwake, (a, v) => a.playOnAwake = v),
        ],
      ),
    );
  }
}
