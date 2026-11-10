part of '../../engine.dart';

/// Marks a [GameObject] (typically the active [Camera] or player character) as
/// the spatial listener for 3D [AudioSource] distance attenuation and stereo
/// panning (E10-1).
final class AudioListener extends Component {
  double volume;

  AudioListener({this.volume = 1.0});

  /// Returns the most recently enabled [AudioListener] in [scene], if any.
  static AudioListener? of(Scene scene) => scene._audioListeners.lastOrNull;

  @override
  void _onEnableInternal() => scene._audioListeners.add(this);

  @override
  void _onDisableInternal() => scene._audioListeners.remove(this);
}

/// Named mix bus (`master`, `sfx`, `music`, `ambient`) with independent volume
/// and mute state (E10-1).
final class AudioBus {
  final String name;
  double volume;
  bool muted;

  AudioBus(this.name, {this.volume = 1.0, this.muted = false});
}

/// Scene-level audio bus mixer supporting `master`, `sfx`, `music`, and
/// `ambient` buses (plus any custom named bus).
final class AudioMixer {
  final Map<String, AudioBus> _buses = {
    'master': AudioBus('master'),
    'sfx': AudioBus('sfx'),
    'music': AudioBus('music'),
    'ambient': AudioBus('ambient'),
  };

  AudioBus bus(String name) => _buses.putIfAbsent(name, () => AudioBus(name));

  double effectiveBusGain(String busName) {
    final master = bus('master');
    if (master.muted) return 0.0;
    if (busName == 'master') return master.volume.clamp(0.0, 2.0);
    final b = bus(busName);
    if (b.muted) return 0.0;
    return (master.volume * b.volume).clamp(0.0, 2.0);
  }
}

/// Plays [AudioClip]s through the host's [AudioDevice]: either overlapping
/// one-shots via [playOneShot] or a single controllable voice via [play]
/// (for engine hums, music, ambience).
///
/// Supports spatial 3D attenuation (`spatialBlend` in `0..1`, `minDistance`,
/// `maxDistance`) relative to the active [AudioListener] (or [Camera]) and
/// per-bus routing via [AudioMixer] (E10-1).
final class AudioSource extends Component {
  AudioClip? clip;
  double _volume = 1.0;
  double _pitch = 1.0;
  bool loop;
  bool playOnAwake;
  String bus;

  /// `0.0` = 2D (full volume regardless of position), `1.0` = 3D distance
  /// attenuated between [minDistance] and [maxDistance].
  double spatialBlend;
  double minDistance;
  double maxDistance;

  AudioChannel? _channel;
  double _lastEvaluatedPan = 0.0;

  AudioSource({
    this.clip,
    double volume = 1.0,
    double pitch = 1.0,
    this.loop = false,
    this.playOnAwake = false,
    this.bus = 'sfx',
    this.spatialBlend = 0.0,
    this.minDistance = 1.0,
    this.maxDistance = 50.0,
  }) {
    _volume = volume;
    _pitch = pitch;
  }

  double get volume => _volume;
  set volume(double value) {
    _volume = value;
    _syncChannelVolume();
  }

  double get pitch => _pitch;
  set pitch(double value) {
    _pitch = value;
    _channel?.pitch = value;
  }

  bool get isPlaying => _channel?.isPlaying ?? false;

  /// Most recent stereo pan (`-1.0` left .. `+1.0` right) computed from the
  /// listener's right vector.
  double get currentPan => _lastEvaluatedPan;

  /// Evaluates the effective gain (`0..1+`) and stereo pan (`-1..1`) for a
  /// sound emitted at [sourcePosition] heard by a listener at
  /// [listenerPosition] with [listenerRight].
  ({double volume, double pan}) evaluateSpatial({
    Vec3? sourcePosition,
    Vec3? listenerPosition,
    Vec3? listenerRight,
  }) {
    final busGain = isAttached && scene.isLoaded
        ? scene.audioMixer.effectiveBusGain(bus)
        : 1.0;
    final listener = isAttached && scene.isLoaded ? AudioListener.of(scene) : null;
    final listenerGain = listener?.volume ?? 1.0;
    final baseGain = _volume * busGain * listenerGain;

    final blend = spatialBlend.clamp(0.0, 1.0);
    if (blend <= 0.0) {
      _lastEvaluatedPan = 0.0;
      return (volume: baseGain, pan: 0.0);
    }

    final srcPos = sourcePosition ?? (isAttached ? transform.position : Vec3.zero);
    final TransformComponent? listenerTransform = listener?.transform ??
        (isAttached && scene.isLoaded ? Camera.of(scene)?.transform : null);
    final dstPos = listenerPosition ?? listenerTransform?.position ?? Vec3.zero;
    final right = listenerRight ?? listenerTransform?.right ?? Vec3.unitX;

    final delta = srcPos - dstPos;
    final dist = delta.length;
    final minD = math.max(0.001, minDistance);
    final maxD = math.max(minD + 0.001, maxDistance);

    final double atten3d;
    if (dist <= minD) {
      atten3d = 1.0;
    } else if (dist >= maxD) {
      atten3d = 0.0;
    } else {
      final t = (dist - minD) / (maxD - minD);
      atten3d = (1.0 - t) * (1.0 - t);
    }

    final pan = dist > 1e-5
        ? ((delta * (1.0 / dist)).dot(right) * blend).clamp(-1.0, 1.0)
        : 0.0;
    _lastEvaluatedPan = pan;
    final blendedAtten = 1.0 + (atten3d - 1.0) * blend;
    return (volume: baseGain * blendedAtten, pan: pan);
  }

  void _syncChannelVolume() {
    final ch = _channel;
    if (ch == null) return;
    ch.volume = evaluateSpatial().volume;
  }

  void play([AudioClip? overrideClip]) {
    final c = overrideClip ?? clip;
    if (c == null) return;
    clip = c;
    final ch = _channel ??= engine.audio.createChannel();
    final eval = evaluateSpatial();
    ch.play(c, volume: eval.volume, pitch: _pitch, loop: loop);
  }

  void stop() => _channel?.stop();

  /// Plays [clip] at world position [position] on a transient GameObject
  /// that automatically destroys itself after [duration] seconds (E18-2).
  static GameObject? playClipAtPoint(
    Scene scene,
    AudioClip clip,
    Vec3 position, {
    double volume = 1.0,
    double pitch = 1.0,
    double spatialBlend = 1.0,
    double minDistance = 1.0,
    double maxDistance = 50.0,
    String bus = 'sfx',
    double duration = 5.0,
  }) {
    if (!scene.isLoaded) return null;
    final go = scene.createGameObject(
      'SpatialAudioOneShot_${clip.path}',
      position: position,
    );
    final src = go.addComponent(
      AudioSource(
        clip: clip,
        volume: volume,
        pitch: pitch,
        spatialBlend: spatialBlend,
        minDistance: minDistance,
        maxDistance: maxDistance,
        bus: bus,
      ),
    );
    src.play();
    scene.engine.invoke(duration, () {
      if (!go.isDestroyed) go.destroy();
    });
    return go;
  }

  void playOneShot(AudioClip oneShot, {double volumeScale = 1.0, double pitch = 1.0}) {
    final eval = evaluateSpatial();
    engine.audio.playOneShot(
      oneShot,
      volume: eval.volume * volumeScale,
      pitch: _pitch * pitch,
    );
  }

  @override
  void onEnable() {
    if (playOnAwake && clip != null) play();
  }

  @override
  void _onEnableInternal() => scene._audioSources.add(this);

  @override
  void _onDisableInternal() {
    scene._audioSources.remove(this);
    _channel?.stop();
  }

  @override
  void _onDestroyInternal() {
    scene._audioSources.remove(this);
    _channel?.dispose();
    _channel = null;
  }
}
