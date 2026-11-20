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
      componentFieldOverrides: parsedComps.isEmpty
          ? const {}
          : Map.unmodifiable(parsedComps),
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
  GameObject applyToInstance(GameObject root, {ComponentRegistry? registry}) {
    _applyToInstanceInternal(root, registry: registry, deferRootActive: false);
    return root;
  }

  bool? _applyToInstanceInternal(
    GameObject root, {
    ComponentRegistry? registry,
    required bool deferRootActive,
  }) {
    final reg =
        registry ??
        (root.scene._engine?.registry ?? ComponentRegistry.defaults());
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
      final root = direct.instantiate(
        scene,
        parent: parent,
        position: position,
        rotation: rotation,
        scale: scale,
        name: name,
        active: active,
      );
      _ensureInstanceComponent(root, id);
      return root;
    }

    final chain = <PrefabVariant>[];
    final visited = <String>{};
    var currentId = id;
    Prefab? basePrefab;

    while (true) {
      if (!visited.add(currentId)) {
        throw StateError('PrefabVariant cycle detected involving "$currentId"');
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

    _ensureInstanceComponent(root, id);
    final finalActive = active && (rootActiveOverride ?? true);
    if (finalActive) root.setActive(true);
    return root;
  }

  static void _ensureInstanceComponent(GameObject root, String prefabId) {
    final existing = root.getComponent<PrefabInstanceComponent>();
    if (existing != null) {
      existing.prefabName = prefabId;
    } else {
      root.addComponent(PrefabInstanceComponent(prefabName: prefabId));
    }
  }

  /// Diffs [instance] against its registered baseline prefab/variant hierarchy
  /// and extracts per-node transform, activation, and component field overrides
  /// (P10-W18-C).
  List<PrefabNodeOverride> computeInstanceOverrides(
    GameObject instance, {
    String? basePrefabId,
    ComponentRegistry? registry,
  }) {
    final prefabId =
        basePrefabId ??
        instance.getComponent<PrefabInstanceComponent>()?.prefabName;
    if (prefabId == null || prefabId.isEmpty || !contains(prefabId)) {
      throw StateError(
        'Cannot compute overrides for "${instance.name}": unknown prefab id "$prefabId"',
      );
    }

    final reg =
        registry ??
        (instance.scene._engine?.registry ?? ComponentRegistry.defaults());
    final scratch = Scene('_prefab_diff_scratch');
    final baselineRoot = instantiate(scratch, prefabId, registry: reg);

    final overrides = <PrefabNodeOverride>[];
    const eps = 1e-5;

    bool vec3Differs(Vec3 a, Vec3 b) =>
        (a.x - b.x).abs() > eps ||
        (a.y - b.y).abs() > eps ||
        (a.z - b.z).abs() > eps;

    bool quatDiffers(Quat a, Quat b) {
      final dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
      return (1.0 - dot.abs()) > eps;
    }

    Map<String, Map<String, Object?>> diffComponents(
      GameObject actual,
      GameObject base,
    ) {
      final baseByType = <String, Map<String, Object?>>{};
      for (final c in base._components) {
        if (c is TransformComponent ||
            c is PrefabInstanceComponent ||
            c._destroyRequested) {
          continue;
        }
        final spec = reg.specFor(c);
        if (spec == null) continue;
        final data = spec.toJson(c);
        if (c is Behaviour) data['enabled'] = c.enabled;
        baseByType[spec.typeName] = data;
      }

      final result = <String, Map<String, Object?>>{};
      for (final c in actual._components) {
        if (c is TransformComponent ||
            c is PrefabInstanceComponent ||
            c._destroyRequested) {
          continue;
        }
        final spec = reg.specFor(c);
        if (spec == null) continue;
        final actualData = spec.toJson(c);
        if (c is Behaviour) actualData['enabled'] = c.enabled;
        final baseData = baseByType[spec.typeName];

        final changed = <String, Object?>{};
        for (final entry in actualData.entries) {
          if (entry.key == 'type') continue;
          final baseVal = baseData?[entry.key];
          if (baseData == null || !_jsonValuesEqual(entry.value, baseVal)) {
            changed[entry.key] = entry.value;
          }
        }
        if (changed.isNotEmpty) {
          result[spec.typeName] = changed;
        }
      }
      return result;
    }

    void walk(GameObject actual, GameObject base, String nodePath) {
      final posDiff = vec3Differs(
        actual.transform.localPosition,
        base.transform.localPosition,
      );
      final rotDiff = quatDiffers(
        actual.transform.localRotation,
        base.transform.localRotation,
      );
      final scaleDiff =
          (actual.transform.localScale - base.transform.localScale).abs() > eps;
      final activeDiff = actual.activeSelf != base.activeSelf;
      final compDiffs = diffComponents(actual, base);

      if (posDiff ||
          rotDiff ||
          scaleDiff ||
          activeDiff ||
          compDiffs.isNotEmpty) {
        overrides.add(
          PrefabNodeOverride(
            nodePath: nodePath,
            localPosition: posDiff ? actual.transform.localPosition : null,
            localRotation: rotDiff ? actual.transform.localRotation : null,
            localScale: scaleDiff ? actual.transform.localScale : null,
            active: activeDiff ? actual.activeSelf : null,
            componentFieldOverrides: compDiffs,
          ),
        );
      }

      for (final child in actual._children) {
        if (child._destroyRequested || child._destroyed) continue;
        GameObject? baseChild;
        for (final bc in base._children) {
          if (!bc._destroyRequested && bc.name == child.name) {
            baseChild = bc;
            break;
          }
        }
        if (baseChild != null) {
          final childPath = nodePath.isEmpty
              ? child.name
              : '$nodePath/${child.name}';
          walk(child, baseChild, childPath);
        }
      }
    }

    walk(instance, baselineRoot, '');
    return List.unmodifiable(overrides);
  }

  static bool _jsonValuesEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is num && b is num) {
      return (a.toDouble() - b.toDouble()).abs() <= 1e-5;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonValuesEqual(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_jsonValuesEqual(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }

  /// Extracts a reusable [PrefabVariant] from an edited in-scene [instance]
  /// by diffing it against its base prefab definition (P10-W18-C).
  PrefabVariant extractVariantFromInstance(
    String variantName,
    GameObject instance, {
    String? basePrefabId,
    ComponentRegistry? registry,
  }) {
    final resolvedBase =
        basePrefabId ??
        instance.getComponent<PrefabInstanceComponent>()?.prefabName;
    if (resolvedBase == null || resolvedBase.isEmpty) {
      throw StateError(
        'Cannot extract variant from "${instance.name}": no base prefab id',
      );
    }
    final overrides = computeInstanceOverrides(
      instance,
      basePrefabId: resolvedBase,
      registry: registry,
    );
    return PrefabVariant(
      name: variantName,
      basePrefabId: resolvedBase,
      overrides: overrides,
    );
  }

  /// Hot-propagates updated prefab/variant definitions for [id] to all live
  /// instances in [scene], preserving each instance's placement and overrides
  /// (P10-W18-C).
  int propagatePrefabChanges(
    Scene scene,
    String id, {
    ComponentRegistry? registry,
    Map<String, List<PrefabNodeOverride>>? preservedOverridesByObjectName,
  }) {
    if (!contains(id)) {
      throw ArgumentError('Unknown prefab or variant id "$id"');
    }

    final targets = <GameObject>[];
    void collect(GameObject go) {
      if (go._destroyRequested || go._destroyed) return;
      final inst = go.getComponent<PrefabInstanceComponent>();
      if (inst != null && inst.prefabName == id) {
        targets.add(go);
        return;
      }
      for (final child in go._children) {
        collect(child);
      }
    }

    for (final root in List.of(scene._roots)) {
      collect(root);
    }

    for (final instance in targets) {
      final savedName = instance.name;
      final savedTag = instance.tag;
      final savedLayer = instance.layer;
      final savedParent = instance.parent;
      final savedPos = instance.transform.localPosition;
      final savedRot = instance.transform.localRotation;
      final savedScale = instance.transform.localScale;
      final savedActive = instance.activeSelf;
      final instComp = instance.getComponent<PrefabInstanceComponent>();
      final savedPropOverrides = instComp == null
          ? const <PrefabOverride>[]
          : [
              for (final o in instComp.overrides)
                PrefabOverride(
                  propertyName: o.propertyName,
                  originalValue: o.originalValue,
                  overrideValue: o.overrideValue,
                ),
            ];
      final nodeOverrides = preservedOverridesByObjectName?[savedName];

      final fresh = instantiate(
        scene,
        id,
        parent: savedParent,
        position: savedPos,
        rotation: savedRot,
        scale: savedScale,
        name: savedName,
        active: savedActive,
        registry: registry,
      );
      fresh.tag = savedTag;
      fresh.layer = savedLayer;

      if (nodeOverrides != null && nodeOverrides.isNotEmpty) {
        PrefabVariant(
          name: '_propagated_overrides',
          basePrefabId: id,
          overrides: nodeOverrides,
        ).applyToInstance(fresh, registry: registry);
        final hasRootTransformOverride = nodeOverrides.any(
          (ov) =>
              (ov.nodePath.isEmpty || ov.nodePath == '.') &&
              (ov.localPosition != null ||
                  ov.localRotation != null ||
                  ov.localScale != null),
        );
        if (!hasRootTransformOverride) {
          fresh.transform
            ..localPosition = savedPos
            ..localRotation = savedRot
            ..localScale = savedScale;
        }
      }

      if (savedPropOverrides.isNotEmpty) {
        final freshInst = fresh.getComponent<PrefabInstanceComponent>();
        if (freshInst != null) {
          freshInst.overrides
            ..clear()
            ..addAll(savedPropOverrides);
          for (final o in savedPropOverrides) {
            if (o.propertyName == 'position' && o.overrideValue is Vec3) {
              fresh.transform.position = o.overrideValue as Vec3;
            } else if (o.propertyName == 'rotation' &&
                o.overrideValue is Quat) {
              fresh.transform.rotation = o.overrideValue as Quat;
            } else if (o.propertyName == 'scale' && o.overrideValue is double) {
              fresh.transform.localScale = o.overrideValue as double;
            }
          }
        }
      }

      instance.destroy();
    }

    scene._flushDestroyed();
    return targets.length;
  }

  /// Exports registered prefab metadata, variant definitions, and IDs as JSON.
  Map<String, Object?> exportManifestJson() {
    final prefabIds = _prefabs.keys.toList()..sort();
    final variantIds = _variants.keys.toList()..sort();
    return {
      'prefabs': {
        for (final id in prefabIds) id: {'name': _prefabs[id]!.name},
      },
      'variants': {for (final id in variantIds) id: _variants[id]!.toJson()},
      'registeredIds': registeredIds,
    };
  }
}
