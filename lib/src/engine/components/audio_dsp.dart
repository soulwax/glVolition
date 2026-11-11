part of '../../engine.dart';

dsp.DspVec3 _toDspVec3(Vec3 v) => dsp.DspVec3(v.x, v.y, v.z);

/// Spatial 3D environmental reverb zone (cave, cathedral, room) (E36).
class AudioReverbZone extends Component {
  double minDistance;
  double maxDistance;
  final dsp.SchroederReverb reverb;

  AudioReverbZone({
    this.minDistance = 2.0,
    this.maxDistance = 20.0,
    double roomSize = 0.7,
    double damp = 0.3,
    double wet = 0.5,
  }) : reverb = dsp.SchroederReverb(
          roomSize: roomSize,
          damp: damp,
          wet: wet,
        );

  double get roomSize => reverb.roomSize;
  set roomSize(double val) => reverb.roomSize = val;

  double get damp => reverb.damp;
  set damp(double val) => reverb.damp = val;

  double get wet => reverb.wet;
  set wet(double val) => reverb.wet = val;

  /// Calculates the wet reverberation mix factor for a listener at [listenerPosition].
  /// Inside [minDistance], wet mix is 100% of zone [wet]. Between [minDistance] and
  /// [maxDistance], wet mix attenuates linearly to 0. Outside [maxDistance], 0.
  double calculateReverbMix(Vec3 listenerPosition) {
    final dist = (transform.position - listenerPosition).length;
    if (dist <= minDistance) return wet;
    if (dist >= maxDistance) return 0.0;
    final t = 1.0 - ((dist - minDistance) / (maxDistance - minDistance));
    return wet * t.clamp(0.0, 1.0);
  }

  /// Processes an audio buffer with the zone's reverberator.
  void processBuffer(List<double> buffer) {
    reverb.processBuffer(buffer);
  }
}

/// Dynamic biquad lowpass filter for underwater muffling, door occlusion, or wall isolation (E36).
class AudioLowPassFilterComponent extends Component {
  final dsp.BiquadFilter filter;

  AudioLowPassFilterComponent({
    double cutoffFrequency = 1000.0,
    double q = 0.70710678,
  }) : filter = dsp.BiquadFilter.lowpass(
          cutoffFrequency: cutoffFrequency,
          q: q,
        );

  double get cutoffFrequency => filter.cutoffFrequency;
  set cutoffFrequency(double val) => filter.cutoffFrequency = val;

  double get q => filter.q;
  set q(double val) => filter.q = val;

  double process(double sample) => filter.process(sample);

  void processBuffer(List<double> buffer) => filter.processBuffer(buffer);
}

/// Extension on [AudioSource] adding 3D Spatial DSP calculations from `package:voxdsp` (E36).
extension SpatialAudioDspExt on AudioSource {
  /// Evaluates advanced 3D spatial audio parameters using `package:voxdsp`.
  dsp.SpatialAudioResult calculateSpatialDsp({
    AudioListener? listener,
    dsp.DistanceModel distanceModel = dsp.DistanceModel.inverse,
    Vec3 sourceVelocity = Vec3.zero,
    Vec3 listenerVelocity = Vec3.zero,
    double dopplerIntensity = 1.0,
  }) {
    final activeListener = listener ?? (isAttached && scene.isLoaded ? AudioListener.of(scene) : null);
    final listenerPos = activeListener?.transform.position ?? Vec3.zero;
    final listenerForward = activeListener?.transform.forward ?? kForward;
    final listenerRight = activeListener?.transform.right ?? kRight;

    return dsp.SpatialAudio3D.calculate(
      sourcePosition: _toDspVec3(transform.position),
      listenerPosition: _toDspVec3(listenerPos),
      listenerForward: _toDspVec3(listenerForward),
      listenerRight: _toDspVec3(listenerRight),
      sourceVelocity: _toDspVec3(sourceVelocity),
      listenerVelocity: _toDspVec3(listenerVelocity),
      distanceModel: distanceModel,
      minDistance: minDistance,
      maxDistance: maxDistance,
      dopplerIntensity: dopplerIntensity,
    );
  }
}
