/// Studio Module Registry & Coverage Evaluator (S1-D).
library;

import 'module_descriptor.dart';

/// Result of checking discovered `vendor/*` packages against registered
/// [StudioModuleDescriptor] entries and a minimum maturity gate.
final class StudioModuleCoverageReport {
  final int totalDiscovered;
  final int totalRegistered;
  final StudioModuleMaturity minMaturity;
  final List<String> unregisteredPackages;
  final List<String> orphanedDescriptors;
  final List<String> belowMinMaturity;
  final Map<StudioModuleMaturity, int> countsByMaturity;
  final Map<StudioModuleFamily, int> countsByFamily;

  const StudioModuleCoverageReport({
    required this.totalDiscovered,
    required this.totalRegistered,
    required this.minMaturity,
    required this.unregisteredPackages,
    required this.orphanedDescriptors,
    required this.belowMinMaturity,
    required this.countsByMaturity,
    required this.countsByFamily,
  });

  bool get passed =>
      unregisteredPackages.isEmpty &&
      orphanedDescriptors.isEmpty &&
      belowMinMaturity.isEmpty;

  Map<String, Object?> toJson() => {
    'passed': passed,
    'totalDiscovered': totalDiscovered,
    'totalRegistered': totalRegistered,
    'minMaturity': minMaturity.cliName,
    'unregisteredPackages': unregisteredPackages,
    'orphanedDescriptors': orphanedDescriptors,
    'belowMinMaturity': belowMinMaturity,
    'countsByMaturity': {
      for (final e in countsByMaturity.entries) e.key.cliName: e.value,
    },
    'countsByFamily': {
      for (final e in countsByFamily.entries) e.key.taskId: e.value,
    },
  };
}

/// Pure-Dart registry of all `vendor/*` Studio module descriptors.
final class StudioModuleRegistry {
  final Map<String, StudioModuleDescriptor> _byPackage = {};

  StudioModuleRegistry(Iterable<StudioModuleDescriptor> descriptors) {
    for (final desc in descriptors) {
      register(desc);
    }
  }

  void register(StudioModuleDescriptor descriptor) {
    if (_byPackage.containsKey(descriptor.package)) {
      throw ArgumentError.value(
        descriptor.package,
        'package',
        'Duplicate StudioModuleDescriptor for ${descriptor.package}',
      );
    }
    _byPackage[descriptor.package] = descriptor;
  }

  int get length => _byPackage.length;

  StudioModuleDescriptor? lookup(String packageName) => _byPackage[packageName];

  List<StudioModuleDescriptor> get all {
    final list = _byPackage.values.toList()
      ..sort((a, b) => a.package.compareTo(b.package));
    return List<StudioModuleDescriptor>.unmodifiable(list);
  }

  List<StudioModuleDescriptor> byFamily(StudioModuleFamily family) {
    final list = _byPackage.values.where((d) => d.family == family).toList()
      ..sort((a, b) => a.package.compareTo(b.package));
    return List<StudioModuleDescriptor>.unmodifiable(list);
  }

  /// Resolves the sorted deduplicated list of root wrapper files owned by
  /// [family] for `[S6-*]` worker partitioning.
  List<String> ownersForFamily(StudioModuleFamily family) {
    final files = <String>{};
    for (final desc in byFamily(family)) {
      files.addAll(desc.wrapperFiles);
    }
    final sorted = files.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  StudioModuleCoverageReport checkCoverage(
    Iterable<String> discoveredVendorPackages, {
    StudioModuleMaturity minMaturity = StudioModuleMaturity.runtimeOnly,
  }) {
    final discovered = discoveredVendorPackages.toSet();
    final unregistered =
        discovered.where((pkg) => !_byPackage.containsKey(pkg)).toList()
          ..sort();
    final orphaned =
        _byPackage.keys.where((pkg) => !discovered.contains(pkg)).toList()
          ..sort();
    final belowMin = <String>[];
    final byMaturity = <StudioModuleMaturity, int>{
      for (final m in StudioModuleMaturity.values) m: 0,
    };
    final byFamily = <StudioModuleFamily, int>{
      for (final f in StudioModuleFamily.values) f: 0,
    };

    for (final pkg in (discovered.toList()..sort())) {
      final desc = _byPackage[pkg];
      if (desc == null) continue;
      byMaturity[desc.maturity] = (byMaturity[desc.maturity] ?? 0) + 1;
      byFamily[desc.family] = (byFamily[desc.family] ?? 0) + 1;
      if (!desc.maturity.meets(minMaturity)) {
        belowMin.add(pkg);
      }
    }

    return StudioModuleCoverageReport(
      totalDiscovered: discovered.length,
      totalRegistered: _byPackage.length,
      minMaturity: minMaturity,
      unregisteredPackages: List<String>.unmodifiable(unregistered),
      orphanedDescriptors: List<String>.unmodifiable(orphaned),
      belowMinMaturity: List<String>.unmodifiable(belowMin),
      countsByMaturity: Map<StudioModuleMaturity, int>.unmodifiable(byMaturity),
      countsByFamily: Map<StudioModuleFamily, int>.unmodifiable(byFamily),
    );
  }
}
