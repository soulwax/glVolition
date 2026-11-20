/// Volition project manifest (`volition.project.json`) model & codec (S1-C).
///
/// Pure-Dart schema shared between Studio, CLI, and build pipelines.
library;

import 'dart:convert';

import 'project_fs.dart';

const String kProjectManifestFilename = 'volition.project.json';
const int kProjectManifestSchemaVersion = 1;

/// Quality tier preset declared inside `volition.project.json`.
final class ProjectQualityTier {
  final String name;
  final int maxVisibleLights;
  final int shadowMapResolution;
  final int shadowCascades;
  final bool hdrEnabled;
  final int msaaSamples;

  const ProjectQualityTier({
    required this.name,
    this.maxVisibleLights = 64,
    this.shadowMapResolution = 1024,
    this.shadowCascades = 2,
    this.hdrEnabled = true,
    this.msaaSamples = 1,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'maxVisibleLights': maxVisibleLights,
    'shadowMapResolution': shadowMapResolution,
    'shadowCascades': shadowCascades,
    'hdrEnabled': hdrEnabled,
    'msaaSamples': msaaSamples,
  };

  factory ProjectQualityTier.fromJson(Map<String, Object?> json) =>
      ProjectQualityTier(
        name: json['name'] as String? ?? 'Standard',
        maxVisibleLights: (json['maxVisibleLights'] as num?)?.toInt() ?? 64,
        shadowMapResolution:
            (json['shadowMapResolution'] as num?)?.toInt() ?? 1024,
        shadowCascades: (json['shadowCascades'] as num?)?.toInt() ?? 2,
        hdrEnabled: json['hdrEnabled'] as bool? ?? true,
        msaaSamples: (json['msaaSamples'] as num?)?.toInt() ?? 1,
      );
}

/// Complete `volition.project.json` manifest.
final class VolitionProjectConfig {
  final int schemaVersion;
  final String name;
  final String version;
  final List<String> enabledModules;
  final List<String> scenesInBuild;
  final List<String> tags;
  final List<String> layers;
  final Map<String, List<String>> physicsLayerMatrix;
  final String? inputActionsAssetGuid;
  final String? renderPipelineSettingsAssetGuid;
  final List<ProjectQualityTier> qualityTiers;
  final Map<String, Map<String, Object?>> buildProfiles;

  const VolitionProjectConfig({
    this.schemaVersion = kProjectManifestSchemaVersion,
    required this.name,
    this.version = '0.1.0',
    this.enabledModules = const ['pixeldart'],
    this.scenesInBuild = const [],
    this.tags = const ['Untagged', 'Player', 'MainCamera', 'Enemy', 'Trigger'],
    this.layers = const [
      'Default',
      'TransparentFX',
      'IgnoreRaycast',
      'Water',
      'UI',
    ],
    this.physicsLayerMatrix = const {},
    this.inputActionsAssetGuid,
    this.renderPipelineSettingsAssetGuid,
    this.qualityTiers = const [
      ProjectQualityTier(
        name: 'Low',
        maxVisibleLights: 32,
        shadowMapResolution: 512,
        shadowCascades: 1,
        hdrEnabled: false,
      ),
      ProjectQualityTier(
        name: 'Medium',
        maxVisibleLights: 128,
        shadowMapResolution: 1024,
        shadowCascades: 2,
        hdrEnabled: true,
      ),
      ProjectQualityTier(
        name: 'High',
        maxVisibleLights: 256,
        shadowMapResolution: 2048,
        shadowCascades: 4,
        hdrEnabled: true,
        msaaSamples: 4,
      ),
    ],
    this.buildProfiles = const {},
  });

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'name': name,
    'version': version,
    'enabledModules': enabledModules,
    'scenesInBuild': scenesInBuild,
    'tags': tags,
    'layers': layers,
    'physicsLayerMatrix': physicsLayerMatrix,
    if (inputActionsAssetGuid != null)
      'inputActionsAssetGuid': inputActionsAssetGuid,
    if (renderPipelineSettingsAssetGuid != null)
      'renderPipelineSettingsAssetGuid': renderPipelineSettingsAssetGuid,
    'qualityTiers': qualityTiers.map((t) => t.toJson()).toList(),
    'buildProfiles': buildProfiles,
  };

  String toJsonString({bool pretty = true}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  factory VolitionProjectConfig.fromJson(Map<String, Object?> json) {
    final name = (json['name'] as String? ?? '').trim();
    if (name.isEmpty) {
      throw const FormatException('volition.project.json requires a name');
    }
    List<String> stringList(String key, List<String> fallback) {
      final raw = json[key];
      if (raw is! List) return fallback;
      return raw.map((e) => e.toString()).toList();
    }

    final rawMatrix = json['physicsLayerMatrix'];
    final matrix = <String, List<String>>{};
    if (rawMatrix is Map) {
      for (final entry in rawMatrix.entries) {
        final v = entry.value;
        if (v is List) {
          matrix[entry.key.toString()] = v.map((e) => e.toString()).toList();
        }
      }
    }

    final rawTiers = json['qualityTiers'];
    final tiers = rawTiers is List
        ? rawTiers
              .whereType<Map>()
              .map(
                (m) => ProjectQualityTier.fromJson(m.cast<String, Object?>()),
              )
              .toList()
        : const <ProjectQualityTier>[];

    final rawProfiles = json['buildProfiles'];
    final profiles = <String, Map<String, Object?>>{};
    if (rawProfiles is Map) {
      for (final entry in rawProfiles.entries) {
        if (entry.value is Map) {
          profiles[entry.key.toString()] = (entry.value as Map)
              .cast<String, Object?>();
        }
      }
    }

    return VolitionProjectConfig(
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ??
          kProjectManifestSchemaVersion,
      name: name,
      version: json['version'] as String? ?? '0.1.0',
      enabledModules: stringList('enabledModules', const ['pixeldart']),
      scenesInBuild: stringList('scenesInBuild', const []),
      tags: stringList('tags', const ['Untagged']),
      layers: stringList('layers', const ['Default']),
      physicsLayerMatrix: matrix,
      inputActionsAssetGuid: json['inputActionsAssetGuid'] as String?,
      renderPipelineSettingsAssetGuid:
          json['renderPipelineSettingsAssetGuid'] as String?,
      qualityTiers: tiers,
      buildProfiles: profiles,
    );
  }

  static Future<VolitionProjectConfig> load(ProjectFileSystem fs) async {
    final text = await fs.readString(kProjectManifestFilename);
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('volition.project.json must be a JSON map');
    }
    return VolitionProjectConfig.fromJson(decoded.cast<String, Object?>());
  }

  Future<void> save(ProjectFileSystem fs) =>
      fs.writeString(kProjectManifestFilename, toJsonString());
}
