part of '../../engine.dart';

/// Keyframe animation component wrapping pixeldart's [AnimationPlayer] (E5-1).
/// Advances with `time.deltaTime` so it respects `time.timeScale`.
final class Animator extends Behaviour {
  final AnimationPlayer player = AnimationPlayer();
  final Map<String, AnimationClip> clips = {};
  String? defaultClip;

  Animator({
    Iterable<AnimationClip> initialClips = const [],
    this.defaultClip,
  }) {
    for (final c in initialClips) {
      clips[c.name] = c;
    }
  }

  static final spec = ComponentSpec<Animator>(
    'Animator',
    Animator.new,
    const [],
  );

  void addClip(AnimationClip clip) => clips[clip.name] = clip;

  void play(String clipName, {double speed = 1.0}) {
    final clip =
        clips[clipName] ??
        (throw ArgumentError.value(
          clipName,
          'clipName',
          'AnimationClip not registered on Animator',
        ));
    player.play(clip, speed: speed);
  }

  void playClip(AnimationClip clip, {double speed = 1.0}) {
    clips[clip.name] = clip;
    player.play(clip, speed: speed);
  }

  void pause(String clipName) => player.pause(clipName);
  void resume(String clipName) => player.resume(clipName);
  void stop(String clipName) => player.stop(clipName);
  bool isPlaying(String clipName) => player.isPlaying(clipName);

  @override
  void start() {
    final def = defaultClip;
    if (def != null && clips.containsKey(def)) {
      play(def);
    }
  }

  @override
  void update() {
    player.update(time.deltaTime);
  }

  @override
  void _onDisableInternal() => player.clear();
}
