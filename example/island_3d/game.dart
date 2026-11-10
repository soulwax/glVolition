import 'dart:math' as math;

import 'package:gl_volition/gl_volition.dart';

/// Builds a 3D coastal island [Scene] combining procedural [TerrainComponent],
/// dynamic [WaterSurfaceComponent] waves, a [BuoyantBody] vessel, a
/// [SplinePath] + [SplineFollower] camera rail, a keyframe [Animator] beacon,
/// and a live [AtmosphereVolume] solar cycle (Phase E5 validation).
Scene buildIsland3DScene() {
  final scene = Scene('Island3D');

  // Sky + solar cycle + sun directional light
  scene.createGameObject(
    'Atmosphere',
    components: [
      Light.directional(intensity: 1.2),
      AtmosphereVolume(
        timeOfDayHours: 16.5, // Golden hour
        hoursPerSecond: 0.25,
        cloudCoverage: 0.3,
      ),
      DebugController(),
    ],
  );

  // Procedural island terrain
  final terrainGen = TerrainGenerator(
    width: 64,
    depth: 64,
    subdivisionsX: 24,
    subdivisionsZ: 24,
    maxHeight: 6.0,
    baseHeight: -0.6,
    islandRadius: 22.0,
    seed: 101,
  );
  scene.createGameObject(
    'IslandTerrain',
    components: [TerrainComponent(terrainGen, biomeTextureSize: 64)],
  );

  // Ocean surface
  final waves = GerstnerWaveEvaluator.ocean(baseHeight: 0.0);
  scene.createGameObject(
    'OceanSurface',
    components: [
      WaterSurfaceComponent(
        surface: WaterSurfaceMesh(
          width: 80,
          depth: 80,
          subdivisionsX: 16,
          subdivisionsZ: 16,
        ),
        waves: waves,
      ),
    ],
  );

  // Buoyant boat floating offshore
  scene.createGameObject(
    'Skiff',
    position: const Vec3(14, 0.5, 10),
    components: [BuoyantBody(width: 2.0, length: 4.0)],
  );

  // Lighthouse beacon animated with RotationTrack
  final peakY = terrainGen.sampleHeight(0, 0);
  final beacon = scene.createGameObject(
    'LighthouseBeacon',
    position: Vec3(0, peakY + 2.5, 0),
  );
  final spinClip = AnimationClip(
    name: 'spin',
    duration: 4.0,
    loopMode: LoopMode.loop,
    tracks: [
      RotationTrack(
        target: beacon.node,
        keyframes: [
          Keyframe(0.0, Quat.axisAngle(kUp, 0)),
          Keyframe(2.0, Quat.axisAngle(kUp, math.pi)),
          Keyframe(4.0, Quat.axisAngle(kUp, math.pi * 2)),
        ],
      ),
    ],
  );
  beacon.addComponent(Animator(initialClips: [spinClip], defaultClip: 'spin'));

  // Spline camera rail orbiting the island
  final rail = SplinePath.fromPoints(
    const [
      Vec3(0, 8, 28),
      Vec3(28, 9, 0),
      Vec3(0, 8, -28),
      Vec3(-28, 9, 0),
    ],
    closed: true,
  );
  scene.createGameObject(
    'TourCamera',
    position: const Vec3(0, 8, 28),
    components: [
      Camera(fovYRadians: 0.95),
      rail,
      SplineFollower(
        path: rail,
        speed: 6.0,
        loopMode: LoopMode.loop,
        alignToTangent: true,
      ),
    ],
  );

  return scene;
}
