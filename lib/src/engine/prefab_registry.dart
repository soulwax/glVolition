part of '../engine.dart';

/// Declarative per-node transform, activation, and component field overrides
/// applied by a [PrefabVariant] when instantiating a [Prefab] hierarchy (E98-1).
final class PrefabNodeOverride {
  /// Relative child path from the prefab root (`''` or `'.'` targets the root
  /// itself; `'Turret/Barrel'` targets a nested descendant by name).
  final String nodePath;

  final Vec3? localPosition;
  final Quat? localRotation;
  final double? localScale;
  final bool? active;

  /// Maps `ComponentSpec.typeName` -> `{fieldName: jsonValue}`.
  final Map<String, Map<String, Object?>> componentFieldOverrides;

  const PrefabNodeOverride({
    this.nodePath = '',
    this.localPosition,
    this.localRotation,
    this.localScale,
    this.active,
    this.componentFieldOverrides = const {},
  });

  Map<String, Object?> toJson() => {
        'nodePath': nodePath,
        if (localPosition != null) 'localPosition': _vec3ToJson(localPosition!),
        if (localRotation != null) 'localRotation': _quatToJson(localRotation!),
        if (localScale != null) 'localScale': localScale,
        if (active != null) 'active': active,
        if (componentFieldOverrides.isNotEmpty)
          'componentFieldOverrides': {
            for (final entry in componentFieldOverrides.entries)
              entry.key: Map<String, Object?>.from(entry.value),
          },
      };

  factory PrefabNodeOverride.fromJson(Map<String, Object?> json) {
    final rawComps = json['componentFieldOverrides'];
    final parsedComps = <String, Map<String, Object?>>{};
    if (rawComps is Map) {
      for (final entry in rawComps.entries) {
        final key = entry.key;
        final val = entry.value;
        if (key is String && val is Map) {
          parsedComps[key] = Map<String, Object?>.unmodifiable(
            Map<String, Object?>.from(val),
          );
        }
      }
    }
    return PrefabNodeOverride(
      nodePath: (json['nodePath'] as String?) ?? '',
      localPosition: json['localPosition'] != null
          ? _vec3FromJson(json['localPosition'])
          : null,
      localRotation: json['localRotation'] != null
          ? _quatFromJson(json['localRotation'])
          : null,
      localScale: (json['localScale'] as num?)?.toDouble(),
      active: json['active'] as bool?,
      componentFieldOverrides:
          parsedComps.isEmpty ? const {} : Map.unmodifiable(parsedComps),
    );
  }
}

/// A named variant layered on top of a base [Prefab] or another [PrefabVariant]
/// via [PrefabNodeOverride] deltas (E98-1).
final class PrefabVariant {
  final String name;
  final String basePrefabId;
  final List<PrefabNodeOverride> overrides;

  const PrefabVariant({
    required this.name,
    required this.basePrefabId,
    this.overrides = const [],
  });

  /// Applies all [overrides] to an instantiated [root] hierarchy in order.
  GameObject applyToInstance(
    GameObject root, {
    ComponentRegistry? registry,
  }) {
    _applyToInstanceInternal(root, registry: registry, deferRootActive: false);
    return root;
  }

  bool? _applyToInstanceInternal(
    GameObject root, {
    ComponentRegistry? registry,
    required bool deferRootActive,
  }) {
    final reg =
        registry ?? (root.scene._engine?.registry ?? ComponentRegistry.defaults());
    bool? rootActiveOverride;

    for (final ov in overrides) {
      final target = _resolveNode(root, ov.nodePath);
      if (target == null) continue;

      if (ov.localPosition != null) {
        target.transform.localPosition = ov.localPosition!;
      }
      if (ov.localRotation != null) {
        target.transform.localRotation = ov.localRotation!;
      }
      if (ov.localScale != null) {
        target.transform.localScale = ov.localScale!;
      }

      if (ov.componentFieldOverrides.isNotEmpty) {
        for (final entry in ov.componentFieldOverrides.entries) {
          final typeName = entry.key;
          final fieldMap = entry.value;
          final spec = reg.specByName(typeName);
          if (spec == null) continue;

          Component? existing;
          for (final c in target._components) {
            if (!c._destroyRequested && c.runtimeType == spec.componentType) {
              existing = c;
              break;
            }
          }
          final component = existing ?? target.addComponent(spec.create());
          spec.applyJson(component, fieldMap);
          if (component is Behaviour && fieldMap['enabled'] is bool) {
            component.enabled = fieldMap['enabled'] as bool;
          }
        }
      }

      if (ov.active != null) {
        if (deferRootActive && identical(target, root)) {
          rootActiveOverride = ov.active;
        } else {
          target.setActive(ov.active!);
        }
      }
    }

    return rootActiveOverride;
  }

  static GameObject? _resolveNode(GameObject root, String nodePath) {
    final trimmed = nodePath.trim();
    if (trimmed.isEmpty || trimmed == '.') return root;
    GameObject? current = root;
    for (final segment in trimmed.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      current = current?._children
          .where((c) => c.name == segment && !c._destroyRequested)
          .firstOrNull;
      if (current == null) return null;
    }
    return current;
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'basePrefabId': basePrefabId,
        'overrides': [for (final ov in overrides) ov.toJson()],
      };

  factory PrefabVariant.fromJson(Map<String, Object?> json) {
    final rawOverrides = json['overrides'];
    final parsed = <PrefabNodeOverride>[];
    if (rawOverrides is List) {
      for (final item in rawOverrides) {
        if (item is Map<String, Object?>) {
          parsed.add(PrefabNodeOverride.fromJson(item));
        } else if (item is Map) {
          parsed.add(
            PrefabNodeOverride.fromJson(Map<String, Object?>.from(item)),
          );
        }
      }
    }
    return PrefabVariant(
      name: (json['name'] as String?) ?? 'Variant',
      basePrefabId: (json['basePrefabId'] as String?) ?? '',
      overrides: List.unmodifiable(parsed),
    );
  }
}

/// Central catalog for named [Prefab]s and layered [PrefabVariant]s (E98-1).
final class PrefabRegistry {
  static const int _maxVariantDepth = 8;

  final Map<String, Prefab> _prefabs = {};
  final Map<String, PrefabVariant> _variants = {};

  void register(String id, Prefab prefab) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Prefab id must not be empty');
    }
    _variants.remove(id);
    _prefabs[id] = prefab;
  }

  void registerVariant(String id, PrefabVariant variant) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Variant id must not be empty');
    }
    _prefabs.remove(id);
    _variants[id] = variant;
  }

  bool contains(String id) =>
      _prefabs.containsKey(id) || _variants.containsKey(id);

  Prefab? findPrefab(String id) => _prefabs[id];

  PrefabVariant? findVariant(String id) => _variants[id];

  /// Sorted, unmodifiable list of all registered prefab and variant IDs.
  List<String> get registeredIds {
    final ids = <String>{..._prefabs.keys, ..._variants.keys}.toList()..sort();
    return List.unmodifiable(ids);
  }

  /// Instantiates either a direct [Prefab] or a [PrefabVariant] chain in
  /// [scene], enforcing cycle detection and a max variant depth of 8.
  GameObject instantiate(
    Scene scene,
    String id, {
    GameObject? parent,
    Vec3? position,
    Quat? rotation,
    double? scale,
    String? name,
    bool active = true,
    ComponentRegistry? registry,
  }) {
    final direct = _prefabs[id];
    if (direct != null) {
      return direct.instantiate(
        scene,
        parent: parent,
        position: position,
        rotation: rotation,
        scale: scale,
        name: name,
        active: active,
      );
    }

    final chain = <PrefabVariant>[];
    final visited = <String>{};
    var currentId = id;
    Prefab? basePrefab;

    while (true) {
      if (!visited.add(currentId)) {
        throw StateError(
          'PrefabVariant cycle detected involving "$currentId"',
        );
      }
      final prefab = _prefabs[currentId];
      if (prefab != null) {
        basePrefab = prefab;
        break;
      }
      final variant = _variants[currentId];
      if (variant == null) {
        throw ArgumentError('Unknown prefab or variant id "$currentId"');
      }
      if (chain.length >= _maxVariantDepth) {
        throw StateError(
          'PrefabVariant inheritance depth exceeded $_maxVariantDepth starting at "$id"',
        );
      }
      chain.add(variant);
      currentId = variant.basePrefabId;
    }

    final root = basePrefab.instantiate(
      scene,
      parent: parent,
      name: name ?? chain.first.name,
      active: false,
    );

    bool? rootActiveOverride;
    for (final variant in chain.reversed) {
      final ovActive = variant._applyToInstanceInternal(
        root,
        registry: registry,
        deferRootActive: true,
      );
      if (ovActive != null) {
        rootActiveOverride = ovActive;
      }
    }

    if (position != null) root.transform.localPosition = position;
    if (rotation != null) root.transform.localRotation = rotation;
    if (scale != null) root.transform.localScale = scale;

    final finalActive = active && (rootActiveOverride ?? true);
    if (finalActive) root.setActive(true);
    return root;
  }

  /// Exports registered prefab metadata, variant definitions, and IDs as JSON.
  Map<String, Object?> exportManifestJson() {
    final prefabIds = _prefabs.keys.toList()..sort();
    final variantIds = _variants.keys.toList()..sort();
    return {
      'prefabs': {
        for (final id in prefabIds) id: {'name': _prefabs[id]!.name},
      },
      'variants': {
        for (final id in variantIds) id: _variants[id]!.toJson(),
      },
      'registeredIds': registeredIds,
    };
  }
}
