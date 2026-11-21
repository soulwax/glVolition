/// S6-F: Audio, Input, Net & Infrastructure Family Studio Integration
/// (12 packages): `voxdsp`, `voxreverb`, `voxsynth`, `voxrhythm`, `voxpad`,
/// `voxnet`, `voxrollback`, `voxecs`, `voxui`, `voxlog`, `voxpack`, `voxalloc`.
library;

import '../../../engine.dart';
import '../../commands/menu_registry.dart';

/// Audio mixer bus descriptor for the Studio Audio Mixer window (`[S6-F]`).
final class AudioMixerBusState {
  final String name;
  double volume;
  bool muted;
  bool solo;
  double peakDb;

  AudioMixerBusState({
    required this.name,
    this.volume = 1.0,
    this.muted = false,
    this.solo = false,
    this.peakDb = -60.0,
  });
}

/// Studio Audio Mixer window model (buses, snapshots, mute/solo, `[S6-F]`).
final class AudioMixerWindowModel {
  final List<AudioMixerBusState> buses;
  String activeSnapshot;

  AudioMixerWindowModel({
    List<AudioMixerBusState>? buses,
    this.activeSnapshot = 'Default',
  }) : buses =
           buses ??
           [
             AudioMixerBusState(name: 'Master'),
             AudioMixerBusState(name: 'SFX'),
             AudioMixerBusState(name: 'Music'),
             AudioMixerBusState(name: 'Voice'),
           ];

  AudioMixerBusState? busByName(String name) {
    for (final b in buses) {
      if (b.name == name) return b;
    }
    return null;
  }

  /// Effective linear gain for [busName], respecting mute/solo & Master gain.
  double effectiveGain(String busName) {
    final bus = busByName(busName);
    if (bus == null || bus.muted) return 0.0;
    final anySolo = buses.any((b) => b.solo && b.name != 'Master');
    if (anySolo && !bus.solo && bus.name != 'Master') return 0.0;
    final master = busByName('Master');
    if (bus.name != 'Master' && master != null) {
      if (master.muted) return 0.0;
      return (bus.volume * master.volume).clamp(0.0, 2.0);
    }
    return bus.volume.clamp(0.0, 2.0);
  }
}

/// Network "Play with N clients" launcher configuration (`[S6-F]`).
final class MultiplayerLaunchConfig {
  final int clientCount;
  final bool startHeadlessServer;
  final int serverPort;

  const MultiplayerLaunchConfig({
    this.clientCount = 2,
    this.startHeadlessServer = true,
    this.serverPort = 7777,
  });
}

abstract final class InfraFamilyModule {
  static const List<String> packages = [
    'voxdsp',
    'voxreverb',
    'voxsynth',
    'voxrhythm',
    'voxpad',
    'voxnet',
    'voxrollback',
    'voxecs',
    'voxui',
    'voxlog',
    'voxpack',
    'voxalloc',
  ];

  static const List<String> createMenus = [
    'GameObject/Create/Audio & Net/Audio Source',
    'GameObject/Create/Audio & Net/Network Identity',
  ];

  static void registerMenus(StudioMenuRegistry menus, Scene Function() scene) {
    menus.register(
      StudioMenuItem(
        id: 'create.infra.audio_source',
        menuPath: 'GameObject/Create/Audio & Net/Audio Source',
        action: () =>
            scene().createGameObject('Audio Source')
              ..addComponent(AudioSource()),
      ),
    );
    menus.register(
      StudioMenuItem(
        id: 'create.infra.net_identity',
        menuPath: 'GameObject/Create/Audio & Net/Network Identity',
        action: () =>
            scene().createGameObject('Network Entity')
              ..addComponent(NetworkIdentity(netId: 1)),
      ),
    );
  }

  static Scene buildSampleScene() {
    final scene = Scene('InfraSample');
    scene.createGameObject('AmbientAudio').addComponent(AudioSource());
    scene.createGameObject('NetPlayer').addComponent(NetworkIdentity(netId: 1));
    return scene;
  }
}
