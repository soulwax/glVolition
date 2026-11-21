/// Volition Studio Protocol v2 Daemon (S2-A / S2-M):
/// Dispatches typed [StudioRequest] envelopes over [ProjectFileSystem],
/// [AssetDatabase], [StudioModuleRegistry], and [VolitionCliService], with
/// atomic GUID scene save/load and `.volition/autosave/` crash recovery.
library;

import 'dart:convert';
import 'dart:io';

import 'package:gl_volition/src/studio/studio.dart';

import '../cli_service.dart';
import 'io_project_fs.dart';

const String kAutosaveDir = '.volition/autosave';

/// Platform-neutral + IO-backed Studio Protocol v2 RPC daemon.
final class StudioDaemon {
  final VolitionCliService cliService;
  final ProjectFileSystem fs;
  final AssetDatabase assetDatabase;
  final StudioMethodRegistry methodRegistry;
  final StudioModuleRegistry moduleRegistry;

  VolitionProjectConfig? _projectConfig;

  StudioDaemon({
    VolitionCliService? cliService,
    ProjectFileSystem? fs,
    AssetDatabase? assetDatabase,
    StudioMethodRegistry? methodRegistry,
    StudioModuleRegistry? moduleRegistry,
  }) : cliService = cliService ?? VolitionCliService(),
       fs = fs ?? IoProjectFileSystem(Directory.current),
       methodRegistry = methodRegistry ?? StudioMethodRegistry(),
       moduleRegistry =
           moduleRegistry ?? StudioModuleRegistry(kStudioModuleInventory),
       assetDatabase =
           assetDatabase ??
           AssetDatabase(fs ?? IoProjectFileSystem(Directory.current));

  VolitionProjectConfig? get projectConfig => _projectConfig;

  /// Executes a typed Studio Protocol v2 [request] and returns a typed
  /// [StudioResponse].
  Future<StudioResponse> dispatch(StudioRequest request) async {
    final p = request.params;
    try {
      switch (request.method) {
        case 'studio.init':
          return StudioResponse.ok(request.id, {
            'protocolVersion': studioProtocolVersion,
            'workingDirectory': cliService.workingDirectory,
            'serveStatus': cliService.serveStatus,
            'methods': [
              for (final m in methodRegistry.all)
                {
                  'method': m.method,
                  'cliCommand': m.cliCommand,
                  'summary': m.summary,
                },
            ],
          });

        case 'doctor.run':
          final report = await cliService.runDoctor();
          return StudioResponse.ok(request.id, {'report': report.toJson()});

        case 'entries.list':
          return StudioResponse.ok(request.id, {
            'entries': cliService.discoverEntries(),
          });

        case 'inspector.list':
          return StudioResponse.ok(request.id, {
            'files': cliService.discoverInspectableFiles(),
          });

        case 'inspector.inspect':
          final path = (p['path'] as String? ?? '').trim();
          if (path.isEmpty) {
            return StudioResponse.err(
              request.id,
              const StudioError(
                code: StudioErrorCode.invalidParams,
                message: 'Parameter "path" is required.',
              ),
            );
          }
          final xorKey = (p['xorKey'] as num?)?.toInt();
          return StudioResponse.ok(request.id, {
            'report': cliService.inspectArtifact(path, xorKey: xorKey),
          });

        case 'tape.verify':
          final path = (p['path'] as String? ?? '').trim();
          if (path.isEmpty) {
            return StudioResponse.err(
              request.id,
              const StudioError(
                code: StudioErrorCode.invalidParams,
                message: 'Parameter "path" is required.',
              ),
            );
          }
          return StudioResponse.ok(request.id, {
            'result': cliService.verifyInputTapeFile(path),
          });

        case 'modules.list':
          return StudioResponse.ok(request.id, {
            'total': moduleRegistry.length,
            'modules': [for (final m in moduleRegistry.all) m.toJson()],
          });

        case 'project.open':
          if (await fs.exists(kProjectManifestFilename)) {
            _projectConfig = await VolitionProjectConfig.load(fs);
          } else {
            _projectConfig = VolitionProjectConfig(
              name: (p['name'] as String?) ?? 'VolitionProject',
            );
          }
          await assetDatabase.refresh();
          return StudioResponse.ok(request.id, {
            'project': _projectConfig!.toJson(),
            'assetCount': assetDatabase.allAssets.length,
          });

        case 'assets.list':
          await assetDatabase.refresh();
          return StudioResponse.ok(request.id, {
            'assets': [
              for (final a in assetDatabase.allAssets)
                {
                  'guid': a.guid,
                  'path': a.path,
                  'importerId': a.meta.importerId,
                  'contentHash': a.meta.contentHash,
                },
            ],
            'orphanMetas': assetDatabase.orphanMetas,
          });

        case 'assets.reimport':
          final guid = (p['guid'] as String? ?? '').trim();
          if (guid.isNotEmpty) {
            final settings =
                (p['settings'] as Map?)?.cast<String, Object?>() ?? const {};
            final updated = await assetDatabase.updateImportSettings(
              guid,
              settings,
            );
            return StudioResponse.ok(request.id, {'reimportedGuids': updated});
          }
          await assetDatabase.refresh();
          return StudioResponse.ok(request.id, {
            'assetCount': assetDatabase.allAssets.length,
            'importCount': assetDatabase.importCount,
          });

        case 'scene.save':
          final path = (p['path'] as String? ?? '').trim();
          final sceneJson = p['scene'];
          if (path.isEmpty || sceneJson is! Map) {
            return StudioResponse.err(
              request.id,
              const StudioError(
                code: StudioErrorCode.invalidParams,
                message:
                    'Parameters "path" (String) and "scene" (Map) required.',
              ),
            );
          }
          final encoded = const JsonEncoder.withIndent('  ').convert(sceneJson);
          await fs.writeString(path, encoded);
          final autosavePath = _autosavePathFor(path);
          await fs.writeString(autosavePath, encoded);
          return StudioResponse.ok(request.id, {
            'path': normalizeProjectPath(path),
            'autosavePath': autosavePath,
            'byteLength': encoded.length,
          });

        case 'scene.load':
          final path = (p['path'] as String? ?? '').trim();
          final useAutosave = p['useAutosave'] == true;
          if (path.isEmpty) {
            return StudioResponse.err(
              request.id,
              const StudioError(
                code: StudioErrorCode.invalidParams,
                message: 'Parameter "path" is required.',
              ),
            );
          }
          final target = useAutosave ? _autosavePathFor(path) : path;
          if (!await fs.exists(target)) {
            return StudioResponse.err(
              request.id,
              StudioError(
                code: StudioErrorCode.assetNotFound,
                message: 'Scene not found: $target',
              ),
            );
          }
          final raw = await fs.readString(target);
          final decoded = jsonDecode(raw) as Map<String, Object?>;
          return StudioResponse.ok(request.id, {
            'path': normalizeProjectPath(target),
            'scene': decoded,
          });

        default:
          return StudioResponse.err(
            request.id,
            StudioError(
              code: StudioErrorCode.methodNotFound,
              message: 'Unknown Studio Protocol v2 method: ${request.method}',
            ),
          );
      }
    } catch (e) {
      return StudioResponse.err(
        request.id,
        StudioError(code: StudioErrorCode.internalError, message: '$e'),
      );
    }
  }

  static String _autosavePathFor(String scenePath) {
    final norm = normalizeProjectPath(scenePath).replaceAll('/', '__');
    return '$kAutosaveDir/$norm.autosave.json';
  }
}
