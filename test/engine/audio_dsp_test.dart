/// Integration tests for Spatial AudioListener pose sync, AudioSource DSP
/// graph parameters (pan, biquad LPF cutoff/Q, reverb send) on HeadlessHost
/// and NativeEngineHost + NativeAudioDevice + SoftwareCaptureAudioSink.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

double _channelRms(
  Float32List interleaved,
  int channelIndex, {
  int startFrame = 0,
}) {
  final totalFrames = interleaved.length ~/ 2;
  if (startFrame >= totalFrames) return 0.0;
  var sumSq = 0.0;
  var count = 0;
  for (var f = startFrame; f < totalFrames; f++) {
    final s = interleaved[f * 2 + channelIndex];
    sumSq += s * s;
    count++;
  }
  return count == 0 ? 0.0 : math.sqrt(sumSq / count);
}

void main() {
  group('AudioSource DSP & AudioListener pose integration on HeadlessHost', () {
    test(
      'AudioListener propagates pose on enable, move, rotate, and Camera fallback',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final listenerObj = engine.scene.createGameObject(
          'Listener',
          position: const Vec3(3.0, 2.0, -5.0),
          rotation: lookRotation(kRight),
          components: [AudioListener()],
        );
        expect(host.audio.listenerPosition.x, closeTo(3.0, 1e-5));
        expect(host.audio.listenerPosition.y, closeTo(2.0, 1e-5));
        expect(host.audio.listenerPosition.z, closeTo(-5.0, 1e-5));
        expect(
          host.audio.listenerForward.x,
          closeTo(listenerObj.transform.forward.x, 1e-5),
        );
        expect(
          host.audio.listenerForward.z,
          closeTo(listenerObj.transform.forward.z, 1e-5),
        );

        final src = AudioSource(
          clip: host.audio.clip('ping.wav'),
          spatialBlend: 1.0,
          loop: true,
        );
        engine.scene.createGameObject(
          'Emitter',
          position: const Vec3(10.0, 2.0, -5.0),
          components: [src],
        );
        src.play();

        listenerObj.transform.position = const Vec3(-4.0, 1.0, 8.0);
        engine.step(1 / 60);
        expect(host.audio.listenerPosition.x, closeTo(-4.0, 1e-5));
        expect(host.audio.listenerPosition.y, closeTo(1.0, 1e-5));
        expect(host.audio.listenerPosition.z, closeTo(8.0, 1e-5));

        final camObj = engine.scene.createGameObject(
          'MainCamera',
          position: const Vec3(0.0, 6.0, 12.0),
          components: [Camera()],
        );
        listenerObj.setActive(false);
        engine.step(1 / 60);
        expect(
          host.audio.listenerPosition.x,
          closeTo(camObj.transform.position.x, 1e-5),
        );
        expect(
          host.audio.listenerPosition.y,
          closeTo(camObj.transform.position.y, 1e-5),
        );
        expect(
          host.audio.listenerPosition.z,
          closeTo(camObj.transform.position.z, 1e-5),
        );
      },
    );

    test(
      'AudioSource pushes spatial volume, setPan, AudioLowPassFilterComponent, and AudioReverbZone',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final listenerObj = engine.scene.createGameObject(
          'Listener',
          position: Vec3.zero,
          components: [AudioListener()],
        );

        final zoneA = AudioReverbZone(
          minDistance: 2.0,
          maxDistance: 10.0,
          wet: 0.8,
        );
        engine.scene.createGameObject(
          'CaveZone',
          position: Vec3.zero,
          components: [zoneA],
        );
        final zoneB = AudioReverbZone(
          minDistance: 1.0,
          maxDistance: 5.0,
          wet: 0.35,
        );
        engine.scene.createGameObject(
          'HallZone',
          position: const Vec3(20.0, 0.0, 0.0),
          components: [zoneB],
        );

        final srcFilter = AudioLowPassFilterComponent(
          cutoffFrequency: 950.0,
          q: 2.4,
        );
        final src = AudioSource(
          clip: host.audio.clip('beacon.wav'),
          spatialBlend: 1.0,
          minDistance: 2.0,
          maxDistance: 12.0,
          loop: true,
        );
        final emitter = engine.scene.createGameObject(
          'Emitter',
          position: const Vec3(7.0, 0.0, 0.0),
          components: [srcFilter, src],
        );

        src.play();
        expect(host.audio.channels, hasLength(1));
        final ch = host.audio.channels.single;
        expect(ch.lastVolume, closeTo(0.25, 1e-5));
        expect(ch.lastPan, closeTo(1.0, 1e-5));
        expect(ch.lastLowPassCutoffHz, closeTo(950.0, 1e-5));
        expect(ch.lastLowPassResonance, closeTo(2.4, 1e-5));
        expect(ch.lastReverbSend, closeTo(0.8, 1e-5));

        // Moving source to hard left within minDistance restores unity volume and flips pan.
        emitter.transform.position = const Vec3(-2.0, 0.0, 0.0);
        srcFilter.cutoffFrequency = 420.0;
        srcFilter.q = 3.5;
        engine.step(1 / 60);
        expect(ch.lastVolume, closeTo(1.0, 1e-5));
        expect(ch.lastPan, closeTo(-1.0, 1e-5));
        expect(ch.lastLowPassCutoffHz, closeTo(420.0, 1e-5));
        expect(ch.lastLowPassResonance, closeTo(3.5, 1e-5));

        // Active listener-side AudioLowPassFilterComponent applies the lower cutoff.
        final listenerFilter = listenerObj.addComponent(
          AudioLowPassFilterComponent(cutoffFrequency: 280.0, q: 1.2),
        );
        engine.step(1 / 60);
        expect(ch.lastLowPassCutoffHz, closeTo(280.0, 1e-5));
        expect(ch.lastLowPassResonance, closeTo(1.2, 1e-5));

        listenerFilter.destroy();
        engine.step(1 / 60);
        engine.step(1 / 60);
        expect(ch.lastLowPassCutoffHz, closeTo(420.0, 1e-5));

        // Occlusion scales cutoff down further and recovers when cleared.
        src.occlusion = 0.5;
        engine.step(1 / 60);
        expect(ch.lastLowPassCutoffHz, closeTo(420.0, 1e-5));
        srcFilter.destroy();
        engine.step(1 / 60);
        engine.step(1 / 60);
        expect(ch.lastLowPassCutoffHz, closeTo(2000.0, 1e-3));
        src.occlusion = 0.0;
        engine.step(1 / 60);
        expect(ch.lastLowPassCutoffHz, closeTo(20000.0, 1e-5));

        // ReverbZone proximity: midpoint of CaveZone (dist = 6 -> 0.5 * 0.8 = 0.4).
        listenerObj.transform.position = const Vec3(6.0, 0.0, 0.0);
        engine.step(1 / 60);
        expect(ch.lastReverbSend, closeTo(0.4, 1e-5));

        // Entering second zone selects HallZone (0.35), leaving all zones drops to 0.
        listenerObj.transform.position = const Vec3(20.0, 0.0, 0.0);
        engine.step(1 / 60);
        expect(ch.lastReverbSend, closeTo(0.35, 1e-5));

        listenerObj.transform.position = const Vec3(40.0, 0.0, 0.0);
        engine.step(1 / 60);
        expect(ch.lastReverbSend, closeTo(0.0, 1e-5));

        // Explicit source.reverbSend overrides zone proximity.
        src.reverbSend = 0.65;
        expect(ch.lastReverbSend, closeTo(0.65, 1e-5));
      },
    );
  });

  group(
    'AudioSource DSP & NativeAudioDevice live mixing via SoftwareCaptureAudioSink',
    () {
      test(
        'spatial pan, distance attenuation, and AudioListener pose drive live stereo PCM',
        () async {
          final sink = SoftwareCaptureAudioSink();
          final device = NativeAudioDevice(
            sink: sink,
            config: const NativeAudioConfig(
              sampleRate: 48000,
              framesPerBuffer: 128,
            ),
          );
          final runner = await NativeEngineHost.boot(audio: device);
          try {
            runner.scene.createGameObject(
              'Listener',
              position: Vec3.zero,
              components: [AudioListener()],
            );

            final constantTone = NativeAudioClip.fromSamples(
              path: 'dc_tone.wav',
              samples: Float32List.fromList(List<double>.filled(256, 0.35)),
              sampleRate: 48000,
            );
            final src = AudioSource(
              clip: constantTone,
              spatialBlend: 1.0,
              minDistance: 2.0,
              maxDistance: 12.0,
              loop: true,
            );
            final emitter = runner.scene.createGameObject(
              'RightEmitter',
              position: const Vec3(2.0, 0.0, 0.0),
              components: [src],
            );

            src.play();
            runner.renderFrame(1 / 60);
            expect(device.listenerPosition, Vec3.zero);

            expect(device.pumpAudio(frames: 128), 256);
            final rightPcm = sink.capturedSamples;
            expect(_channelRms(rightPcm, 0), closeTo(0.0, 1e-6));
            expect(_channelRms(rightPcm, 1), closeTo(0.35, 1e-3));

            // Move halfway toward maxDistance on the left: dist=7 -> atten=0.25, pan=-1.0.
            emitter.transform.position = const Vec3(-7.0, 0.0, 0.0);
            sink.clear();
            runner.renderFrame(1 / 60);
            expect(device.pumpAudio(frames: 128), 256);
            final leftPcm = sink.capturedSamples;
            expect(_channelRms(leftPcm, 0), closeTo(0.35 * 0.25, 1e-3));
            expect(_channelRms(leftPcm, 1), closeTo(0.0, 1e-6));
          } finally {
            runner.dispose();
          }
        },
      );

      test(
        'AudioLowPassFilterComponent cutoff & Q shape live NativeAudioDevice frequency response',
        () async {
          final sink = SoftwareCaptureAudioSink();
          final device = NativeAudioDevice(
            sink: sink,
            config: const NativeAudioConfig(
              sampleRate: 48000,
              framesPerBuffer: 128,
            ),
          );
          final runner = await NativeEngineHost.boot(audio: device);
          try {
            runner.scene.createGameObject(
              'Listener',
              position: Vec3.zero,
              components: [AudioListener()],
            );

            final nyquist = NativeAudioClip.fromSamples(
              path: 'nyquist.wav',
              samples: Float32List.fromList([
                for (var i = 0; i < 512; i++) i.isEven ? 0.5 : -0.5,
              ]),
              sampleRate: 48000,
            );
            final lpf = AudioLowPassFilterComponent(
              cutoffFrequency: 19500.0,
              q: 0.70710678,
            );
            final src = AudioSource(clip: nyquist, loop: true);
            runner.scene.createGameObject(
              'FilteredEmitter',
              position: Vec3.zero,
              components: [lpf, src],
            );

            src.play();
            runner.renderFrame(1 / 60);
            device.pumpAudio(frames: 256);
            final openRms = _channelRms(
              sink.capturedSamples,
              0,
              startFrame: 64,
            );
            expect(openRms, greaterThan(0.4));

            lpf.cutoffFrequency = 300.0;
            lpf.q = 1.2;
            sink.clear();
            runner.renderFrame(1 / 60);
            device.pumpAudio(frames: 256);
            final muffledRms = _channelRms(
              sink.capturedSamples,
              0,
              startFrame: 64,
            );
            expect(muffledRms, lessThan(0.02));
            expect(src.currentLowPassCutoffHz, closeTo(300.0, 1e-5));
            expect(src.currentLowPassResonance, closeTo(1.2, 1e-5));
          } finally {
            runner.dispose();
          }

          // Verify biquad Q resonance boost around cutoff frequency directly on NativeAudioDevice.
          final qSink = SoftwareCaptureAudioSink();
          final qDevice = NativeAudioDevice(
            sink: qSink,
            config: const NativeAudioConfig(
              sampleRate: 48000,
              framesPerBuffer: 256,
            ),
          );
          try {
            final sine1k = NativeAudioClip.fromSamples(
              path: 'sine_1k.wav',
              samples: Float32List.fromList([
                for (var i = 0; i < 4800; i++)
                  0.2 * math.sin(2.0 * math.pi * 1000.0 * i / 48000.0),
              ]),
              sampleRate: 48000,
            );
            final ch = qDevice.createChannel();
            ch.setLowPass(1000.0, resonance: 0.5);
            ch.play(sine1k, loop: true);
            final dampedPcm = qDevice.mixFrames(1024);
            final dampedRms = _channelRms(dampedPcm, 0, startFrame: 512);

            ch.setLowPass(1000.0, resonance: 4.0);
            ch.play(sine1k, loop: true);
            final resonantPcm = qDevice.mixFrames(1024);
            final resonantRms = _channelRms(resonantPcm, 0, startFrame: 512);

            expect(resonantRms, greaterThan(dampedRms * 2.0));
          } finally {
            qDevice.dispose();
          }
        },
      );

      test(
        'AudioReverbZone proximity drives delayed wet reverb tail in SoftwareCaptureAudioSink',
        () async {
          final sink = SoftwareCaptureAudioSink();
          final device = NativeAudioDevice(
            sink: sink,
            config: const NativeAudioConfig(
              sampleRate: 48000,
              framesPerBuffer: 2000,
            ),
          );
          final runner = await NativeEngineHost.boot(audio: device);
          try {
            final listener = runner.scene.createGameObject(
              'Listener',
              position: const Vec3(30.0, 0.0, 0.0),
              components: [AudioListener()],
            );
            runner.scene.createGameObject(
              'CathedralZone',
              position: Vec3.zero,
              components: [
                AudioReverbZone(minDistance: 2.0, maxDistance: 10.0, wet: 0.75),
              ],
            );

            final impulse = NativeAudioClip.fromSamples(
              path: 'impulse.wav',
              samples: Float32List.fromList([
                0.8,
                ...List<double>.filled(2400, 0.0),
              ]),
              sampleRate: 48000,
            );
            final src = AudioSource(
              clip: impulse,
              spatialBlend: 0.0,
              loop: false,
            );
            runner.scene.createGameObject('Clap', components: [src]);

            // Outside reverb zone -> delayed echo region is silent.
            src.play();
            runner.renderFrame(1 / 60);
            expect(src.currentReverbSend, closeTo(0.0, 1e-6));
            device.pumpAudio(frames: 2000);
            final dryPcm = sink.capturedSamples;
            var dryTailPeak = 0.0;
            for (var f = 1000; f < 2000; f++) {
              dryTailPeak = math.max(dryTailPeak, dryPcm[f * 2].abs());
              dryTailPeak = math.max(dryTailPeak, dryPcm[f * 2 + 1].abs());
            }
            expect(dryTailPeak, closeTo(0.0, 1e-6));

            // Move inside CathedralZone -> audible delayed reverb echo tail appears.
            listener.transform.position = Vec3.zero;
            sink.clear();
            src.play();
            runner.renderFrame(1 / 60);
            expect(src.currentReverbSend, closeTo(0.75, 1e-5));
            device.pumpAudio(frames: 2000);
            final wetPcm = sink.capturedSamples;
            var wetTailPeak = 0.0;
            for (var f = 1000; f < 2000; f++) {
              wetTailPeak = math.max(wetTailPeak, wetPcm[f * 2].abs());
              wetTailPeak = math.max(wetTailPeak, wetPcm[f * 2 + 1].abs());
            }
            expect(wetTailPeak, greaterThan(0.08));
          } finally {
            runner.dispose();
          }
        },
      );
    },
  );
}
