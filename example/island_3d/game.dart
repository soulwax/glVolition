import 'dart:math' as math;

import 'package:gl_volition/gl_volition.dart';

/// Lighthouse beam controller that aims its [Light.spot] at [aimPoint] on the
/// ocean surface and illuminates nearby ships so they avoid coastal reefs
/// (E5-5 Tidewatch).
final class LighthouseBehaviour extends Behaviour {
  Vec3 aimPoint;
  double beamRadius;

  LighthouseBehaviour({
    this.aimPoint = const Vec3(14, 0, 10),
    this.beamRadius = 12.0,
  });

  static final spec = ComponentSpec<LighthouseBehaviour>(
    'LighthouseBehaviour',
    LighthouseBehaviour.new,
    [
      Field.vec3('aimPoint', (l) => l.aimPoint, (l, v) => l.aimPoint = v),
      Field.number(
        'beamRadius',
        (l) => l.beamRadius,
        (l, v) => l.beamRadius = v,
      ),
    ],
  );

  bool illuminates(Vec3 worldPos) {
    final dx = worldPos.x - aimPoint.x;
    final dz = worldPos.z - aimPoint.z;
    return (dx * dx + dz * dz) <= beamRadius * beamRadius;
  }

  @override
  void update() {
    // Allow pointer aiming onto the ocean surface when a Camera is active
    final cam = scene.findObjectOfType<Camera>();
    final raw = input.raw;
    if (cam != null && (raw.pointerX != 0 || raw.pointerY != 0)) {
      final hit = cam.screenToGroundPlane(raw.pointerX, raw.pointerY, 0.0);
      if (hit != null) {
        aimPoint = hit;
      }
    }
    if (raw.pointerPressed) {
      scene.findObjectOfType<HarbourDirector>()?.launchFlareAt(aimPoint);
    }

    final dir = aimPoint - transform.position;
    if (dir.lengthSquared > 1e-6) {
      transform.rotation = lookRotation(dir);
    }
  }
}

/// Rising signal flare launched from a tapped ship or ocean coordinate (E5-5).
final class FlareBehaviour extends Behaviour {
  double verticalSpeed;
  double lifetime;
  double elapsed = 0;

  FlareBehaviour({this.verticalSpeed = 9.0, this.lifetime = 3.0});

  static final spec =
      ComponentSpec<FlareBehaviour>('FlareBehaviour', FlareBehaviour.new, [
        Field.number(
          'verticalSpeed',
          (f) => f.verticalSpeed,
          (f, v) => f.verticalSpeed = v,
        ),
        Field.number('lifetime', (f) => f.lifetime, (f, v) => f.lifetime = v),
      ]);

  @override
  void update() {
    elapsed += time.deltaTime;
    if (elapsed >= lifetime) {
      gameObject.destroy();
      return;
    }
    transform.translate(
      Vec3(0, verticalSpeed * time.deltaTime, 0),
      relativeTo: Space.world,
    );
  }
}

/// Coastal vessel that follows a [SplinePath] into the harbour when illuminated
/// by the [LighthouseBehaviour] (or a nearby [FlareBehaviour]), or drifts into
/// the reef when left in darkness (E5-5 Tidewatch).
final class ShipAgentBehaviour extends Behaviour {
  final SplinePath route;
  Vec3 reefCenter;
  double reefRadius;
  double speed;
  double distance = 0;
  bool dockedSafely = false;
  bool wreckedOnReef = false;

  ShipAgentBehaviour({
    SplinePath? route,
    this.reefCenter = const Vec3(10, 0, 0),
    this.reefRadius = 4.5,
    this.speed = 8.0,
  }) : route =
           route ??
           SplinePath.fromPoints(const [Vec3(14, 0.5, 10), Vec3(8, 0.5, -10)]);

  static final spec = ComponentSpec<ShipAgentBehaviour>(
    'ShipAgentBehaviour',
    ShipAgentBehaviour.new,
    [
      Field.vec3('reefCenter', (s) => s.reefCenter, (s, v) => s.reefCenter = v),
      Field.number(
        'reefRadius',
        (s) => s.reefRadius,
        (s, v) => s.reefRadius = v,
      ),
      Field.number('speed', (s) => s.speed, (s, v) => s.speed = v),
      Field.number('distance', (s) => s.distance, (s, v) => s.distance = v),
      Field.boolean(
        'dockedSafely',
        (s) => s.dockedSafely,
        (s, v) => s.dockedSafely = v,
      ),
      Field.boolean(
        'wreckedOnReef',
        (s) => s.wreckedOnReef,
        (s, v) => s.wreckedOnReef = v,
      ),
    ],
  );

  @override
  void update() {
    if (dockedSafely || wreckedOnReef) return;

    final lighthouse = scene.findObjectOfType<LighthouseBehaviour>();
    final hasFlare = scene.findObjectsOfType<FlareBehaviour>().isNotEmpty;
    final pos = transform.localPosition;
    final guided =
        (lighthouse != null && lighthouse.illuminates(pos)) || hasFlare;

    if (guided) {
      distance += speed * time.deltaTime;
      if (distance >= route.totalLength) {
        distance = route.totalLength;
        dockedSafely = true;
      }
      final target = route.sampleAtDistance(distance);
      transform.localPosition = Vec3(target.x, pos.y, target.z);
    } else {
      // Unilluminated ship drifts toward the reef hazard
      final toReef = Vec3(reefCenter.x - pos.x, 0, reefCenter.z - pos.z);
      final d = toReef.length;
      if (d <= reefRadius) {
        wreckedOnReef = true;
        return;
      }
      final step = toReef * (math.min(d, speed * 0.75 * time.deltaTime) / d);
      transform.localPosition = Vec3(pos.x + step.x, pos.y, pos.z + step.z);
    }
  }
}

/// Spawns signal flares and coordinates the harbour's [AtmosphereVolume] clock
/// from golden hour (17:00) into night (E5-5 Tidewatch).
final class HarbourDirector extends Behaviour {
  int flaresLaunched = 0;

  static final spec =
      ComponentSpec<HarbourDirector>('HarbourDirector', HarbourDirector.new, [
        Field.integer(
          'flaresLaunched',
          (h) => h.flaresLaunched,
          (h, v) => h.flaresLaunched = v,
        ),
      ]);

  GameObject launchFlareAt(Vec3 worldPos) {
    flaresLaunched++;
    return scene.createGameObject(
      'Flare_$flaresLaunched',
      position: worldPos + const Vec3(0, 1.0, 0),
      components: [
        Light.point(
          color: const LinearColor(1.0, 0.35, 0.15),
          intensity: 3.0,
          range: 18.0,
        ),
        FlareBehaviour(),
      ],
    );
  }
}

/// Registers custom [ComponentSpec]s for the Island3D (Tidewatch) scene.
void registerIsland3DSpecs(ComponentRegistry registry) {
  registry
    ..register(LighthouseBehaviour.spec)
    ..register(FlareBehaviour.spec)
    ..register(ShipAgentBehaviour.spec)
    ..register(HarbourDirector.spec);
}

/// Builds a 3D coastal island [Scene] (Tidewatch port) combining procedural
/// [TerrainComponent], dynamic [WaterSurfaceComponent] waves, a [BuoyantBody]
/// vessel with [ShipAgentBehaviour], a [LighthouseBehaviour] spotlight, a
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
        timeOfDayHours: 17.0, // Dusk / golden hour
        hoursPerSecond: 0.5,
        cloudCoverage: 0.3,
      ),
      DebugController(),
      HarbourDirector(),
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

  // Safe harbour shipping channel spline
  final shipRoute = SplinePath.fromPoints(const [
    Vec3(14, 0.5, 10),
    Vec3(16, 0.5, 0),
    Vec3(8, 0.5, -10),
  ]);

  // Buoyant boat floating offshore
  scene.createGameObject(
    'Skiff',
    position: const Vec3(14, 0.5, 10),
    components: [
      BuoyantBody(width: 2.0, length: 4.0),
      shipRoute,
      ShipAgentBehaviour(route: shipRoute),
    ],
  );

  // Lighthouse beacon + sweeping spotlight
  final peakY = terrainGen.sampleHeight(0, 0);
  final beacon = scene.createGameObject(
    'LighthouseBeacon',
    position: Vec3(0, peakY + 2.5, 0),
    components: [
      Light.spot(
        color: const LinearColor(1.0, 0.92, 0.72),
        intensity: 4.5,
        range: 45.0,
        innerSpotAngle: 0.18,
        spotAngle: 0.42,
      ),
      LighthouseBehaviour(aimPoint: const Vec3(14, 0, 10), beamRadius: 20.0),
    ],
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
  final rail = SplinePath.fromPoints(const [
    Vec3(0, 8, 28),
    Vec3(28, 9, 0),
    Vec3(0, 8, -28),
    Vec3(-28, 9, 0),
  ], closed: true);
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
