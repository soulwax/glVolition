import 'dart:async';
import 'dart:io';

import '../../gl_volition.dart';

final serverLog = voxlog.stdoutColor('volition-server', level: LogLevel.info);

/// Headless dedicated zero-GPU multiplayer game server runner (P7-W15-C).
class DedicatedServerHost {
  final Engine engine;
  final int tickRateHz;
  final int port;
  final String bindAddress;
  final bool enableWebSockets;
  final String? authToken;

  bool _running = false;
  Timer? _tickTimer;
  int _ticksExecuted = 0;

  DedicatedServerHost({
    Engine? engine,
    this.tickRateHz = 30,
    this.port = 7777,
    this.bindAddress = '0.0.0.0',
    this.enableWebSockets = false,
    this.authToken,
  }) : engine = engine ?? Engine(HeadlessHost());

  bool get isRunning => _running;
  int get ticksExecuted => _ticksExecuted;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    serverLog.info(
      'Starting DedicatedServerHost on $bindAddress:$port at $tickRateHz Hz (WS: $enableWebSockets)',
    );

    // Setup network transport if needed
    if (enableWebSockets) {
      final wsServer = await WebSocketNetTransport.bindServer(
        bindAddress,
        port,
        serverPeerId: 0,
        authOptions: NetTransportAuthOptions(bearerToken: authToken),
      );
      engine.scene.network.startServer(
        serverTransport: wsServer,
        config: NetworkSyncConfig(
          snapshotRateHz: tickRateHz.toDouble(),
          auth: NetTransportAuthOptions(bearerToken: authToken),
        ),
      );
    } else {
      final udpServer = await UdpNetTransport.bind(
        InternetAddress(bindAddress),
        port,
        localPeerId: 0,
        authOptions: NetTransportAuthOptions(bearerToken: authToken),
      );
      engine.scene.network.startServer(
        serverTransport: udpServer,
        config: NetworkSyncConfig(
          snapshotRateHz: tickRateHz.toDouble(),
          auth: NetTransportAuthOptions(bearerToken: authToken),
        ),
      );
    }

    final dt = 1.0 / tickRateHz;
    final intervalMs = (dt * 1000).round();

    _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!_running) return;
      stepTick(dt);
    });
  }

  void stepTick(double dt) {
    _ticksExecuted++;
    engine.step(dt);
  }

  void stop() {
    _running = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    engine.scene.network.stop();
    serverLog.info('DedicatedServerHost stopped after $_ticksExecuted ticks.');
  }
}
