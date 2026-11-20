part of '../../engine.dart';

/// Identifies the expected root structure when validating a scene or prefab
/// payload in [SceneMigrator].
enum ScenePayloadKind { scene, prefab }

/// Single forward schema upgrade step operating on deep-copied scene or prefab
/// JSON maps.
abstract interface class SceneMigrationStep {
  int get fromVersion;
  int get toVersion;
  Map<String, Object?> migrate(Map<String, Object?> data);
}

/// Outcome returned by [SceneMigrator.migrate].
final class SceneMigrationResult {
  final Map<String, Object?> data;
  final int fromVersion;
  final int toVersion;
  final List<String> appliedSteps;
  final List<String> warnings;

  const SceneMigrationResult({
    required this.data,
    required this.fromVersion,
    required this.toVersion,
    this.appliedSteps = const [],
    this.warnings = const [],
  });

  bool get didMigrate => fromVersion != toVersion;
}

/// Built-in v1 -> v2 normalization step for scenes and prefabs.
///
/// Losslessly normalizes legacy transform aliases (`position`/`pos`,
/// `rotation`/`rot`, `scale`) and backfills missing canonical v2 defaults on
/// `renderSettings` (including `post`) and non-override GameObject nodes.
final class SceneV1ToV2MigrationStep implements SceneMigrationStep {
  const SceneV1ToV2MigrationStep();

  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  Map<String, Object?> migrate(Map<String, Object?> data) {
    if (data.containsKey('objects')) {
      _migrateSceneV1ToV2(data);
    } else if (_looksLikeNodePayload(data)) {
      _normalizeNodeV1ToV2(data, path: 'prefab', allowPrefabOverride: false);
    }
    data['schemaVersion'] = toVersion;
    return data;
  }

  static bool _looksLikeNodePayload(Map<String, Object?> data) =>
      data.containsKey('name') ||
      data.containsKey('tag') ||
      data.containsKey('layer') ||
      data.containsKey('active') ||
      data.containsKey('transform') ||
      data.containsKey('components') ||
      data.containsKey('children');

  static void _migrateSceneV1ToV2(Map<String, Object?> data) {
    final nameRaw = data['name'];
    if (nameRaw == null) {
      data['name'] = 'Scene';
    } else if (nameRaw is! String) {
      throw FormatException(
        'Invalid scene "name": expected String, got ${nameRaw.runtimeType}',
      );
    }

    final rsRaw = data['renderSettings'];
    if (rsRaw == null) {
      data['renderSettings'] = _defaultRenderSettingsJson();
    } else if (rsRaw is Map<String, Object?>) {
      _normalizeRenderSettings(rsRaw);
    } else {
      throw FormatException(
        'Invalid scene "renderSettings": expected Map, got ${rsRaw.runtimeType}',
      );
    }

    final objectsRaw = data['objects'];
    if (objectsRaw is! List<Object?>) {
      throw FormatException(
        'Invalid scene "objects": expected List, got ${objectsRaw.runtimeType}',
      );
    }
    for (var i = 0; i < objectsRaw.length; i++) {
      final entry = objectsRaw[i];
      if (entry is! Map<String, Object?>) {
        throw FormatException(
          'Invalid node at objects[$i]: expected Map, got ${entry.runtimeType}',
        );
      }
      _normalizeNodeV1ToV2(
        entry,
        path: 'objects[$i]',
        allowPrefabOverride: true,
      );
    }
  }

  static void _normalizeRenderSettings(Map<String, Object?> rsMap) {
    final defaults = _defaultRenderSettingsJson();
    for (final entry in defaults.entries) {
      if (entry.key == 'post') continue;
      if (!rsMap.containsKey(entry.key) || rsMap[entry.key] == null) {
        rsMap[entry.key] = entry.value;
      }
    }

    final postRaw = rsMap['post'];
    if (postRaw == null) {
      rsMap['post'] = defaults['post'];
    } else if (postRaw is Map<String, Object?>) {
      final postDefaults = defaults['post']! as Map<String, Object?>;
      for (final entry in postDefaults.entries) {
        if (!postRaw.containsKey(entry.key) || postRaw[entry.key] == null) {
          postRaw[entry.key] = entry.value;
        }
      }
    } else {
      throw FormatException(
        'Invalid "renderSettings.post": expected Map, got ${postRaw.runtimeType}',
      );
    }
  }

  static Map<String, Object?> _defaultRenderSettingsJson() {
    final rs = RenderSettings();
    return <String, Object?>{
      'clearColor': _colorToJson(rs.clearColor),
      'ambientColor': _colorToJson(rs.ambientColor),
      'ambientIntensity': rs.ambientIntensity,
      'reflectionColor': _colorToJson(rs.reflectionColor),
      'reflectionIntensity': rs.reflectionIntensity,
      'reflectionConfidence': rs.reflectionConfidence,
      'fogEnabled': rs.fogEnabled,
      'fogColor': _colorToJson(rs.fogColor),
      'fogStart': rs.fogStart,
      'fogEnd': rs.fogEnd,
      'shadowFilterRadius': rs.shadowFilterRadius,
      'shadowBias': rs.shadowBias,
      'ambientLightScale': rs.ambientLightScale,
      'directLightScale': rs.directLightScale,
      'post': SceneSerializer._postToJson(rs.post),
    };
  }

  static void _normalizeNodeV1ToV2(
    Map<String, Object?> node, {
    required String path,
    required bool allowPrefabOverride,
  }) {
    final prefabKey = node['prefab'];
    final isPrefabOverride = allowPrefabOverride && prefabKey != null;

    if (!isPrefabOverride) {
      if (!node.containsKey('tag') || node['tag'] == null) {
        node['tag'] = 'Untagged';
      }
      if (!node.containsKey('layer') || node['layer'] == null) {
        node['layer'] = 0;
      }
      if (!node.containsKey('active') || node['active'] == null) {
        node['active'] = true;
      }
    }

    final tRaw = node['transform'];
    if (tRaw == null) {
      if (!isPrefabOverride) {
        node['transform'] = <String, Object?>{
          'p': <Object?>[0.0, 0.0, 0.0],
          'r': <Object?>[0.0, 0.0, 0.0, 1.0],
          's': 1.0,
          'stretch': <Object?>[1.0, 1.0, 1.0],
        };
      }
    } else if (tRaw is Map<String, Object?>) {
      _normalizeTransform(tRaw, backfillDefaults: !isPrefabOverride);
    } else {
      throw FormatException(
        'Invalid "$path.transform": expected Map, got ${tRaw.runtimeType}',
      );
    }

    if (!node.containsKey('components') || node['components'] == null) {
      node['components'] = <Object?>[];
    } else if (node['components'] is! List<Object?>) {
      throw FormatException(
        'Invalid "$path.components": expected List, got ${node['components'].runtimeType}',
      );
    }

    final childrenRaw = node['children'];
    if (childrenRaw == null) {
      node['children'] = <Object?>[];
    } else if (childrenRaw is List<Object?>) {
      for (var i = 0; i < childrenRaw.length; i++) {
        final child = childrenRaw[i];
        if (child is! Map<String, Object?>) {
          throw FormatException(
            'Invalid node at $path.children[$i]: expected Map, got ${child.runtimeType}',
          );
        }
        _normalizeNodeV1ToV2(
          child,
          path: '$path.children[$i]',
          allowPrefabOverride: true,
        );
      }
    } else {
      throw FormatException(
        'Invalid "$path.children": expected List, got ${childrenRaw.runtimeType}',
      );
    }
  }

  static void _normalizeTransform(
    Map<String, Object?> tMap, {
    required bool backfillDefaults,
  }) {
    _promoteAlias(tMap, const ['position', 'pos'], 'p');
    _promoteAlias(tMap, const ['rotation', 'rot'], 'r');
    _promoteAlias(tMap, const ['scale'], 's');

    if (backfillDefaults) {
      if (!tMap.containsKey('p') || tMap['p'] == null) {
        tMap['p'] = <Object?>[0.0, 0.0, 0.0];
      }
      if (!tMap.containsKey('r') || tMap['r'] == null) {
        tMap['r'] = <Object?>[0.0, 0.0, 0.0, 1.0];
      }
      if (!tMap.containsKey('s') || tMap['s'] == null) {
        tMap['s'] = 1.0;
      }
      if (!tMap.containsKey('stretch') || tMap['stretch'] == null) {
        tMap['stretch'] = <Object?>[1.0, 1.0, 1.0];
      }
    }
  }

  static void _promoteAlias(
    Map<String, Object?> map,
    List<String> legacyKeys,
    String canonicalKey,
  ) {
    for (final legacy in legacyKeys) {
      if (map.containsKey(legacy)) {
        final legacyVal = map.remove(legacy);
        if (!map.containsKey(canonicalKey) || map[canonicalKey] == null) {
          map[canonicalKey] = legacyVal;
        }
      }
    }
  }
}

/// Injectable path/key-to-GUID resolver used by [SceneV2ToV3GuidMigrationStep]
/// so `lib/src/engine` stays decoupled from `lib/src/studio` (`[S1-M]`).
typedef AssetGuidResolver = String? Function(String pathOrKey);

/// Built-in v2 -> v3 migration step converting legacy string asset path/key
/// fields in component payloads into [AssetRef] (`{"$assetGuid": "..."}`)
/// objects when [guidResolver] resolves a GUID.
final class SceneV2ToV3GuidMigrationStep implements SceneMigrationStep {
  static const Set<String> defaultAssetFieldKeys = {
    'mesh',
    'material',
    'texture',
    'albedo',
    'audio',
    'clip',
    'lut',
    'assetPath',
    'meshPath',
    'materialPath',
    'texturePath',
  };

  final AssetGuidResolver? guidResolver;
  final Set<String> assetFieldKeys;

  const SceneV2ToV3GuidMigrationStep({
    this.guidResolver,
    this.assetFieldKeys = defaultAssetFieldKeys,
  });

  @override
  int get fromVersion => 2;

  @override
  int get toVersion => 3;

  @override
  Map<String, Object?> migrate(Map<String, Object?> data) {
    final resolver = guidResolver;
    if (resolver != null) {
      if (data['objects'] is List) {
        for (final node in data['objects']! as List) {
          if (node is Map<String, Object?>) {
            _rewriteNodeAssets(node, resolver);
          }
        }
      } else if (data.containsKey('components') ||
          data.containsKey('children')) {
        _rewriteNodeAssets(data, resolver);
      }
    }
    data['schemaVersion'] = toVersion;
    return data;
  }

  void _rewriteNodeAssets(
    Map<String, Object?> node,
    AssetGuidResolver resolver,
  ) {
    final comps = node['components'];
    if (comps is List) {
      for (final comp in comps) {
        if (comp is Map<String, Object?>) {
          _rewriteMapFields(comp, resolver);
          final dataMap = comp['data'];
          if (dataMap is Map<String, Object?>) {
            _rewriteMapFields(dataMap, resolver);
          }
        }
      }
    }
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map<String, Object?>) {
          _rewriteNodeAssets(child, resolver);
        }
      }
    }
  }

  void _rewriteMapFields(Map<String, Object?> map, AssetGuidResolver resolver) {
    for (final key in map.keys.toList()) {
      if (!assetFieldKeys.contains(key)) continue;
      final val = map[key];
      if (val is String && val.isNotEmpty) {
        final guid = resolver(val);
        if (guid != null && guid.isNotEmpty) {
          map[key] = AssetRef(guid).toJson();
        }
      }
    }
  }
}

/// Validates and executes chained [SceneMigrationStep] upgrades from legacy
/// schema versions up to [currentVersion] without mutating input payloads.
final class SceneMigrator {
  /// Default built-in migration steps upgrading legacy schemas to
  /// [SceneSerializer.schemaVersion].
  static const List<SceneMigrationStep> defaultSteps = [
    SceneV1ToV2MigrationStep(),
    SceneV2ToV3GuidMigrationStep(),
  ];

  /// Creates a [SceneMigrator] wired with [guidResolver] for v2->v3 GUID
  /// asset reference conversion.
  factory SceneMigrator.withGuidResolver(AssetGuidResolver guidResolver) =>
      SceneMigrator(
        currentVersion: SceneSerializer.schemaVersion,
        steps: [
          const SceneV1ToV2MigrationStep(),
          SceneV2ToV3GuidMigrationStep(guidResolver: guidResolver),
        ],
        validateStructure: true,
      );

  final int currentVersion;
  final List<SceneMigrationStep> _steps;
  final bool _validateStructure;

  SceneMigrator({
    this.currentVersion = SceneSerializer.schemaVersion,
    List<SceneMigrationStep> steps = defaultSteps,
    bool? validateStructure,
  }) : _steps = List<SceneMigrationStep>.of(steps),
       _validateStructure =
           validateStructure ?? identical(steps, defaultSteps) {
    if (currentVersion < 0) {
      throw ArgumentError.value(
        currentVersion,
        'currentVersion',
        'must be non-negative',
      );
    }
  }

  List<SceneMigrationStep> get steps =>
      List<SceneMigrationStep>.unmodifiable(_steps);

  /// Decodes [json] and verifies that the root JSON value is an object map.
  static Map<String, Object?> decodeJsonObject(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) {
      throw FormatException(
        'Expected JSON object map, got ${decoded.runtimeType}',
      );
    }
    return deepCopyMap(decoded);
  }

  /// Recursively clones [source] and verifies all map keys are [String]s.
  static Map<String, Object?> deepCopyMap(
    Map<Object?, Object?> source, {
    String path = 'root',
  }) {
    final copy = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (key is! String) {
        throw FormatException(
          'Corrupted JSON at $path: expected String key, got ${key.runtimeType}',
        );
      }
      copy[key] = _deepCopyValue(entry.value, path: '$path.$key');
    }
    return copy;
  }

  static List<Object?> _deepCopyList(
    List<Object?> source, {
    required String path,
  }) {
    final copy = <Object?>[];
    for (var i = 0; i < source.length; i++) {
      copy.add(_deepCopyValue(source[i], path: '$path[$i]'));
    }
    return copy;
  }

  static Object? _deepCopyValue(Object? value, {required String path}) {
    if (value is Map) {
      return deepCopyMap(value, path: path);
    }
    if (value is List) {
      return _deepCopyList(value, path: path);
    }
    return value;
  }

  /// Validates [input]'s schema envelope, deep-copies it, executes sequential
  /// [steps] up to [currentVersion], and optionally validates the resulting
  /// scene/prefab structural integrity.
  SceneMigrationResult migrate(
    Object? input, {
    ScenePayloadKind? kind,
    bool? validateStructure,
  }) {
    if (input is! Map) {
      throw FormatException(
        'Expected JSON object map, got ${input.runtimeType}',
      );
    }

    var current = deepCopyMap(input);
    final startVersion = _validateSchemaVersion(current['schemaVersion']);
    if (startVersion > currentVersion) {
      throw FormatException(
        'Unsupported future scene schemaVersion: $startVersion '
        '(max supported: $currentVersion)',
      );
    }

    var version = startVersion;
    final applied = <String>[];
    final warnings = <String>[];

    while (version < currentVersion) {
      SceneMigrationStep? match;
      for (final step in _steps) {
        if (step.fromVersion != version) continue;
        if (step.toVersion <= version) {
          throw FormatException(
            'Invalid migration step v${step.fromVersion}->v${step.toVersion}: '
            'toVersion must be greater than fromVersion',
          );
        }
        if (step.toVersion > currentVersion) continue;
        match = step;
        break;
      }
      if (match == null) {
        throw FormatException(
          'Missing migration path from schemaVersion $version to $currentVersion',
        );
      }
      current = deepCopyMap(match.migrate(current));
      version = match.toVersion;
      current['schemaVersion'] = version;
      applied.add('v${match.fromVersion}->v${match.toVersion}');
    }

    final shouldValidate =
        validateStructure ?? (kind != null || _validateStructure);
    if (shouldValidate) {
      _validatePayloadInternal(current, kind: kind);
    }

    return SceneMigrationResult(
      data: current,
      fromVersion: startVersion,
      toVersion: version,
      appliedSteps: List<String>.unmodifiable(applied),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static int _validateSchemaVersion(Object? versionRaw) {
    if (versionRaw == null) {
      throw const FormatException('Missing required "schemaVersion" field');
    }
    if (versionRaw is! int) {
      throw FormatException(
        'Invalid "schemaVersion": expected integer, got '
        '${versionRaw.runtimeType} ($versionRaw)',
      );
    }
    if (versionRaw < 0) {
      throw FormatException(
        'Invalid "schemaVersion": expected non-negative integer, got $versionRaw',
      );
    }
    return versionRaw;
  }

  /// Validates structural integrity of a migrated scene or prefab map.
  static void validatePayload(
    Map<String, Object?> data, {
    ScenePayloadKind? kind,
  }) => _validatePayloadInternal(deepCopyMap(data), kind: kind);

  static void _validatePayloadInternal(
    Map<String, Object?> data, {
    ScenePayloadKind? kind,
  }) {
    _validateSchemaVersion(data['schemaVersion']);

    final resolvedKind = switch (kind) {
      ScenePayloadKind.scene => ScenePayloadKind.scene,
      ScenePayloadKind.prefab => ScenePayloadKind.prefab,
      null =>
        data.containsKey('objects')
            ? ScenePayloadKind.scene
            : data.containsKey('name')
            ? ScenePayloadKind.prefab
            : throw const FormatException(
                'Corrupted payload: missing required structural fields '
                '("objects" for a scene or "name" for a prefab)',
              ),
    };

    switch (resolvedKind) {
      case ScenePayloadKind.scene:
        _validateScenePayload(data);
      case ScenePayloadKind.prefab:
        _validatePrefabPayload(data);
    }
  }

  static void _validateScenePayload(Map<String, Object?> data) {
    if (data.containsKey('name') &&
        data['name'] != null &&
        data['name'] is! String) {
      throw FormatException(
        'Invalid scene "name": expected String, got ${data['name'].runtimeType}',
      );
    }
    if (!data.containsKey('objects') || data['objects'] == null) {
      throw const FormatException(
        'Invalid scene payload: missing required "objects" list',
      );
    }
    final objects = data['objects'];
    if (objects is! List<Object?>) {
      throw FormatException(
        'Invalid scene "objects": expected List, got ${objects.runtimeType}',
      );
    }

    if (data.containsKey('renderSettings') && data['renderSettings'] != null) {
      final rs = data['renderSettings'];
      if (rs is! Map<String, Object?>) {
        throw FormatException(
          'Invalid scene "renderSettings": expected Map, got ${rs.runtimeType}',
        );
      }
      _validateRenderSettings(rs);
    }

    for (var i = 0; i < objects.length; i++) {
      _validateNode(
        objects[i],
        path: 'objects[$i]',
        allowPrefabReference: true,
        requireNameWhenNoPrefab: true,
      );
    }
  }

  static void _validatePrefabPayload(Map<String, Object?> data) {
    if (data.containsKey('objects')) {
      throw const FormatException(
        'Invalid prefab payload: unexpected scene "objects" field',
      );
    }
    if (!data.containsKey('name') || data['name'] is! String) {
      throw FormatException(
        'Invalid prefab payload: missing or non-String "name" field',
      );
    }
    _validateNode(
      data,
      path: 'prefab',
      allowPrefabReference: false,
      requireNameWhenNoPrefab: true,
    );
  }

  static void _validateRenderSettings(Map<String, Object?> rsMap) {
    const colorKeys = [
      'clearColor',
      'ambientColor',
      'reflectionColor',
      'fogColor',
    ];
    for (final key in colorKeys) {
      if (rsMap.containsKey(key) && rsMap[key] != null) {
        _requireNumList(rsMap[key], 3, 'renderSettings.$key');
      }
    }

    const numKeys = [
      'ambientIntensity',
      'reflectionIntensity',
      'reflectionConfidence',
      'fogStart',
      'fogEnd',
      'fogHeightFalloff',
      'fogDensity',
      'shadowFilterRadius',
      'shadowBias',
      'ambientLightScale',
      'directLightScale',
    ];
    for (final key in numKeys) {
      final val = rsMap[key];
      if (val != null && val is! num) {
        throw FormatException(
          'Invalid "renderSettings.$key": expected num, got ${val.runtimeType}',
        );
      }
    }

    final fogEnabled = rsMap['fogEnabled'];
    if (fogEnabled != null && fogEnabled is! bool) {
      throw FormatException(
        'Invalid "renderSettings.fogEnabled": expected bool, got ${fogEnabled.runtimeType}',
      );
    }

    final post = rsMap['post'];
    if (post != null) {
      if (post is! Map<String, Object?>) {
        throw FormatException(
          'Invalid "renderSettings.post": expected Map, got ${post.runtimeType}',
        );
      }
      _validatePostProcess(post);
    }
  }

  static void _validatePostProcess(Map<String, Object?> post) {
    const numKeys = [
      'exposure',
      'bloomStrength',
      'ssaoStrength',
      'depthOfFieldStrength',
      'vignette',
      'grain',
      'rainIntensity',
      'surfaceWetness',
      'surfaceSnowCoverage',
      'surfaceDissolution',
      'rainWindowVisibility',
      'ditherStrength',
      'colorGradeStrength',
      'affineWarpStrength',
      'vertexSnapGrid',
      'quantizationBits',
      'vhsChromaWeight',
      'vhsTrackingWeight',
      'vhsNoiseWeight',
      'vhsHeadSwitchWeight',
      'vhsDropoutWeight',
      'vhsGhostWeight',
    ];
    for (final key in numKeys) {
      final val = post[key];
      if (val != null && val is! num) {
        throw FormatException(
          'Invalid "renderSettings.post.$key": expected num, got ${val.runtimeType}',
        );
      }
    }

    final reducedMotion = post['reducedMotion'];
    if (reducedMotion != null && reducedMotion is! bool) {
      throw FormatException(
        'Invalid "renderSettings.post.reducedMotion": expected bool, '
        'got ${reducedMotion.runtimeType}',
      );
    }

    final toneMapping = post['toneMapping'];
    if (toneMapping != null && toneMapping is! String) {
      throw FormatException(
        'Invalid "renderSettings.post.toneMapping": expected String, '
        'got ${toneMapping.runtimeType}',
      );
    }
  }

  static void _validateNode(
    Object? rawNode, {
    required String path,
    required bool allowPrefabReference,
    required bool requireNameWhenNoPrefab,
  }) {
    if (rawNode is! Map<String, Object?>) {
      throw FormatException(
        'Invalid node at $path: expected Map, got ${rawNode.runtimeType}',
      );
    }

    final prefabVal = rawNode['prefab'];
    if (prefabVal != null) {
      if (!allowPrefabReference) {
        throw FormatException(
          'Invalid node at $path: "prefab" reference is not allowed on a prefab root',
        );
      }
      if (prefabVal is! String || prefabVal.isEmpty) {
        throw FormatException(
          'Invalid "$path.prefab": expected non-empty String, got $prefabVal',
        );
      }
    }

    final nameVal = rawNode['name'];
    if (nameVal != null && nameVal is! String) {
      throw FormatException(
        'Invalid "$path.name": expected String, got ${nameVal.runtimeType}',
      );
    }
    if (requireNameWhenNoPrefab && prefabVal == null && nameVal == null) {
      throw FormatException(
        'Invalid node at $path: missing required "name" field',
      );
    }

    final tagVal = rawNode['tag'];
    if (tagVal != null && tagVal is! String) {
      throw FormatException(
        'Invalid "$path.tag": expected String, got ${tagVal.runtimeType}',
      );
    }

    final layerVal = rawNode['layer'];
    if (layerVal != null) {
      if (layerVal is! int || layerVal < 0 || layerVal > 31) {
        throw FormatException(
          'Invalid "$path.layer": expected integer in 0..31, got $layerVal',
        );
      }
    }

    final activeVal = rawNode['active'];
    if (activeVal != null && activeVal is! bool) {
      throw FormatException(
        'Invalid "$path.active": expected bool, got ${activeVal.runtimeType}',
      );
    }

    final transformVal = rawNode['transform'];
    if (transformVal != null) {
      if (transformVal is! Map<String, Object?>) {
        throw FormatException(
          'Invalid "$path.transform": expected Map, got ${transformVal.runtimeType}',
        );
      }
      _validateTransform(transformVal, '$path.transform');
    }

    final compsVal = rawNode['components'];
    if (compsVal != null) {
      if (compsVal is! List<Object?>) {
        throw FormatException(
          'Invalid "$path.components": expected List, got ${compsVal.runtimeType}',
        );
      }
      for (var i = 0; i < compsVal.length; i++) {
        final comp = compsVal[i];
        if (comp is! Map<String, Object?>) {
          throw FormatException(
            'Invalid component at $path.components[$i]: expected Map, '
            'got ${comp.runtimeType}',
          );
        }
        final typeName = comp['type'];
        if (typeName is! String || typeName.isEmpty) {
          throw FormatException(
            'Invalid "$path.components[$i].type": expected non-empty String, '
            'got $typeName',
          );
        }
        final enabled = comp['enabled'];
        if (enabled != null && enabled is! bool) {
          throw FormatException(
            'Invalid "$path.components[$i].enabled": expected bool, '
            'got ${enabled.runtimeType}',
          );
        }
      }
    }

    final childrenVal = rawNode['children'];
    if (childrenVal != null) {
      if (childrenVal is! List<Object?>) {
        throw FormatException(
          'Invalid "$path.children": expected List, got ${childrenVal.runtimeType}',
        );
      }
      for (var i = 0; i < childrenVal.length; i++) {
        _validateNode(
          childrenVal[i],
          path: '$path.children[$i]',
          allowPrefabReference: true,
          requireNameWhenNoPrefab: true,
        );
      }
    }
  }

  static void _validateTransform(Map<String, Object?> tMap, String path) {
    if (tMap['p'] != null) {
      _requireNumList(tMap['p'], 3, '$path.p');
    }
    if (tMap['r'] != null) {
      _requireNumList(tMap['r'], 4, '$path.r');
    }
    if (tMap['s'] != null && tMap['s'] is! num) {
      throw FormatException(
        'Invalid "$path.s": expected num, got ${tMap['s'].runtimeType}',
      );
    }
    if (tMap['stretch'] != null) {
      _requireNumList(tMap['stretch'], 3, '$path.stretch');
    }
  }

  static void _requireNumList(Object? raw, int length, String path) {
    if (raw is! List<Object?> || raw.length != length) {
      throw FormatException(
        'Invalid "$path": expected List of $length numbers, got $raw',
      );
    }
    for (var i = 0; i < length; i++) {
      if (raw[i] is! num) {
        throw FormatException(
          'Invalid "$path[$i]": expected num, got ${raw[i].runtimeType}',
        );
      }
    }
  }
}
