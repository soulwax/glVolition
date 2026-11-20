part of '../../engine.dart';

/// Marks a [GameObject] (typically the active [Camera] or player character) as
/// the spatial listener for 3D [AudioSource] distance attenuation and stereo
/// panning (E10-1).
final class AudioListener extends Component {
  double volume;

  AudioListener({this.volume = 1.0});

  /// Returns the most recently enabled [AudioListener] in [scene], if any.
  static AudioListener? of(Scene scene) => scene._audioListeners.lastOrNull;

  /// Pushes the active listener (or fallback [Camera]) pose in [scene] to
  /// `engine.audio.setListenerPose`.
  static void _syncPoseForScene(Scene scene) {
    if (!scene.isLoaded) return;
    final active = of(scene);
    final TransformComponent? t =
        active?.transform ?? Camera.of(scene)?.transform;
    scene.engine.audio.setListenerPose(
      position: t?.position ?? Vec3.zero,
      forward: t?.forward ?? kForward,
      up: t?.up ?? kUp,
    );
  }

  /// Immediately pushes this listener scene's current pose to the audio device.
  void syncPose() {
    if (isAttached && scene.isLoaded) {
      _syncPoseForScene(scene);
    }
  }

  @override
  void _onEnableInternal() {
    scene._audioListeners.add(this);
    _syncPoseForScene(scene);
  }

  @override
  void _onDisableInternal() {
    scene._audioListeners.remove(this);
    _syncPoseForScene(scene);
  }
}

/// Named mix bus (`master`, `sfx`, `music`, `ambient`) with independent volume
/// and mute state (E10-1).
final class AudioBus {
  final String name;
  double volume;
  bool muted;

  AudioBus(this.name, {this.volume = 1.0, this.muted = false});
}

/// Named mix preset capturing per-bus volumes and mute states for [AudioMixer]
/// (P12-W20-C).
final class AudioMixerSnapshot {
  final String name;
  final Map<String, double> busVolumes;
  final Map<String, bool> busMutes;

  AudioMixerSnapshot({
    required this.name,
    Map<String, double> busVolumes = const {},
    Map<String, bool> busMutes = const {},
  }) : busVolumes = Map.unmodifiable(busVolumes),
       busMutes = Map.unmodifiable(busMutes);
}

final class _AudioSnapshotBlend {
  final AudioMixerSnapshot target;
  final Map<String, double> startVolumes;
  final double duration;
  double elapsed = 0.0;

  _AudioSnapshotBlend({
    required this.target,
    required this.startVolumes,
    required this.duration,
  });

  bool get isComplete => elapsed >= duration;
}

final class _AudioBusDuck {
  final String busName;
  final double targetGain;
  final double attackSeconds;
  final double holdSeconds;
  final double releaseSeconds;
  double elapsed = 0.0;

  _AudioBusDuck({
    required this.busName,
    required this.targetGain,
    required this.attackSeconds,
    required this.holdSeconds,
    required this.releaseSeconds,
  });

  double get totalDuration => attackSeconds + holdSeconds + releaseSeconds;
  bool get isComplete => elapsed >= totalDuration;

  double get currentMultiplier {
    if (elapsed < attackSeconds) {
      final t = attackSeconds <= 0 ? 1.0 : (elapsed / attackSeconds);
      return 1.0 + (targetGain - 1.0) * t.clamp(0.0, 1.0);
    }
    final afterAttack = elapsed - attackSeconds;
    if (afterAttack < holdSeconds) {
      return targetGain;
    }
    final afterHold = afterAttack - holdSeconds;
    if (releaseSeconds <= 0) return 1.0;
    final t = (afterHold / releaseSeconds).clamp(0.0, 1.0);
    return targetGain + (1.0 - targetGain) * t;
  }
}

/// Scene-level audio bus mixer supporting `master`, `sfx`, `music`, and
/// `ambient` buses (plus custom named buses), named [AudioMixerSnapshot]
/// crossfades, and dynamic bus ducking (E10-1, P12-W20-C).
final class AudioMixer {
  final Map<String, AudioBus> _buses = {
    'master': AudioBus('master'),
    'sfx': AudioBus('sfx'),
    'music': AudioBus('music'),
    'ambient': AudioBus('ambient'),
  };
  final Map<String, AudioMixerSnapshot> _snapshots = {};
  final List<_AudioBusDuck> _ducks = [];
  _AudioSnapshotBlend? _activeBlend;
  String? _activeSnapshotName;

  AudioBus bus(String name) => _buses.putIfAbsent(name, () => AudioBus(name));

  String? get activeSnapshotName => _activeSnapshotName;
  Iterable<String> get snapshotNames => _snapshots.keys;

  /// Registers a named [snapshot] preset on this mixer.
  void defineSnapshot(AudioMixerSnapshot snapshot) {
    _snapshots[snapshot.name] = snapshot;
  }

  /// Captures the current volumes and mute flags of all buses into a named
  /// [AudioMixerSnapshot] and registers it.
  AudioMixerSnapshot captureSnapshot(String name) {
    final snap = AudioMixerSnapshot(
      name: name,
      busVolumes: {for (final e in _buses.entries) e.key: e.value.volume},
      busMutes: {for (final e in _buses.entries) e.key: e.value.muted},
    );
    _snapshots[name] = snap;
    return snap;
  }

  /// Applies the registered snapshot [name] immediately or over
  /// [transitionSeconds] of unscaled time.
  bool applySnapshot(String name, {double transitionSeconds = 0.0}) {
    final snap = _snapshots[name];
    if (snap == null) return false;
    _activeSnapshotName = name;
    for (final e in snap.busMutes.entries) {
      bus(e.key).muted = e.value;
    }
    if (transitionSeconds <= 0.0) {
      _activeBlend = null;
      for (final e in snap.busVolumes.entries) {
        bus(e.key).volume = e.value;
      }
      return true;
    }
    final starts = <String, double>{
      for (final key in snap.busVolumes.keys) key: bus(key).volume,
    };
    _activeBlend = _AudioSnapshotBlend(
      target: snap,
      startVolumes: starts,
      duration: transitionSeconds,
    );
    return true;
  }

  /// Temporarily ducks [busName] down to [targetGain] (e.g. `0.25` during
  /// voice-over or explosions) with attack/hold/release envelopes.
  void duckBus(
    String busName, {
    double targetGain = 0.25,
    double holdSeconds = 0.5,
    double attackSeconds = 0.05,
    double releaseSeconds = 0.25,
  }) {
    _ducks.add(
      _AudioBusDuck(
        busName: busName,
        targetGain: targetGain.clamp(0.0, 1.0),
        attackSeconds: math.max(0.0, attackSeconds),
        holdSeconds: math.max(0.0, holdSeconds),
        releaseSeconds: math.max(0.0, releaseSeconds),
      ),
    );
  }

  void _step(double unscaledDt) {
    if (unscaledDt <= 0) return;
    final blend = _activeBlend;
    if (blend != null) {
      blend.elapsed += unscaledDt;
      final t = (blend.elapsed / blend.duration).clamp(0.0, 1.0);
      for (final e in blend.target.busVolumes.entries) {
        final start = blend.startVolumes[e.key] ?? bus(e.key).volume;
        bus(e.key).volume = start + (e.value - start) * t;
      }
      if (blend.isComplete) {
        _activeBlend = null;
      }
    }
    if (_ducks.isNotEmpty) {
      for (var i = _ducks.length - 1; i >= 0; i--) {
        final duck = _ducks[i];
        duck.elapsed += unscaledDt;
        if (duck.isComplete) {
          _ducks.removeAt(i);
        }
      }
    }
  }

  double _duckMultiplierFor(String busName) {
    var mult = 1.0;
    for (final duck in _ducks) {
      if (duck.busName == busName) {
        final m = duck.currentMultiplier;
        if (m < mult) mult = m;
      }
    }
    return mult;
  }

  double effectiveBusGain(String busName) {
    final master = bus('master');
    if (master.muted) return 0.0;
    final masterGain = master.volume * _duckMultiplierFor('master');
    if (busName == 'master') return masterGain.clamp(0.0, 2.0);
    final b = bus(busName);
    if (b.muted) return 0.0;
    final busGain = b.volume * _duckMultiplierFor(busName);
    return (masterGain * busGain).clamp(0.0, 2.0);
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

  /// Scales how strongly active [AudioReverbZone]s feed this source's reverb
  /// send when no explicit [reverbSend] override is set (`0.0`..`1.0+`).
  double reverbZoneMix;

  AudioChannel? _channel;
  double _lastEvaluatedPan = 0.0;
  double _lastEvaluatedLowPassCutoffHz = 20000.0;
  double _lastEvaluatedLowPassResonance = 0.70710678;
  double _lastEvaluatedReverbSend = 0.0;
  double? _lowPassCutoffOverride;
  double? _lowPassResonanceOverride;
  double? _reverbSendOverride;
  double _occlusion = 0.0;
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
    this.reverbZoneMix = 1.0,
    double? lowPassCutoffHz,
    double? lowPassResonance,
    double? reverbSend,
    double occlusion = 0.0,
  }) : _lowPassCutoffOverride = lowPassCutoffHz,
       _lowPassResonanceOverride = lowPassResonance,
       _reverbSendOverride = reverbSend,
       _occlusion = occlusion.isFinite ? occlusion.clamp(0.0, 1.0) : 0.0 {
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

  /// Optional explicit low-pass cutoff override in Hz (`null` uses attached
  /// [AudioLowPassFilterComponent] or bypassed `20000` Hz).
  double? get lowPassCutoffHz => _lowPassCutoffOverride;
  set lowPassCutoffHz(double? value) {
    _lowPassCutoffOverride = value;
    _syncChannelVolume();
  }

  /// Optional explicit biquad resonance (`Q`) override for the channel low-pass
  /// filter (`null` uses attached [AudioLowPassFilterComponent.q] or `0.7071`).
  double? get lowPassResonance => _lowPassResonanceOverride;
  set lowPassResonance(double? value) {
    _lowPassResonanceOverride = value;
    _syncChannelVolume();
  }

  /// Optional explicit wet reverb send override (`0.0`..`1.0`); `null` derives
  /// wet send from nearby [AudioReverbZone]s scaled by [reverbZoneMix].
  double? get reverbSend => _reverbSendOverride;
  set reverbSend(double? value) {
    _reverbSendOverride = value;
    _syncChannelVolume();
  }

  /// Additional wall/obstacle muffling (`0.0` = open .. `1.0` = heavily muffled).
  double get occlusion => _occlusion;
  set occlusion(double value) {
    _occlusion = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    _syncChannelVolume();
  }

  /// Most recent low-pass cutoff frequency (Hz) sent to the audio channel.
  double get currentLowPassCutoffHz => _lastEvaluatedLowPassCutoffHz;

  /// Most recent low-pass filter resonance (`Q`) sent to the audio channel.
  double get currentLowPassResonance => _lastEvaluatedLowPassResonance;

  /// Most recent wet reverb send (`0.0`..`1.0`) sent to the audio channel.
  double get currentReverbSend => _lastEvaluatedReverbSend;

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
        final t = half <= 0.0
            ? 1.0
            : ((cross.elapsed - half) / half).clamp(0.0, 1.0);
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
    final listener = isAttached && scene.isLoaded
        ? AudioListener.of(scene)
        : null;
    final listenerGain = listener?.volume ?? 1.0;
    final baseGain = _volume * busGain * listenerGain;

    final blend = spatialBlend.clamp(0.0, 1.0);
    if (blend <= 0.0) {
      _lastEvaluatedPan = 0.0;
      return (volume: baseGain, pan: 0.0);
    }

    final srcPos =
        sourcePosition ?? (isAttached ? transform.position : Vec3.zero);
    final TransformComponent? listenerTransform =
        listener?.transform ??
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

  /// Evaluates spatial gain, stereo pan, low-pass cutoff/resonance, and
  /// environmental reverb wet send for the attached [GameObject] and active
  /// listener.
  ({
    double volume,
    double pan,
    double lowPassCutoffHz,
    double lowPassResonance,
    double reverbSend,
  })
  evaluateDsp({
    Vec3? sourcePosition,
    Vec3? listenerPosition,
    Vec3? listenerRight,
  }) {
    final spatial = evaluateSpatial(
      sourcePosition: sourcePosition,
      listenerPosition: listenerPosition,
      listenerRight: listenerRight,
    );

    final attachedLoaded = isAttached && scene.isLoaded;
    final listener = attachedLoaded ? AudioListener.of(scene) : null;
    final TransformComponent? listenerTransform =
        listener?.transform ??
        (attachedLoaded ? Camera.of(scene)?.transform : null);
    final dstPos = listenerPosition ?? listenerTransform?.position ?? Vec3.zero;

    var cutoff = 20000.0;
    var resonance = 0.70710678;

    void applyFilterComponent(AudioLowPassFilterComponent? comp) {
      if (comp == null || !comp.isActiveAndEnabled) return;
      final c = comp.cutoffFrequency.isFinite
          ? comp.cutoffFrequency.clamp(20.0, 20000.0)
          : 20000.0;
      final q = comp.q.isFinite ? comp.q.clamp(0.1, 20.0) : 0.70710678;
      if (c <= cutoff) {
        cutoff = c;
        resonance = q;
      }
    }

    if (isAttached) {
      applyFilterComponent(
        gameObject.getComponent<AudioLowPassFilterComponent>(),
      );
    }
    if (listener != null && listener.isAttached) {
      applyFilterComponent(
        listener.gameObject.getComponent<AudioLowPassFilterComponent>(),
      );
    }

    final overrideCutoff = _lowPassCutoffOverride;
    if (overrideCutoff != null && overrideCutoff.isFinite) {
      final c = overrideCutoff.clamp(20.0, 20000.0);
      if (c < cutoff) cutoff = c;
    }

    if (_occlusion > 0.0) {
      final occCutoff = 20000.0 * math.pow(0.01, _occlusion.clamp(0.0, 1.0));
      if (occCutoff < cutoff) cutoff = occCutoff;
    }

    final overrideQ = _lowPassResonanceOverride;
    if (overrideQ != null && overrideQ.isFinite) {
      resonance = overrideQ.clamp(0.1, 20.0);
    }

    cutoff = cutoff.clamp(20.0, 20000.0);
    resonance = resonance.clamp(0.1, 20.0);

    final double reverb;
    final overrideReverb = _reverbSendOverride;
    if (overrideReverb != null) {
      reverb = overrideReverb.isFinite ? overrideReverb.clamp(0.0, 1.0) : 0.0;
    } else if (attachedLoaded) {
      final zoneMix = AudioReverbZone.sampleNearestWetMix(scene, dstPos);
      reverb = (zoneMix * reverbZoneMix).clamp(0.0, 1.0);
    } else {
      reverb = 0.0;
    }

    _lastEvaluatedLowPassCutoffHz = cutoff;
    _lastEvaluatedLowPassResonance = resonance;
    _lastEvaluatedReverbSend = reverb;

    return (
      volume: spatial.volume,
      pan: spatial.pan,
      lowPassCutoffHz: cutoff,
      lowPassResonance: resonance,
      reverbSend: reverb,
    );
  }

  ({
    double volume,
    double pan,
    double lowPassCutoffHz,
    double lowPassResonance,
    double reverbSend,
  })
  _pushChannelDsp(AudioChannel ch) {
    if (isAttached && scene.isLoaded) {
      AudioListener._syncPoseForScene(scene);
    }
    final eval = evaluateDsp();
    ch.volume = eval.volume;
    ch.setPan(eval.pan);
    ch.setLowPass(eval.lowPassCutoffHz, resonance: eval.lowPassResonance);
    ch.setReverbSend(eval.reverbSend);
    return eval;
  }

  void _syncChannelVolume() {
    final ch = _channel;
    if (ch == null) return;
    _pushChannelDsp(ch);
  }

  void play([AudioClip? overrideClip]) {
    final c = overrideClip ?? clip;
    if (c == null) return;
    clip = c;
    if (isAttached && scene.isLoaded) {
      AudioListener._syncPoseForScene(scene);
    }
    final ch = _channel ??= engine.audio.createChannel();
    final eval = evaluateDsp();
    ch.setPan(eval.pan);
    ch.setLowPass(eval.lowPassCutoffHz, resonance: eval.lowPassResonance);
    ch.setReverbSend(eval.reverbSend);
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

  void playOneShot(
    AudioClip oneShot, {
    double volumeScale = 1.0,
    double pitch = 1.0,
  }) {
    if (isAttached && scene.isLoaded) {
      AudioListener._syncPoseForScene(scene);
    }
    final eval = evaluateDsp();
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
