/// Multi-client networked replication, delta compression, and rollback sync test suite (P6-W14-C).
library;

import 'dart:async';
import 'dart:io';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

class _TestTickHook implements NetworkTickHook {
  int preTickCount = 0;
  int postTickCount = 0;
  int reconcileCount = 0;
  Vec3 lastCorrection = Vec3.zero;

  @override
  void onPreFixedTick(NetworkManager manager, int tick, double dt) {
    preTickCount++;
  }

  @override
  void onPostFixedTick(NetworkManager manager, int tick, double dt) {
    postTickCount++;
  }

  @override
  void onSnapshotReconcile(
    NetworkIdentity identity,
    int serverTick,
    Vec3 correctionDelta,
  ) {
    reconcileCount++;
    lastCorrection = correctionDelta;
  }
}

void main() {
  group('P6-W14-C — Multiplayer Sync over WebSocketNetTransport', () {
    late WebSocketNetTransport serverTransport;
    late int serverPort;
    late Engine serverEngine;

    setUp(() async {
      serverTransport = await WebSocketNetTransport.bindServer(
        '127.0.0.1',
        0,
        serverPeerId: 0,
        pingInterval: const Duration(milliseconds: 25),
      );
      serverPort = serverTransport.port;
      serverEngine = Engine(HeadlessHost());
      serverEngine.scene.network.startServer(
        serverTransport: serverTransport,
        config: const NetworkSyncConfig(
          enableDeltaCompression: true,
          divergenceThresholdSq: 0.01,
        ),
      );
    });

    tearDown(() async {
      serverEngine.scene.network.stop();
      await serverTransport.closeAsync();
    });

    test(
      'multi-client entity replication, delta-skip, and clock synchronization',
      () async {
        final client1Transport = WebSocketNetTransport.connect(
          Uri.parse('ws://127.0.0.1:$serverPort'),
          pingInterval: const Duration(milliseconds: 25),
        );
        final client2Transport = WebSocketNetTransport.connect(
          Uri.parse('ws://127.0.0.1:$serverPort'),
          pingInterval: const Duration(milliseconds: 25),
        );

        final client1Engine = Engine(HeadlessHost());
        final client2Engine = Engine(HeadlessHost());

        addTearDown(() async {
          client1Engine.scene.network.stop();
          client2Engine.scene.network.stop();
          await client1Transport.closeAsync();
          await client2Transport.closeAsync();
        });

        await client1Transport.waitUntilConnected();
        await client2Transport.waitUntilConnected();
        await Future<void>.delayed(const Duration(milliseconds: 60));

        final c1Id = client1Transport.peerId;
        final c2Id = client2Transport.peerId;
        expect(c1Id, greaterThan(0));
        expect(c2Id, greaterThan(0));
        expect(c1Id, isNot(equals(c2Id)));

        client1Engine.scene.network.startClient(
          c1Id,
          clientTransport: client1Transport,
        );
        client2Engine.scene.network.startClient(
          c2Id,
          clientTransport: client2Transport,
        );

        // Server authoritative entity
        final serverObj = serverEngine.scene.createGameObject(
          'ServerProp',
          position: const Vec3(10.0, 20.0, 30.0),
        );
        serverObj.addComponent(NetworkIdentity(netId: 101, ownerPeerId: 0));
        serverObj.addComponent(
          NetworkTransform(interpolationDelaySeconds: 0.0),
        );

        // Client 1 & 2 proxies
        final c1Obj = client1Engine.scene.createGameObject(
          'ProxyProp1',
          position: Vec3.zero,
        );
        c1Obj.addComponent(NetworkIdentity(netId: 101, ownerPeerId: 0));
        c1Obj.addComponent(NetworkTransform(interpolationDelaySeconds: 0.0));

        final c2Obj = client2Engine.scene.createGameObject(
          'ProxyProp2',
          position: Vec3.zero,
        );
        c2Obj.addComponent(NetworkIdentity(netId: 101, ownerPeerId: 0));
        c2Obj.addComponent(NetworkTransform(interpolationDelaySeconds: 0.0));

        // Step server to emit snapshot
        serverEngine.step(0.05);

        // Allow async WebSocket frame dispatch
        await Future<void>.delayed(const Duration(milliseconds: 40));

        // Step clients to poll and apply snapshot
        client1Engine.step(0.05);
        client2Engine.step(0.05);

        expect(c1Obj.transform.position.x, closeTo(10.0, 0.01));
        expect(c1Obj.transform.position.y, closeTo(20.0, 0.01));
        expect(c1Obj.transform.position.z, closeTo(30.0, 0.01));

        expect(c2Obj.transform.position.x, closeTo(10.0, 0.01));
        expect(c2Obj.transform.position.y, closeTo(20.0, 0.01));
        expect(c2Obj.transform.position.z, closeTo(30.0, 0.01));

        expect(
          serverEngine.scene.network.stats.snapshotsSent,
          greaterThanOrEqualTo(1),
        );

        // Step server without moving the object -> delta compression should skip broadcast
        final initialDeltaSkipped =
            serverEngine.scene.network.stats.snapshotsDeltaSkipped;
        serverEngine.step(0.05);
        expect(
          serverEngine.scene.network.stats.snapshotsDeltaSkipped,
          greaterThan(initialDeltaSkipped),
        );

        // Send a ping message from client1 to server to verify clock sync calculation
        client1Engine.scene.network.transport?.send(
          0,
          MessageRegistry.serialize(PingMsg(1000)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
        serverEngine.step(0.05);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        client1Engine.step(0.05);

        expect(
          client1Engine.scene.network.clockSync.sampleCount,
          greaterThan(0),
        );
      },
    );

    test(
      'client-side prediction rolls back and reconciles upon server divergence',
      () async {
        final clientTransport = WebSocketNetTransport.connect(
          Uri.parse('ws://127.0.0.1:$serverPort'),
        );
        final clientEngine = Engine(HeadlessHost());
        final hook = _TestTickHook();

        addTearDown(() async {
          clientEngine.scene.network.stop();
          await clientTransport.closeAsync();
        });

        await clientTransport.waitUntilConnected();
        await Future<void>.delayed(const Duration(milliseconds: 40));

        final cId = clientTransport.peerId;
        clientEngine.scene.network.startClient(
          cId,
          clientTransport: clientTransport,
          hook: hook,
          config: const NetworkSyncConfig(
            divergenceThresholdSq: 0.01, // 10cm threshold
          ),
        );

        // Client owned entity
        final clientPlayer = clientEngine.scene.createGameObject(
          'Player',
          position: const Vec3(0.0, 0.0, 0.0),
        );
        clientPlayer.addComponent(
          NetworkIdentity(netId: 202, ownerPeerId: cId),
        );
        final clientTransform = clientPlayer.addComponent(
          NetworkTransform(
            enablePrediction: true,
            interpolationDelaySeconds: 0.0,
          ),
        );

        // Client predicts 3 ticks of movement at velocity (2.0, 0, 0)
        clientEngine.scene.network.currentTick = 10;
        clientPlayer.transform.position = const Vec3(2.0, 0.0, 0.0);
        clientTransform.recordPrediction(
          10,
          const Vec3(2.0, 0.0, 0.0),
          const Vec3(2.0, 0.0, 0.0),
        );

        clientEngine.scene.network.currentTick = 11;
        clientPlayer.transform.position = const Vec3(4.0, 0.0, 0.0);
        clientTransform.recordPrediction(
          11,
          const Vec3(2.0, 0.0, 0.0),
          const Vec3(4.0, 0.0, 0.0),
        );

        clientEngine.scene.network.currentTick = 12;
        clientPlayer.transform.position = const Vec3(6.0, 0.0, 0.0);
        clientTransform.recordPrediction(
          12,
          const Vec3(2.0, 0.0, 0.0),
          const Vec3(6.0, 0.0, 0.0),
        );

        expect(clientPlayer.transform.position.x, closeTo(6.0, 0.001));

        // Authoritative server sends snapshot for tick 10 saying true pos was (1.0, 0.0, 0.0)
        // Divergence = (2.0 - 1.0)^2 = 1.0 > 0.01 threshold!
        clientTransform.receiveSnapshot(
          tick: 10,
          timestampMs: 500,
          position: const Vec3(1.0, 0.0, 0.0),
          rotation: Quat.identity,
          velocity: const Vec3(2.0, 0.0, 0.0),
        );

        // Reconcile replayed ticks 11 and 12:
        // tick 11: 1.0 + 2.0 * 0.02 = 1.04
        // tick 12: 1.04 + 2.0 * 0.02 = 1.08
        expect(hook.reconcileCount, equals(1));
        expect(
          clientEngine.scene.network.stats.rollbackReconciliations,
          equals(1),
        );
        expect(clientPlayer.transform.position.x, closeTo(1.08, 0.01));
      },
    );
  });

  group(
    'P6-W14-C — Multiplayer Sync over UdpNetTransport with Fault Injection',
    () {
      test(
        'converges entity state over RawDatagramSocket under simulated packet drop and jitter',
        () async {
          final serverTransport = await UdpNetTransport.bind(
            InternetAddress.loopbackIPv4,
            0,
            localPeerId: 0,
            authOptions: const NetTransportAuthOptions(
              bearerToken: 'udp-sync-key',
            ),
            maxMtuBytes: 512,
          );

          final clientTransport = await UdpNetTransport.connect(
            InternetAddress.loopbackIPv4,
            serverTransport.port,
            localPeerId: 44,
            remotePeerId: 0,
            authOptions: const NetTransportAuthOptions(
              bearerToken: 'udp-sync-key',
            ),
            maxMtuBytes: 512,
            faultInjector: UdpFaultInjector(
              dropProbability: 0.05,
              reorderProbability: 0.10,
              minLatencyMs: 1,
              maxJitterMs: 5,
              seed: 4242,
            ),
          );

          final serverEngine = Engine(HeadlessHost());
          final clientEngine = Engine(HeadlessHost());

          addTearDown(() async {
            serverEngine.scene.network.stop();
            clientEngine.scene.network.stop();
            await clientTransport.closeAsync();
            await serverTransport.closeAsync();
          });

          // Wait for UDP handshake
          final deadline = DateTime.now().add(const Duration(seconds: 4));
          while (DateTime.now().isBefore(deadline)) {
            serverTransport.poll();
            clientTransport.poll();
            if (clientTransport.connectionState ==
                    NetConnectionState.connected &&
                serverTransport.connectedPeerIds.contains(44)) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }

          expect(clientTransport.connectionState, NetConnectionState.connected);
          expect(serverTransport.connectedPeerIds, contains(44));

          serverEngine.scene.network.startServer(
            serverTransport: serverTransport,
            config: const NetworkSyncConfig(enableDeltaCompression: false),
          );
          clientEngine.scene.network.startClient(
            44,
            clientTransport: clientTransport,
          );

          final serverEntity = serverEngine.scene.createGameObject(
            'ServerBot',
            position: const Vec3(42.0, -7.0, 15.0),
          );
          serverEntity.addComponent(
            NetworkIdentity(netId: 303, ownerPeerId: 0),
          );
          serverEntity.addComponent(
            NetworkTransform(interpolationDelaySeconds: 0.0),
          );

          final clientProxy = clientEngine.scene.createGameObject(
            'ProxyBot',
            position: Vec3.zero,
          );
          clientProxy.addComponent(NetworkIdentity(netId: 303, ownerPeerId: 0));
          clientProxy.addComponent(
            NetworkTransform(interpolationDelaySeconds: 0.0),
          );

          // Drive multiple simulation steps so packets traverse the socket and fault injector
          for (var step = 0; step < 10; step++) {
            serverEngine.step(0.02);
            clientEngine.step(0.02);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }

          expect(clientProxy.transform.position.x, closeTo(42.0, 0.01));
          expect(clientProxy.transform.position.y, closeTo(-7.0, 0.01));
          expect(clientProxy.transform.position.z, closeTo(15.0, 0.01));
        },
      );
    },
  );
}
