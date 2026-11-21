/// S1-D tests: Studio Module Registry, 74-package inventory, maturity gates,
/// family ownership resolution, and CLI coverage checker failure on unregistered
/// vendor packages.
library;

import 'dart:convert';
import 'dart:io';

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S1-D — Studio Module Registry & Coverage Gate', () {
    test(
      'registers all 74 vendor packages with valid families and versions',
      () {
        final registry = StudioModuleRegistry(kStudioModuleInventory);
        expect(registry.length, equals(74));

        expect(
          registry.byFamily(StudioModuleFamily.renderingVisuals).length,
          equals(17),
        );
        expect(
          registry.byFamily(StudioModuleFamily.physicsSimulation).length,
          equals(11),
        );
        expect(
          registry.byFamily(StudioModuleFamily.animationMotion).length,
          equals(9),
        );
        expect(
          registry.byFamily(StudioModuleFamily.aiGameplayNarrative).length,
          equals(15),
        );
        expect(
          registry.byFamily(StudioModuleFamily.worldProcedural).length,
          equals(10),
        );
        expect(
          registry.byFamily(StudioModuleFamily.audioInputNetInfra).length,
          equals(12),
        );

        final pixeldart = registry.lookup('pixeldart');
        expect(pixeldart, isNotNull);
        expect(pixeldart!.version, isNotEmpty);
        expect(pixeldart.family, equals(StudioModuleFamily.renderingVisuals));

        // Editor-tooled targets from PLAN §13.7
        expect(
          registry.lookup('voxanim')!.requiredMaturity,
          equals(StudioModuleMaturity.editorTooled),
        );
        expect(
          registry.lookup('voxui')!.requiredMaturity,
          equals(StudioModuleMaturity.editorTooled),
        );
      },
    );

    test('checkCoverage detects unregistered and below-maturity packages', () {
      final registry = StudioModuleRegistry(kStudioModuleInventory);
      final allPkgs = registry.all.map((d) => d.package).toList();

      final passReport = registry.checkCoverage(
        allPkgs,
        minMaturity: StudioModuleMaturity.runtimeOnly,
      );
      expect(passReport.passed, isTrue);
      expect(passReport.totalDiscovered, equals(74));
      expect(passReport.unregisteredPackages, isEmpty);

      final missingReport = registry.checkCoverage([
        ...allPkgs,
        'vox_unregistered_test_pkg',
      ]);
      expect(missingReport.passed, isFalse);
      expect(
        missingReport.unregisteredPackages,
        contains('vox_unregistered_test_pkg'),
      );

      final inspectableReport = registry.checkCoverage(
        allPkgs,
        minMaturity: StudioModuleMaturity.inspectable,
      );
      expect(inspectableReport.passed, isTrue);
      expect(inspectableReport.belowMinMaturity, isEmpty);

      final maturityReport = registry.checkCoverage(
        allPkgs,
        minMaturity: StudioModuleMaturity.editorTooled,
      );
      expect(maturityReport.passed, isFalse);
      expect(maturityReport.belowMinMaturity, isNotEmpty);
    });

    test(
      'CLI check_module_coverage passes on repo and fails on unregistered fixture package',
      () {
        final okRes = Process.runSync(Platform.resolvedExecutable, [
          'run',
          'tool/check_module_coverage.dart',
          '--report',
          '--json',
          '--min-maturity',
          'runtime-only',
        ]);
        expect(okRes.exitCode, equals(0), reason: '${okRes.stderr}');
        final payload =
            jsonDecode(okRes.stdout.toString()) as Map<String, Object?>;
        final report = payload['report'] as Map<String, Object?>;
        expect(report['passed'], isTrue);
        expect(report['totalRegistered'], equals(74));
        expect(report['totalDiscovered'], equals(74));

        // Fixture with an unregistered vendor package must fail with exit 1
        final tmp = Directory.systemTemp.createTempSync('volition_modcov_');
        try {
          final bogus = Directory('${tmp.path}/vendor/vox_bogus_pkg');
          bogus.createSync(recursive: true);
          File(
            '${bogus.path}/pubspec.yaml',
          ).writeAsStringSync('name: vox_bogus_pkg\nversion: 0.1.0\n');
          final failRes = Process.runSync(Platform.resolvedExecutable, [
            'run',
            'tool/check_module_coverage.dart',
            '--root',
            tmp.path,
          ]);
          expect(failRes.exitCode, equals(1));
          expect(failRes.stderr.toString(), contains('vox_bogus_pkg'));
        } finally {
          tmp.deleteSync(recursive: true);
        }
      },
    );
  });
}
