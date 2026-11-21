/// Volition Studio Nested Prefabs, Variant Chains & Prefab Mode Stage (`[S5-D]`):
/// Supports 2+ level nested prefab hierarchies with layered override precedence
/// (outermost wins), variant-of-variant chains, isolated Prefab Mode editing
/// with breadcrumbs, propagation, and broken-reference detection/repair.
library;

/// A single nested prefab asset node with optional parent variant & overrides.
final class NestedPrefabAsset {
  final String id;
  final String name;
  final String? basePrefabId;
  final Map<String, Object?> properties;
  final List<NestedPrefabChildRef> children;

  const NestedPrefabAsset({
    required this.id,
    required this.name,
    this.basePrefabId,
    this.properties = const {},
    this.children = const [],
  });

  NestedPrefabAsset copyWith({
    String? name,
    String? basePrefabId,
    Map<String, Object?>? properties,
    List<NestedPrefabChildRef>? children,
  }) => NestedPrefabAsset(
    id: id,
    name: name ?? this.name,
    basePrefabId: basePrefabId ?? this.basePrefabId,
    properties: properties ?? this.properties,
    children: children ?? this.children,
  );
}

/// Reference to a child prefab embedded inside a parent [NestedPrefabAsset],
/// carrying outermost overrides for that child instance.
final class NestedPrefabChildRef {
  final String instanceName;
  final String prefabId;
  final Map<String, Object?> overrides;

  const NestedPrefabChildRef({
    required this.instanceName,
    required this.prefabId,
    this.overrides = const {},
  });
}

/// Broken prefab reference diagnostic with repair helper.
final class BrokenPrefabReference {
  final String ownerPrefabId;
  final String childInstanceName;
  final String missingPrefabId;

  const BrokenPrefabReference({
    required this.ownerPrefabId,
    required this.childInstanceName,
    required this.missingPrefabId,
  });
}

/// Resolved flattened node produced by evaluating a [NestedPrefabAsset] tree.
final class ResolvedPrefabNode {
  final String name;
  final String prefabId;
  final Map<String, Object?> properties;
  final List<ResolvedPrefabNode> children;

  const ResolvedPrefabNode({
    required this.name,
    required this.prefabId,
    required this.properties,
    this.children = const [],
  });
}

/// Manages nested prefabs, variant chains, isolated Prefab Mode editing with
/// breadcrumbs, propagation, and broken-reference repair (`[S5-D]`).
final class PrefabModeStage {
  final Map<String, NestedPrefabAsset> _assets = {};
  final List<String> _breadcrumbs = [];
  NestedPrefabAsset? _workingCopy;

  void register(NestedPrefabAsset asset) => _assets[asset.id] = asset;
  NestedPrefabAsset? find(String id) => _assets[id];

  List<String> get breadcrumbs => List.unmodifiable(_breadcrumbs);
  bool get isInPrefabMode => _workingCopy != null;
  NestedPrefabAsset? get workingCopy => _workingCopy;

  /// Resolves a prefab (including variant-of-variant chains and nested
  /// children) with **outermost-wins** override precedence.
  ResolvedPrefabNode resolve(
    String prefabId, {
    Map<String, Object?> outerOverrides = const {},
    String? instanceName,
    Set<String>? visited,
  }) {
    final seen = visited ?? <String>{};
    if (!seen.add(prefabId)) {
      throw StateError('Circular prefab reference detected: $prefabId');
    }
    final asset = _assets[prefabId];
    if (asset == null) {
      throw StateError('Missing prefab asset: $prefabId');
    }

    // 1. Collect variant chain from base -> derived
    final mergedProps = <String, Object?>{};
    final mergedChildren = <String, NestedPrefabChildRef>{};
    if (asset.basePrefabId != null) {
      final base = resolve(asset.basePrefabId!, visited: Set<String>.of(seen));
      mergedProps.addAll(base.properties);
    }
    mergedProps.addAll(asset.properties);
    // Outermost overrides win!
    mergedProps.addAll(outerOverrides);

    for (final c in asset.children) {
      mergedChildren[c.instanceName] = c;
    }

    final resolvedChildren = <ResolvedPrefabNode>[];
    for (final c in mergedChildren.values) {
      if (!_assets.containsKey(c.prefabId)) continue;
      // Forward any nested dot-path overrides ("childName.prop") from outerOverrides
      final childOuter = <String, Object?>{...c.overrides};
      final prefix = '${c.instanceName}.';
      for (final e in outerOverrides.entries) {
        if (e.key.startsWith(prefix)) {
          childOuter[e.key.substring(prefix.length)] = e.value;
        }
      }
      resolvedChildren.add(
        resolve(
          c.prefabId,
          outerOverrides: childOuter,
          instanceName: c.instanceName,
          visited: Set<String>.of(seen),
        ),
      );
    }

    return ResolvedPrefabNode(
      name: instanceName ?? asset.name,
      prefabId: asset.id,
      properties: Map.unmodifiable(mergedProps),
      children: List.unmodifiable(resolvedChildren),
    );
  }

  /// Opens [prefabId] in isolated Prefab Mode, pushing onto [breadcrumbs].
  NestedPrefabAsset openPrefab(String prefabId) {
    final asset = _assets[prefabId];
    if (asset == null) throw StateError('Unknown prefab: $prefabId');
    _breadcrumbs.add(prefabId);
    _workingCopy = asset;
    return asset;
  }

  /// Edits a property on the currently open Prefab Mode working copy.
  void setWorkingProperty(String key, Object? value) {
    final wc = _workingCopy;
    if (wc == null) throw StateError('Not in Prefab Mode');
    final nextProps = Map<String, Object?>.of(wc.properties)..[key] = value;
    _workingCopy = wc.copyWith(properties: nextProps);
  }

  /// Saves the working copy back into the registry (propagating to all nested
  /// parents and variants) and pops the breadcrumb stack.
  NestedPrefabAsset saveAndExit() {
    final wc = _workingCopy;
    if (wc == null) throw StateError('Not in Prefab Mode');
    _assets[wc.id] = wc;
    if (_breadcrumbs.isNotEmpty) _breadcrumbs.removeLast();
    _workingCopy = _breadcrumbs.isEmpty ? null : _assets[_breadcrumbs.last];
    return wc;
  }

  /// Scans all registered prefabs for missing base or child references.
  List<BrokenPrefabReference> findBrokenReferences() {
    final broken = <BrokenPrefabReference>[];
    for (final asset in _assets.values) {
      if (asset.basePrefabId != null &&
          !_assets.containsKey(asset.basePrefabId)) {
        broken.add(
          BrokenPrefabReference(
            ownerPrefabId: asset.id,
            childInstanceName: '<base>',
            missingPrefabId: asset.basePrefabId!,
          ),
        );
      }
      for (final c in asset.children) {
        if (!_assets.containsKey(c.prefabId)) {
          broken.add(
            BrokenPrefabReference(
              ownerPrefabId: asset.id,
              childInstanceName: c.instanceName,
              missingPrefabId: c.prefabId,
            ),
          );
        }
      }
    }
    return broken;
  }

  /// Repairs a broken reference by remapping [missingPrefabId] to
  /// [replacementPrefabId].
  int repairBrokenReference(
    String missingPrefabId,
    String replacementPrefabId,
  ) {
    if (!_assets.containsKey(replacementPrefabId)) {
      throw ArgumentError(
        'Replacement prefab does not exist: $replacementPrefabId',
      );
    }
    var fixed = 0;
    for (final entry in _assets.entries.toList()) {
      final a = entry.value;
      var changed = false;
      var nextBase = a.basePrefabId;
      if (nextBase == missingPrefabId) {
        nextBase = replacementPrefabId;
        changed = true;
        fixed++;
      }
      final nextChildren = <NestedPrefabChildRef>[];
      for (final c in a.children) {
        if (c.prefabId == missingPrefabId) {
          nextChildren.add(
            NestedPrefabChildRef(
              instanceName: c.instanceName,
              prefabId: replacementPrefabId,
              overrides: c.overrides,
            ),
          );
          changed = true;
          fixed++;
        } else {
          nextChildren.add(c);
        }
      }
      if (changed) {
        _assets[entry.key] = a.copyWith(
          basePrefabId: nextBase,
          children: nextChildren,
        );
      }
    }
    return fixed;
  }
}
