part of '../../engine.dart';

/// Round-trips a [Scene] (hierarchy, transforms, tags, layers,
/// [RenderSettings], registered components, and prefab instances with field
/// overrides) to and from JSON maps (E3-3).
abstract final class SceneSerializer {
  static const int schemaVersion = 1;

  static String toJsonString(
    Scene scene, {
    ComponentRegistry? registry,
  }) =>
      jsonEncode(toJson(scene, registry: registry));

  static Scene fromJsonString(
    String json, {
    ComponentRegistry? registry,
    Map<String, Prefab> prefabs = const {},
  }) =>
      fromJson(
        jsonDecode(json) as Map<String, Object?>,
        registry: registry,
        prefabs: prefabs,
      );

  static Map<String, Object?> toJson(
    Scene scene, {
    ComponentRegistry? registry,
  }) {
    final reg = registry ?? ComponentRegistry.defaults();
    final rs = scene.renderSettings;
    return {
      'schemaVersion': schemaVersion,
      'name': scene.name,
      'renderSettings': {
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
        if (rs.fogHeightFalloff != null) 'fogHeightFalloff': rs.fogHeightFalloff,
        if (rs.fogDensity != null) 'fogDensity': rs.fogDensity,
        'shadowFilterRadius': rs.shadowFilterRadius,
        'shadowBias': rs.shadowBias,
        'ambientLightScale': rs.ambientLightScale,
        'directLightScale': rs.directLightScale,
        'post': _postToJson(rs.post),
      },
      'objects': [
        for (final root in scene.rootGameObjects)
          if (!root._destroyRequested) _objectToJson(root, reg),
      ],
    };
  }

  static Map<String, Object?> _objectToJson(GameObject go, ComponentRegistry reg) {
    final t = go.transform;
    final comps = <Map<String, Object?>>[];
    for (final c in go._components) {
      if (c is TransformComponent || c._destroyRequested) continue;
      final spec = reg.specFor(c);
      if (spec == null) continue;
      final serialized = spec.toJson(c);
      if (c is Behaviour) {
        serialized['enabled'] = c.enabled;
      }
      comps.add(serialized);
    }
    return {
      'name': go.name,
      'tag': go.tag,
      'layer': go.layer,
      'active': go.activeSelf,
      'transform': {
        'p': _vec3ToJson(t.localPosition),
        'r': _quatToJson(t.localRotation),
        's': t.localScale,
        'stretch': _vec3ToJson(t.localStretch),
      },
      'components': comps,
      'children': [
        for (final child in go.children)
          if (!child._destroyRequested) _objectToJson(child, reg),
      ],
    };
  }

  static Scene fromJson(
    Map<String, Object?> data, {
    ComponentRegistry? registry,
    Map<String, Prefab> prefabs = const {},
  }) {
    final version = (data['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version != schemaVersion) {
      throw FormatException('Unsupported scene schemaVersion: $version');
    }
    final reg = registry ?? ComponentRegistry.defaults();
    final scene = Scene((data['name'] as String?) ?? 'Scene');

    final rsMap = data['renderSettings'] as Map<String, Object?>?;
    if (rsMap != null) {
      final rs = scene.renderSettings;
      if (rsMap['clearColor'] != null) rs.clearColor = _colorFromJson(rsMap['clearColor']);
      if (rsMap['ambientColor'] != null) rs.ambientColor = _colorFromJson(rsMap['ambientColor']);
      if (rsMap['ambientIntensity'] != null) rs.ambientIntensity = (rsMap['ambientIntensity'] as num).toDouble();
      if (rsMap['reflectionColor'] != null) rs.reflectionColor = _colorFromJson(rsMap['reflectionColor']);
      if (rsMap['reflectionIntensity'] != null) {
        rs.reflectionIntensity = (rsMap['reflectionIntensity'] as num).toDouble();
      }
      if (rsMap['reflectionConfidence'] != null) {
        rs.reflectionConfidence = (rsMap['reflectionConfidence'] as num).toDouble();
      }
      if (rsMap['fogEnabled'] != null) rs.fogEnabled = rsMap['fogEnabled'] as bool;
      if (rsMap['fogColor'] != null) rs.fogColor = _colorFromJson(rsMap['fogColor']);
      if (rsMap['fogStart'] != null) rs.fogStart = (rsMap['fogStart'] as num).toDouble();
      if (rsMap['fogEnd'] != null) rs.fogEnd = (rsMap['fogEnd'] as num).toDouble();
      if (rsMap.containsKey('fogHeightFalloff')) {
        final raw = rsMap['fogHeightFalloff'];
        rs.fogHeightFalloff = raw is num ? raw.toDouble() : null;
      }
      if (rsMap.containsKey('fogDensity')) {
        final raw = rsMap['fogDensity'];
        rs.fogDensity = raw is num ? raw.toDouble() : null;
      }
      if (rsMap['shadowFilterRadius'] is num) {
        rs.shadowFilterRadius = (rsMap['shadowFilterRadius'] as num).toDouble();
      }
      if (rsMap['shadowBias'] is num) {
        rs.shadowBias = (rsMap['shadowBias'] as num).toDouble();
      }
      if (rsMap['ambientLightScale'] is num) {
        rs.ambientLightScale = (rsMap['ambientLightScale'] as num).toDouble();
      }
      if (rsMap['directLightScale'] is num) {
        rs.directLightScale = (rsMap['directLightScale'] as num).toDouble();
      }
      final postRaw = rsMap['post'];
      if (postRaw is Map<String, Object?>) {
        rs.post = _postFromJson(postRaw);
      } else if (postRaw is Map) {
        rs.post = _postFromJson(Map<String, Object?>.from(postRaw));
      }
    }

    final objects = (data['objects'] as List<Object?>?) ?? const [];
    for (final raw in objects) {
      _buildObjectFromJson(scene, null, raw as Map<String, Object?>, reg, prefabs);
    }
    return scene;
  }

  static GameObject _buildObjectFromJson(
    Scene scene,
    GameObject? parent,
    Map<String, Object?> data,
    ComponentRegistry reg,
    Map<String, Prefab> prefabs,
  ) {
    final prefabKey = data['prefab'] as String?;
    final name = (data['name'] as String?) ?? prefabKey ?? 'GameObject';
    final active = (data['active'] as bool?) ?? true;

    final GameObject go;
    if (prefabKey != null) {
      final prefab = prefabs[prefabKey];
      if (prefab == null) {
        throw ArgumentError('Scene references unknown prefab "$prefabKey"');
      }
      go = prefab.instantiate(scene, parent: parent, name: name, active: false);
    } else {
      go = scene.createGameObject(name, parent: parent, active: false);
    }

    _populateGameObjectFromJson(go, data, reg, prefabs);
    if (active) go.setActive(true);
    return go;
  }

  static void _populateGameObjectFromJson(
    GameObject go,
    Map<String, Object?> data,
    ComponentRegistry reg,
    Map<String, Prefab> prefabs,
  ) {
    if (data['name'] is String) go.name = data['name'] as String;
    if (data['tag'] is String) go.tag = data['tag'] as String;
    if (data['layer'] is num) go.layer = (data['layer'] as num).toInt();

    final tMap = data['transform'] as Map<String, Object?>?;
    if (tMap != null) {
      if (tMap['p'] != null) go.transform.localPosition = _vec3FromJson(tMap['p']);
      if (tMap['r'] != null) go.transform.localRotation = _quatFromJson(tMap['r']);
      if (tMap['s'] != null) go.transform.localScale = (tMap['s'] as num).toDouble();
      if (tMap['stretch'] != null) go.transform.localStretch = _vec3FromJson(tMap['stretch']);
    }

    final comps = (data['components'] as List<Object?>?) ?? const [];
    for (final rawComp in comps) {
      final cMap = rawComp as Map<String, Object?>;
      final typeName = cMap['type'] as String;
      final spec = reg.specByName(typeName);
      if (spec == null) continue;

      // If instantiated from a prefab that already attached this component type,
      // apply overrides in place; otherwise create and attach it.
      Component? existing;
      for (final c in go._components) {
        if (c.runtimeType == spec.componentType) {
          existing = c;
          break;
        }
      }
      final target = existing ?? go.addComponent(spec.create());
      spec.applyJson(target, cMap);
      if (target is Behaviour && cMap['enabled'] is bool) {
        target.enabled = cMap['enabled'] as bool;
      }
    }

    final children = (data['children'] as List<Object?>?) ?? const [];
    for (final rawChild in children) {
      _buildObjectFromJson(go.scene, go, rawChild as Map<String, Object?>, reg, prefabs);
    }
  }

  static Map<String, Object?> _postToJson(PostProcessState p) => {
        'exposure': p.exposure,
        'bloomStrength': p.bloomStrength,
        'ssaoStrength': p.ssaoStrength,
        'depthOfFieldStrength': p.depthOfFieldStrength,
        'vignette': p.vignette,
        'grain': p.grain,
        'rainIntensity': p.rainIntensity,
        'surfaceWetness': p.surfaceWetness,
        'surfaceSnowCoverage': p.surfaceSnowCoverage,
        'surfaceDissolution': p.surfaceDissolution,
        'rainWindowVisibility': p.rainWindowVisibility,
        'ditherStrength': p.ditherStrength,
        'colorGradeStrength': p.colorGradeStrength,
        'affineWarpStrength': p.affineWarpStrength,
        'vertexSnapGrid': p.vertexSnapGrid,
        'quantizationBits': p.quantizationBits,
        'vhsChromaWeight': p.vhsChromaWeight,
        'vhsTrackingWeight': p.vhsTrackingWeight,
        'vhsNoiseWeight': p.vhsNoiseWeight,
        'vhsHeadSwitchWeight': p.vhsHeadSwitchWeight,
        'vhsDropoutWeight': p.vhsDropoutWeight,
        'vhsGhostWeight': p.vhsGhostWeight,
        'reducedMotion': p.reducedMotion,
        'toneMapping': p.toneMapping.name,
      };

  static PostProcessState _postFromJson(Map<String, Object?> map) {
    const defaults = PostProcessState();
    double readDouble(String key, double fallback) {
      final raw = map[key];
      return raw is num ? raw.toDouble() : fallback;
    }

    int readInt(String key, int fallback) {
      final raw = map[key];
      return raw is num ? raw.toInt() : fallback;
    }

    bool readBool(String key, bool fallback) {
      final raw = map[key];
      return raw is bool ? raw : fallback;
    }

    var toneMapping = defaults.toneMapping;
    final rawTone = map['toneMapping'];
    if (rawTone is String) {
      try {
        toneMapping = ToneMappingMode.values.byName(rawTone);
      } on ArgumentError {
        toneMapping = defaults.toneMapping;
      }
    }

    return PostProcessState(
      exposure: readDouble('exposure', defaults.exposure),
      bloomStrength: readDouble('bloomStrength', defaults.bloomStrength),
      ssaoStrength: readDouble('ssaoStrength', defaults.ssaoStrength),
      depthOfFieldStrength: readDouble(
        'depthOfFieldStrength',
        defaults.depthOfFieldStrength,
      ),
      vignette: readDouble('vignette', defaults.vignette),
      grain: readDouble('grain', defaults.grain),
      rainIntensity: readDouble('rainIntensity', defaults.rainIntensity),
      surfaceWetness: readDouble('surfaceWetness', defaults.surfaceWetness),
      surfaceSnowCoverage: readDouble(
        'surfaceSnowCoverage',
        defaults.surfaceSnowCoverage,
      ),
      surfaceDissolution: readDouble(
        'surfaceDissolution',
        defaults.surfaceDissolution,
      ),
      rainWindowVisibility: readDouble(
        'rainWindowVisibility',
        defaults.rainWindowVisibility,
      ),
      ditherStrength: readDouble('ditherStrength', defaults.ditherStrength),
      colorGradeStrength: readDouble(
        'colorGradeStrength',
        defaults.colorGradeStrength,
      ),
      affineWarpStrength: readDouble(
        'affineWarpStrength',
        defaults.affineWarpStrength,
      ),
      vertexSnapGrid: readDouble('vertexSnapGrid', defaults.vertexSnapGrid),
      quantizationBits: readInt('quantizationBits', defaults.quantizationBits),
      vhsChromaWeight: readDouble('vhsChromaWeight', defaults.vhsChromaWeight),
      vhsTrackingWeight: readDouble(
        'vhsTrackingWeight',
        defaults.vhsTrackingWeight,
      ),
      vhsNoiseWeight: readDouble('vhsNoiseWeight', defaults.vhsNoiseWeight),
      vhsHeadSwitchWeight: readDouble(
        'vhsHeadSwitchWeight',
        defaults.vhsHeadSwitchWeight,
      ),
      vhsDropoutWeight: readDouble(
        'vhsDropoutWeight',
        defaults.vhsDropoutWeight,
      ),
      vhsGhostWeight: readDouble('vhsGhostWeight', defaults.vhsGhostWeight),
      reducedMotion: readBool('reducedMotion', defaults.reducedMotion),
      toneMapping: toneMapping,
    );
  }
}
