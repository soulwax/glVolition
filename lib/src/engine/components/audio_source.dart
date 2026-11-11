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

final class _AudioFade {
  final double startVolume;
  final double targetVolume;
  final double duration;
  final void Function()? onComplete;
  double elapsed = 0.0;

  _AudioFade({
    required this.startVolume,
    required this.targetVolume,
    required this.duration,
    this.onComplete,
  });

  bool get isComplete => elapsed >= duration;
  double get currentVolume {
    if (duration <= 0.0) return targetVolume;
    final t = (elapsed / duration).clamp(0.0, 1.0);
    return startVolume + (targetVolume - startVolume) * t;
  }
}

final class _AudioCrossFade {
  final AudioClip nextClip;
  final double duration;
  final double targetVolume;
  final bool loop;
  final void Function()? onComplete;
  double elapsed = 0.0;
  bool _swapped = false;

  _AudioCrossFade({
    required this.nextClip,
    required this.duration,
    required this.targetVolume,
    this.loop = true,
    this.onComplete,
  });
}

/// In-memory procedural audio clip synthesized via `package:voxsynth` (E28-1).
final class ProceduralAudioClip implements AudioClip {
  @override
  final String path;
  final Uint8List wavBytes;
  final SynthSound? synthSound;

  ProceduralAudioClip({
    required this.path,
    required this.wavBytes,
    this.synthSound,
  });

  factory ProceduralAudioClip.fromSynth(
    SynthSound synth, {
    String? name,
    int sampleRate = 44100,
  }) {
    final bytes = synth.toWavBytes(sampleRate: sampleRate);
    final clipPath = 'procedural://${name ?? "synth_${bytes.length}"}';
    return ProceduralAudioClip(
      path: clipPath,
      wavBytes: bytes,
      synthSound: synth,
    );
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
  _AudioFade? _activeFade;
  _AudioCrossFade? _activeCrossFade;

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
  bool get isFading => _activeFade != null || _activeCrossFade != null;

  /// Smoothly ramps volume to [targetVolume] over [duration] seconds (E25-1).
  void fadeVolumeTo(
    double targetVolume, {
    double duration = 1.0,
    void Function()? onComplete,
  }) {
    _activeCrossFade = null;
    _activeFade = _AudioFade(
      startVolume: _volume,
      targetVolume: targetVolume,
      duration: duration,
      onComplete: onComplete,
    );
  }

  /// Smoothly fades out current playback and cross-fades into [nextClip] over [duration] seconds (E25-1).
  void crossFadeTo(
    AudioClip nextClip, {
    double duration = 1.5,
    double targetVolume = 1.0,
    bool loop = true,
    void Function()? onComplete,
  }) {
    _activeFade = null;
    _activeCrossFade = _AudioCrossFade(
      nextClip: nextClip,
      duration: duration,
      targetVolume: targetVolume,
      loop: loop,
      onComplete: onComplete,
    );
  }

  void _stepFade(double dt) {
    final fade = _activeFade;
    if (fade != null) {
      fade.elapsed += dt;
      _volume = fade.currentVolume;
      _syncChannelVolume();
      if (fade.isComplete) {
        _volume = fade.targetVolume;
        _syncChannelVolume();
        _activeFade = null;
        fade.onComplete?.call();
      }
      return;
    }

    final cross = _activeCrossFade;
    if (cross != null) {
      cross.elapsed += dt;
      final half = cross.duration * 0.5;
      if (!cross._swapped) {
        final t = half <= 0.0 ? 1.0 : (cross.elapsed / half).clamp(0.0, 1.0);
        _volume = cross.targetVolume * (1.0 - t);
        _syncChannelVolume();
        if (cross.elapsed >= half) {
          cross._swapped = true;
          loop = cross.loop;
          play(cross.nextClip);
        }
      } else {
        final t = half <= 0.0 ? 1.0 : ((cross.elapsed - half) / half).clamp(0.0, 1.0);
        _volume = cross.targetVolume * t;
        _syncChannelVolume();
        if (cross.elapsed >= cross.duration) {
          _volume = cross.targetVolume;
          _syncChannelVolume();
          _activeCrossFade = null;
          cross.onComplete?.call();
        }
      }
    }
  }

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

  /// Plays a procedurally synthesized sound effect via `package:voxsynth` (E28-1).
  void playSynth(
    SynthSound synth, {
    double volumeScale = 1.0,
    double pitch = 1.0,
    String? name,
  }) {
    final clip = ProceduralAudioClip.fromSynth(synth, name: name);
    playOneShot(clip, volumeScale: volumeScale, pitch: pitch);
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
