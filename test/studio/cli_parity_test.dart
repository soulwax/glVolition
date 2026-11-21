/// S2-M test: Studio ⇄ CLI Parity Gate — verifies every registered Protocol v2
/// method declares a CLI mapping and `volition rpc <method> --json` executes
/// cleanly.
library;

import 'dart:convert';
import 'dart:io';

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S2-M — Studio ⇄ CLI Parity Gate', () {
    test(
      'every registered Studio Protocol v2 method declares a valid CLI command',
      () {
        final registry = StudioMethodRegistry();
        expect(registry.all.length, greaterThanOrEqualTo(15));
        for (final desc in registry.all) {
          expect(
            desc.cliCommand.trim(),
            isNotEmpty,
            reason: 'Method "${desc.method}" is missing a CLI mapping',
          );
          expect(
            desc.cliCommand.startsWith('volition ') ||
                desc.cliCommand.startsWith('dart '),
            isTrue,
            reason:
                'Method "${desc.method}" CLI mapping must start with volition/dart: '
                '${desc.cliCommand}',
          );
        }
      },
    );

    test('volition rpc studio.init --json and modules.list --json succeed', () {
      final initProc = Process.runSync(Platform.resolvedExecutable, [
        'run',
        'bin/volition.dart',
        'rpc',
        'studio.init',
        '--json',
      ]);
      expect(initProc.exitCode, equals(0), reason: '${initProc.stderr}');
      final initJson =
          jsonDecode(initProc.stdout.toString()) as Map<String, Object?>;
      expect(initJson['ok'], isTrue);
      expect((initJson['result'] as Map)['protocolVersion'], equals(2));

      final modProc = Process.runSync(Platform.resolvedExecutable, [
        'run',
        'bin/volition.dart',
        'rpc',
        'modules.list',
        '--json',
      ]);
      expect(modProc.exitCode, equals(0), reason: '${modProc.stderr}');
      final modJson =
          jsonDecode(modProc.stdout.toString()) as Map<String, Object?>;
      expect(modJson['ok'], isTrue);
      expect((modJson['result'] as Map)['total'], equals(74));
    });
  });
}
