import 'dart:convert';
import 'dart:io';

import 'package:gl_volition/src/studio/modules/module_descriptor.dart';
import 'package:gl_volition/src/studio/modules/module_inventory.g.dart';
import 'package:gl_volition/src/studio/modules/module_registry.dart';

/// Studio Module Registry & Coverage Gate (S1-D).
///
/// Usage:
///   dart run tool/check_module_coverage.dart --report [--json]
///   dart run tool/check_module_coverage.dart --min-maturity runtime-only
///   dart run tool/check_module_coverage.dart --owners S6-A
///   dart run tool/check_module_coverage.dart --generate
void main(List<String> args) {
  var showReport = false;
  var asJson = false;
  var generate = false;
  var minMaturity = StudioModuleMaturity.runtimeOnly;
  String? ownersArg;
  String? explicitRoot;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      stdout.writeln(
        'Usage: dart run tool/check_module_coverage.dart '
        '[--report] [--json] [--min-maturity <level>] '
        '[--owners <family|S6-A..S6-F>] [--generate] [--root <dir>]',
      );
      return;
    } else if (arg == '--report') {
      showReport = true;
    } else if (arg == '--json') {
      asJson = true;
    } else if (arg == '--generate') {
      generate = true;
    } else if (arg == '--min-maturity' && i + 1 < args.length) {
      minMaturity = StudioModuleMaturity.parse(args[++i]);
    } else if (arg == '--owners' && i + 1 < args.length) {
      ownersArg = args[++i];
    } else if (arg == '--root' && i + 1 < args.length) {
      explicitRoot = args[++i];
    } else {
      stderr.writeln('Unknown or incomplete argument: $arg');
      exit(64);
    }
  }

  final root = explicitRoot != null
      ? Directory(explicitRoot).absolute
      : Directory.current.absolute;

  if (generate) {
    _generateInventory(root);
    return;
  }

  final registry = StudioModuleRegistry(kStudioModuleInventory);

  if (ownersArg != null) {
    final family = StudioModuleFamily.tryParse(ownersArg);
    if (family == null) {
      stderr.writeln('Unknown module family: $ownersArg');
      exit(64);
    }
    final owners = registry.ownersForFamily(family);
    if (asJson) {
      stdout.writeln(
        jsonEncode({
          'family': family.name,
          'taskId': family.taskId,
          'packages': registry.byFamily(family).map((d) => d.package).toList(),
          'wrapperFiles': owners,
        }),
      );
    } else {
      stdout.writeln('${family.taskId} (${family.label}) wrapper files:');
      for (final f in owners) {
        stdout.writeln('  $f');
      }
    }
    return;
  }

  final discovered = _discoverVendorPackages(root);
  final report = registry.checkCoverage(discovered, minMaturity: minMaturity);

  if (asJson) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'report': report.toJson(),
        if (showReport) 'modules': registry.all.map((d) => d.toJson()).toList(),
      }),
    );
  } else {
    if (showReport) {
      stdout.writeln(
        '${'Package'.padRight(16)}'
        '${'Version'.padRight(10)}'
        '${'Family'.padRight(8)}'
        '${'Maturity'.padRight(15)}'
        '${'Target'.padRight(15)}'
        'Wrappers',
      );
      stdout.writeln('-' * 76);
      for (final d in registry.all) {
        stdout.writeln(
          '${d.package.padRight(16)}'
          '${d.version.padRight(10)}'
          '${d.family.taskId.padRight(8)}'
          '${d.maturity.cliName.padRight(15)}'
          '${d.requiredMaturity.cliName.padRight(15)}'
          '${d.wrapperFiles.length}',
        );
      }
      stdout.writeln('-' * 76);
    }
    stdout.writeln(
      'Module coverage: ${report.totalRegistered}/${report.totalDiscovered} '
      'registered (min-maturity: ${report.minMaturity.cliName}) — '
      '${report.passed ? 'PASS' : 'FAIL'}',
    );
    if (report.unregisteredPackages.isNotEmpty) {
      stderr.writeln(
        '  Unregistered vendor packages: '
        '${report.unregisteredPackages.join(', ')}',
      );
    }
    if (report.orphanedDescriptors.isNotEmpty) {
      stderr.writeln(
        '  Orphaned descriptors: ${report.orphanedDescriptors.join(', ')}',
      );
    }
    if (report.belowMinMaturity.isNotEmpty) {
      stderr.writeln(
        '  Below ${report.minMaturity.cliName}: '
        '${report.belowMinMaturity.join(', ')}',
      );
    }
  }

  if (!report.passed) {
    exit(1);
  }
}

List<String> _discoverVendorPackages(Directory root) {
  final vendorDir = Directory('${root.path}${Platform.pathSeparator}vendor');
  if (!vendorDir.existsSync()) return const [];
  final pkgs = <String>[];
  for (final entity in vendorDir.listSync()) {
    if (entity is Directory) {
      final pubspec = File(
        '${entity.path}${Platform.pathSeparator}pubspec.yaml',
      );
      if (pubspec.existsSync()) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        pkgs.add(name);
      }
    }
  }
  pkgs.sort();
  return pkgs;
}

const Map<String, StudioModuleFamily> _familyByPackage = {
  // S6-A: Rendering & visuals (17)
  'pixeldart': StudioModuleFamily.renderingVisuals,
  'voxvfx': StudioModuleFamily.renderingVisuals,
  'voxribbon': StudioModuleFamily.renderingVisuals,
  'voxdecal': StudioModuleFamily.renderingVisuals,
  'voxlight': StudioModuleFamily.renderingVisuals,
  'voxshadow': StudioModuleFamily.renderingVisuals,
  'voxsky': StudioModuleFamily.renderingVisuals,
  'voxcolor': StudioModuleFamily.renderingVisuals,
  'voxlens': StudioModuleFamily.renderingVisuals,
  'voxcam': StudioModuleFamily.renderingVisuals,
  'voxprobe': StudioModuleFamily.renderingVisuals,
  'voxatlas': StudioModuleFamily.renderingVisuals,
  'voxbatch': StudioModuleFamily.renderingVisuals,
  'voxoctree': StudioModuleFamily.renderingVisuals,
  'voxsdf': StudioModuleFamily.renderingVisuals,
  'voxgreedy': StudioModuleFamily.renderingVisuals,
  'voxvox': StudioModuleFamily.renderingVisuals,
  // S6-B: Physics & simulation (11)
  'voxphys': StudioModuleFamily.physicsSimulation,
  'voxbroad': StudioModuleFamily.physicsSimulation,
  'voxcloth': StudioModuleFamily.physicsSimulation,
  'voxfluid': StudioModuleFamily.physicsSimulation,
  'voxfracture': StudioModuleFamily.physicsSimulation,
  'voxragdoll': StudioModuleFamily.physicsSimulation,
  'voxverlet': StudioModuleFamily.physicsSimulation,
  'voxwheel': StudioModuleFamily.physicsSimulation,
  'voxtraffic': StudioModuleFamily.physicsSimulation,
  'voxcrowd': StudioModuleFamily.physicsSimulation,
  'voxsteer': StudioModuleFamily.physicsSimulation,
  // S6-C: Animation & motion (9)
  'voxanim': StudioModuleFamily.animationMotion,
  'voxblend': StudioModuleFamily.animationMotion,
  'voxik2d': StudioModuleFamily.animationMotion,
  'voxgait': StudioModuleFamily.animationMotion,
  'voxtween': StudioModuleFamily.animationMotion,
  'voxcurve': StudioModuleFamily.animationMotion,
  'voxseq': StudioModuleFamily.animationMotion,
  'voxspline3d': StudioModuleFamily.animationMotion,
  'voxextrude': StudioModuleFamily.animationMotion,
  // S6-D: AI, gameplay & narrative (15)
  'voxai': StudioModuleFamily.aiGameplayNarrative,
  'voxhtn': StudioModuleFamily.aiGameplayNarrative,
  'voxnav3d': StudioModuleFamily.aiGameplayNarrative,
  'voxpath': StudioModuleFamily.aiGameplayNarrative,
  'voxflow': StudioModuleFamily.aiGameplayNarrative,
  'voxgraph': StudioModuleFamily.aiGameplayNarrative,
  'voxcircuit': StudioModuleFamily.aiGameplayNarrative,
  'voxrule': StudioModuleFamily.aiGameplayNarrative,
  'voxitem': StudioModuleFamily.aiGameplayNarrative,
  'voxcraft': StudioModuleFamily.aiGameplayNarrative,
  'voxquest': StudioModuleFamily.aiGameplayNarrative,
  'voxtalk': StudioModuleFamily.aiGameplayNarrative,
  'voxstat': StudioModuleFamily.aiGameplayNarrative,
  'voxscore': StudioModuleFamily.aiGameplayNarrative,
  'voxloc': StudioModuleFamily.aiGameplayNarrative,
  // S6-E: World & procedural (10)
  'voxbiome': StudioModuleFamily.worldProcedural,
  'voxnoise3d': StudioModuleFamily.worldProcedural,
  'voxproc': StudioModuleFamily.worldProcedural,
  'voxarch': StudioModuleFamily.worldProcedural,
  'voxbuild': StudioModuleFamily.worldProcedural,
  'voxgrid': StudioModuleFamily.worldProcedural,
  'voxhex': StudioModuleFamily.worldProcedural,
  'voxsnap': StudioModuleFamily.worldProcedural,
  'voxgeom': StudioModuleFamily.worldProcedural,
  'voxfoliage': StudioModuleFamily.worldProcedural,
  // S6-F: Audio, input, net & infrastructure (12)
  'voxdsp': StudioModuleFamily.audioInputNetInfra,
  'voxreverb': StudioModuleFamily.audioInputNetInfra,
  'voxsynth': StudioModuleFamily.audioInputNetInfra,
  'voxrhythm': StudioModuleFamily.audioInputNetInfra,
  'voxpad': StudioModuleFamily.audioInputNetInfra,
  'voxnet': StudioModuleFamily.audioInputNetInfra,
  'voxrollback': StudioModuleFamily.audioInputNetInfra,
  'voxecs': StudioModuleFamily.audioInputNetInfra,
  'voxui': StudioModuleFamily.audioInputNetInfra,
  'voxlog': StudioModuleFamily.audioInputNetInfra,
  'voxpack': StudioModuleFamily.audioInputNetInfra,
  'voxalloc': StudioModuleFamily.audioInputNetInfra,
};

const Set<String> _editorTooledTargets = {
  'voxanim',
  'voxblend',
  'voxseq',
  'voxcurve',
  'voxgraph',
  'voxflow',
  'voxtalk',
  'voxhtn',
  'voxcircuit',
  'voxrule',
  'voxbiome',
  'voxfoliage',
  'voxnav3d',
  'voxspline3d',
  'voxsnap',
  'voxbuild',
  'voxatlas',
  'voxui',
  'voxloc',
  'voxitem',
  'voxquest',
  'voxstat',
};

void _generateInventory(Directory root) {
  final sep = Platform.pathSeparator;
  final packages = _discoverVendorPackages(root);

  // Scan lib/src/engine/**/*.dart for package:<pkg>/ imports.
  final wrappersByPkg = <String, Set<String>>{
    for (final p in packages) p: <String>{},
  };
  final engineDir = Directory('${root.path}${sep}lib${sep}src${sep}engine');
  final importRe = RegExp(r'''import\s+['"]package:([a-z0-9_]+)/''');
  if (engineDir.existsSync()) {
    for (final entity in engineDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path
          .substring(root.path.length + 1)
          .replaceAll('\\', '/');
      final text = entity.readAsStringSync();
      for (final m in importRe.allMatches(text)) {
        final pkg = m.group(1)!;
        wrappersByPkg[pkg]?.add(rel);
      }
    }
  }

  final buf = StringBuffer()
    ..writeln('// GENERATED CODE — DO NOT EDIT BY HAND.')
    ..writeln(
      '// Regenerate with: dart run tool/check_module_coverage.dart --generate',
    )
    ..writeln('library;')
    ..writeln()
    ..writeln("import 'module_descriptor.dart';")
    ..writeln()
    ..writeln(
      '/// Complete inventory of all ${packages.length} `vendor/*` packages.',
    )
    ..writeln('const List<StudioModuleDescriptor> kStudioModuleInventory = [');

  final versionRe = RegExp(r'^version:\s*(.+)$', multiLine: true);
  for (final pkg in packages) {
    final pubspecFile = File(
      '${root.path}${sep}vendor$sep$pkg${sep}pubspec.yaml',
    );
    final pubText = pubspecFile.readAsStringSync();
    final version = versionRe.firstMatch(pubText)?.group(1)?.trim() ?? '0.0.0';
    final family = _familyByPackage[pkg];
    if (family == null) {
      stderr.writeln('No family assignment in _familyByPackage for $pkg');
      exit(1);
    }
    final wrappers = (wrappersByPkg[pkg]?.toList() ?? <String>[])..sort();
    final reqMaturity = _editorTooledTargets.contains(pkg)
        ? 'StudioModuleMaturity.editorTooled'
        : 'StudioModuleMaturity.inspectable';
    buf
      ..writeln('  StudioModuleDescriptor(')
      ..writeln("    package: '$pkg',")
      ..writeln("    version: '$version',")
      ..writeln('    family: StudioModuleFamily.${family.name},');
    if (wrappers.isNotEmpty) {
      buf.writeln('    wrapperFiles: [');
      for (final w in wrappers) {
        buf.writeln("      '$w',");
      }
      buf.writeln('    ],');
    }
    buf
      ..writeln("    sampleScenes: ['example/studio_samples/${family.name}/'],")
      ..writeln('    maturity: StudioModuleMaturity.inspectable,')
      ..writeln('    requiredMaturity: $reqMaturity,')
      ..writeln('  ),');
  }

  buf.writeln('];');

  final outFile = File(
    '${root.path}${sep}lib${sep}src${sep}studio${sep}modules${sep}module_inventory.g.dart',
  );
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(buf.toString());
  stdout.writeln(
    'Generated ${outFile.path} with ${packages.length} module descriptors.',
  );
}
