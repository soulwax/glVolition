/// Studio Module Descriptor & Maturity Model (S1-D).
///
/// Pure-Dart metadata describing each `vendor/*` submodule package, its
/// `PLAN.md §13.7` family assignment, wrapper files, inspector/editor
/// contributions, and maturity level.
library;

/// Module family assignment matching `PLAN.md §13.7` (`[S6-A]`..`[S6-F]`).
enum StudioModuleFamily {
  renderingVisuals('S6-A', 'Rendering & visuals'),
  physicsSimulation('S6-B', 'Physics & simulation'),
  animationMotion('S6-C', 'Animation & motion'),
  aiGameplayNarrative('S6-D', 'AI, gameplay & narrative'),
  worldProcedural('S6-E', 'World & procedural'),
  audioInputNetInfra('S6-F', 'Audio, input, net & infrastructure');

  final String taskId;
  final String label;
  const StudioModuleFamily(this.taskId, this.label);

  static StudioModuleFamily? tryParse(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final f in values) {
      if (f.name.toLowerCase() == normalized ||
          f.taskId.toLowerCase() == normalized ||
          f.label.toLowerCase().startsWith(normalized)) {
        return f;
      }
    }
    return null;
  }
}

/// Studio integration maturity level for a `vendor/*` module.
enum StudioModuleMaturity {
  runtimeOnly('runtime-only', 0),
  inspectable('inspectable', 1),
  editorTooled('editor-tooled', 2);

  final String cliName;
  final int rank;
  const StudioModuleMaturity(this.cliName, this.rank);

  bool meets(StudioModuleMaturity minimum) => rank >= minimum.rank;

  static StudioModuleMaturity parse(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final m in values) {
      if (m.cliName == normalized || m.name.toLowerCase() == normalized) {
        return m;
      }
    }
    throw ArgumentError.value(
      raw,
      'maturity',
      'Expected one of: runtime-only, inspectable, editor-tooled',
    );
  }
}

/// Describes one `vendor/*` submodule's integration with Volition Studio.
final class StudioModuleDescriptor {
  final String package;
  final String version;
  final StudioModuleFamily family;
  final List<String> wrapperFiles;
  final List<String> componentSpecIds;
  final List<String> importers;
  final List<String> gizmoDrawers;
  final List<String> customInspectors;
  final List<String> createMenuEntries;
  final List<String> sampleScenes;
  final StudioModuleMaturity maturity;
  final StudioModuleMaturity requiredMaturity;

  const StudioModuleDescriptor({
    required this.package,
    required this.version,
    required this.family,
    this.wrapperFiles = const [],
    this.componentSpecIds = const [],
    this.importers = const [],
    this.gizmoDrawers = const [],
    this.customInspectors = const [],
    this.createMenuEntries = const [],
    this.sampleScenes = const [],
    this.maturity = StudioModuleMaturity.runtimeOnly,
    this.requiredMaturity = StudioModuleMaturity.inspectable,
  });

  Map<String, Object?> toJson() => {
    'package': package,
    'version': version,
    'family': family.name,
    'taskId': family.taskId,
    'wrapperFiles': wrapperFiles,
    'componentSpecIds': componentSpecIds,
    'importers': importers,
    'gizmoDrawers': gizmoDrawers,
    'customInspectors': customInspectors,
    'createMenuEntries': createMenuEntries,
    'sampleScenes': sampleScenes,
    'maturity': maturity.cliName,
    'requiredMaturity': requiredMaturity.cliName,
  };
}
