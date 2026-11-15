import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/package_native.dart';

void main() {
  group('NativeBuildTarget', () {
    test('tryParse resolves explicit and host-relative native targets', () {
      expect(NativeBuildTarget.tryParse('windows'), NativeBuildTarget.windows);
      expect(NativeBuildTarget.tryParse('linux'), NativeBuildTarget.linux);
      expect(NativeBuildTarget.tryParse('macos'), NativeBuildTarget.macos);
      expect(NativeBuildTarget.tryParse('webview'), NativeBuildTarget.webview);

      expect(
        NativeBuildTarget.tryParse('native', hostOperatingSystem: 'windows'),
        NativeBuildTarget.windows,
      );
      expect(
        NativeBuildTarget.tryParse('exe', hostOperatingSystem: 'linux'),
        NativeBuildTarget.linux,
      );
      expect(
        NativeBuildTarget.tryParse('native', hostOperatingSystem: 'macos'),
        NativeBuildTarget.macos,
      );

      expect(NativeBuildTarget.tryParse('js'), isNull);
      expect(NativeBuildTarget.tryParse('wasm'), isNull);
      expect(NativeBuildTarget.tryParse('unknown'), isNull);
    });
  });

  group('NativePackager.planBuild', () {
    late Directory tempRoot;
    late Directory workspaceDir;
    late Directory entryDir;
    late File entryFile;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('volition_plan_test_');
      workspaceDir = Directory('${tempRoot.path}/ws')..createSync();
      entryDir = Directory('${workspaceDir.path}/example/demo_game')
        ..createSync(recursive: true);
      entryFile = File('${entryDir.path}/main.dart')
        ..writeAsStringSync('void main() {}\n');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('plans windows native AOT layout and runtime DLLs', () {
      final packager = NativePackager(
        dartExecutable: 'dart',
        hostOperatingSystem: 'windows',
      );
      final plan = packager.planBuild(
        entryPath: entryFile.path,
        target: NativeBuildTarget.windows,
        name: 'demo_game',
        version: '1.2.3',
        workspaceDir: workspaceDir.path,
        librarySearchDirs: const [],
      );

      expect(plan.target, NativeBuildTarget.windows);
      expect(plan.binaryFileName, 'demo_game.exe');
      expect(
        plan.binaryPath.replaceAll('\\', '/'),
        endsWith('demo_game/windows/demo_game.exe'),
      );
      expect(plan.launcherFileName, 'Launch_demo_game.cmd');
      expect(plan.expectedRuntimeLibraries, [
        'SDL3.dll',
        'libGLESv2.dll',
        'libEGL.dll',
      ]);
      expect(plan.compileArguments, [
        'compile',
        'exe',
        '-o',
        plan.binaryPath,
        entryFile.path,
      ]);
      expect(plan.formatDryRunReport(), contains('Dry-run build plan'));
    });

    test('plans linux native AOT layout and runtime SOs', () {
      final packager = NativePackager(
        dartExecutable: 'dart',
        hostOperatingSystem: 'windows',
      );
      final plan = packager.planBuild(
        entryPath: entryFile.path,
        target: NativeBuildTarget.linux,
        name: 'demo_game',
        version: '1.2.3',
        workspaceDir: workspaceDir.path,
        librarySearchDirs: const [],
      );

      expect(plan.target, NativeBuildTarget.linux);
      expect(plan.binaryFileName, 'demo_game');
      expect(plan.launcherFileName, 'launch_demo_game.sh');
      expect(plan.expectedRuntimeLibraries, [
        'libSDL3.so.0',
        'libGLESv2.so.2',
        'libEGL.so.1',
      ]);
      expect(plan.compileArguments, [
        'compile',
        'exe',
        '--target-os',
        'linux',
        '-o',
        plan.binaryPath,
        entryFile.path,
      ]);
    });

    test('plans macos native AOT layout and runtime dylibs', () {
      final packager = NativePackager(
        dartExecutable: 'dart',
        hostOperatingSystem: 'macos',
      );
      final plan = packager.planBuild(
        entryPath: entryFile.path,
        target: NativeBuildTarget.macos,
        name: 'demo_game',
        version: '1.2.3',
        workspaceDir: workspaceDir.path,
        librarySearchDirs: const [],
      );

      expect(plan.target, NativeBuildTarget.macos);
      expect(plan.binaryFileName, 'demo_game');
      expect(plan.launcherFileName, 'launch_demo_game.sh');
      expect(plan.expectedRuntimeLibraries, [
        'libSDL3.dylib',
        'libGLESv2.dylib',
        'libEGL.dylib',
      ]);
      expect(plan.compileArguments, [
        'compile',
        'exe',
        '-o',
        plan.binaryPath,
        entryFile.path,
      ]);
    });

    test('plans webview target preserving WinForms WebView2 host flow', () {
      final hostDir = Directory(
        '${workspaceDir.path}/vendor/pixeldart/examples/desktop_host',
      )..createSync(recursive: true);
      final hostCs = File('${hostDir.path}/Program.cs')
        ..writeAsStringSync('// host\n');
      File('${entryDir.path}/index.html').writeAsStringSync('<html></html>');

      final packager = NativePackager(dartExecutable: 'dart');
      final plan = packager.planBuild(
        entryPath: entryFile.path,
        target: NativeBuildTarget.webview,
        name: 'demo_game',
        version: '1.2.3',
        workspaceDir: workspaceDir.path,
      );

      expect(plan.target, NativeBuildTarget.webview);
      expect(plan.binaryFileName, 'GlVolitionGame.exe');
      expect(plan.launcherFileName, 'Launch_demo_game.cmd');
      expect(plan.expectedRuntimeLibraries, isEmpty);
      expect(
        plan.compileArguments,
        containsAllInOrder(['compile', 'js', '-O4']),
      );
      expect(
        plan.webviewHostSourcePath?.replaceAll('\\', '/'),
        hostCs.path.replaceAll('\\', '/'),
      );
      expect(
        plan.webviewCsprojPath?.replaceAll('\\', '/'),
        endsWith('/desktop/GlVolitionGame.csproj'),
      );
      expect(plan.indexHtmlSourcePath, isNotNull);
    });
  });

  group('NativePackager.package', () {
    late Directory tempRoot;
    late Directory workspaceDir;
    late Directory entryDir;
    late Directory libsDir;
    late File entryFile;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('volition_pkg_test_');
      workspaceDir = Directory('${tempRoot.path}/ws')..createSync();
      entryDir = Directory('${workspaceDir.path}/example/star_pilot')
        ..createSync(recursive: true);
      libsDir = Directory('${tempRoot.path}/native_libs')..createSync();
      entryFile = File('${entryDir.path}/main.dart')
        ..writeAsStringSync('void main() {}\n');

      // Static assets across entry-adjacent and workspace-level folders.
      Directory('${entryDir.path}/assets/sprites').createSync(recursive: true);
      File('${entryDir.path}/assets/sprites/ship.png').writeAsStringSync('png');
      Directory('${entryDir.path}/res').createSync(recursive: true);
      File('${entryDir.path}/res/config.json').writeAsStringSync('{}');
      Directory('${workspaceDir.path}/audio').createSync(recursive: true);
      File('${workspaceDir.path}/audio/laser.wav').writeAsStringSync('wav');
      Directory('${workspaceDir.path}/models').createSync(recursive: true);
      File('${workspaceDir.path}/models/asteroid.glb').writeAsStringSync('glb');

      // .pak files next to entry and workspace root (shared.pak tests precedence).
      File('${entryDir.path}/level1.pak').writeAsStringSync('entry-level1');
      File('${entryDir.path}/shared.pak').writeAsStringSync('entry-shared');
      File('${workspaceDir.path}/shared.pak').writeAsStringSync('ws-shared');
      File('${workspaceDir.path}/engine.pak').writeAsStringSync('ws-engine');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('dry-run creates no directories and invokes no processes', () async {
      File('${libsDir.path}/SDL3.dll').writeAsStringSync('sdl3');
      var invoked = 0;
      final outDir = '${tempRoot.path}/out_dry_run';

      final packager = NativePackager(
        dartExecutable: 'dart',
        hostOperatingSystem: 'windows',
        processRunner: (exe, args, {workingDirectory}) async {
          invoked++;
          return ProcessResult(1, 0, '', '');
        },
      );

      final result = await packager.package(
        entryPath: entryFile.path,
        target: NativeBuildTarget.windows,
        outputDir: outDir,
        name: 'star_pilot',
        version: '0.2.0',
        workspaceDir: workspaceDir.path,
        librarySearchDirs: [libsDir.path],
        dryRun: true,
      );

      expect(result.dryRun, isTrue);
      expect(result.success, isTrue);
      expect(result.exitCode, 0);
      expect(invoked, 0);
      expect(Directory(outDir).existsSync(), isFalse);
      expect(result.bundledLibraries, ['SDL3.dll']);
      expect(result.missingLibraries, ['libGLESv2.dll', 'libEGL.dll']);
      expect(result.copiedPakFiles, ['engine.pak', 'level1.pak', 'shared.pak']);
    });

    test(
      'windows package copies assets, .pak files, available DLLs, launcher, and metadata',
      () async {
        File('${libsDir.path}/SDL3.dll').writeAsStringSync('sdl3-bytes');
        File('${libsDir.path}/libGLESv2.dll').writeAsStringSync('gles-bytes');
        // Intentionally omit libEGL.dll to verify partial library bundling.

        final outDir = '${tempRoot.path}/out_win';
        final invocations = <List<String>>[];

        final packager = NativePackager(
          dartExecutable: 'dart',
          hostOperatingSystem: 'windows',
          gitCommitResolver: () => 'abc1234',
          clock: () => DateTime.utc(2026, 11, 15, 12, 0, 0),
          processRunner: (exe, args, {workingDirectory}) async {
            invocations.add([exe, ...args]);
            final outIdx = args.indexOf('-o');
            if (outIdx != -1 && outIdx + 1 < args.length) {
              File(args[outIdx + 1])
                ..parent.createSync(recursive: true)
                ..writeAsStringSync('fake-pe-binary');
            }
            return ProcessResult(1, 0, 'ok', '');
          },
        );

        final result = await packager.package(
          entryPath: entryFile.path,
          target: NativeBuildTarget.windows,
          outputDir: outDir,
          name: 'star_pilot',
          version: '0.2.0',
          workspaceDir: workspaceDir.path,
          librarySearchDirs: [libsDir.path],
          dryRun: false,
        );

        expect(result.success, isTrue);
        expect(result.exitCode, 0);
        expect(invocations, hasLength(1));
        expect(
          invocations.single,
          containsAllInOrder(['dart', 'compile', 'exe', '-o']),
        );

        expect(File('$outDir/star_pilot.exe').existsSync(), isTrue);
        expect(
          File('$outDir/assets/sprites/ship.png').readAsStringSync(),
          'png',
        );
        expect(File('$outDir/res/config.json').existsSync(), isTrue);
        expect(File('$outDir/audio/laser.wav').existsSync(), isTrue);
        expect(File('$outDir/models/asteroid.glb').existsSync(), isTrue);

        expect(File('$outDir/level1.pak').readAsStringSync(), 'entry-level1');
        expect(File('$outDir/engine.pak').readAsStringSync(), 'ws-engine');
        expect(File('$outDir/shared.pak').readAsStringSync(), 'entry-shared');

        expect(File('$outDir/SDL3.dll').readAsStringSync(), 'sdl3-bytes');
        expect(File('$outDir/libGLESv2.dll').readAsStringSync(), 'gles-bytes');
        expect(File('$outDir/libEGL.dll').existsSync(), isFalse);
        expect(result.bundledLibraries, ['SDL3.dll', 'libGLESv2.dll']);
        expect(result.missingLibraries, ['libEGL.dll']);

        final launcher = File('$outDir/Launch_star_pilot.cmd');
        expect(launcher.existsSync(), isTrue);
        expect(launcher.readAsStringSync(), contains('star_pilot.exe'));

        final metaFile = File('$outDir/metadata.json');
        expect(metaFile.existsSync(), isTrue);
        final meta = jsonDecode(metaFile.readAsStringSync()) as Map;
        expect(meta['name'], 'star_pilot');
        expect(meta['version'], '0.2.0');
        expect(meta['target'], 'windows');
        expect(meta['nativeAot'], isTrue);
        expect(meta['bundledLibraries'], ['SDL3.dll', 'libGLESv2.dll']);
        expect(meta['builtAt'], '2026-11-15T12:00:00.000Z');
        expect(meta['commit'], 'abc1234');
      },
    );

    test(
      'linux package copies .so libraries and generates POSIX launch script',
      () async {
        File('${libsDir.path}/libSDL3.so.0').writeAsStringSync('so-sdl3');
        File('${libsDir.path}/libGLESv2.so.2').writeAsStringSync('so-gles');
        File('${libsDir.path}/libEGL.so.1').writeAsStringSync('so-egl');

        final outDir = '${tempRoot.path}/out_linux';
        final packager = NativePackager(
          dartExecutable: 'dart',
          hostOperatingSystem: 'linux',
          gitCommitResolver: () => 'def5678',
          processRunner: (exe, args, {workingDirectory}) async {
            final outIdx = args.indexOf('-o');
            File(args[outIdx + 1])
              ..parent.createSync(recursive: true)
              ..writeAsStringSync('fake-elf-binary');
            return ProcessResult(1, 0, '', '');
          },
        );

        final result = await packager.package(
          entryPath: entryFile.path,
          target: NativeBuildTarget.linux,
          outputDir: outDir,
          name: 'star_pilot',
          version: '0.2.0',
          workspaceDir: workspaceDir.path,
          librarySearchDirs: [libsDir.path],
        );

        expect(result.success, isTrue);
        expect(File('$outDir/star_pilot').existsSync(), isTrue);
        expect(File('$outDir/libSDL3.so.0').existsSync(), isTrue);
        expect(File('$outDir/libGLESv2.so.2').existsSync(), isTrue);
        expect(File('$outDir/libEGL.so.1').existsSync(), isTrue);
        expect(result.missingLibraries, isEmpty);

        final launcher = File('$outDir/launch_star_pilot.sh');
        expect(launcher.existsSync(), isTrue);
        final script = launcher.readAsStringSync();
        expect(script, contains('LD_LIBRARY_PATH'));
        expect(script, contains('exec "\$DIR/star_pilot"'));
      },
    );

    test(
      'macos package copies .dylib libraries and generates POSIX launch script',
      () async {
        File('${libsDir.path}/libSDL3.dylib').writeAsStringSync('dylib-sdl3');
        File('${libsDir.path}/libGLESv2.dylib').writeAsStringSync('dylib-gles');
        File('${libsDir.path}/libEGL.dylib').writeAsStringSync('dylib-egl');

        final outDir = '${tempRoot.path}/out_macos';
        final packager = NativePackager(
          dartExecutable: 'dart',
          hostOperatingSystem: 'macos',
          gitCommitResolver: () => 'mac9012',
          processRunner: (exe, args, {workingDirectory}) async {
            final outIdx = args.indexOf('-o');
            File(args[outIdx + 1])
              ..parent.createSync(recursive: true)
              ..writeAsStringSync('fake-macho-binary');
            return ProcessResult(1, 0, '', '');
          },
        );

        final result = await packager.package(
          entryPath: entryFile.path,
          target: NativeBuildTarget.macos,
          outputDir: outDir,
          name: 'star_pilot',
          version: '0.2.0',
          workspaceDir: workspaceDir.path,
          librarySearchDirs: [libsDir.path],
        );

        expect(result.success, isTrue);
        expect(File('$outDir/star_pilot').existsSync(), isTrue);
        expect(File('$outDir/libSDL3.dylib').existsSync(), isTrue);
        expect(File('$outDir/libGLESv2.dylib').existsSync(), isTrue);
        expect(File('$outDir/libEGL.dylib').existsSync(), isTrue);
        expect(result.missingLibraries, isEmpty);

        final launcher = File('$outDir/launch_star_pilot.sh');
        expect(launcher.existsSync(), isTrue);
        expect(launcher.readAsStringSync(), contains('DYLD_LIBRARY_PATH'));
      },
    );

    test(
      'webview package generates csproj and copies JS + WinForms executable',
      () async {
        final hostDir = Directory(
          '${workspaceDir.path}/vendor/pixeldart/examples/desktop_host',
        )..createSync(recursive: true);
        File('${hostDir.path}/Program.cs').writeAsStringSync('// WebView2');
        File('${entryDir.path}/index.html').writeAsStringSync('<html></html>');

        final outDir = '${tempRoot.path}/out_webview';
        final packager = NativePackager(
          dartExecutable: 'dart',
          gitCommitResolver: () => 'web1234',
          processRunner: (exe, args, {workingDirectory}) async {
            if (args.contains('js')) {
              final outIdx = args.indexOf('-o');
              File(args[outIdx + 1])
                ..parent.createSync(recursive: true)
                ..writeAsStringSync('// compiled js');
              return ProcessResult(1, 0, '', '');
            }
            if (exe == 'dotnet') {
              final outIdx = args.indexOf('-o');
              final pubDir = Directory(args[outIdx + 1])
                ..createSync(recursive: true);
              File(
                '${pubDir.path}/GlVolitionGame.exe',
              ).writeAsStringSync('fake-webview-exe');
              return ProcessResult(2, 0, '', '');
            }
            return ProcessResult(3, 1, '', 'unexpected command');
          },
        );

        final result = await packager.package(
          entryPath: entryFile.path,
          target: NativeBuildTarget.webview,
          outputDir: outDir,
          name: 'star_pilot',
          version: '0.2.0',
          workspaceDir: workspaceDir.path,
        );

        expect(result.success, isTrue);
        expect(File('$outDir/index.html').existsSync(), isTrue);
        expect(File('$outDir/main.dart.js').existsSync(), isTrue);
        expect(File('$outDir/build/main.dart.js').existsSync(), isTrue);
        expect(
          File('$outDir/desktop/GlVolitionGame.csproj').existsSync(),
          isTrue,
        );
        expect(File('$outDir/GlVolitionGame.exe').existsSync(), isTrue);
        expect(File('$outDir/star_pilot.exe').existsSync(), isTrue);
        expect(File('$outDir/Launch_star_pilot.cmd').existsSync(), isTrue);
        expect(File('$outDir/launch_desktop.cmd').existsSync(), isTrue);

        final meta =
            jsonDecode(File('$outDir/metadata.json').readAsStringSync()) as Map;
        expect(meta['nativeAot'], isFalse);
        expect(meta['target'], 'webview');
      },
    );

    test(
      'returns failure cleanly when entry file is missing or compiler fails',
      () async {
        final packager = NativePackager(
          dartExecutable: 'dart',
          processRunner: (exe, args, {workingDirectory}) async =>
              ProcessResult(1, 2, '', 'compile failure'),
        );

        final missingRes = await packager.package(
          entryPath: '${tempRoot.path}/does_not_exist.dart',
          target: NativeBuildTarget.windows,
          outputDir: '${tempRoot.path}/missing_out',
          workspaceDir: workspaceDir.path,
        );
        expect(missingRes.success, isFalse);
        expect(missingRes.exitCode, 66);

        final compileFailOut = '${tempRoot.path}/fail_out';
        final failRes = await packager.package(
          entryPath: entryFile.path,
          target: NativeBuildTarget.windows,
          outputDir: compileFailOut,
          workspaceDir: workspaceDir.path,
        );
        expect(failRes.success, isFalse);
        expect(failRes.exitCode, 2);
        expect(failRes.errorMessage, contains('compile failure'));
        expect(File('$compileFailOut/metadata.json').existsSync(), isFalse);
      },
    );
  });
}
