/// Native hardware PCM audio device, WAV decoder, and SDL3 sink tests (W9-C).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

Uint8List _buildManualPcm16Wav({
  required List<int> samples,
  required int sampleRate,
  required int channels,
  bool includeOddJunkChunk = false,
}) {
  final dataSize = samples.length * 2;
  final junkChunkBytes = includeOddJunkChunk
      ? 12
      : 0; // 8 hdr + 3 payload + 1 pad
  final totalSize = 12 + 24 + junkChunkBytes + 8 + dataSize;
  final bytes = Uint8List(totalSize);
  final bd = ByteData.sublistView(bytes);

  void writeTag(int offset, String tag) {
    for (var i = 0; i < 4; i++) {
      bytes[offset + i] = tag.codeUnitAt(i);
    }
  }

  writeTag(0, 'RIFF');
  bd.setUint32(4, totalSize - 8, Endian.little);
  writeTag(8, 'WAVE');

  var pos = 12;
  writeTag(pos, 'fmt ');
  bd.setUint32(pos + 4, 16, Endian.little);
  bd.setUint16(pos + 8, 1, Endian.little); // PCM
  bd.setUint16(pos + 10, channels, Endian.little);
  bd.setUint32(pos + 12, sampleRate, Endian.little);
  bd.setUint32(pos + 16, sampleRate * channels * 2, Endian.little);
  bd.setUint16(pos + 20, channels * 2, Endian.little);
  bd.setUint16(pos + 22, 16, Endian.little);
  pos += 24;

  if (includeOddJunkChunk) {
    writeTag(pos, 'JUNK');
    bd.setUint32(
      pos + 4,
      3,
      Endian.little,
    ); // Odd length -> requires 1 pad byte.
    bytes[pos + 8] = 0xAA;
    bytes[pos + 9] = 0xBB;
    bytes[pos + 10] = 0xCC;
    pos += 12;
  }

  writeTag(pos, 'data');
  bd.setUint32(pos + 4, dataSize, Endian.little);
  pos += 8;
  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(pos + i * 2, samples[i], Endian.little);
  }
  return bytes;
}

void main() {
  group('WavPcmDecoder & NativeAudioClip', () {
    test(
      'round-trips SynthSound procedural WAV bytes through WavPcmDecoder',
      () {
        final synth = SynthSound.laser(random: math.Random(42));
        final procedural = ProceduralAudioClip.fromSynth(
          synth,
          name: 'test_laser',
          sampleRate: 44100,
        );
        final expectedSamples = synth.generatePcm(sampleRate: 44100);

        expect(WavPcmDecoder.isWavHeader(procedural.wavBytes), isTrue);
        expect(WavPcmDecoder.isOggHeader(procedural.wavBytes), isFalse);

        final decoded = WavPcmDecoder.decode(procedural.wavBytes);
        expect(decoded.isFallback, isFalse);
        expect(decoded.format, AudioContainerFormat.wavPcm16);
        expect(decoded.sampleRate, 44100);
        expect(decoded.channels, 1);
        expect(decoded.frameCount, expectedSamples.length);
        for (var i = 0; i < expectedSamples.length; i++) {
          expect(decoded.samples[i], closeTo(expectedSamples[i], 1e-3));
        }

        final clip = NativeAudioClip.fromProcedural(procedural);
        expect(clip.isFallback, isFalse);
        expect(clip.sampleRate, 44100);
        expect(clip.channels, 1);
        expect(clip.frameCount, expectedSamples.length);
      },
    );

    test('decodes manual 16-bit PCM stereo WAV with odd-sized JUNK chunk', () {
      final wav = _buildManualPcm16Wav(
        samples: [16384, -16384, 32767, -32768],
        sampleRate: 48000,
        channels: 2,
        includeOddJunkChunk: true,
      );

      final decoded = WavPcmDecoder.tryDecodeWav(wav);
      expect(decoded, isNotNull);
      expect(decoded!.format, AudioContainerFormat.wavPcm16);
      expect(decoded.sampleRate, 48000);
      expect(decoded.channels, 2);
      expect(decoded.frameCount, 2);
      expect(decoded.samples[0], closeTo(0.5, 1e-4));
      expect(decoded.samples[1], closeTo(-0.5, 1e-4));
      expect(decoded.samples[2], closeTo(1.0, 1e-4));
      expect(decoded.samples[3], closeTo(-1.0, 1e-4));
    });

    test('round-trips 32-bit IEEE float mono and stereo WAV buffers', () {
      final input = Float32List.fromList([0.25, -0.75, 0.5, -0.125]);
      final wavBytes = WavPcmDecoder.encodeFloat32(
        input,
        sampleRate: 44100,
        channels: 2,
      );

      final decoded = WavPcmDecoder.decode(wavBytes);
      expect(decoded.isFallback, isFalse);
      expect(decoded.format, AudioContainerFormat.wavFloat32);
      expect(decoded.sampleRate, 44100);
      expect(decoded.channels, 2);
      expect(decoded.frameCount, 2);
      for (var i = 0; i < input.length; i++) {
        expect(decoded.samples[i], closeTo(input[i], 1e-6));
      }
    });

    test('detects OGG header and returns clean fallback PCM buffers', () {
      final oggStub = Uint8List.fromList([0x4F, 0x67, 0x67, 0x53, 0, 2, 0, 0]);
      expect(WavPcmDecoder.isWavHeader(oggStub), isFalse);
      expect(WavPcmDecoder.isOggHeader(oggStub), isTrue);

      final silentFallback = WavPcmDecoder.decode(oggStub);
      expect(silentFallback.isFallback, isTrue);
      expect(silentFallback.format, AudioContainerFormat.oggFallback);
      expect(silentFallback.samples.every((s) => s == 0.0), isTrue);

      final toneFallback = WavPcmDecoder.decode(
        oggStub,
        generateToneOnFallback: true,
        fallbackSampleRate: 48000,
        fallbackDurationSeconds: 0.05,
      );
      expect(toneFallback.isFallback, isTrue);
      expect(toneFallback.format, AudioContainerFormat.oggFallback);
      expect(toneFallback.samples.any((s) => s.abs() > 0.05), isTrue);
    });

    test('loads WAV file from disk and falls back cleanly when missing', () {
      final tempDir = Directory.systemTemp.createTempSync('glv_audio_test_');
      try {
        final wavFile = File('${tempDir.path}/beep.wav');
        final source = Float32List.fromList([0.0, 0.5, -0.5, 0.25]);
        wavFile.writeAsBytesSync(
          WavPcmDecoder.encodePcm16(source, sampleRate: 48000, channels: 1),
        );

        final loaded = NativeAudioClip.fromFile(
          'beep.wav',
          rootDirectory: tempDir,
        );
        expect(loaded.isFallback, isFalse);
        expect(loaded.sampleRate, 48000);
        expect(loaded.frameCount, 4);
        expect(loaded.samples[1], closeTo(0.5, 1e-3));

        final missing = NativeAudioClip.fromFile(
          'does_not_exist.wav',
          rootDirectory: tempDir,
        );
        expect(missing.isFallback, isTrue);
        expect(missing.diagnostic, contains('Missing audio file'));
        expect(missing.samples.every((s) => s == 0.0), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('NativeAudioDevice & SoftwareCaptureAudioSink', () {
    test(
      'pumps deterministic non-zero stereo PCM frames into capture sink',
      () {
        final sink = SoftwareCaptureAudioSink();
        const config = NativeAudioConfig(
          sampleRate: 48000,
          channels: 2,
          framesPerBuffer: 128,
        );
        final device = NativeAudioDevice(sink: sink, config: config);

        expect(sink.isOpen, isTrue);
        expect(sink.isHardwareBacked, isFalse);
        expect(sink.backendName, 'software-pcm');

        final synthClip = ProceduralAudioClip.fromSynth(
          SynthSound.laser(random: math.Random(7)),
          sampleRate: 48000,
        );
        device.playOneShot(synthClip, volume: 0.8);

        final written = device.pumpAudio();
        expect(written, 256); // 128 stereo frames * 2 channels
        expect(sink.writeCount, 1);
        expect(sink.capturedFrameCount, 128);
        expect(sink.capturedSampleCount, 256);
        expect(sink.peakAmplitude, greaterThan(0.01));
        expect(sink.rmsAmplitude, greaterThan(0.005));

        device.dispose();
        expect(sink.isOpen, isFalse);
      },
    );

    test('mixes multiple voices and soft-clamps peaks within [-1.0, 1.0]', () {
      final sink = SoftwareCaptureAudioSink();
      final device = NativeAudioDevice(
        sink: sink,
        config: const NativeAudioConfig(sampleRate: 48000, framesPerBuffer: 8),
      );

      final clipA = NativeAudioClip.fromSamples(
        path: 'a.wav',
        samples: Float32List.fromList(List<double>.filled(8, 0.3)),
        sampleRate: 48000,
      );
      final clipB = NativeAudioClip.fromSamples(
        path: 'b.wav',
        samples: Float32List.fromList(List<double>.filled(8, 0.2)),
        sampleRate: 48000,
      );

      final chA = device.createChannel()..play(clipA);
      final chB = device.createChannel()..play(clipB);

      final mixed = device.mixFrames(4);
      for (var i = 0; i < mixed.length; i++) {
        expect(mixed[i], closeTo(0.5, 1e-5));
      }

      // Now push total sum to +1.6 and verify smooth soft-clamping <= 1.0.
      chA.stop();
      chB.stop();
      final hotClip = NativeAudioClip.fromSamples(
        path: 'hot.wav',
        samples: Float32List.fromList(List<double>.filled(8, 0.8)),
        sampleRate: 48000,
      );
      chA.play(hotClip);
      chB.play(hotClip);

      final hotMixed = device.mixFrames(4);
      for (var i = 0; i < hotMixed.length; i++) {
        expect(hotMixed[i], greaterThan(0.9));
        expect(hotMixed[i], lessThanOrEqualTo(1.0));
      }

      device.dispose();
    });

    test('supports volume scaling and muted = true silence', () {
      final sink = SoftwareCaptureAudioSink();
      final device = NativeAudioDevice(
        sink: sink,
        config: const NativeAudioConfig(sampleRate: 48000, framesPerBuffer: 16),
      );

      final clip = NativeAudioClip.fromSamples(
        path: 'const.wav',
        samples: Float32List.fromList(List<double>.filled(32, 0.6)),
        sampleRate: 48000,
      );

      final ch = device.createChannel()..play(clip, volume: 1.0, loop: true);
      final full = device.mixFrames(4);
      expect(full[0], closeTo(0.6, 1e-5));

      ch.volume = 0.5;
      final half = device.mixFrames(4);
      expect(half[0], closeTo(0.3, 1e-5));

      device.muted = true;
      final silenced = device.mixFrames(4);
      expect(silenced.every((s) => s == 0.0), isTrue);
      expect(ch.isPlaying, isTrue);

      device.muted = false;
      final unmuted = device.mixFrames(4);
      expect(unmuted[0], closeTo(0.3, 1e-5));

      device.dispose();
    });

    test(
      'wraps looping clips and stops one-shot/non-looping channels at end',
      () {
        final sink = SoftwareCaptureAudioSink();
        final device = NativeAudioDevice(
          sink: sink,
          config: const NativeAudioConfig(
            sampleRate: 48000,
            framesPerBuffer: 16,
          ),
        );

        final pattern = NativeAudioClip.fromSamples(
          path: 'loop.wav',
          samples: Float32List.fromList([0.1, 0.2, 0.3, 0.4]),
          sampleRate: 48000,
        );

        final loopCh = device.createChannel()..play(pattern, loop: true);
        final outLoop = device.mixFrames(10);
        expect(loopCh.isPlaying, isTrue);

        const expected = [0.1, 0.2, 0.3, 0.4, 0.1, 0.2, 0.3, 0.4, 0.1, 0.2];
        for (var f = 0; f < 10; f++) {
          expect(outLoop[f * 2], closeTo(expected[f], 1e-5));
          expect(outLoop[f * 2 + 1], closeTo(expected[f], 1e-5));
        }

        loopCh.stop();
        expect(loopCh.isPlaying, isFalse);
        expect(loopCh.playheadFrame, 0.0);
        expect(device.mixFrames(4).every((s) => s == 0.0), isTrue);

        // Non-looping playback ends cleanly and emits zeros afterward.
        loopCh.play(pattern, loop: false);
        final outOnce = device.mixFrames(6);
        expect(loopCh.isPlaying, isFalse);
        expect(outOnce[0], closeTo(0.1, 1e-5));
        expect(outOnce[6], closeTo(0.4, 1e-5));
        expect(outOnce[8], closeTo(0.0, 1e-5));
        expect(outOnce[10], closeTo(0.0, 1e-5));

        device.dispose();
      },
    );

    test(
      'supports pitch linear-interpolated resampling, pan, LPF, pause/resume',
      () {
        final sink = SoftwareCaptureAudioSink();
        final device = NativeAudioDevice(
          sink: sink,
          config: const NativeAudioConfig(
            sampleRate: 48000,
            framesPerBuffer: 16,
          ),
        );

        // Half-speed pitch (0.5) should linearly interpolate between samples.
        final ramp = NativeAudioClip.fromSamples(
          path: 'ramp.wav',
          samples: Float32List.fromList([0.0, 0.4, 0.8, 0.8]),
          sampleRate: 48000,
        );
        final ch = device.createChannel()..play(ramp, pitch: 0.5);
        final halfSpeed = device.mixFrames(4);
        // Output cursors: 0.0, 0.5, 1.0, 1.5 -> [0.0, 0.2, 0.4, 0.6]
        expect(halfSpeed[0], closeTo(0.0, 1e-5));
        expect(halfSpeed[2], closeTo(0.2, 1e-5));
        expect(halfSpeed[4], closeTo(0.4, 1e-5));
        expect(halfSpeed[6], closeTo(0.6, 1e-5));

        // Pause freezes playhead and outputs silence; resume continues.
        final savedCursor = ch.playheadFrame;
        ch.pause();
        expect(ch.isPlaying, isFalse);
        expect(ch.isPaused, isTrue);
        expect(device.mixFrames(2).every((s) => s == 0.0), isTrue);
        expect(ch.playheadFrame, closeTo(savedCursor, 1e-6));

        ch.resume();
        expect(ch.isPlaying, isTrue);
        expect(ch.isPaused, isFalse);

        // Double-speed pitch (2.0) consumes clip in half as many output frames.
        final eightFrames = NativeAudioClip.fromSamples(
          path: 'eight.wav',
          samples: Float32List.fromList(List<double>.filled(8, 0.5)),
          sampleRate: 48000,
        );
        ch.play(eightFrames, pitch: 2.0);
        device.mixFrames(4); // 4 output frames * step 2.0 = 8 source frames.
        expect(ch.isPlaying, isFalse);

        // Stereo panning (-1.0 hard left, +1.0 hard right).
        ch.pan = -1.0;
        ch.play(eightFrames, loop: true);
        final leftOnly = device.mixFrames(2);
        expect(leftOnly[0], closeTo(0.5, 1e-5));
        expect(leftOnly[1], closeTo(0.0, 1e-5));

        ch.pan = 1.0;
        final rightOnly = device.mixFrames(2);
        expect(rightOnly[0], closeTo(0.0, 1e-5));
        expect(rightOnly[1], closeTo(0.5, 1e-5));

        // One-pole LPF (< 18000 Hz) attenuates Nyquist oscillation [0.8, -0.8...].
        final nyquist = NativeAudioClip.fromSamples(
          path: 'nyq.wav',
          samples: Float32List.fromList(
            List<double>.generate(64, (i) => i.isEven ? 0.8 : -0.8),
          ),
          sampleRate: 48000,
        );
        ch.pan = 0.0;
        ch.lowPassCutoffHz = 300.0;
        ch.play(nyquist);
        final filtered = device.mixFrames(32);
        expect(filtered.last.abs(), lessThan(0.2));

        device.dispose();
      },
    );

    test(
      'enforces bounded one-shot voice pool and clears state on dispose',
      () {
        final sink = SoftwareCaptureAudioSink();
        final device = NativeAudioDevice(
          sink: sink,
          config: const NativeAudioConfig(
            sampleRate: 48000,
            framesPerBuffer: 64,
          ),
          maxOneShotVoices: 4,
        );

        final clipA = NativeAudioClip.fromSamples(
          path: 'sfx_a.wav',
          samples: Float32List.fromList(List<double>.filled(200, 0.1)),
          sampleRate: 48000,
          maxVoices: 2,
        );
        final clipB = NativeAudioClip.fromSamples(
          path: 'sfx_b.wav',
          samples: Float32List.fromList(List<double>.filled(200, 0.1)),
          sampleRate: 48000,
          maxVoices: 3,
        );

        // Per-clip limit (2) caps clipA at 2 voices.
        device.playOneShot(clipA);
        device.playOneShot(clipA);
        device.playOneShot(clipA);
        expect(device.activeOneShotCount, 2);

        // Global maxOneShotVoices (4) caps combined voices at 4.
        device.playOneShot(clipB);
        device.playOneShot(clipB);
        device.playOneShot(clipB);
        expect(device.activeOneShotCount, 4);

        device.dispose();
        expect(device.isDisposed, isTrue);
        expect(device.activeChannelCount, 0);
        expect(device.activeOneShotCount, 0);
        expect(sink.isOpen, isFalse);
        expect(device.pumpAudio(), 0);
        expect(device.mixFrames(8), isEmpty);

        // Idempotent second dispose.
        device.dispose();
      },
    );

    test(
      'mixes stereo clips, resamples mismatched sample rates, and applies reverb tail',
      () {
        final tempDir = Directory.systemTemp.createTempSync('glv_audio_dev_');
        try {
          // Stereo 24kHz clip played on 48kHz device -> 0.5x step resampling.
          final stereoSamples = Float32List.fromList([0.8, -0.4, 0.2, 0.6]);
          File('${tempDir.path}/stereo24k.wav').writeAsBytesSync(
            WavPcmDecoder.encodeFloat32(
              stereoSamples,
              sampleRate: 24000,
              channels: 2,
            ),
          );

          final sink = SoftwareCaptureAudioSink();
          final device = NativeAudioDevice(
            sink: sink,
            config: const NativeAudioConfig(
              sampleRate: 48000,
              framesPerBuffer: 8,
            ),
            rootDirectory: tempDir,
          );

          final clip = device.clip('stereo24k.wav', volume: 0.5, voices: 2);
          expect(clip.channels, 2);
          expect(clip.sampleRate, 24000);
          expect(clip.isFallback, isFalse);

          final ch = device.createChannel()..play(clip);
          final out = device.mixFrames(4);
          // Frame 0 (cursor 0.0): L=0.8*0.5=0.4, R=-0.4*0.5=-0.2
          // Frame 1 (cursor 0.5): L=0.5*0.5=0.25, R=0.1*0.5=0.05
          expect(out[0], closeTo(0.4, 1e-5));
          expect(out[1], closeTo(-0.2, 1e-5));
          expect(out[2], closeTo(0.25, 1e-5));
          expect(out[3], closeTo(0.05, 1e-5));

          // Reverb wet > 0 emits a delayed echo tail after initial impulse.
          final impulse = NativeAudioClip.fromSamples(
            path: 'impulse.wav',
            samples: Float32List.fromList([
              1.0,
              ...List<double>.filled(2000, 0.0),
            ]),
            sampleRate: 48000,
          );
          ch
            ..reverbWet = 0.6
            ..play(impulse);
          final withTail = device.mixFrames(1900);
          var tailPeak = 0.0;
          for (var f = 1000; f < 1900; f++) {
            tailPeak = math.max(tailPeak, withTail[f * 2].abs());
            tailPeak = math.max(tailPeak, withTail[f * 2 + 1].abs());
          }
          expect(tailPeak, greaterThan(0.1));

          device.dispose();
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );
  });

  group('Sdl3AudioSink graceful fallback', () {
    test(
      'default Sdl3AudioSink probes safely without throwing uncaught errors',
      () {
        final sink = Sdl3AudioSink();
        final opened = sink.open(const NativeAudioConfig());
        if (opened) {
          expect(sink.isOpen, isTrue);
          expect(sink.isHardwareBacked, isTrue);
          expect(sink.lastError, isNull);
          sink.close();
        } else {
          expect(sink.isOpen, isFalse);
          expect(sink.isHardwareBacked, isFalse);
          expect(sink.lastError, isNotNull);
        }
      },
    );
    test(
      'missing SDL3 shared library fails cleanly without throwing FFI errors',
      () {
        final sink = Sdl3AudioSink(
          candidateLibraries: const <String>[
            'definitely_missing_sdl3_audio_lib_w9c.dll',
            'definitely_missing_libSDL3.so.0',
          ],
        );

        expect(sink.isOpen, isFalse);
        expect(sink.isHardwareBacked, isFalse);
        expect(sink.backendName, 'sdl3-audio');

        final opened = sink.open(const NativeAudioConfig());
        expect(opened, isFalse);
        expect(sink.isOpen, isFalse);
        expect(sink.isHardwareBacked, isFalse);
        expect(sink.lastError, isNotNull);
        expect(sink.lastError, isNotEmpty);

        expect(sink.writeInterleavedFloat32(Float32List(16)), 0);
        sink.close();
        expect(sink.isOpen, isFalse);
      },
    );

    test(
      'NativeAudioDevice with unavailable SDL3 sink boots inside NativeEngineHost cleanly',
      () async {
        final sdlSink = Sdl3AudioSink(
          candidateLibraries: const <String>['nonexistent_sdl3_w9c.dll'],
        );
        final audioDevice = NativeAudioDevice(sink: sdlSink);
        expect(sdlSink.isOpen, isFalse);
        expect(sdlSink.isHardwareBacked, isFalse);

        final runner = await NativeEngineHost.boot(audio: audioDevice);
        final go = runner.scene.createGameObject('Emitter');
        final src = go.addComponent(AudioSource());
        src.playSynth(SynthSound.coin(random: math.Random(1)));
        expect(audioDevice.activeOneShotCount, 1);

        // Mixing works even when OS sink is unavailable; pumpAudio returns 0.
        expect(audioDevice.pumpAudio(frames: 32), 0);
        runner.renderFrame(1 / 60);

        runner.dispose();
        expect(audioDevice.isDisposed, isTrue);
      },
    );
  });
}
