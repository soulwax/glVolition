/// Spatial 3D audio, procedural synth, DSP filters, acoustics, adaptive music & rhythm.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('E10 — Spatial 3D AudioListener, AudioMixer & AudioSource', () {
    test(
      'AudioListener, AudioMixer, and spatial AudioSource attenuate volume and pan',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        engine.scene.createGameObject(
          'Listener',
          position: Vec3.zero,
          components: [AudioListener(volume: 1.0)],
        );
        final src = AudioSource(
          clip: host.audio.clip('beacon.wav'),
          volume: 1.0,
          bus: 'sfx',
          spatialBlend: 1.0,
          minDistance: 2.0,
          maxDistance: 12.0,
          loop: true,
          playOnAwake: true,
        );
        final beacon = engine.scene.createGameObject(
          'Beacon',
          position: const Vec3(
            7.0,
            0,
            0,
          ), // halfway between min=2 and max=12 -> t=0.5 -> atten=0.25, right=+1
          components: [src],
        );

        engine.step(1 / 60);
        final eval = src.evaluateSpatial();
        expect(eval.volume, closeTo(0.25, 1e-4));
        expect(eval.pan, closeTo(1.0, 1e-4));

        // Mute the 'sfx' bus on Scene.audioMixer
        engine.scene.audioMixer.bus('sfx').muted = true;
        expect(src.evaluateSpatial().volume, 0.0);

        // Unmute and move within minDistance on the left (-X)
        engine.scene.audioMixer.bus('sfx').muted = false;
        beacon.transform.position = const Vec3(-1.0, 0, 0);
        final nearEval = src.evaluateSpatial();
        expect(nearEval.volume, closeTo(1.0, 1e-4));
        expect(nearEval.pan, closeTo(-1.0, 1e-4));
      },
    );
  });

  group('E18 — Spatial Audio One-Shots', () {
    test(
      'AudioSource.playClipAtPoint and Scene.playClipAt spawn spatial one-shot GameObject that auto-destroys',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final clip = host.audio.clip('explosion.wav');

        final initialObjects = engine.scene.rootGameObjects.length;
        final go = engine.scene.playClipAt(
          clip,
          const Vec3(10, 0, 0),
          spatialBlend: 1.0,
          minDistance: 2.0,
          maxDistance: 30.0,
          duration: 0.1,
        );

        expect(go, isNotNull);
        expect(engine.scene.rootGameObjects.length, initialObjects + 1);
        final src = go!.getComponent<AudioSource>();
        expect(src, isNotNull);
        expect(src!.spatialBlend, closeTo(1.0, 1e-6));
        expect(src.minDistance, closeTo(2.0, 1e-6));
        expect(src.maxDistance, closeTo(30.0, 1e-6));

        // Advance time beyond duration (0.1s)
        engine.step(0.06);
        engine.step(0.06);
        // Deferred destruction flushes at end of frame
        expect(go.isDestroyed, isTrue);
      },
    );
  });

  group('E25 — AudioSource Fades & CrossFades', () {
    test(
      'AudioSource fadeVolumeTo and crossFadeTo ramp volume and switch clips smoothly',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final clipA = host.audio.clip('music_a.ogg');
        final clipB = host.audio.clip('music_b.ogg');

        final src = AudioSource(clip: clipA, volume: 1.0);
        engine.scene.createGameObject('MusicPlayer', components: [src]);
        src.play();

        var fadeFinished = false;
        src.fadeVolumeTo(
          0.2,
          duration: 0.2,
          onComplete: () => fadeFinished = true,
        );
        expect(src.isFading, isTrue);

        // Step 2 frames of 0.05s = 0.1s: half-way through fade
        engine.step(0.05);
        engine.step(0.05);
        expect(src.volume, closeTo(0.6, 1e-4));
        expect(fadeFinished, isFalse);

        // Step 2 more frames of 0.05s = 0.2s: finished
        engine.step(0.05);
        engine.step(0.05);
        expect(src.volume, closeTo(0.2, 1e-4));
        expect(fadeFinished, isTrue);
        expect(src.isFading, isFalse);

        // Cross fade from clipA to clipB over 0.2s
        var crossFinished = false;
        src.crossFadeTo(
          clipB,
          duration: 0.2,
          targetVolume: 0.8,
          onComplete: () => crossFinished = true,
        );
        expect(src.isFading, isTrue);

        // Step 2 frames of 0.05s = 0.1s: midpoint reached -> clip swapped to clipB
        engine.step(0.05);
        engine.step(0.05);
        expect(src.clip, clipB);

        // Step 2 more frames = 0.2s: cross-fade finishes at target volume 0.8
        engine.step(0.05);
        engine.step(0.05);
        expect(src.volume, closeTo(0.8, 1e-4));
        expect(crossFinished, isTrue);
        expect(src.isFading, isFalse);
      },
    );
  });

  group('E28 — Procedural Audio Synth (voxsynth)', () {
    test(
      'AudioSource.playSynth and Scene.playSynthAt spawn procedural sound one-shots',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final go = engine.scene.createGameObject('Player');
        final src = go.addComponent(AudioSource());

        // Play procedural laser synth via AudioSource
        final laser = voxsynth.laser();
        src.playSynth(laser);

        // Play spatial procedural explosion synth via Scene
        final explosion = voxsynth.explosion();
        final oneShotGo = engine.scene.playSynthAt(
          explosion,
          const Vec3(10, 0, 5),
        );

        expect(oneShotGo, isNotNull);
        expect(oneShotGo!.name, contains('SpatialAudioOneShot_procedural://'));
        expect(oneShotGo.transform.position.x, closeTo(10.0, 1e-4));

        final oneShotSrc = oneShotGo.getComponent<AudioSource>();
        expect(oneShotSrc, isNotNull);
        expect(oneShotSrc!.clip, isA<ProceduralAudioClip>());
        expect(
          (oneShotSrc.clip as ProceduralAudioClip).wavBytes.length,
          greaterThan(44),
        );
      },
    );
  });

  group('E36 — AudioLowPassFilter, AudioReverbZone & Spatial DSP', () {
    test('E36: AudioLowPassFilterComponent processes audio buffer', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final audioGo = engine.scene.createGameObject('AudioEmitter');
      final lpf = audioGo.addComponent(
        AudioLowPassFilterComponent(cutoffFrequency: 400.0),
      );

      final buffer = List<double>.generate(
        100,
        (i) => i.isEven ? 1.0 : -1.0,
      ); // High frequency alternations
      lpf.processBuffer(buffer);

      // Filtered high-frequency buffer should have significantly attenuated amplitude
      expect(buffer.last.abs(), lessThan(0.5));
    });

    test('E36: AudioReverbZone calculates proximity wet mix', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final zoneGo = engine.scene.createGameObject(
        'CaveReverb',
        position: const Vec3(0.0, 0.0, 0.0),
      );
      final zone = zoneGo.addComponent(
        AudioReverbZone(minDistance: 5.0, maxDistance: 15.0, wet: 0.8),
      );

      // Close to center -> 100% wet (0.8)
      expect(
        zone.calculateReverbMix(const Vec3(2.0, 0.0, 0.0)),
        closeTo(0.8, 1e-4),
      );

      // Midpoint between min and max (dist = 10.0) -> 50% of wet (0.4)
      expect(
        zone.calculateReverbMix(const Vec3(10.0, 0.0, 0.0)),
        closeTo(0.4, 0.05),
      );

      // Far outside zone -> 0.0
      expect(zone.calculateReverbMix(const Vec3(20.0, 0.0, 0.0)), equals(0.0));
    });

    test(
      'E36: AudioSource.calculateSpatialDsp evaluates 3D pan and doppler pitch',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final listenerGo = engine.scene.createGameObject(
          'Listener',
          position: const Vec3(0.0, 0.0, 0.0),
        );
        final listener = listenerGo.addComponent(AudioListener());

        final sourceGo = engine.scene.createGameObject(
          'Siren',
          position: const Vec3(10.0, 0.0, 0.0),
        );
        final source = sourceGo.addComponent(
          AudioSource(minDistance: 1.0, maxDistance: 50.0),
        );

        engine.step(0.05);

        final res = source.calculateSpatialDsp(
          listener: listener,
          sourceVelocity: const Vec3(
            -20.0,
            0.0,
            0.0,
          ), // Moving towards listener
        );

        // Stereo pan right
        expect(res.pan, closeTo(1.0, 1e-4));
        expect(res.rightGain, greaterThan(res.leftGain));

        // Doppler pitch shift > 1.0
        expect(res.dopplerFactor, greaterThan(1.02));
      },
    );
  });

  group('E70 — Room Acoustics, Eyring RT60 & Portal Diffraction (voxreverb)', () {
    test(
      'AcousticRoomComponent & AcousticPortalComponent drive AudioReverbZone, LPF & AcousticsInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final listenerGo = scene.createGameObject(
          'PlayerListener',
          position: const Vec3(-4.0, 1.5, 0.0),
          components: [AudioListener()],
        );

        final cavernZone = AudioReverbZone();
        final cavernGo = scene.createGameObject(
          'StoneCavern',
          position: const Vec3(-5.0, 2.5, 0.0),
        );
        cavernGo.addComponent(cavernZone);
        final cavernRoom = cavernGo.addComponent(
          AcousticRoomComponent(
            roomId: 'cavern',
            size: const Vec3(10.0, 6.0, 10.0),
            materialPreset: AcousticMaterialPreset.stoneCavern,
            autoSyncReverbZone: true,
          ),
        );

        final boothGo = scene.createGameObject(
          'VoiceBooth',
          position: const Vec3(5.0, 2.5, 0.0),
        );
        final boothRoom = boothGo.addComponent(
          AcousticRoomComponent(
            roomId: 'booth',
            size: const Vec3(10.0, 6.0, 10.0),
            materialPreset: AcousticMaterialPreset.acousticFoam,
          ),
        );

        final lpf = AudioLowPassFilterComponent();
        final doorGo = scene.createGameObject(
          'OakPortal',
          position: const Vec3(0.0, 1.5, 3.0),
        );
        doorGo.addComponent(lpf);
        final doorPortal = doorGo.addComponent(
          AcousticPortalComponent(
            portalId: 'oak_door',
            roomAId: 'cavern',
            roomBId: 'booth',
            openFactor: 1.0,
          ),
        );

        engine.step(0.05);
        expect(cavernRoom.eyringRt60, greaterThan(boothRoom.eyringRt60 * 3.0));
        expect(cavernZone.roomSize, greaterThan(0.5));

        final openRes = boothRoom.solveToListener(
          emitterPosition: const Vec3(6.0, 1.5, -2.0),
          listenerPosition: listenerGo.transform.position,
        );
        expect(openRes.traversedPortalIds, ['oak_door']);
        expect(openRes.diffractionGain, greaterThan(0.5));
        expect(openRes.lowPassCutoffHz, greaterThan(15000.0));

        // Click 'Toggle Door' (x=174, y=156) & 'Solve Path' (x=74, y=156) & 'Cycle Mat' (x=271, y=156)
        final ui = VoxUiContext();
        final uiState = AcousticsInspectorUiState();
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: 174.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        AcousticsInspectorUI.render(
          ui,
          boothRoom,
          portal: doorPortal,
          emitterPosition: const Vec3(6.0, 1.5, -2.0),
          listenerPosition: listenerGo.transform.position,
          state: uiState,
        );
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 174.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        AcousticsInspectorUI.render(
          ui,
          boothRoom,
          portal: doorPortal,
          emitterPosition: const Vec3(6.0, 1.5, -2.0),
          listenerPosition: listenerGo.transform.position,
          state: uiState,
        );
        ui.endFrame();
        expect(doorPortal.openFactor, closeTo(0.0, 1e-6));
        expect(lpf.cutoffFrequency, lessThan(800.0));

        ui.beginFrame(
          VoxInput(
            mouseX: 74.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        AcousticsInspectorUI.render(
          ui,
          boothRoom,
          portal: doorPortal,
          emitterPosition: const Vec3(6.0, 1.5, -2.0),
          listenerPosition: listenerGo.transform.position,
          state: uiState,
        );
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 74.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        AcousticsInspectorUI.render(
          ui,
          boothRoom,
          portal: doorPortal,
          emitterPosition: const Vec3(6.0, 1.5, -2.0),
          listenerPosition: listenerGo.transform.position,
          state: uiState,
        );
        ui.endFrame();
        expect(boothRoom.lastSolvedPath!.diffractionGain, lessThan(0.15));

        ui.beginFrame(
          VoxInput(
            mouseX: 271.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        AcousticsInspectorUI.render(
          ui,
          cavernRoom,
          portal: doorPortal,
          state: uiState,
        );
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 271.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        AcousticsInspectorUI.render(
          ui,
          cavernRoom,
          portal: doorPortal,
          state: uiState,
        );
        ui.endFrame();

        expect(cavernRoom.materialPreset, AcousticMaterialPreset.woodPanel);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('AcousticRoomComponent'), isNotNull);
        expect(reg.specByName('AcousticPortalComponent'), isNotNull);
        expect(reg.specFor(cavernRoom)!.toJson(cavernRoom)['roomId'], 'cavern');
        expect(
          reg.specFor(doorPortal)!.toJson(doorPortal)['portalId'],
          'oak_door',
        );
      },
    );
  });

  group('E71 — Adaptive Music Stems & Beat-Quantized Transitions (voxscore)', () {
    test(
      'AdaptiveMusicComponent drives bound stem AudioSources, triggers stingers & renders MusicScoreInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final padClip = ProceduralAudioClip.fromSynth(
          SynthSound.laser(),
          name: 'pad',
        );
        final drumClip = ProceduralAudioClip.fromSynth(
          SynthSound.explosion(),
          name: 'drums',
        );
        final stingerClip = ProceduralAudioClip.fromSynth(
          SynthSound.powerup(),
          name: 'sting',
        );

        final padSrc = scene
            .createGameObject('StemPad')
            .addComponent(AudioSource(clip: padClip, loop: true, bus: 'music'));
        final drumSrc = scene
            .createGameObject('StemDrums')
            .addComponent(
              AudioSource(clip: drumClip, loop: true, bus: 'music'),
            );

        final music =
            scene
                .createGameObject('MusicDirector')
                .addComponent(
                  AdaptiveMusicComponent(
                    initialIntensity: 0.2,
                    targetIntensity: 0.2,
                    intensitySmoothingPerSecond: 10.0,
                  ),
                )
              ..registerSection(
                MusicSectionDef(
                  id: 'calm',
                  name: 'Explore',
                  bpm: 120.0,
                  stems: [
                    MusicStemLayer(
                      id: 'pad',
                      minIntensity: 0.0,
                      fadeInSeconds: 0.1,
                    ),
                    MusicStemLayer(
                      id: 'drums',
                      minIntensity: 0.45,
                      fadeInSeconds: 0.1,
                      fadeOutSeconds: 0.1,
                    ),
                  ],
                ),
              )
              ..registerSection(
                MusicSectionDef(
                  id: 'battle',
                  name: 'Combat',
                  bpm: 140.0,
                  stems: [
                    MusicStemLayer(
                      id: 'drums',
                      minIntensity: 0.0,
                      fadeInSeconds: 0.1,
                    ),
                  ],
                ),
              )
              ..registerStinger(
                const MusicStingerCue(
                  id: 'alert_fanfare',
                  quantization: MusicQuantization.nextBeat,
                  durationSeconds: 0.8,
                  duckAmount: 0.5,
                ),
                clip: stingerClip,
              )
              ..bindStemSource('pad', padSrc)
              ..bindStemSource('drums', drumSrc);

        expect(music.startSection('calm'), isTrue);
        for (var i = 0; i < 6; i++) {
          engine.step(0.05);
        }
        expect(padSrc.volume, closeTo(1.0, 0.05));
        expect(padSrc.isPlaying, isTrue);
        expect(drumSrc.volume, closeTo(0.0, 1e-6));

        // Click 'Int +0.3' (x=71), 'Stinger' (x=159), and 'Next Sec' (x=247) at y=156 in MusicScoreInspectorUI
        final ui = VoxUiContext();
        final uiState = MusicScoreInspectorUiState();
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: 71.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        MusicScoreInspectorUI.render(ui, music, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 71.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        MusicScoreInspectorUI.render(ui, music, state: uiState);
        ui.endFrame();
        expect(music.targetIntensity, closeTo(0.5, 1e-6));

        ui.beginFrame(
          VoxInput(
            mouseX: 159.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        MusicScoreInspectorUI.render(ui, music, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 159.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        MusicScoreInspectorUI.render(ui, music, state: uiState);
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: 247.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        MusicScoreInspectorUI.render(ui, music, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 247.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        MusicScoreInspectorUI.render(ui, music, state: uiState);
        ui.endFrame();
        expect(music.pendingSectionId, 'battle');

        // Advance past beat (stinger fires & drums swell) then past bar 1 (section switches to 'battle' @ 140 BPM)
        for (var i = 0; i < 6; i++) {
          engine.step(0.05); // t = 0.60s (> beat 1 at 0.50s)
        }
        expect(music.lastSnapshot!.musicDuckMultiplier, lessThan(0.75));
        expect(drumSrc.volume, greaterThan(0.2));

        for (var i = 0; i < 32; i++) {
          engine.step(0.05); // crosses bar 1 at 2.00s
        }
        expect(music.activeSectionId, 'battle');
        expect(music.conductor.clock.bpm, 140.0);

        ui.beginFrame(VoxInput());
        MusicScoreInspectorUI.render(ui, music, state: uiState);
        final drawList = ui.endFrame();
        expect(
          drawList.commands.any((c) => c.text == 'Combat (140 BPM)'),
          isTrue,
        );

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('AdaptiveMusicComponent'), isNotNull);
        final json = reg.specFor(music)!.toJson(music);
        expect(json['targetIntensity'], closeTo(0.5, 1e-6));
      },
    );
  });

  group(
    'E76 — Beat-Synced Rhythm Sequencing, Note Charts & DSP Calibration (voxrhythm)',
    () {
      test(
        'RhythmSequencerComponent & RhythmJudgeUI handle lookahead, hit grading, DSP calibration & serialization',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          var crossedBeats = 0;

          final chart = RhythmChart(
            title: 'Pulse Trial',
            laneCount: 4,
            notes: const [
              RhythmNote(id: 'n1', lane: 0, beat: 1.0),
              RhythmNote(id: 'n2', lane: 1, beat: 2.0),
              RhythmNote(id: 'n3', lane: 2, beat: 3.0, durationBeats: 1.0),
            ],
          );

          final go = engine.scene.createGameObject('RhythmRig');
          final seq = go.addComponent(
            RhythmSequencerComponent(
              bpm: 120.0,
              lookaheadSeconds: 1.5,
              paused: true,
              chart: chart,
            ),
          );
          seq.onBeatCrossed = (_, __) => crossedBeats++;

          // At 0.0s, 1.5s lookahead shows notes up to beat 3.0 (1.5s)
          final initialVisible = seq.queryActiveNotes();
          expect(initialVisible.map((n) => n.note.id).toList(), [
            'n1',
            'n2',
            'n3',
          ]);

          // Step to 0.510s (+10ms past beat 1.0 @ 0.500s -> marvelous hit, records +10ms delta)
          seq.stepSequencer(0.510);
          expect(crossedBeats, greaterThanOrEqualTo(1));
          final j1 = seq.submitLaneInput(0);
          expect(j1, isNotNull);
          expect(j1!.grade, HitGrade.marvelous);
          expect(seq.combo, 1);
          expect(seq.score, greaterThan(0));

          // Step to 1.012s (+12ms past beat 2.0 @ 1.000s -> marvelous hit, records +12ms delta)
          seq.stepSequencer(0.502);
          final j2 = seq.submitLaneInput(1);
          expect(j2, isNotNull);
          expect(j2!.grade, HitGrade.marvelous);
          expect(seq.combo, 2);

          // UI interaction: click Ofs +5ms (x=226, y=159) then Calibrate (x=309, y=159)
          final ui = VoxUiContext();
          final uiState = RhythmJudgeUiState();
          ui.beginFrame(
            VoxInput(
              mouseX: 226.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          RhythmJudgeUI.render(ui, seq, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 226.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          RhythmJudgeUI.render(ui, seq, state: uiState);
          ui.endFrame();
          expect(seq.audioOffsetSeconds, closeTo(0.005, 1e-6));

          ui.beginFrame(
            VoxInput(
              mouseX: 309.0,
              mouseY: 159.0,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
          );
          RhythmJudgeUI.render(ui, seq, state: uiState);
          ui.endFrame();
          ui.beginFrame(
            VoxInput(
              mouseX: 309.0,
              mouseY: 159.0,
              isMouseDown: false,
              wasMouseReleased: true,
            ),
          );
          RhythmJudgeUI.render(ui, seq, state: uiState);
          final dl = ui.endFrame();
          expect(seq.audioOffsetSeconds, greaterThan(0.010));
          expect(dl.commands.any((c) => c.text == 'Rhythm Sequencer'), isTrue);

          // Verify ComponentRegistry registration & round-trip
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('RhythmSequencerComponent'), isNotNull);
          final json = reg.specFor(seq)!.toJson(seq);
          expect(json['bpm'], closeTo(120.0, 1e-6));
          expect(json['paused'], isTrue);
        },
      );
    },
  );
}
