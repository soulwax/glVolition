/// S2-A test: VolitionGuiServer speaking Studio Protocol v2 over loopback
/// WebSocket alongside legacy v1 compatibility.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

import '../../tool/cli_gui_server.dart';

void main() {
  group('S2-A — VolitionGuiServer Protocol v2', () {
    test(
      'handles typed StudioRequest/StudioResponse envelopes over WebSocket',
      () async {
        final server = VolitionGuiServer();
        final uri = await server.start(port: 0);
        final wsUrl = 'ws://127.0.0.1:${uri.port}/ws';
        final ws = await WebSocket.connect(wsUrl);

        final codec = const StudioProtocolCodec();
        final responses = StreamIterator<dynamic>(ws);

        try {
          // 1. studio.init
          ws.add(
            codec.encode(const StudioRequest(id: 'r1', method: 'studio.init')),
          );
          expect(await responses.moveNext(), isTrue);
          final initRes =
              codec.decode(responses.current as String) as StudioResponse;
          expect(initRes.id, equals('r1'));
          expect(initRes.ok, isTrue);
          expect(initRes.result?['protocolVersion'], equals(2));

          // 2. modules.list -> 74 vendor packages
          ws.add(
            codec.encode(const StudioRequest(id: 'r2', method: 'modules.list')),
          );
          expect(await responses.moveNext(), isTrue);
          final modRes =
              codec.decode(responses.current as String) as StudioResponse;
          expect(modRes.ok, isTrue);
          expect(modRes.result?['total'], equals(74));

          // 3. Unknown method returns typed methodNotFound error
          ws.add(
            codec.encode(
              const StudioRequest(id: 'r3', method: 'does.not.exist'),
            ),
          );
          expect(await responses.moveNext(), isTrue);
          final errRes =
              codec.decode(responses.current as String) as StudioResponse;
          expect(errRes.ok, isFalse);
          expect(errRes.error?.code, equals(StudioErrorCode.methodNotFound));

          // 4. Legacy v1 alias still works
          ws.add(jsonEncode({'id': 'legacy1', 'method': 'entries.list'}));
          expect(await responses.moveNext(), isTrue);
          final v1 =
              jsonDecode(responses.current as String) as Map<String, Object?>;
          expect(v1['type'], equals('entries.result'));
        } finally {
          await responses.cancel();
          await ws.close();
          await server.stop();
        }
      },
    );
  });
}
