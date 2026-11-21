/// Shared Timeline & Dopesheet View Model (`[S7-0]` / `[S7-A]`):
/// Tracks, clips, keyframes, frame snapping, scrubbing, record mode, and
/// JSON round-trip.
library;

/// Supported track types matching `CutsceneSequencer` & Animation windows.
enum TimelineTrackKind { animation, audio, activation, signal, camera }

/// Single keyframe on a [TimelineTrack].
final class TimelineKey {
  final double time;
  final String propertyPath;
  final Object? value;

  const TimelineKey({
    required this.time,
    required this.propertyPath,
    required this.value,
  });

  Map<String, Object?> toJson() => {
    'time': time,
    'propertyPath': propertyPath,
    'value': value,
  };

  factory TimelineKey.fromJson(Map<String, Object?> json) => TimelineKey(
    time: (json['time'] as num).toDouble(),
    propertyPath: json['propertyPath'] as String,
    value: json['value'],
  );
}

/// Time-range clip on a [TimelineTrack].
final class TimelineClip {
  final String id;
  final String assetGuid;
  double startTime;
  double duration;

  TimelineClip({
    required this.id,
    required this.assetGuid,
    required this.startTime,
    required this.duration,
  });

  double get endTime => startTime + duration;
  bool contains(double t) => t >= startTime && t <= endTime;

  Map<String, Object?> toJson() => {
    'id': id,
    'assetGuid': assetGuid,
    'startTime': startTime,
    'duration': duration,
  };

  factory TimelineClip.fromJson(Map<String, Object?> json) => TimelineClip(
    id: json['id'] as String,
    assetGuid: json['assetGuid'] as String? ?? '',
    startTime: (json['startTime'] as num).toDouble(),
    duration: (json['duration'] as num).toDouble(),
  );
}

/// A single track inside a [StudioTimelineModel].
final class TimelineTrack {
  final String id;
  final String name;
  final TimelineTrackKind kind;
  bool muted;
  final List<TimelineClip> clips;
  final List<TimelineKey> keys;

  TimelineTrack({
    required this.id,
    required this.name,
    required this.kind,
    this.muted = false,
    List<TimelineClip>? clips,
    List<TimelineKey>? keys,
  }) : clips = clips ?? [],
       keys = keys ?? [];

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'muted': muted,
    'clips': [for (final c in clips) c.toJson()],
    'keys': [for (final k in keys) k.toJson()],
  };

  factory TimelineTrack.fromJson(Map<String, Object?> json) => TimelineTrack(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    kind: TimelineTrackKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => TimelineTrackKind.animation,
    ),
    muted: json['muted'] as bool? ?? false,
    clips: [
      for (final c in (json['clips'] as List?) ?? const [])
        TimelineClip.fromJson((c as Map).cast<String, Object?>()),
    ],
    keys: [
      for (final k in (json['keys'] as List?) ?? const [])
        TimelineKey.fromJson((k as Map).cast<String, Object?>()),
    ],
  );
}

/// Pure-Dart Timeline & Dopesheet controller (`[S7-0]` / `[S7-A]`).
final class StudioTimelineModel {
  double frameRate;
  bool snapToFrames;
  bool recordMode;
  double playheadSeconds;
  final List<TimelineTrack> tracks;

  StudioTimelineModel({
    this.frameRate = 60.0,
    this.snapToFrames = true,
    this.recordMode = false,
    this.playheadSeconds = 0.0,
    List<TimelineTrack>? tracks,
  }) : tracks = tracks ?? [];

  /// Snaps [timeSeconds] to the nearest frame boundary when [snapToFrames] is
  /// enabled.
  double snapTime(double timeSeconds) {
    final t = timeSeconds < 0.0 ? 0.0 : timeSeconds;
    if (!snapToFrames || frameRate <= 0) return t;
    return (t * frameRate).round() / frameRate;
  }

  void scrubTo(double timeSeconds) {
    playheadSeconds = snapTime(timeSeconds);
  }

  /// Records a keyframe on [trackId] at the current [playheadSeconds] when
  /// [recordMode] is active.
  bool recordKey(String trackId, String propertyPath, Object? value) {
    if (!recordMode) return false;
    for (final track in tracks) {
      if (track.id == trackId) {
        track.keys.removeWhere(
          (k) =>
              k.propertyPath == propertyPath &&
              (k.time - playheadSeconds).abs() < 1e-4,
        );
        track.keys.add(
          TimelineKey(
            time: playheadSeconds,
            propertyPath: propertyPath,
            value: value,
          ),
        );
        track.keys.sort((a, b) => a.time.compareTo(b.time));
        return true;
      }
    }
    return false;
  }

  /// Returns all active clips across unmuted tracks at [playheadSeconds].
  List<TimelineClip> activeClipsAtPlayhead() => [
    for (final track in tracks)
      if (!track.muted)
        for (final clip in track.clips)
          if (clip.contains(playheadSeconds)) clip,
  ];

  Map<String, Object?> toJson() => {
    'frameRate': frameRate,
    'snapToFrames': snapToFrames,
    'tracks': [for (final t in tracks) t.toJson()],
  };

  factory StudioTimelineModel.fromJson(Map<String, Object?> json) =>
      StudioTimelineModel(
        frameRate: (json['frameRate'] as num?)?.toDouble() ?? 60.0,
        snapToFrames: json['snapToFrames'] as bool? ?? true,
        tracks: [
          for (final t in (json['tracks'] as List?) ?? const [])
            TimelineTrack.fromJson((t as Map).cast<String, Object?>()),
        ],
      );
}
