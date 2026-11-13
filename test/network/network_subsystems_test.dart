/// Networking, RPC replication & deterministic rollback subsystem tests (E33, E73).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('E33 — NetworkManager, NetworkTransform & RPC Dispatch', () {
    test(
      'E33: NetworkManager and NetworkTransform replicate state across loopback transport',
      () {
        final net = LoopbackNetwork();
        final serverTransport = net.createEndpoint(0);
        final clientTransport = net.createEndpoint(1);

        final serverHost = HeadlessHost();
        final serverEngine = Engine(serverHost);
        serverEngine.scene.network.startServer(
          serverTransport: serverTransport,
        );

        final clientHost = HeadlessHost();
        final clientEngine = Engine(clientHost);
        clientEngine.scene.network.startClient(
          1,
          clientTransport: clientTransport,
        );

        // Server entity
        final serverGo = serverEngine.scene.createGameObject(
          'Player',
          position: const Vec3(0.0, 0.0, 0.0),
        );
        serverGo.addComponent(NetworkIdentity(netId: 10, ownerPeerId: 0));
        serverGo.addComponent(NetworkTransform(interpolationDelaySeconds: 0.0));

        // Client proxy entity
        final clientGo = clientEngine.scene.createGameObject(
          'PlayerProxy',
          position: const Vec3(0.0, 0.0, 0.0),
        );
        clientGo.addComponent(NetworkIdentity(netId: 10, ownerPeerId: 0));
        clientGo.addComponent(NetworkTransform(interpolationDelaySeconds: 0.0));

        // Move server entity
        serverGo.transform.position = const Vec3(15.0, 2.0, -5.0);

        // Step server (broadcasts snapshot)
        serverEngine.step(0.05);

        // Step client (receives snapshot and applies interpolation)
        clientEngine.step(0.05);

        expect(clientGo.transform.position.x, closeTo(15.0, 0.01));
        expect(clientGo.transform.position.y, closeTo(2.0, 0.01));
        expect(clientGo.transform.position.z, closeTo(-5.0, 0.01));
      },
    );

    test('E33: NetworkManager sends and dispatches RPCs', () {
      final net = LoopbackNetwork();
      final serverTransport = net.createEndpoint(0);
      final clientTransport = net.createEndpoint(1);

      final serverEngine = Engine(HeadlessHost());
      serverEngine.scene.network.startServer(serverTransport: serverTransport);

      final clientEngine = Engine(HeadlessHost());
      clientEngine.scene.network.startClient(
        1,
        clientTransport: clientTransport,
      );

      var rpcReceived = false;
      var receivedDamage = 0;

      clientEngine.scene.network.rpc.register('applyDamage', (
        senderId,
        payload,
      ) {
        rpcReceived = true;
        receivedDamage = ByteReader(payload).readInt32();
      });

      final payload = ByteWriter()..writeInt32(85);
      serverEngine.scene.network.sendRpc(
        1,
        'applyDamage',
        payload.toBytes(),
        recipientId: 1,
      );

      // Step client to process network messages
      clientEngine.step(0.05);

      expect(rpcReceived, isTrue);
      expect(receivedDamage, equals(85));
    });
  });

  group('E73 — Deterministic Rollback Frames & State Checksums (voxrollback)', () {
    test(
      'RollbackSessionComponent rewinds tracked GameObjects on late remote input & renders RollbackDiagnosticsUI',
      () {
        final engineA = Engine(HeadlessHost());
        final p0A = engineA.scene.createGameObject('P0_A');
        final p1A = engineA.scene.createGameObject('P1_A');
        final rbA =
            engineA.scene
                .createGameObject('RollbackA')
                .addComponent(
                  RollbackSessionComponent(
                    playerCount: 2,
                    localPlayerId: 0,
                    inputDelayFrames: 0,
                    autoStepInFixedUpdate: false,
                  ),
                )
              ..trackGameObject(p0A)
              ..trackGameObject(p1A);

        final engineB = Engine(HeadlessHost());
        final p0B = engineB.scene.createGameObject('P0_B');
        final p1B = engineB.scene.createGameObject('P1_B');
        final rbB =
            engineB.scene
                .createGameObject('RollbackB')
                .addComponent(
                  RollbackSessionComponent(
                    playerCount: 2,
                    localPlayerId: 0,
                    inputDelayFrames: 0,
                    autoStepInFixedUpdate: false,
                  ),
                )
              ..trackGameObject(p0B)
              ..trackGameObject(p1B);

        // Step frames 0..3: Peer B receives true P1 moveX = -1.0; Peer A initially predicts 0.0
        for (var f = 0; f < 4; f++) {
          final in0 = RollbackFrameInput.fromAxes(
            frame: f,
            playerId: 0,
            moveX: 1.0,
          );
          final in1True = RollbackFrameInput.fromAxes(
            frame: f,
            playerId: 1,
            moveX: f == 0 ? 0.0 : -1.0,
          );
          rbB.submitLocalInput(in0, overrideTargetFrame: f);
          rbB.receiveRemoteInput(in1True);
          rbB.stepRollbackTick();

          rbA.submitLocalInput(in0, overrideTargetFrame: f);
          if (f == 0) rbA.receiveRemoteInput(in1True);
          rbA.stepRollbackTick();
        }

        expect(rbA.latestChecksum, isNot(rbB.latestChecksum));

        // Deliver late remote inputs for frames 1..3 via UI click on 'Resim' (x=145, y=156)
        for (var f = 1; f < 4; f++) {
          expect(
            rbA.receiveRemoteInput(
              RollbackFrameInput.fromAxes(frame: f, playerId: 1, moveX: -1.0),
            ),
            isTrue,
          );
        }

        final ui = VoxUiContext();
        final uiState = RollbackDiagnosticsUiState();
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: 145.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        RollbackDiagnosticsUI.render(ui, rbA, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 145.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        RollbackDiagnosticsUI.render(ui, rbA, state: uiState);
        ui.endFrame();

        expect(rbA.totalRollbacks, 1);
        expect(
          p1A.transform.position.x,
          closeTo(p1B.transform.position.x, 1e-6),
        );
        expect(rbA.latestChecksum, rbB.latestChecksum);
        expect(rbA.receiveRemoteChecksum(3, rbB.latestChecksum), isTrue);

        // Click 'Delay +1' (x=230)
        ui.beginFrame(
          VoxInput(
            mouseX: 230.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        RollbackDiagnosticsUI.render(ui, rbA, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 230.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        RollbackDiagnosticsUI.render(ui, rbA, state: uiState);
        ui.endFrame();
        expect(rbA.inputDelayFrames, 1);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('RollbackSessionComponent'), isNotNull);
        final json = reg.specFor(rbA)!.toJson(rbA);
        expect(json['inputDelayFrames'], 1);
      },
    );
  });
}
