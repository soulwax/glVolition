part of '../../engine.dart';

/// Keyframe track for a skeletal bone/joint.
final class BoneTrack {
  final int jointIndex;
  final String? boneName;
  final List<Keyframe<Vec3>> translationKeys;
  final List<Keyframe<Quat>> rotationKeys;
  final List<Keyframe<Vec3>> scaleKeys;

  BoneTrack({
    required this.jointIndex,
    this.boneName,
    List<Keyframe<Vec3>> translationKeys = const [],
    List<Keyframe<Quat>> rotationKeys = const [],
    List<Keyframe<Vec3>> scaleKeys = const [],
  }) : translationKeys = List.unmodifiable(
         List<Keyframe<Vec3>>.from(translationKeys)
           ..sort((a, b) => a.time.compareTo(b.time)),
       ),
       rotationKeys = List.unmodifiable(
         List<Keyframe<Quat>>.from(rotationKeys)
           ..sort((a, b) => a.time.compareTo(b.time)),
       ),
       scaleKeys = List.unmodifiable(
         List<Keyframe<Vec3>>.from(scaleKeys)
           ..sort((a, b) => a.time.compareTo(b.time)),
       );

  Vec3? sampleTranslation(double time) {
    if (translationKeys.isEmpty) return null;
    final (k0, k1, t) = _bracket(translationKeys, time);
    return k0.value + ((k1.value - k0.value) * t);
  }

  Quat? sampleRotation(double time) {
    if (rotationKeys.isEmpty) return null;
    final (k0, k1, t) = _bracket(rotationKeys, time);
    return Quat.slerp(k0.value, k1.value, t);
  }

  Vec3? sampleScale(double time) {
    if (scaleKeys.isEmpty) return null;
    final (k0, k1, t) = _bracket(scaleKeys, time);
    return k0.value + ((k1.value - k0.value) * t);
  }

  static (Keyframe<T>, Keyframe<T>, double) _bracket<T>(
    List<Keyframe<T>> keys,
    double time,
  ) {
    if (time <= keys.first.time) return (keys.first, keys.first, 0.0);
    if (time >= keys.last.time) return (keys.last, keys.last, 1.0);
    var i = 0;
    while (i < keys.length - 1 && keys[i + 1].time <= time) {
      i++;
    }
    final k0 = keys[i];
    final k1 = keys[i + 1];
    final dt = k1.time - k0.time;
    final tNorm = dt > 1e-6 ? (time - k0.time) / dt : 0.0;
    final curve = k0.curve ?? Curves.linear;
    return (k0, k1, curve.transform(tNorm));
  }
}

/// Clip containing hierarchical bone tracks for skeletal animation.
final class SkeletalClip {
  final String name;
  final double duration;
  final LoopMode loopMode;
  final List<BoneTrack> boneTracks;

  SkeletalClip({
    required this.name,
    required this.duration,
    this.loopMode = LoopMode.loop,
    List<BoneTrack> boneTracks = const [],
  }) : boneTracks = List.unmodifiable(boneTracks) {
    if (duration <= 0) {
      throw ArgumentError.value(duration, 'duration', 'Duration must be > 0');
    }
  }

  double sampleTime(double time) {
    var t = time;
    switch (loopMode) {
      case LoopMode.once:
        return t.clamp(0.0, duration);
      case LoopMode.loop:
        t = t % duration;
        if (t < 0) t += duration;
        return t;
      case LoopMode.pingPong:
        final cycle = (t / duration).floor();
        final rem = t % duration;
        final normRem = rem < 0 ? rem + duration : rem;
        return cycle.isEven ? normRem : duration - normRem;
    }
  }
}

final class _ActiveSkeletalInstance {
  final SkeletalClip clip;
  double currentTime = 0.0;
  double speed = 1.0;
  bool isPaused = false;

  _ActiveSkeletalInstance(this.clip, {this.speed = 1.0});

  bool update(double dt) {
    if (isPaused) return true;
    currentTime += dt * speed;
    if (clip.loopMode == LoopMode.once && currentTime >= clip.duration) {
      currentTime = clip.duration;
      return false;
    }
    return true;
  }
}

final class _ActiveCrossFade {
  final _ActiveSkeletalInstance fromInstance;
  final _ActiveSkeletalInstance toInstance;
  final double duration;
  double elapsed = 0.0;

  _ActiveCrossFade({
    required this.fromInstance,
    required this.toInstance,
    required this.duration,
  });

  double get weight =>
      duration > 1e-6 ? (elapsed / duration).clamp(0.0, 1.0) : 1.0;

  bool update(double dt) {
    fromInstance.update(dt);
    toInstance.update(dt);
    elapsed += dt;
    return elapsed >= duration;
  }
}

/// Keyframe animation component wrapping pixeldart's [AnimationPlayer] (E5-1)
/// and driving hierarchical skeletal GPU bone palettes.
/// Advances with `time.deltaTime` so it respects `time.timeScale`.
final class Animator extends Behaviour {
  final AnimationPlayer player = AnimationPlayer();
  final Map<String, AnimationClip> clips = {};
  final Map<String, SkeletalClip> skeletalClips = {};
  String? defaultClip;

  SkinData? skin;
  SkinnedMeshRenderer? targetRenderer;

  _ActiveSkeletalInstance? _activeSkeletal;
  _ActiveCrossFade? _crossFade;
  Float32List? _currentPalette;

  Animator({
    Iterable<AnimationClip> initialClips = const [],
    Iterable<SkeletalClip> initialSkeletalClips = const [],
    this.defaultClip,
    this.skin,
    this.targetRenderer,
  }) {
    for (final c in initialClips) {
      clips[c.name] = c;
    }
    for (final s in initialSkeletalClips) {
      skeletalClips[s.name] = s;
    }
  }

  static final spec = ComponentSpec<Animator>(
    'Animator',
    Animator.new,
    const [],
  );

  void addClip(AnimationClip clip) => clips[clip.name] = clip;

  void addSkeletalClip(SkeletalClip clip) => skeletalClips[clip.name] = clip;

  /// Plays a registered [AnimationClip] or [SkeletalClip] by name.
  void play(String clipName, {double speed = 1.0, double crossFade = 0.0}) {
    if (skeletalClips.containsKey(clipName)) {
      playSkeletal(clipName, speed: speed, crossFadeDuration: crossFade);
      return;
    }
    final clip = clips[clipName];
    if (clip != null) {
      player.play(clip, speed: speed);
      return;
    }
    throw ArgumentError.value(
      clipName,
      'clipName',
      'Clip not registered on Animator',
    );
  }

  void playClip(AnimationClip clip, {double speed = 1.0}) {
    clips[clip.name] = clip;
    player.play(clip, speed: speed);
  }

  /// Plays a [SkeletalClip] with an optional cross-fade blend duration in seconds.
  void playSkeletal(
    String clipName, {
    double speed = 1.0,
    double crossFadeDuration = 0.0,
  }) {
    final clip =
        skeletalClips[clipName] ??
        (throw ArgumentError.value(
          clipName,
          'clipName',
          'SkeletalClip not registered on Animator',
        ));

    final nextInstance = _ActiveSkeletalInstance(clip, speed: speed);
    if (crossFadeDuration > 0.0 && _activeSkeletal != null) {
      _crossFade = _ActiveCrossFade(
        fromInstance: _activeSkeletal!,
        toInstance: nextInstance,
        duration: crossFadeDuration,
      );
      _activeSkeletal = null;
    } else {
      _crossFade = null;
      _activeSkeletal = nextInstance;
    }
  }

  /// Cross-fades smoothly from the current skeletal animation into [clipName].
  void crossFade(String clipName, double duration, {double speed = 1.0}) {
    playSkeletal(clipName, speed: speed, crossFadeDuration: duration);
  }

  void pause(String clipName) {
    player.pause(clipName);
    if (_activeSkeletal?.clip.name == clipName) {
      _activeSkeletal!.isPaused = true;
    }
  }

  void resume(String clipName) {
    player.resume(clipName);
    if (_activeSkeletal?.clip.name == clipName) {
      _activeSkeletal!.isPaused = false;
    }
  }

  void stop(String clipName) {
    player.stop(clipName);
    if (_activeSkeletal?.clip.name == clipName) {
      _activeSkeletal = null;
    }
  }

  void stopSkeletal() {
    _activeSkeletal = null;
    _crossFade = null;
  }

  bool isPlaying(String clipName) =>
      player.isPlaying(clipName) ||
      _activeSkeletal?.clip.name == clipName ||
      _crossFade?.toInstance.clip.name == clipName;

  /// Current evaluated bone palette matrix floats (16 floats per joint).
  Float32List get currentPalette =>
      _currentPalette ??
      (_currentPalette = skin?.computeSkinPalette() ?? Float32List(0));

  /// Evaluates Forward Kinematics (FK) and returns the resulting joint palette.
  Float32List computeJointPalette({
    List<Vec3>? translations,
    List<Quat>? rotations,
    List<Vec3>? scales,
  }) {
    final s = skin;
    if (s == null) return Float32List(0);
    return s.computeSkinPalette(
      translations: translations,
      rotations: rotations,
      scales: scales,
    );
  }

  /// Immediately applies the current bone palette to [graphics].
  void applyJointPalette(Graphics graphics) {
    targetRenderer?.applySkinPalette(graphics);
  }

  @override
  void start() {
    targetRenderer ??= gameObject.getComponent<SkinnedMeshRenderer>();
    skin ??= targetRenderer?.skin;

    final def = defaultClip;
    if (def != null) {
      if (skeletalClips.containsKey(def) || clips.containsKey(def)) {
        play(def);
      }
    }
  }

  @override
  void update() {
    final dt = time.deltaTime;
    player.update(dt);
    _updateSkeletal(dt);
  }

  void _updateSkeletal(double dt) {
    targetRenderer ??= gameObject.getComponent<SkinnedMeshRenderer>();
    skin ??= targetRenderer?.skin;
    final currentSkin = skin;
    if (currentSkin == null) return;

    final jointCount = currentSkin.jointCount;

    if (_crossFade != null) {
      final finished = _crossFade!.update(dt);
      final weight = _crossFade!.weight;

      final fromPose = _sampleClipPose(_crossFade!.fromInstance, currentSkin);
      final toPose = _sampleClipPose(_crossFade!.toInstance, currentSkin);

      final blendedT = <Vec3>[];
      final blendedR = <Quat>[];
      final blendedS = <Vec3>[];

      for (var j = 0; j < jointCount; j++) {
        final tA = fromPose.t[j], tB = toPose.t[j];
        final rA = fromPose.r[j], rB = toPose.r[j];
        final sA = fromPose.s[j], sB = toPose.s[j];

        blendedT.add(tA + ((tB - tA) * weight));
        blendedR.add(Quat.slerp(rA, rB, weight));
        blendedS.add(sA + ((sB - sA) * weight));
      }

      _currentPalette = currentSkin.computeSkinPalette(
        translations: blendedT,
        rotations: blendedR,
        scales: blendedS,
      );

      if (finished) {
        _activeSkeletal = _crossFade!.toInstance;
        _crossFade = null;
      }
    } else if (_activeSkeletal != null) {
      _activeSkeletal!.update(dt);
      final pose = _sampleClipPose(_activeSkeletal!, currentSkin);
      _currentPalette = currentSkin.computeSkinPalette(
        translations: pose.t,
        rotations: pose.r,
        scales: pose.s,
      );
    } else {
      _currentPalette = currentSkin.computeSkinPalette();
    }

    final pal = _currentPalette;
    if (pal != null && targetRenderer != null) {
      targetRenderer!.setJointPalette(pal);
    }
  }

  ({List<Vec3> t, List<Quat> r, List<Vec3> s}) _sampleClipPose(
    _ActiveSkeletalInstance instance,
    SkinData skinData,
  ) {
    final sampleTime = instance.clip.sampleTime(instance.currentTime);
    final count = skinData.jointCount;

    final translations = <Vec3>[];
    final rotations = <Quat>[];
    final scales = <Vec3>[];

    for (var j = 0; j < count; j++) {
      translations.add(skinData.joints[j].restTranslation);
      rotations.add(skinData.joints[j].restRotation);
      scales.add(skinData.joints[j].restScale);
    }

    for (final track in instance.clip.boneTracks) {
      final j = track.jointIndex;
      if (j >= 0 && j < count) {
        final t = track.sampleTranslation(sampleTime);
        if (t != null) translations[j] = t;

        final r = track.sampleRotation(sampleTime);
        if (r != null) rotations[j] = r;

        final s = track.sampleScale(sampleTime);
        if (s != null) scales[j] = s;
      }
    }

    return (t: translations, r: rotations, s: scales);
  }

  @override
  void _onDisableInternal() {
    player.clear();
    stopSkeletal();
  }
}
