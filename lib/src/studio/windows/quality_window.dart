/// Volition Studio Quality Window Model (`[S3-E]`):
/// Switches `VrpQualityTier` live across Scene and Game viewports and applies
/// per-tier overrides cleanly.
library;

import 'package:pixeldart/rendering/api/settings.dart';

/// Pure-Dart view model for live VRP quality tier switching (`[S3-E]`).
final class QualityWindowModel {
  VrpQualityTier _activeTier;
  RenderPipelineSettings _activeSettings;

  final List<void Function(RenderPipelineSettings)> _onSettingsChanged = [];

  QualityWindowModel({VrpQualityTier initialTier = VrpQualityTier.high})
    : _activeTier = initialTier,
      _activeSettings = RenderPipelineSettings.forTier(initialTier);

  VrpQualityTier get activeTier => _activeTier;
  RenderPipelineSettings get activeSettings => _activeSettings;

  void addListener(void Function(RenderPipelineSettings) listener) {
    _onSettingsChanged.add(listener);
  }

  /// Switches the active quality tier preset (`low | medium | high | ultra`)
  /// and notifies attached Scene & Game viewports.
  RenderPipelineSettings selectTier(VrpQualityTier tier) {
    _activeTier = tier;
    _activeSettings = RenderPipelineSettings.forTier(tier);
    for (final l in _onSettingsChanged) {
      l(_activeSettings);
    }
    return _activeSettings;
  }

  /// Applies fine-grained overrides on top of the active tier settings.
  RenderPipelineSettings applyOverrides({
    bool? hdrEnabled,
    int? msaaSamples,
    double? renderScale,
    int? shadowCascadeCount,
    int? shadowAtlasSize,
    int? maxVisibleLights,
  }) {
    final next = RenderPipelineSettings(
      tier: _activeTier,
      hdrEnabled: hdrEnabled ?? _activeSettings.hdrEnabled,
      hdrFormat: _activeSettings.hdrFormat,
      msaaSamples: msaaSamples ?? _activeSettings.msaaSamples,
      renderScale: renderScale ?? _activeSettings.renderScale,
      maxVisibleLights: maxVisibleLights ?? _activeSettings.maxVisibleLights,
      clusterDimX: _activeSettings.clusterDimX,
      clusterDimY: _activeSettings.clusterDimY,
      clusterDimZ: _activeSettings.clusterDimZ,
      shadowDistance: _activeSettings.shadowDistance,
      shadowCascadeCount:
          shadowCascadeCount ?? _activeSettings.shadowCascadeCount,
      shadowSplitLambda: _activeSettings.shadowSplitLambda,
      shadowAtlasSize: shadowAtlasSize ?? _activeSettings.shadowAtlasSize,
      shadowResolutionTiers: _activeSettings.shadowResolutionTiers,
    )..validate();
    _activeSettings = next;
    for (final l in _onSettingsChanged) {
      l(_activeSettings);
    }
    return next;
  }
}
