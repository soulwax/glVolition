import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../rocket.dart';

final class WebAudioClip implements AudioClip {
  @override
  final String path;
  final double baseVolume;
  final List<web.HTMLAudioElement> pool;
  int next = 0;

  WebAudioClip(this.path, this.baseVolume, int voices)
    : pool = [
        for (var i = 0; i < voices; i++)
          web.HTMLAudioElement()
            ..src = path
            ..preload = 'auto'
            ..volume = baseVolume.clamp(0.0, 1.0),
      ];
}

final class WebAudioChannel implements AudioChannel {
  final WebAudioDevice _device;
  web.HTMLAudioElement? _el;
  double _baseVolume = 1.0;
  double _volume = 1.0;
  double _pitch = 1.0;
  double _pan = 0.0;
  double _lowPassCutoffHz = 20000.0;
  double _reverbWet = 0.0;
  bool _playing = false;

  WebAudioChannel(this._device);

  double get pan => _pan;
  double get lowPassCutoffHz => _lowPassCutoffHz;
  double get reverbWet => _reverbWet;

  @override
  bool get isPlaying => _playing && (_el != null && !_el!.paused);

  @override
  void play(
    AudioClip clip, {
    double volume = 1,
    double pitch = 1,
    bool loop = false,
  }) {
    final base = clip is WebAudioClip ? clip.baseVolume : 1.0;
    _baseVolume = base;
    _volume = volume;
    _pitch = pitch;
    final el = _el ??= web.HTMLAudioElement()..preload = 'auto';
    if (!el.src.endsWith(clip.path)) {
      el.src = clip.path;
    }
    el
      ..loop = loop
      ..volume = (_baseVolume * _volume).clamp(0.0, 1.0)
      ..playbackRate = _pitch.clamp(0.25, 4.0);
    _playing = true;
    _syncMute();
  }

  void _syncMute() {
    final el = _el;
    if (el == null) return;
    if (_playing && !_device.muted) {
      if (el.paused) WebAudioDevice._safePlay(el);
    } else if (!el.paused) {
      el.pause();
    }
  }

  @override
  void stop() {
    _playing = false;
    final el = _el;
    if (el != null && !el.paused) el.pause();
  }

  @override
  set volume(double value) {
    _volume = value;
    _el?.volume = (_baseVolume * _volume).clamp(0.0, 1.0);
  }

  @override
  set pitch(double value) {
    _pitch = value;
    _el?.playbackRate = _pitch.clamp(0.25, 4.0);
    _syncMute();
  }

  @override
  void setPan(double pan) {
    _pan = pan.clamp(-1.0, 1.0);
  }

  @override
  void setLowPass(double cutoffHz, {double resonance = 0.707}) {
    _lowPassCutoffHz = cutoffHz;
  }

  @override
  void setReverbSend(double wet) {
    _reverbWet = wet.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    stop();
    _device._channels.remove(this);
    _el = null;
  }
}

final class WebAudioDevice implements AudioDevice {
  bool _muted = false;
  final List<WebAudioChannel> _channels = [];
  Vec3 _listenerPosition = const Vec3(0, 0, 0);
  Vec3 _listenerForward = const Vec3(0, 0, -1);
  Vec3 _listenerUp = const Vec3(0, 1, 0);

  Vec3 get listenerPosition => _listenerPosition;
  Vec3 get listenerForward => _listenerForward;
  Vec3 get listenerUp => _listenerUp;

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    for (final ch in _channels) {
      ch._syncMute();
    }
  }

  @override
  AudioClip clip(String path, {double volume = 1, int voices = 3}) =>
      WebAudioClip(path, volume, voices);

  @override
  AudioChannel createChannel() {
    final ch = WebAudioChannel(this);
    _channels.add(ch);
    return ch;
  }

  @override
  void playOneShot(AudioClip clip, {double volume = 1, double pitch = 1}) {
    if (_muted || clip is! WebAudioClip || clip.pool.isEmpty) return;
    final i = clip.next;
    clip.next = (i + 1) % clip.pool.length;
    final voice = clip.pool[i]
      ..currentTime = 0
      ..volume = (clip.baseVolume * volume).clamp(0.0, 1.0)
      ..playbackRate = pitch.clamp(0.25, 4.0);
    _safePlay(voice);
  }

  @override
  void setListenerPose({
    Vec3 position = const Vec3(0, 0, 0),
    Vec3 forward = const Vec3(0, 0, -1),
    Vec3 up = const Vec3(0, 1, 0),
  }) {
    _listenerPosition = position;
    _listenerForward = forward;
    _listenerUp = up;
  }

  void dispose() {
    for (final ch in List<WebAudioChannel>.of(_channels)) {
      ch.dispose();
    }
  }

  // Browser autoplay policies reject play() before the first user gesture;
  // swallow that rejection rather than surfacing an unhandled error.
  static void _safePlay(web.HTMLAudioElement voice) {
    voice.play().toDart.then((_) {}, onError: (Object _) {});
  }
}
