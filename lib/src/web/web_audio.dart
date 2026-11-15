import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../rocket.dart';

/// Web browser [AudioClip] backing both async-decoded [web.AudioBuffer]
/// playback and pooled [web.HTMLAudioElement] fallback.
final class WebAudioClip implements AudioClip {
  @override
  final String path;
  final double baseVolume;
  final List<web.HTMLAudioElement> pool;
  int next = 0;

  web.AudioBuffer? _decodedBuffer;
  bool _decodeAttempted = false;

  WebAudioClip(this.path, this.baseVolume, int voices)
    : pool = [
        for (var i = 0; i < voices; i++)
          web.HTMLAudioElement()
            ..src = path
            ..preload = 'auto'
            ..volume = baseVolume.clamp(0.0, 1.0),
      ];
}

/// Web Audio API channel routing an [AudioBufferSourceNode] or fallback
/// [MediaElementAudioSourceNode] through a low-pass [BiquadFilterNode],
/// [StereoPannerNode], optional 3D [PannerNode], channel [GainNode], and
/// dry / reverb send [GainNode]s.
final class WebAudioChannel implements AudioChannel {
  final WebAudioDevice _device;

  web.HTMLAudioElement? _el;
  web.MediaElementAudioSourceNode? _mediaSource;
  web.AudioBufferSourceNode? _bufferSource;
  int _playbackToken = 0;
  AudioClip? _currentClip;

  web.BiquadFilterNode? _filterNode;
  web.StereoPannerNode? _pannerNode;
  web.PannerNode? _spatialPannerNode;
  web.GainNode? _channelGain;
  web.GainNode? _dryGain;
  web.GainNode? _wetGain;
  bool _spatialPannerWired = false;
  Vec3? _spatialPosition;

  double _baseVolume = 1.0;
  double _volume = 1.0;
  double _pitch = 1.0;
  bool _loop = false;
  double _pan = 0.0;
  double _lowPassCutoffHz = 20000.0;
  double _lowPassResonance = 0.70710678;
  double _reverbWet = 0.0;
  bool _playing = false;
  bool _disposed = false;
  bool _pendingElementPlay = false;

  WebAudioChannel(this._device);

  double get pan => _pan;
  double get lowPassCutoffHz => _lowPassCutoffHz;
  double get lowPassResonance => _lowPassResonance;
  double get reverbWet => _reverbWet;
  Vec3? get spatialPosition => _spatialPosition;

  @override
  bool get isPlaying =>
      _playing && (_bufferSource != null || (_el != null && !_el!.paused));

  /// Ensures this channel's Web Audio DSP chain exists when an
  /// [web.AudioContext] is available. Returns `false` if Web Audio is
  /// unavailable or closed.
  bool _ensureGraph() {
    if (_disposed) return false;
    final ctx = _device._ensureAudioContext();
    final master = _device._masterGain;
    final reverbBus = _device._reverbSendBus;
    if (ctx == null || master == null) return false;
    if (_filterNode != null) return true;

    try {
      final filter = ctx.createBiquadFilter()..type = 'lowpass';
      final panner = ctx.createStereoPanner();
      final gain = ctx.createGain();
      final dry = ctx.createGain();
      final wet = ctx.createGain();

      filter.connect(panner);
      panner.connect(gain);
      gain.connect(dry);
      dry.connect(master);

      if (reverbBus != null) {
        gain.connect(wet);
        wet.connect(reverbBus);
      }

      _filterNode = filter;
      _pannerNode = panner;
      _channelGain = gain;
      _dryGain = dry;
      _wetGain = wet;

      _syncDspParams();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Optionally enables a Web Audio 3D [web.PannerNode] in series before
  /// [_channelGain] for world-space HRTF positioning, or passes `null` to
  /// bypass it and rely on [setPan] + spatial attenuation.
  void setSpatialPosition(Vec3? position) {
    _spatialPosition = position;
    if (position == null) {
      _setSpatialPannerWired(false);
      return;
    }
    if (!_ensureGraph()) return;
    final ctx = _device._ctx;
    final panner = _pannerNode;
    final gain = _channelGain;
    if (ctx == null || panner == null || gain == null) return;

    var spatial = _spatialPannerNode;
    if (spatial == null) {
      try {
        spatial = ctx.createPanner()
          ..panningModel = 'HRTF'
          ..distanceModel = 'inverse';
        _spatialPannerNode = spatial;
      } catch (_) {
        return;
      }
    }
    _applySpatialPosition(spatial, position);
    _setSpatialPannerWired(true);
  }

  void _setSpatialPannerWired(bool wire) {
    if (_spatialPannerWired == wire) return;
    final panner = _pannerNode;
    final gain = _channelGain;
    final spatial = _spatialPannerNode;
    if (panner == null || gain == null) return;
    try {
      panner.disconnect();
      if (wire && spatial != null) {
        spatial.disconnect();
        panner.connect(spatial);
        spatial.connect(gain);
        _spatialPannerWired = true;
      } else {
        panner.connect(gain);
        _spatialPannerWired = false;
      }
    } catch (_) {}
  }

  static void _applySpatialPosition(web.PannerNode node, Vec3 pos) {
    final x = _finiteOr(pos.x, 0.0);
    final y = _finiteOr(pos.y, 0.0);
    final z = _finiteOr(pos.z, 0.0);
    try {
      node.positionX.value = x;
      node.positionY.value = y;
      node.positionZ.value = z;
    } catch (_) {
      try {
        node.setPosition(x, y, z);
      } catch (_) {}
    }
  }

  void _syncDspParams() {
    final ctx = _device._ctx;
    if (ctx != null) {
      final nyquistLimit = math.max(
        200.0,
        math.min(22000.0, ctx.sampleRate.toDouble() * 0.49),
      );
      final cutoff = _lowPassCutoffHz.clamp(20.0, nyquistLimit);
      final q = _lowPassResonance.clamp(0.1, 20.0);
      final filter = _filterNode;
      if (filter != null) {
        filter.frequency.value = cutoff;
        filter.Q.value = q;
      }
    }

    _pannerNode?.pan.value = _pan;

    final effectiveGain = _device.muted ? 0.0 : (_baseVolume * _volume);
    final clampedGain = effectiveGain.isFinite
        ? effectiveGain.clamp(0.0, 2.0)
        : 0.0;
    _channelGain?.gain.value = clampedGain;
    _dryGain?.gain.value = 1.0;
    _wetGain?.gain.value = _reverbWet;

    final el = _el;
    if (el != null) {
      // Once connected to MediaElementAudioSourceNode, gain/mute are driven by
      // Web Audio GainNodes (which also allow >1.0 gain cleanly); otherwise
      // fall back to direct HTMLAudioElement volume control.
      el.volume = _mediaSource != null
          ? 1.0
          : (effectiveGain.isFinite ? effectiveGain.clamp(0.0, 1.0) : 0.0);
    }
  }

  @override
  void play(
    AudioClip clip, {
    double volume = 1,
    double pitch = 1,
    bool loop = false,
  }) {
    if (_disposed) return;
    _currentClip = clip;
    _baseVolume = clip is WebAudioClip ? clip.baseVolume : 1.0;
    _volume = _finiteOr(volume, 1.0);
    _pitch = _finiteOr(pitch, 1.0);
    _loop = loop;
    _playing = true;
    _playbackToken++;

    _device._installUnlockListeners();
    _device._attemptResumeIfGestureNotBlocked();
    _ensureGraph();
    _syncDspParams();

    final buffer = _device._resolveClipBuffer(clip);
    if (buffer != null && _startBufferSource(buffer)) {
      _pauseElement();
      return;
    }

    if (clip is WebAudioClip) {
      _device._prefetchClipBuffer(clip);
      _playFallbackElement(clip);
    }
  }

  bool _startBufferSource(web.AudioBuffer buffer) {
    final ctx = _device._ctx;
    final filter = _filterNode;
    if (ctx == null || filter == null) return false;
    _stopBufferSource();

    final token = _playbackToken;
    try {
      final src = ctx.createBufferSource()
        ..buffer = buffer
        ..loop = _loop;
      src.playbackRate.value = _pitch.clamp(0.25, 4.0);
      src.connect(filter);
      src.onended = ((web.Event _) {
        if (_disposed || token != _playbackToken) return;
        if (identical(_bufferSource, src)) {
          _bufferSource = null;
          if (!_loop) _playing = false;
        }
        try {
          src.disconnect();
        } catch (_) {}
      }).toJS;
      _bufferSource = src;
      src.start();
      return true;
    } catch (_) {
      _bufferSource = null;
      return false;
    }
  }

  void _stopBufferSource() {
    final src = _bufferSource;
    if (src == null) return;
    _bufferSource = null;
    try {
      src.onended = null;
      src.stop();
    } catch (_) {}
    try {
      src.disconnect();
    } catch (_) {}
  }

  void _playFallbackElement(WebAudioClip clip) {
    final el = _el ??= web.HTMLAudioElement()..preload = 'auto';
    if (!el.src.endsWith(clip.path)) {
      el.src = clip.path;
    }
    el
      ..loop = _loop
      ..playbackRate = _pitch.clamp(0.25, 4.0);

    _attachMediaElementSourceIfPossible(el);
    _syncDspParams();
    _syncMute();
  }

  void _attachMediaElementSourceIfPossible(web.HTMLAudioElement el) {
    if (_mediaSource != null) return;
    final ctx = _device._ctx;
    final filter = _filterNode;
    if (ctx == null || filter == null) return;
    try {
      final src = ctx.createMediaElementSource(el);
      src.connect(filter);
      _mediaSource = src;
    } catch (_) {
      // CORS / duplicate attachment / unsupported environment: continue with
      // HTMLAudioElement direct output without failing playback.
    }
  }

  void _pauseElement() {
    _pendingElementPlay = false;
    final el = _el;
    if (el != null && !el.paused) {
      try {
        el.pause();
      } catch (_) {}
    }
  }

  void _syncMute() {
    _syncDspParams();
    final el = _el;
    if (el == null || _bufferSource != null) return;
    if (_playing && !_device.muted) {
      if (el.paused) _safePlayElement(el);
    } else if (!el.paused) {
      try {
        el.pause();
      } catch (_) {}
    }
  }

  void _safePlayElement(web.HTMLAudioElement el) {
    try {
      el.play().toDart.then(
        (_) => _pendingElementPlay = false,
        onError: (Object _) {
          if (_playing && !_disposed) _pendingElementPlay = true;
        },
      );
    } catch (_) {
      if (_playing && !_disposed) _pendingElementPlay = true;
    }
  }

  void _onContextUnlocked() {
    if (_disposed || !_playing) return;
    final clip = _currentClip;
    if (_bufferSource == null && _pendingElementPlay && clip != null) {
      final buffer = _device._resolveClipBuffer(clip);
      if (buffer != null && _startBufferSource(buffer)) {
        _pauseElement();
        return;
      }
      final el = _el;
      if (el != null && !_device.muted && el.paused) {
        _safePlayElement(el);
      }
    }
  }

  @override
  void stop() {
    _playing = false;
    _playbackToken++;
    _stopBufferSource();
    _pauseElement();
  }

  @override
  set volume(double value) {
    _volume = _finiteOr(value, _volume);
    _syncDspParams();
  }

  @override
  set pitch(double value) {
    _pitch = _finiteOr(value, _pitch);
    final clamped = _pitch.clamp(0.25, 4.0);
    _bufferSource?.playbackRate.value = clamped;
    final el = _el;
    if (el != null) {
      el.playbackRate = clamped;
      _syncMute();
    }
  }

  @override
  void setPan(double pan) {
    _pan = _finiteOr(pan, 0.0).clamp(-1.0, 1.0);
    _pannerNode?.pan.value = _pan;
  }

  @override
  void setLowPass(double cutoffHz, {double resonance = 0.707}) {
    _lowPassCutoffHz = _finiteOr(cutoffHz, 20000.0).clamp(20.0, 22000.0);
    _lowPassResonance = _finiteOr(resonance, 0.70710678).clamp(0.1, 20.0);
    final ctx = _device._ctx;
    final filter = _filterNode;
    if (ctx != null && filter != null) {
      final nyquistLimit = math.max(
        200.0,
        math.min(22000.0, ctx.sampleRate.toDouble() * 0.49),
      );
      filter.frequency.value = _lowPassCutoffHz.clamp(20.0, nyquistLimit);
      filter.Q.value = _lowPassResonance;
    }
  }

  @override
  void setReverbSend(double wet) {
    _reverbWet = _finiteOr(wet, 0.0).clamp(0.0, 1.0);
    _wetGain?.gain.value = _reverbWet;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    _device._channels.remove(this);
    try {
      _mediaSource?.disconnect();
      _filterNode?.disconnect();
      _pannerNode?.disconnect();
      _spatialPannerNode?.disconnect();
      _channelGain?.disconnect();
      _dryGain?.disconnect();
      _wetGain?.disconnect();
    } catch (_) {}
    _mediaSource = null;
    _filterNode = null;
    _pannerNode = null;
    _spatialPannerNode = null;
    _channelGain = null;
    _dryGain = null;
    _wetGain = null;
    _el = null;
    _currentClip = null;
  }
}

/// Web Audio API host [AudioDevice] implementing a shared master gain, stereo
/// room reverb send bus ([web.ConvolverNode] + damped delay network), decoded
/// [web.AudioBufferSourceNode] synthesis/asset playback, [web.HTMLAudioElement]
/// fallback, [web.AudioListener] pose updates, and user-gesture autoplay unlock.
final class WebAudioDevice implements AudioDevice {
  static const List<String> _unlockEvents = <String>[
    'pointerdown',
    'keydown',
    'touchstart',
    'click',
  ];

  bool _muted = false;
  bool _disposed = false;
  final List<WebAudioChannel> _channels = [];
  final Expando<web.AudioBuffer> _proceduralBuffers = Expando<web.AudioBuffer>(
    'webProceduralBuffers',
  );

  web.AudioContext? _ctx;
  web.GainNode? _masterGain;
  web.GainNode? _reverbSendBus;
  web.DelayNode? _reverbPreDelay;
  web.ConvolverNode? _reverbConvolver;
  web.DelayNode? _reverbFeedbackDelay;
  web.BiquadFilterNode? _reverbToneFilter;
  web.GainNode? _reverbFeedbackGain;
  web.GainNode? _reverbReturnGain;

  web.EventListener? _unlockListener;
  bool _unlockListenersInstalled = false;

  Vec3 _listenerPosition = const Vec3(0, 0, 0);
  Vec3 _listenerForward = const Vec3(0, 0, -1);
  Vec3 _listenerUp = const Vec3(0, 1, 0);

  Vec3 get listenerPosition => _listenerPosition;
  Vec3 get listenerForward => _listenerForward;
  Vec3 get listenerUp => _listenerUp;

  /// Active Web Audio [web.AudioContext], if already initialized.
  web.AudioContext? get audioContext => _ctx;

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    _masterGain?.gain.value = _muted ? 0.0 : 1.0;
    for (final ch in _channels) {
      ch._syncMute();
    }
  }

  web.AudioContext? _ensureAudioContext() {
    if (_disposed) return null;
    final existing = _ctx;
    if (existing != null) return existing;

    try {
      final ctx = web.AudioContext();
      final master = ctx.createGain()..gain.value = _muted ? 0.0 : 1.0;
      master.connect(ctx.destination);

      final sendBus = ctx.createGain()..gain.value = 1.0;
      final preDelay = ctx.createDelay(0.5);
      preDelay.delayTime.value = 0.018;

      final convolver = ctx.createConvolver()..normalize = true;
      convolver.buffer = _createRoomImpulseBuffer(ctx);

      final fbDelay = ctx.createDelay(0.5);
      fbDelay.delayTime.value = 0.073;
      final toneFilter = ctx.createBiquadFilter()..type = 'lowpass';
      toneFilter.frequency.value = 4800.0;
      final fbGain = ctx.createGain()..gain.value = 0.25;
      final returnGain = ctx.createGain()..gain.value = 0.85;

      sendBus.connect(preDelay);
      preDelay.connect(convolver);
      convolver.connect(returnGain);

      preDelay.connect(fbDelay);
      fbDelay.connect(toneFilter);
      toneFilter.connect(fbGain);
      fbGain.connect(fbDelay);
      toneFilter.connect(returnGain);

      returnGain.connect(master);

      _ctx = ctx;
      _masterGain = master;
      _reverbSendBus = sendBus;
      _reverbPreDelay = preDelay;
      _reverbConvolver = convolver;
      _reverbFeedbackDelay = fbDelay;
      _reverbToneFilter = toneFilter;
      _reverbFeedbackGain = fbGain;
      _reverbReturnGain = returnGain;

      _applyListenerPose();
      return ctx;
    } catch (_) {
      return null;
    }
  }

  void _installUnlockListeners() {
    if (_disposed || _unlockListenersInstalled) return;
    final listener = ((web.Event _) {
      _handleUserGesture();
    }).toJS;
    _unlockListener = listener;
    _unlockListenersInstalled = true;
    try {
      for (final evt in _unlockEvents) {
        web.window.addEventListener(evt, listener);
      }
    } catch (_) {}
  }

  void _removeUnlockListeners() {
    final listener = _unlockListener;
    if (!_unlockListenersInstalled || listener == null) return;
    _unlockListenersInstalled = false;
    _unlockListener = null;
    try {
      for (final evt in _unlockEvents) {
        web.window.removeEventListener(evt, listener);
      }
    } catch (_) {}
  }

  void _handleUserGesture() {
    if (_disposed) {
      _removeUnlockListeners();
      return;
    }
    final ctx = _ensureAudioContext();
    if (ctx == null) return;
    if (ctx.state == 'running') {
      _onUnlocked();
      return;
    }
    if (ctx.state == 'suspended') {
      try {
        ctx.resume().toDart.then((_) {
          if (_ctx?.state == 'running') _onUnlocked();
        }, onError: (Object _) {});
      } catch (_) {}
    }
  }

  void _attemptResumeIfGestureNotBlocked() {
    final ctx = _ensureAudioContext();
    if (ctx == null || ctx.state != 'suspended') return;
    try {
      ctx.resume().toDart.then((_) {
        if (_ctx?.state == 'running') _onUnlocked();
      }, onError: (Object _) {});
    } catch (_) {}
  }

  void _onUnlocked() {
    _removeUnlockListeners();
    for (final ch in List<WebAudioChannel>.of(_channels)) {
      ch._onContextUnlocked();
    }
  }

  web.AudioBuffer? _resolveClipBuffer(AudioClip clip) {
    if (clip is WebAudioClip) return clip._decodedBuffer;
    if (clip is ProceduralAudioClip) {
      final cached = _proceduralBuffers[clip];
      if (cached != null) return cached;
      final ctx = _ensureAudioContext();
      if (ctx == null) return null;
      final parsed = _tryDecodeWavBytesToBuffer(ctx, clip.wavBytes);
      if (parsed != null) {
        _proceduralBuffers[clip] = parsed;
        return parsed;
      }
      _decodeWavBytesAsync(ctx, clip);
    }
    return null;
  }

  void _decodeWavBytesAsync(web.AudioContext ctx, ProceduralAudioClip clip) {
    try {
      final copy = Uint8List.fromList(clip.wavBytes);
      ctx.decodeAudioData(copy.buffer.toJS).toDart.then((buf) {
        if (!_disposed) _proceduralBuffers[clip] = buf;
      }, onError: (Object _) {});
    } catch (_) {}
  }

  void _prefetchClipBuffer(WebAudioClip clip) {
    if (_disposed || clip._decodeAttempted || clip._decodedBuffer != null) {
      return;
    }
    clip._decodeAttempted = true;
    final ctx = _ensureAudioContext();
    if (ctx == null) return;
    try {
      web.window.fetch(clip.path.toJS).toDart.then((resp) {
        if (_disposed || !resp.ok) return;
        resp.arrayBuffer().toDart.then((arrBuf) {
          if (_disposed) return;
          ctx.decodeAudioData(arrBuf).toDart.then((audioBuf) {
            if (!_disposed) clip._decodedBuffer = audioBuf;
          }, onError: (Object _) {});
        }, onError: (Object _) {});
      }, onError: (Object _) {});
    } catch (_) {}
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
    if (_muted || _disposed) return;
    _installUnlockListeners();
    _attemptResumeIfGestureNotBlocked();

    final base = clip is WebAudioClip ? clip.baseVolume : 1.0;
    final buf = _resolveClipBuffer(clip);
    final ctx = _ctx;
    final master = _masterGain;
    if (buf != null && ctx != null && master != null) {
      try {
        final src = ctx.createBufferSource()..buffer = buf;
        src.playbackRate.value = _finiteOr(pitch, 1.0).clamp(0.25, 4.0);
        final gain = ctx.createGain();
        final v = _finiteOr(base * volume, 1.0).clamp(0.0, 2.0);
        gain.gain.value = v;
        src.connect(gain);
        gain.connect(master);
        src.onended = ((web.Event _) {
          try {
            src.disconnect();
            gain.disconnect();
          } catch (_) {}
        }).toJS;
        src.start();
        return;
      } catch (_) {}
    }

    if (clip is! WebAudioClip || clip.pool.isEmpty) return;
    _prefetchClipBuffer(clip);
    final i = clip.next;
    clip.next = (i + 1) % clip.pool.length;
    final voice = clip.pool[i]
      ..currentTime = 0
      ..volume = _finiteOr(clip.baseVolume * volume, 1.0).clamp(0.0, 1.0)
      ..playbackRate = _finiteOr(pitch, 1.0).clamp(0.25, 4.0);
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
    _applyListenerPose();
  }

  void _applyListenerPose() {
    final ctx = _ctx;
    if (ctx == null || ctx.state == 'closed') return;
    final px = _finiteOr(_listenerPosition.x, 0.0);
    final py = _finiteOr(_listenerPosition.y, 0.0);
    final pz = _finiteOr(_listenerPosition.z, 0.0);
    final fx = _finiteOr(_listenerForward.x, 0.0);
    final fy = _finiteOr(_listenerForward.y, 0.0);
    final fz = _finiteOr(_listenerForward.z, -1.0);
    final ux = _finiteOr(_listenerUp.x, 0.0);
    final uy = _finiteOr(_listenerUp.y, 1.0);
    final uz = _finiteOr(_listenerUp.z, 0.0);
    try {
      final l = ctx.listener;
      l.positionX.value = px;
      l.positionY.value = py;
      l.positionZ.value = pz;
      l.forwardX.value = fx;
      l.forwardY.value = fy;
      l.forwardZ.value = fz;
      l.upX.value = ux;
      l.upY.value = uy;
      l.upZ.value = uz;
    } catch (_) {
      try {
        ctx.listener
          ..setPosition(px, py, pz)
          ..setOrientation(fx, fy, fz, ux, uy, uz);
      } catch (_) {}
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _removeUnlockListeners();
    for (final ch in List<WebAudioChannel>.of(_channels)) {
      ch.dispose();
    }
    try {
      _reverbSendBus?.disconnect();
      _reverbPreDelay?.disconnect();
      _reverbConvolver?.disconnect();
      _reverbFeedbackDelay?.disconnect();
      _reverbToneFilter?.disconnect();
      _reverbFeedbackGain?.disconnect();
      _reverbReturnGain?.disconnect();
      _masterGain?.disconnect();
    } catch (_) {}
    final ctx = _ctx;
    _ctx = null;
    _masterGain = null;
    _reverbSendBus = null;
    _reverbPreDelay = null;
    _reverbConvolver = null;
    _reverbFeedbackDelay = null;
    _reverbToneFilter = null;
    _reverbFeedbackGain = null;
    _reverbReturnGain = null;
    if (ctx != null && ctx.state != 'closed') {
      try {
        ctx.close().toDart.then((_) {}, onError: (Object _) {});
      } catch (_) {}
    }
  }

  static web.AudioBuffer? _createRoomImpulseBuffer(web.AudioContext ctx) {
    try {
      final sr = ctx.sampleRate.toDouble().clamp(8000.0, 192000.0);
      final length = math.max(1024, (sr * 1.15).round());
      final buf = ctx.createBuffer(2, length, sr);
      var seedL = 0x1234567;
      var seedR = 0x89abcde;
      final ch0 = Float32List(length);
      final ch1 = Float32List(length);
      for (var i = 0; i < length; i++) {
        seedL = (seedL * 1664525 + 1013904223) & 0x7fffffff;
        seedR = (seedR * 1664525 + 1013904223) & 0x7fffffff;
        final nL = (seedL / 0x3fffffff) - 1.0;
        final nR = (seedR / 0x3fffffff) - 1.0;
        final t = i / length;
        final env = math.pow(1.0 - t, 3.2).toDouble();
        ch0[i] = nL * env * 0.35;
        ch1[i] = nR * env * 0.35;
      }
      buf.copyToChannel(ch0.toJS, 0);
      buf.copyToChannel(ch1.toJS, 1);
      return buf;
    } catch (_) {
      return null;
    }
  }

  static web.AudioBuffer? _tryDecodeWavBytesToBuffer(
    web.AudioContext ctx,
    Uint8List bytes,
  ) {
    if (bytes.length < 44) return null;
    if (bytes[0] != 0x52 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46 ||
        bytes[3] != 0x46 ||
        bytes[8] != 0x57 ||
        bytes[9] != 0x41 ||
        bytes[10] != 0x56 ||
        bytes[11] != 0x45) {
      return null;
    }
    final bd = ByteData.sublistView(bytes);
    var offset = 12;
    var audioFormat = -1;
    var channels = 0;
    var sampleRate = 0;
    var bitsPerSample = 0;
    var dataOffset = -1;
    var dataSize = 0;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes, offset, offset + 4);
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final bodyOffset = offset + 8;
      if (chunkId == 'fmt ' && bodyOffset + 16 <= bytes.length) {
        audioFormat = bd.getUint16(bodyOffset, Endian.little);
        channels = bd.getUint16(bodyOffset + 2, Endian.little);
        sampleRate = bd.getUint32(bodyOffset + 4, Endian.little);
        bitsPerSample = bd.getUint16(bodyOffset + 14, Endian.little);
      } else if (chunkId == 'data' && bodyOffset <= bytes.length) {
        dataOffset = bodyOffset;
        dataSize = math.min(chunkSize, bytes.length - bodyOffset);
        break;
      }
      final padded = chunkSize + (chunkSize & 1);
      offset = bodyOffset + padded;
    }

    if (dataOffset < 0 || channels < 1 || channels > 8 || sampleRate < 1000) {
      return null;
    }
    final bytesPerSample = bitsPerSample ~/ 8;
    if (bytesPerSample <= 0) return null;
    final frameBytes = channels * bytesPerSample;
    final frames = dataSize ~/ frameBytes;
    if (frames <= 0) return null;

    final supportedPcm =
        audioFormat == 1 && (bitsPerSample == 8 || bitsPerSample == 16);
    final supportedFloat = audioFormat == 3 && bitsPerSample == 32;
    if (!supportedPcm && !supportedFloat) return null;

    try {
      final buf = ctx.createBuffer(channels, frames, sampleRate);
      final channelData = [
        for (var c = 0; c < channels; c++) Float32List(frames),
      ];
      for (var f = 0; f < frames; f++) {
        final framePos = dataOffset + f * frameBytes;
        for (var c = 0; c < channels; c++) {
          final samplePos = framePos + c * bytesPerSample;
          final double v;
          if (audioFormat == 3) {
            v = bd.getFloat32(samplePos, Endian.little);
          } else if (bitsPerSample == 16) {
            v = bd.getInt16(samplePos, Endian.little) / 32768.0;
          } else {
            v = (bytes[samplePos] - 128) / 128.0;
          }
          channelData[c][f] = v;
        }
      }
      for (var c = 0; c < channels; c++) {
        buf.copyToChannel(channelData[c].toJS, c);
      }
      return buf;
    } catch (_) {
      return null;
    }
  }

  // Browser autoplay policies reject play() before the first user gesture;
  // swallow that rejection rather than surfacing an unhandled error.
  static void _safePlay(web.HTMLAudioElement voice) {
    try {
      voice.play().toDart.then((_) {}, onError: (Object _) {});
    } catch (_) {}
  }
}

double _finiteOr(double value, double fallback) =>
    value.isFinite ? value : fallback;
