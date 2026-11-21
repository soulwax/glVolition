/// Generates `doc/studio/MODULE_CATALOG.md` directly from the 74-package
/// `kStudioModuleInventory` (`[S8-D]`).
library;

import 'dart:io';

import 'package:gl_volition/src/studio/modules/module_descriptor.dart';
import 'package:gl_volition/src/studio/modules/module_inventory.g.dart';
import 'package:gl_volition/src/studio/modules/module_registry.dart';

void main() {
  final registry = StudioModuleRegistry(kStudioModuleInventory);
  final buf = StringBuffer()
    ..writeln('# Volition Studio — Module Catalog (74 Packages)')
    ..writeln()
    ..writeln(
      '_Generated automatically by `dart run tool/generate_module_catalog.dart`._',
    )
    ..writeln();

  for (final family in StudioModuleFamily.values) {
    final members = registry.byFamily(family);
    buf
      ..writeln('## ${family.taskId}: ${family.label} (${members.length})')
      ..writeln()
      ..writeln('| Package | Version | Maturity | Target | Sample |')
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final m in members) {
      final sample = m.sampleScenes.isEmpty ? '-' : m.sampleScenes.first;
      buf.writeln(
        '| `${m.package}` | `${m.version}` | `${m.maturity.cliName}` | '
        '`${m.requiredMaturity.cliName}` | `$sample` |',
      );
    }
    buf.writeln();
  }

  final out = File('doc/studio/MODULE_CATALOG.md');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(buf.toString());
  stdout.writeln(
    'Generated ${out.path} (${registry.all.length} modules across '
    '${StudioModuleFamily.values.length} families).',
  );
}
