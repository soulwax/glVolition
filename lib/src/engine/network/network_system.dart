part of '../../engine.dart';

/// Unique network identity component identifying an object across client-server peers (E33).
class NetworkIdentity extends Component {
  int netId;
  int ownerPeerId;

  NetworkIdentity({
    required this.netId,
    this.ownerPeerId = 0, // 0 = server
  });

  bool get isOwner => scene.network.localPeerId == ownerPeerId;
  bool get isServer => scene.network.isServer;
  bool get isClient => scene.network.isClient;

  @override
  void _onEnableInternal() {
    scene.network._registerIdentity(this);
  }

  @override
  void _onDisableInternal() {
    scene.network._unregisterIdentity(this);
  }
}

/// Automatically synchronizes GameObject position and rotation with snapshot
/// interpolation, client-side prediction, and server reconciliation (E33).
class NetworkTransform extends Component {
  double interpolationDelaySeconds;
  bool synchronizePosition;
  bool synchronizeRotation;
  bool enablePrediction;

  final net.SnapshotBuffer<Vec3> positionBuffer = net.SnapshotBuffer<Vec3>();
  final net.SnapshotBuffer<Quat> rotationBuffer = net.SnapshotBuffer<Quat>();
  final net.PredictionHistory<Vec3, Vec3> prediction =
      net.PredictionHistory<Vec3, Vec3>();

  NetworkTransform({
    this.interpolationDelaySeconds = 0.05,
    this.synchronizePosition = true,
    this.synchronizeRotation = true,
    this.enablePrediction = true,
  });

  NetworkIdentity? get identity => gameObject.getComponent<NetworkIdentity>();

  void receiveSnapshot({
    required int tick,
    required int timestampMs,
    required Vec3 position,
    required Quat rotation,
    Vec3? velocity,
  }) {
    positionBuffer.add(
      net.Snapshot(tick: tick, timestampMs: timestampMs, state: position),
    );
    rotationBuffer.add(
      net.Snapshot(tick: tick, timestampMs: timestampMs, state: rotation),
    );

    final id = identity;
    if (id != null && id.isOwner && !id.isServer && enablePrediction) {
      // Reconcile client-side prediction against authoritative server position
      prediction.reconcile(
        serverTick: tick,
        authoritativeState: position,
        hasDiverged: (pred, auth) =>
            (pred - auth).lengthSquared > 0.04, // >20cm drift
        simulateStep: (cur, vel, t) =>
            cur + vel * (scene.engine.time.fixedDeltaTime),
      );
    }
  }

  void updateInterpolation(int currentNetworkTimeMs) {
    final id = identity;
    // Server or local owner predicts locally; remote proxies interpolate
    if (id != null && (id.isServer || id.isOwner)) return;

    final targetTimeMs =
        currentNetworkTimeMs - (interpolationDelaySeconds * 1000).round();

    if (synchronizePosition && positionBuffer.isNotEmpty) {
      final interpPos = positionBuffer.sample(
        targetTimeMs,
        (from, to, alpha) => Vec3.lerp(from, to, alpha),
      );
      if (interpPos != null) {
        transform.position = interpPos;
      }
    }

    if (synchronizeRotation && rotationBuffer.isNotEmpty) {
      final interpRot = rotationBuffer.sample(
        targetTimeMs,
        (from, to, alpha) => Mathfx.slerp(from, to, alpha),
      );
      if (interpRot != null) {
        transform.rotation = interpRot;
      }
    }
  }
}

/// Central scene network manager managing transport, ticks, snapshots and RPCs (E33).
class NetworkManager {
  final Scene scene;
  net.NetTransport? transport;

  int localPeerId = 0; // 0 = server, 1..N = clients
  bool isServer = true;
  bool isClient = false;

  int currentTick = 0;
  int currentNetworkTimeMs = 0;

  final net.RpcManager rpc = net.RpcManager();
  final Map<int, NetworkIdentity> _identities = {};

  NetworkManager._(this.scene) {
    // Register standard packet handlers in voxnet
    net.MessageRegistry.register(net.PingMsg.kTypeId, net.PingMsg.deserialize);
    net.MessageRegistry.register(net.PongMsg.kTypeId, net.PongMsg.deserialize);
    net.MessageRegistry.register(
      net.InputMsg.kTypeId,
      net.InputMsg.deserialize,
    );
    net.MessageRegistry.register(
      net.EntitySnapshotMsg.kTypeId,
      net.EntitySnapshotMsg.deserialize,
    );
    net.MessageRegistry.register(net.RpcMsg.kTypeId, net.RpcMsg.deserialize);
  }

  void startServer({net.NetTransport? serverTransport}) {
    localPeerId = 0;
    isServer = true;
    isClient = false;
    transport = serverTransport;
  }

  void startClient(int peerId, {net.NetTransport? clientTransport}) {
    localPeerId = peerId;
    isServer = false;
    isClient = true;
    transport = clientTransport;
  }

  void _registerIdentity(NetworkIdentity identity) {
    _identities[identity.netId] = identity;
  }

  void _unregisterIdentity(NetworkIdentity identity) {
    _identities.remove(identity.netId);
  }

  NetworkIdentity? getIdentity(int netId) => _identities[netId];

  void sendRpc(
    int netId,
    String methodName,
    Uint8List payload, {
    int recipientId = -1,
  }) {
    final t = transport;
    if (t == null) return;

    final msg = net.RpcMsg(
      netId: netId,
      methodName: methodName,
      payload: payload,
    );
    final bytes = net.MessageRegistry.serialize(msg);

    if (recipientId == -1) {
      t.broadcast(bytes);
    } else {
      t.send(recipientId, bytes);
    }
  }

  void _step(double dt) {
    currentTick++;
    currentNetworkTimeMs += (dt * 1000).round();

    final t = transport;
    if (t == null) return;

    // 1. Poll incoming transport packets
    final packets = t.poll(currentNetworkTimeMs);
    for (final pkt in packets) {
      final msg = net.MessageRegistry.deserialize(pkt.data);
      if (msg is net.EntitySnapshotMsg) {
        final id = _identities[msg.netId];
        if (id != null) {
          final netTransform = id.gameObject.getComponent<NetworkTransform>();
          if (netTransform != null) {
            netTransform.receiveSnapshot(
              tick: msg.tick,
              timestampMs: pkt.timestampMs,
              position: Vec3(msg.x, msg.y, msg.z),
              rotation: Quat(msg.qx, msg.qy, msg.qz, msg.qw),
              velocity: Vec3(msg.vx, msg.vy, msg.vz),
            );
          }
        }
      } else if (msg is net.RpcMsg) {
        rpc.dispatch(pkt.senderId, msg.methodName, msg.payload);
      }
    }

    // 2. Server broadcast authoritative snapshots
    if (isServer) {
      for (final id in _identities.values) {
        final netTransform = id.gameObject.getComponent<NetworkTransform>();
        if (netTransform != null) {
          final pos = id.transform.position;
          final rot = id.transform.rotation;
          final snapMsg = net.EntitySnapshotMsg(
            tick: currentTick,
            netId: id.netId,
            x: pos.x,
            y: pos.y,
            z: pos.z,
            qx: rot.x,
            qy: rot.y,
            qz: rot.z,
            qw: rot.w,
          );
          t.broadcast(net.MessageRegistry.serialize(snapMsg));
        }
      }
    }

    // 3. Update remote proxies snapshot interpolation
    for (final id in _identities.values) {
      final netTransform = id.gameObject.getComponent<NetworkTransform>();
      if (netTransform != null) {
        netTransform.updateInterpolation(currentNetworkTimeMs);
      }
    }
  }
}
