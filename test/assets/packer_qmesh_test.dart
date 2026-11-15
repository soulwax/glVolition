import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:pixeldart/rendering/assets/qmesh.dart';
import 'package:test/test.dart';

import '../../tool/asset_packer.dart';

String _sampleCubeLut({
  String title = 'Retro Warm 4x4x4',
  int size = 4,
  String lineEnding = '\n',
}) {
  final lines = <String>[
    '# Sample Adobe 3D LUT',
    'TITLE "$title"',
    'LUT_3D_SIZE $size',
    'DOMAIN_MIN 0.0 0.0 0.0',
    'DOMAIN_MAX 1.0 1.0 1.0',
    '',
  ];
  final denom = (size - 1).toDouble();
  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        final rr = (r / denom * 0.9 + 0.05).toStringAsFixed(6);
        final gg = (g / denom * 0.85 + 0.02).toStringAsFixed(6);
        final bb = (b / denom * 0.8).toStringAsFixed(6);
        lines.add('$rr $gg $bb');
      }
    }
  }
  return '${lines.join(lineEnding)}$lineEnding';
}

const String _sampleObj = '''
# Sample unit wedge with two materials and a quad face
mtllib crate.mtl
v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
v 0 0 1
vt 0 0
vt 1 0
vt 1 1
vt 0 1
vn 0 0 -1
vn 0 -1 0
usemtl oak
f 1/1/1 2/2/1 3/3/1 4/4/1
usemtl trim
f 1/1/2 2/2/2 5/3/2
''';

const String _sampleMtl = '''
newmtl oak
Kd 0.6 0.4 0.2
Ks 0.1 0.1 0.1
Ns 16
map_Kd textures/oak_albedo.png

newmtl trim
Kd 0.2 0.25 0.3
Ks 0.4 0.4 0.4
Ns 64
''';

void main() {
  group('OBJ -> QMSH model package pipeline', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('volition_qmesh_test_');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('cooks OBJ + MTL + texture sidecar to valid QMSH package', () async {
      final srcDir = Directory('${tempRoot.path}/src')..createSync();
      Directory('${srcDir.path}/textures').createSync();
      File('${srcDir.path}/crate.obj').writeAsStringSync(_sampleObj);
      File('${srcDir.path}/crate.mtl').writeAsStringSync(_sampleMtl);
      File(
        '${srcDir.path}/textures/oak_albedo.png',
      ).writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

      final pkgDir = Directory('${tempRoot.path}/cooked/crate');
      final cooked = await cookObjFileToDirectory(
        objFile: File('${srcDir.path}/crate.obj'),
        outputDir: pkgDir,
        licenseId: 'cc0-1.0',
      );

      expect(cooked.isValid, isTrue);
      expect(cooked.manifest.assetId, 'crate');
      expect(cooked.manifest.materials, ['oak', 'trim']);
      expect(cooked.manifest.parts, hasLength(2));
      expect(cooked.manifest.textures, ['textures/oak_albedo.png']);
      expect(cooked.manifest.combinedBounds, [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]);

      expect(File('${pkgDir.path}/manifest.json').existsSync(), isTrue);
      expect(File('${pkgDir.path}/mesh-000.qmesh').existsSync(), isTrue);
      expect(File('${pkgDir.path}/mesh-001.qmesh').existsSync(), isTrue);
      expect(
        File('${pkgDir.path}/textures/oak_albedo.png').existsSync(),
        isTrue,
      );
      expect(File('${pkgDir.path}/sidecars.sha256.json').existsSync(), isTrue);

      final dirDiagnostics = validateModelPackageDirectory(pkgDir);
      expect(dirDiagnostics, isEmpty);

      final oakMesh = decodeQmesh(
        File('${pkgDir.path}/mesh-000.qmesh').readAsBytesSync(),
      );
      expect(oakMesh.vertexCount, 6); // Quad triangulated to 2 triangles.
      final trimMesh = decodeQmesh(
        File('${pkgDir.path}/mesh-001.qmesh').readAsBytesSync(),
      );
      expect(trimMesh.vertexCount, 3);
    });

    test(
      'sidecar validation detects missing texture and tampered payload',
      () async {
        final srcDir = Directory('${tempRoot.path}/src2')..createSync();
        Directory('${srcDir.path}/textures').createSync();
        File('${srcDir.path}/crate.obj').writeAsStringSync(_sampleObj);
        File('${srcDir.path}/crate.mtl').writeAsStringSync(_sampleMtl);
        File(
          '${srcDir.path}/textures/oak_albedo.png',
        ).writeAsBytesSync([1, 2, 3]);

        final pkgDir = Directory('${tempRoot.path}/cooked2/crate');
        await cookObjFileToDirectory(
          objFile: File('${srcDir.path}/crate.obj'),
          outputDir: pkgDir,
        );
        expect(validateModelPackageDirectory(pkgDir), isEmpty);

        // Remove declared texture sidecar.
        File('${pkgDir.path}/textures/oak_albedo.png').deleteSync();
        final missingTex = validateModelPackageDirectory(pkgDir);
        expect(
          missingTex.any((d) => d.code == 'MODEL_PACKAGE_TEXTURE_MISSING'),
          isTrue,
        );

        // Corrupt mesh payload and check hash + checksum diagnostics.
        File('${pkgDir.path}/mesh-000.qmesh').writeAsBytesSync([0, 1, 2, 3]);
        final corrupt = validateModelPackageDirectory(pkgDir);
        expect(
          corrupt.any((d) => d.code == 'MODEL_PACKAGE_INVALID_QMESH'),
          isTrue,
        );
        expect(
          corrupt.any((d) => d.code == 'MODEL_PACKAGE_PAYLOAD_HASH'),
          isTrue,
        );
        expect(corrupt.any((d) => d.code == 'SIDECAR_LENGTH_MISMATCH'), isTrue);
      },
    );
  });

  group('Adobe .cube 3D LUT parsing, serialization, and LutAsset loading', () {
    test('parses .cube, serializes .qlut, and loads back into LutAsset', () {
      final cubeText = _sampleCubeLut(
        title: 'VHS Warmth',
        size: 4,
        lineEnding: '\r\n',
      );
      final parsed = parseCubeLut(cubeText);
      expect(parsed.title, 'VHS Warmth');
      expect(parsed.size, 4);
      expect(parsed.texelCount, 64);
      expect(parsed.domainMin, [0.0, 0.0, 0.0]);
      expect(parsed.domainMax, [1.0, 1.0, 1.0]);
      expect(parsed.rgbData.length, 64 * 3);

      final packedBytes = encodePackedLut(parsed);
      final loaded = loadPackedLutAsset(packedBytes, key: 'luts/vhs_warmth');
      expect(loaded, isA<LutAsset>());
      expect(loaded.key, 'luts/vhs_warmth');
      expect(loaded.title, 'VHS Warmth');
      expect(loaded.size, 4);
      expect(loaded.texelCount, 64);
      expect(loaded.rgbData, equals(parsed.rgbData));

      // Re-encoding from LutAsset produces identical bytes.
      expect(encodeLutAsset(loaded), equals(packedBytes));
    });

    test('rejects 1D LUTs, wrong triplet counts, and inverted domains', () {
      expect(
        () => parseCubeLut('LUT_1D_SIZE 16\n0 0 0\n'),
        throwsFormatException,
      );
      expect(
        () => parseCubeLut('LUT_3D_SIZE 2\n0 0 0\n1 1 1\n'),
        throwsFormatException,
      );
      expect(
        () => parseCubeLut(
          'LUT_3D_SIZE 2\nDOMAIN_MIN 1 0 0\nDOMAIN_MAX 0 1 1\n'
          '0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n',
        ),
        throwsFormatException,
      );
      expect(
        () => decodePackedLut(Uint8List.fromList([0x51, 0x4C, 0x55, 0x54])),
        throwsFormatException,
      );
    });
  });

  group('Deterministic .pak packing, VFS mounting, and CLI', () {
    late Directory tempRoot;
    late Directory sourceDir;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('volition_pak_test_');
      sourceDir = Directory('${tempRoot.path}/assets')..createSync();

      Directory(
        '${sourceDir.path}/models/textures',
      ).createSync(recursive: true);
      File('${sourceDir.path}/models/crate.obj').writeAsStringSync(_sampleObj);
      File('${sourceDir.path}/models/crate.mtl').writeAsStringSync(_sampleMtl);
      File(
        '${sourceDir.path}/models/textures/oak_albedo.png',
      ).writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);

      Directory('${sourceDir.path}/luts').createSync(recursive: true);
      File(
        '${sourceDir.path}/luts/warm.cube',
      ).writeAsStringSync(_sampleCubeLut(title: 'Amber Grade', size: 4));

      Directory('${sourceDir.path}/config').createSync(recursive: true);
      File(
        '${sourceDir.path}/config/game.json',
      ).writeAsStringSync('{"version":1,"title":"Test"}');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test(
      'packs deterministic .pak, mounts via PakArchive & VfsAssetLoader, and verifies sidecars',
      () async {
        final pakA = File('${tempRoot.path}/out/bundle_a.pak');
        final pakB = File('${tempRoot.path}/out/bundle_b.pak');
        final sidecarFile = File('${tempRoot.path}/out/bundle_a.manifest.json');
        final dryRunPak = File('${tempRoot.path}/out/dry_run.pak');

        final dryReport = await packAssetDirectory(
          sourceDir: sourceDir,
          outputPak: dryRunPak,
          dryRun: true,
        );
        expect(dryReport.dryRun, isTrue);
        expect(dryRunPak.existsSync(), isFalse);
        expect(dryReport.cookedModels, ['models/crate.obj']);
        expect(dryReport.cookedLuts, ['luts/warm.cube']);

        final reportA = await packAssetDirectory(
          sourceDir: sourceDir,
          outputPak: pakA,
          sidecarManifestOut: sidecarFile,
        );
        final reportB = await packAssetDirectory(
          sourceDir: sourceDir,
          outputPak: pakB,
        );

        expect(reportA.dryRun, isFalse);
        expect(reportB.dryRun, isFalse);
        expect(reportB.entries.length, reportA.entries.length);
        final bytesA = pakA.readAsBytesSync();
        final bytesB = pakB.readAsBytesSync();
        expect(bytesA, equals(bytesB)); // Byte-for-byte deterministic.

        // Verify via PakArchive.parse.
        final archive = PakArchive.parse(bytesA, verifyTocChecksum: true);
        final paths = archive.entries.map((e) => e.path).toList()..sort();
        expect(
          paths,
          containsAll([
            'config/game.json',
            'luts/warm.qlut',
            'models/crate/manifest.json',
            'models/crate/mesh-000.qmesh',
            'models/crate/mesh-001.qmesh',
            'models/crate/textures/oak_albedo.png',
          ]),
        );
        // No un-cooked source files leaked into .pak.
        expect(paths.any((p) => p.endsWith('.obj')), isFalse);
        expect(paths.any((p) => p.endsWith('.mtl')), isFalse);
        expect(paths.any((p) => p.endsWith('.cube')), isFalse);

        // Load packed LUT back into LutAsset via PakArchive and VfsAssetLoader.
        final lutFromPak = loadLutAssetFromPak(archive, 'luts/warm.qlut');
        expect(lutFromPak.title, 'Amber Grade');
        expect(lutFromPak.size, 4);
        expect(lutFromPak.texelCount, 64);

        final vfsLoader = VfsAssetLoader()..mountPakBytes('bundle', bytesA);
        final lutFromVfs = await loadLutAssetFromVfs(
          vfsLoader,
          'luts/warm.qlut',
        );
        expect(lutFromVfs.rgbData, equals(lutFromPak.rgbData));
        expect(
          jsonDecode(await vfsLoader.loadText('config/game.json'))['title'],
          'Test',
        );

        // Load packed QMSH model package through ModelPackageLoader from PakArchive.
        final manifestJson =
            jsonDecode(archive.readText('models/crate/manifest.json')!)
                as Map<String, dynamic>;
        final manifest = ModelPackageManifest.fromJson(manifestJson);
        final loadedPkg = await const ModelPackageLoader().load(
          ModelPackageSource(
            manifest: manifest,
            load: (relPath) async =>
                archive.readBytes('models/crate/$relPath')!,
          ),
          limits: const ModelPackageLimits(requireQmeshPayloads: true),
        );
        expect(loadedPkg.payloads.keys, {'mesh-000.qmesh', 'mesh-001.qmesh'});

        // Verify sidecar manifest checks pass and detect tampering.
        final sidecarMap =
            jsonDecode(sidecarFile.readAsStringSync()) as Map<String, dynamic>;
        expect(
          verifyPakArchiveBytes(bytesA, sidecarManifest: sidecarMap),
          isEmpty,
        );

        final tamperedSidecar = Map<String, dynamic>.from(sidecarMap)
          ..['archiveSha256'] = '0' * 64;
        expect(
          verifyPakArchiveBytes(
            bytesA,
            sidecarManifest: tamperedSidecar,
          ).any((d) => d.code == 'PAK_ARCHIVE_SHA_MISMATCH'),
          isTrue,
        );
      },
    );

    test(
      'CLI runner executes pack --dry-run, pack, and validate cleanly',
      () async {
        final pakOut = File('${tempRoot.path}/cli.pak');
        final sidecarOut = File('${tempRoot.path}/cli.manifest.json');
        final logs = <String>[];
        final errors = <String>[];

        final dryCode = await runAssetPackerCli(
          ['pack', '--in', sourceDir.path, '--out', pakOut.path, '--dry-run'],
          log: logs.add,
          onError: errors.add,
        );
        expect(dryCode, 0);
        expect(errors, isEmpty);
        expect(pakOut.existsSync(), isFalse);
        expect(logs.join('\n'), contains('Dry-run asset pack plan'));

        final packCode = await runAssetPackerCli(
          [
            'pack',
            '--in',
            sourceDir.path,
            '--out',
            pakOut.path,
            '--manifest',
            sidecarOut.path,
          ],
          log: logs.add,
          onError: errors.add,
        );
        expect(packCode, 0);
        expect(errors, isEmpty);
        expect(pakOut.existsSync(), isTrue);

        final validateCode = await runAssetPackerCli(
          ['validate', pakOut.path, '--manifest', sidecarOut.path],
          log: logs.add,
          onError: errors.add,
        );
        expect(validateCode, 0);
        expect(errors, isEmpty);
      },
    );
  });
}
