part of '../../engine.dart';

/// Plays [AudioClip]s through the host's [AudioDevice]: either overlapping
/// one-shots via [playOneShot] or a single controllable voice via [play]
/// (for engine hums, music, ambience).
final class AudioSource extends Component {
  AudioClip? clip;
  double _volume = 1.0;
  double _pitch = 1.0;
  bool loop;
  bool playOnAwake;

  AudioChannel? _channel;

  AudioSource({
    this.clip,
    double volume = 1.0,
    double pitch = 1.0,
    this.loop = false,
    this.playOnAwake = false,
  }) {
    _volume = volume;
    _pitch = pitch;
  }

  double get volume => _volume;
  set volume(double value) {
    _volume = value;
    _channel?.volume = value;
  }

  double get pitch => _pitch;
  set pitch(double value) {
    _pitch = value;
    _channel?.pitch = value;
  }

  bool get isPlaying => _channel?.isPlaying ?? false;

  void play([AudioClip? overrideClip]) {
    final c = overrideClip ?? clip;
    if (c == null) return;
    clip = c;
    final ch = _channel ??= engine.audio.createChannel();
    ch.play(c, volume: _volume, pitch: _pitch, loop: loop);
  }

  void stop() => _channel?.stop();

  void playOneShot(AudioClip oneShot, {double volumeScale = 1.0, double pitch = 1.0}) =>
      engine.audio.playOneShot(oneShot, volume: _volume * volumeScale, pitch: _pitch * pitch);

  @override
  void onEnable() {
    if (playOnAwake && clip != null) play();
  }

  @override
  void _onDisableInternal() => _channel?.stop();

  @override
  void _onDestroyInternal() {
    _channel?.dispose();
    _channel = null;
  }
}
