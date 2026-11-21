/// Volition Studio Modules Package Manager Window (`[S6-M]`):
/// Lists all 74 `vendor/*` modules with per-project enable/disable toggles,
/// family filters, search, version, maturity, and sample scene links.
library;

import '../modules/module_descriptor.dart';
import '../modules/module_registry.dart';

final class ModulesWindowModel {
  final StudioModuleRegistry registry;
  final Set<String> _enabledPackages;
  StudioModuleFamily? familyFilter;
  String searchQuery = '';

  ModulesWindowModel(this.registry, {Iterable<String>? initiallyEnabled})
    : _enabledPackages = initiallyEnabled != null
          ? Set<String>.of(initiallyEnabled)
          : {for (final d in registry.all) d.package};

  bool isEnabled(String package) => _enabledPackages.contains(package);

  void setEnabled(String package, bool enabled) {
    if (enabled) {
      _enabledPackages.add(package);
    } else {
      _enabledPackages.remove(package);
    }
  }

  Set<String> get enabledPackages => Set<String>.unmodifiable(_enabledPackages);

  List<StudioModuleDescriptor> get filteredModules {
    final q = searchQuery.trim().toLowerCase();
    return [
      for (final d in registry.all)
        if ((familyFilter == null || d.family == familyFilter) &&
            (q.isEmpty ||
                d.package.toLowerCase().contains(q) ||
                d.family.label.toLowerCase().contains(q)))
          d,
    ];
  }
}
