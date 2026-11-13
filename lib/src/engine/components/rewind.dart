part of '../../engine.dart';

typedef _RewindFrameState = ({
  snap.TransformSample transform,
  Uint8List? customBytes,
});

/// Records a bounded history of a [GameObject]'s transform and optional custom binary state
/// for smooth time-rewind and timeline branching.
final class TimeRewindComponent extends Behaviour {
  final snap.RewindBuffer<_RewindFrameState> _buffer;
  final void Function(snap.BinarySnapshotWriter writer)? onCaptureState;
  final void Function(snap.BinarySnapshotReader reader)? onRestoreState;

  double rewindSpeed;
  bool isRecording = true;
  bool _isRewinding = false;
  double _clock = 0.0;
  double _rewindCursor = 0.0;

  TimeRewindComponent({
    int maxFrames = 300,
    this.rewindSpeed = 1.0,
    this.onCaptureState,
    this.onRestoreState,
  }) : _buffer = snap.RewindBuffer<_RewindFrameState>(capacity: maxFrames);

  bool get isRewinding => _isRewinding;
  int get recordedFrames => _buffer.length;
  double get recordedDuration => _buffer.totalDuration;
  double get rewindTime => _rewindCursor;

  /// Enters rewind playback mode, moving backward from the most recent recorded time.
  void beginRewind() {
    if (_buffer.isEmpty) return;
    _isRewinding = true;
    _rewindCursor = _buffer.latest!.time;
  }

  /// Exits rewind mode and resumes live gameplay from the current rewound cursor,
  /// discarding overwritten future history cleanly.
  void stopRewind() {
    if (!_isRewinding) return;
    _isRewinding = false;
    _buffer.truncateAfter(_rewindCursor);
    _clock = _rewindCursor;
  }

  /// Rewinds directly back by [seconds] without remaining in continuous rewind mode.
  bool rewindSeconds(double seconds) {
    if (_buffer.isEmpty) return false;
    final targetTime = math.max(
      _buffer.oldest!.time,
      _buffer.latest!.time - seconds,
    );
    _applyTimeSample(targetTime);
    _buffer.truncateAfter(targetTime);
    _clock = targetTime;
    return true;
  }

  void clearHistory() {
    _buffer.clear();
    _clock = 0.0;
    _isRewinding = false;
  }

  void _captureFrame(double dt) {
    _clock += dt;
    final p = transform.position;
    final q = transform.rotation;
    final s = transform.localScale;

    Uint8List? custom;
    if (onCaptureState != null) {
      final w = snap.BinarySnapshotWriter();
      onCaptureState!(w);
      custom = w.toBytes();
    }

    _buffer.push(_clock, (
      transform: snap.TransformSample(
        time: _clock,
        px: p.x,
        py: p.y,
        pz: p.z,
        qx: q.x,
        qy: q.y,
        qz: q.z,
        qw: q.w,
        sx: s,
        sy: s,
        sz: s,
      ),
      customBytes: custom,
    ));
  }

  void _applyTimeSample(double targetTime) {
    final bracket = _buffer.sampleInterpolated(targetTime);
    if (bracket == null) return;

    final lerped = snap.TransformSample.lerp(
      bracket.a.state.transform,
      bracket.b.state.transform,
      bracket.t,
    );

    transform.position = Vec3(lerped.px, lerped.py, lerped.pz);
    transform.rotation = Quat(lerped.qx, lerped.qy, lerped.qz, lerped.qw);
    transform.localScale = lerped.sx;

    final nearest = bracket.t >= 0.5 ? bracket.b.state : bracket.a.state;
    if (onRestoreState != null && nearest.customBytes != null) {
      onRestoreState!(snap.BinarySnapshotReader(nearest.customBytes!));
    }
  }

  @override
  void fixedUpdate() {
    final dt = time.fixedDeltaTime;
    if (_isRewinding) {
      _rewindCursor -= dt * rewindSpeed;
      if (_buffer.oldest != null && _rewindCursor <= _buffer.oldest!.time) {
        _rewindCursor = _buffer.oldest!.time;
        _applyTimeSample(_rewindCursor);
      } else {
        _applyTimeSample(_rewindCursor);
      }
      return;
    }

    if (isRecording) {
      _captureFrame(dt);
    }
  }
}

/// Records the attached [GameObject]'s movement into a compact [snap.GhostTrack] at fixed intervals.
final class GhostRecorderComponent extends Behaviour {
  final snap.GhostTrack track;
  final double sampleInterval;
  bool isRecording;

  double _elapsed = 0.0;
  double _accum = 0.0;

  GhostRecorderComponent({
    snap.GhostTrack? track,
    this.sampleInterval = 0.05, // 20 Hz
    this.isRecording = true,
  }) : track = track ?? snap.GhostTrack();

  Uint8List exportBinary() => track.encodeBinary();

  @override
  void lateUpdate() {
    if (!isRecording) return;
    final dt = time.deltaTime;
    _elapsed += dt;
    _accum += dt;

    if (track.isEmpty || _accum >= sampleInterval) {
      if (_accum >= sampleInterval) _accum %= sampleInterval;
      final p = transform.position;
      final q = transform.rotation;
      final s = transform.localScale;
      track.addSample(
        snap.TransformSample(
          time: _elapsed,
          px: p.x,
          py: p.y,
          pz: p.z,
          qx: q.x,
          qy: q.y,
          qz: q.z,
          qw: q.w,
          sx: s,
          sy: s,
          sz: s,
        ),
      );
    }
  }
}

/// Plays back a recorded [snap.GhostTrack] smoothly on the attached [GameObject].
final class GhostPlaybackComponent extends Behaviour {
  final snap.GhostPlayer player;

  GhostPlaybackComponent(
    snap.GhostTrack track, {
    double playbackSpeed = 1.0,
    bool loop = true,
    bool autoPlay = true,
  }) : player = snap.GhostPlayer(
         track,
         playbackSpeed: playbackSpeed,
         loop: loop,
       ) {
    if (autoPlay) player.play();
  }

  factory GhostPlaybackComponent.fromBinary(
    Uint8List bytes, {
    double playbackSpeed = 1.0,
    bool loop = true,
    bool autoPlay = true,
  }) => GhostPlaybackComponent(
    snap.GhostTrack.decodeBinary(bytes),
    playbackSpeed: playbackSpeed,
    loop: loop,
    autoPlay: autoPlay,
  );

  @override
  void update() {
    final sample = player.advance(time.deltaTime);
    if (sample == null) return;

    transform.position = Vec3(sample.px, sample.py, sample.pz);
    transform.rotation = Quat(sample.qx, sample.qy, sample.qz, sample.qw);
    transform.localScale = sample.sx;
  }
}
