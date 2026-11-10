import 'dart:math' as math;

import 'package:gl_volition/gl_volition.dart';

// Play volume. The ship lives near z = 0 and flies down -Z; the world streams
// past toward +Z.
const shipMinX = -7.0, shipMaxX = 7.0;
const shipMinY = -3.2, shipMaxY = 3.8;
const fieldHalfX = 11.0, fieldHalfY = 6.0;
const spawnFar = -170.0, despawnZ = 9.0;

const meteorCount = 48;
const crystalCount = 10;
const fuelCount = 3;

const cruiseSpeed = 24.0, maxCruise = 58.0, boostFactor = 1.65;
const fuelDrain = 3.2, boostDrain = 11.0;
const shipScale = 0.75, shipRadius = 0.62;
const flameLength = 1.4;

const int kShipLayer = 1;
const int kFieldLayer = 2;

final _shipYaw = Quat.axisAngle(Vec3.unitY, math.pi);
final _flameAlong = Quat.axisAngle(Vec3.unitX, math.pi / 2);

enum BodyKind { meteor, crystal, fuel }

enum GamePhase { title, playing, over }

/// HUD contract so the scene runs unchanged in a browser DOM or a headless test.
abstract interface class RocketHud {
  void message(String title, String body, {int? best});
  void hideMessage();
  void update({
    required int score,
    required double speed,
    required int shields,
    required double fuel,
    required bool boosting,
  });
}

final class NullRocketHud implements RocketHud {
  String? lastTitle;
  String? lastBody;
  bool messageVisible = false;

  @override
  void message(String title, String body, {int? best}) {
    lastTitle = title;
    lastBody = body;
    messageVisible = true;
  }

  @override
  void hideMessage() => messageVisible = false;

  @override
  void update({
    required int score,
    required double speed,
    required int shields,
    required double fuel,
    required bool boosting,
  }) {}
}

/// Optional visual prefabs; in headless tests these can be omitted and the
/// game still runs with colliders, lights, particles and audio.
final class RocketVisualAssets {
  final ModelAsset ship;
  final List<ModelAsset> meteors;
  final ModelAsset crystal;
  final ModelAsset fuel;

  const RocketVisualAssets({
    required this.ship,
    required this.meteors,
    required this.crystal,
    required this.fuel,
  });

  static MaterialDefinition kenneySurface(String name, MaterialDefinition m) =>
      switch (name.toLowerCase()) {
        'crystal' => m.copyWith(roughness: 0.2, emissiveStrength: 2.2),
        'metal' || 'metaldark' => m.copyWith(metallic: 0.55, roughness: 0.38),
        'metalred' => m.copyWith(metallic: 0.35, roughness: 0.42),
        'dark' => m.copyWith(metallic: 0.15, roughness: 0.55),
        _ => m,
      };

  static Future<RocketVisualAssets> load(AssetLoader assets) async {
    Future<ModelAsset> model(String name, {MaterialOverride tweak = kenneySurface}) =>
        assets.loadModel('res/models/$name.glb', materialOverride: tweak);

    final loaded = await Future.wait([
      model('craft_speederA'),
      model('meteor'),
      model('meteor_detailed'),
      model('meteor_half'),
      model('rock_largeA'),
      model('rock_crystals'),
      model(
        'rocket_fuelA',
        tweak: (name, m) {
          final base = kenneySurface(name, m);
          return base.copyWith(
            tintR: base.tintR * 0.3,
            tintB: base.tintB * 0.55,
            emissiveStrength: 0.9,
          );
        },
      ),
    ]);
    return RocketVisualAssets(
      ship: loaded[0],
      meteors: loaded.sublist(1, 5),
      crystal: loaded[5],
      fuel: loaded[6],
    );
  }
}

/// Smooth chase camera that lags laterally at 60% and widens FOV under boost.
final class ChaseCameraController implements CameraController {
  Vec3 target = Vec3.zero;
  double speed01 = 0;

  Vec3 _eye = const Vec3(0, 2, 8);
  Vec3 _look = const Vec3(0, 0, -12);
  double _fov = 1.0;

  static const _offset = Vec3(0, 1.7, 6.8);
  static const _lookAhead = Vec3(0, 0.2, -14);

  @override
  Vec3 get eye => _eye;

  @override
  Vec3 get forward => (_look - _eye).normalized;

  Vec3 get _desiredEye => Vec3(target.x * 0.6, target.y * 0.6, target.z) + _offset;

  void snap() {
    _eye = _desiredEye;
    _look = target + _lookAhead;
  }

  @override
  void update(double deltaTime) {
    final follow = damp(5.5, deltaTime);
    final aim = damp(9.0, deltaTime);
    _eye = Vec3.lerp(_eye, _desiredEye, follow);
    _look = Vec3.lerp(_look, target + _lookAhead, aim);
    final targetFov = 1.05 + speed01 * 0.28;
    _fov += (targetFov - _fov) * follow;
  }

  @override
  CameraView toCameraView(double aspect) => CameraView.look(
        eye: _eye,
        forward: forward,
        fovYRadians: _fov,
        aspect: aspect,
        near: 0.1,
        far: 260,
      );
}

/// One meteor, crystal or fuel canister streaming down +Z, managed via
/// [Prefab] and [ObjectPool].
final class FieldBody extends Behaviour with Poolable {
  final BodyKind kind;
  final double baseRadius;
  Vec3 spinAxis = Vec3.unitY;
  double spinRate = 0;
  bool consumed = false;

  FieldBody(this.kind, {required this.baseRadius});

  static final spec = ComponentSpec<FieldBody>(
    'FieldBody',
    () => FieldBody(BodyKind.meteor, baseRadius: 0.85),
    [
      Field.vec3('spinAxis', (b) => b.spinAxis, (b, v) => b.spinAxis = v),
      Field.number('spinRate', (b) => b.spinRate, (b, v) => b.spinRate = v),
      Field.boolean('consumed', (b) => b.consumed, (b, v) => b.consumed = v),
    ],
  );

  @override
  int get executionOrder => 10;

  @override
  void onSpawned() => consumed = false;

  @override
  void onDespawned() => consumed = true;

  void spawn(math.Random rng, Vec3 shipPos, {bool initial = false}) {
    final z = initial
        ? -55 - rng.nextDouble() * (-spawnFar - 55)
        : spawnFar - rng.nextDouble() * 40;
    final Vec3 pos;
    final double scale;
    switch (kind) {
      case BodyKind.meteor:
        final aimed = !initial && rng.nextDouble() < 0.3;
        pos = aimed
            ? Vec3(
                (shipPos.x + (rng.nextDouble() - 0.5) * 4).clamp(-fieldHalfX, fieldHalfX),
                (shipPos.y + (rng.nextDouble() - 0.5) * 3).clamp(-fieldHalfY, fieldHalfY),
                z,
              )
            : Vec3(
                (rng.nextDouble() * 2 - 1) * fieldHalfX,
                (rng.nextDouble() * 2 - 1) * fieldHalfY,
                z,
              );
        scale = 1.4 + math.pow(rng.nextDouble(), 2) * 3.2;
        spinRate = 0.4 + rng.nextDouble() * 1.8;
      case BodyKind.crystal || BodyKind.fuel:
        pos = Vec3(
          shipMinX + rng.nextDouble() * (shipMaxX - shipMinX),
          shipMinY + rng.nextDouble() * (shipMaxY - shipMinY),
          kind == BodyKind.fuel && !initial ? z - 80 : z,
        );
        scale = kind == BodyKind.fuel ? 1.3 : 1.6;
        spinRate = 1.6;
    }
    spinAxis = kind == BodyKind.meteor
        ? Vec3(
            rng.nextDouble() * 2 - 1,
            rng.nextDouble() * 2 - 1,
            rng.nextDouble() * 2 - 1,
          ).normalized
        : Vec3.unitY;

    transform
      ..localPosition = pos
      ..localScale = scale
      ..localRotation = Quat.axisAngle(spinAxis, rng.nextDouble() * math.pi * 2);
    consumed = false;
    gameObject.setActive(true);
  }

  void consume() {
    consumed = true;
    gameObject.setActive(false);
  }
}

/// Steers the player's ship, animates its tilt/flame/engine light, and handles
/// trigger overlaps with meteors, crystals and fuel canisters.
final class ShipController extends Behaviour {
  final RocketDirector director;
  final GameObject visual;
  final GameObject flamePivot;
  final GameObject flameMesh;
  final Light engineLight;

  Vec3 logicalPos = Vec3.zero;
  Vec3 velocity = Vec3.zero;

  ShipController({
    required this.director,
    required this.visual,
    required this.flamePivot,
    required this.flameMesh,
    required this.engineLight,
  });

  static final spec = ComponentSpec<ShipController>(
    'ShipController',
    () => throw StateError('ShipController is constructed by buildPixelRocketScene'),
    [
      Field.vec3('logicalPos', (s) => s.logicalPos, (s, v) => s.logicalPos = v),
      Field.vec3('velocity', (s) => s.velocity, (s, v) => s.velocity = v),
    ],
  );

  @override
  int get executionOrder => -10;

  void reset() {
    logicalPos = Vec3.zero;
    velocity = Vec3.zero;
    transform.localPosition = Vec3.zero;
    visual.setActive(true);
  }

  void stepSteering(double dt) {
    final ix = input.getAxis('Horizontal');
    final iy = input.getAxis('Vertical');

    const accel = 78.0, drag = 7.5;
    velocity = Vec3(
      velocity.x + (ix * accel - velocity.x * drag) * dt,
      velocity.y + (iy * accel - velocity.y * drag) * dt,
      0,
    );
    var p = logicalPos + velocity * dt;
    if (p.x < shipMinX || p.x > shipMaxX) velocity = Vec3(0, velocity.y, 0);
    if (p.y < shipMinY || p.y > shipMaxY) velocity = Vec3(velocity.x, 0, 0);
    p = Vec3(p.x.clamp(shipMinX, shipMaxX), p.y.clamp(shipMinY, shipMaxY), 0);
    logicalPos = p;
    transform.localPosition = p;
  }

  void pose(double t) {
    final roll = Quat.axisAngle(Vec3.unitZ, (-velocity.x * 0.06).clamp(-0.65, 0.65));
    final pitch = Quat.axisAngle(Vec3.unitX, (velocity.y * 0.05).clamp(-0.5, 0.5));
    final bob = math.sin(t * 3.1) * 0.04;
    final tilt = roll * pitch;

    transform.localPosition = logicalPos + Vec3(0, bob, 0);
    visual.transform.localRotation = tilt * _shipYaw;

    if (director.phase != GamePhase.over) {
      final shown = director.invulnerable <= 0 || (director.invulnerable * 12).floor().isEven;
      visual.setActive(shown);
    }

    final flicker = 0.85 + 0.15 * math.sin(t * 53) * math.sin(t * 31);
    final len = (director.boosting ? 1.9 : 1.0) * flicker;
    flamePivot.transform
      ..localPosition = tilt.rotate(const Vec3(0, 0.02, 0.78))
      ..localRotation = tilt * _flameAlong;
    flameMesh.transform.local = Transform(
      translation: Vec3(0, flameLength / 2 * len, 0),
      stretch: Vec3(1, len, 1),
    );
    flamePivot.setActive(director.engineLit && director.phase != GamePhase.over);

    final lightOn = director.phase != GamePhase.over || director.invulnerable > 0;
    engineLight
      ..intensity = lightOn ? (director.boosting ? 3.2 : 1.8) : 0
      ..range = director.boosting ? 9.0 : 6.0;
  }

  @override
  void onTriggerEnter(Collider other) {
    if (director.phase != GamePhase.playing) return;
    final body = other.getComponent<FieldBody>();
    if (body == null || body.consumed) return;
    director._onHitBody(body);
  }
}

/// Top-level game state machine, world streamer, and input handler.
final class RocketDirector extends Behaviour {
  final RocketHud hud;
  final math.Random rng;
  final ChaseCameraController chaseCamera = ChaseCameraController();

  late final ShipController ship;
  late final Camera mainCamera;
  late final ParticleSystem blast;
  late final ParticleSystem sparkle;
  late final ParticleSystem stars;
  late final AudioSource sfx;
  late final AudioSource engineHum;

  late final AudioClip _crystalClip;
  late final AudioClip _fuelClip;
  late final AudioClip _hitClip;
  late final AudioClip _explodeClip;
  late final AudioClip _crunchClip;
  late final AudioClip _boostClip;
  late final AudioClip _engineClip;

  final List<FieldBody> bodies = [];

  GamePhase phase = GamePhase.title;
  double speed = cruiseSpeed;
  double elapsed = 0;
  double distance = 0;
  int score = 0;
  int best = 0;
  double fuel = 100;
  int shields = 3;
  double invulnerable = 0;
  bool boosting = false;
  bool retro = false;
  bool engineLit = true;
  double _overTimer = 0;
  double _scoreDebt = 0;

  RocketDirector({RocketHud? hud, math.Random? random})
      : hud = hud ?? NullRocketHud(),
        rng = random ?? math.Random();

  static final spec = ComponentSpec<RocketDirector>(
    'RocketDirector',
    RocketDirector.new,
    [
      Field.number('speed', (d) => d.speed, (d, v) => d.speed = v),
      Field.integer('score', (d) => d.score, (d, v) => d.score = v),
      Field.integer('best', (d) => d.best, (d, v) => d.best = v),
      Field.number('fuel', (d) => d.fuel, (d, v) => d.fuel = v),
      Field.integer('shields', (d) => d.shields, (d, v) => d.shields = v),
      Field.number('invulnerable', (d) => d.invulnerable, (d, v) => d.invulnerable = v),
      Field.boolean('boosting', (d) => d.boosting, (d, v) => d.boosting = v),
      Field.boolean('retro', (d) => d.retro, (d, v) => d.retro = v),
    ],
  );

  @override
  void awake() {
    input
      ..button('Boost', ['ShiftLeft', 'ShiftRight'])
      ..button('Retro', ['KeyP'])
      ..button('Mute', ['KeyM']);

    _crystalClip = engine.audio.clip('res/audio/forceField_000.ogg', volume: 0.5);
    _fuelClip = engine.audio.clip('res/audio/laserSmall_000.ogg', volume: 0.55);
    _hitClip = engine.audio.clip('res/audio/impactMetal_002.ogg', volume: 0.7);
    _explodeClip = engine.audio.clip('res/audio/lowFrequency_explosion_000.ogg', volume: 0.8, voices: 1);
    _crunchClip = engine.audio.clip('res/audio/explosionCrunch_000.ogg', volume: 0.6);
    _boostClip = engine.audio.clip('res/audio/thrusterFire_000.ogg', volume: 0.4, voices: 2);
    _engineClip = engine.audio.clip('res/audio/spaceEngineLow_000.ogg', volume: 0.25, voices: 1);

    best = int.tryParse(engine.storage.read('pixelrocket.best') ?? '0') ?? 0;
  }

  void toTitle() {
    phase = GamePhase.title;
    _reset();
    hud.message(
      'PIXEL ROCKET',
      'Thread the meteor field. Grab crystals for points,\n'
          'green canisters for fuel.\n\n'
          'WASD / arrows — steer     Shift — boost (2× score)\n'
          'P — retro mode     M — mute\n\n'
          'Press SPACE to launch',
      best: best,
    );
  }

  void startGame() {
    _reset();
    phase = GamePhase.playing;
    hud.hideMessage();
    sfx.playOneShot(_boostClip);
  }

  void _reset() {
    ship.reset();
    speed = cruiseSpeed;
    elapsed = 0;
    distance = 0;
    score = 0;
    _scoreDebt = 0;
    fuel = 100;
    shields = 3;
    invulnerable = 0;
    boosting = false;
    engineLit = true;
    for (final b in bodies) {
      b.spawn(rng, ship.logicalPos, initial: true);
    }
    chaseCamera
      ..target = ship.logicalPos
      ..snap();
  }

  void _gameOver(String why) {
    phase = GamePhase.over;
    _overTimer = 0;
    final isBest = score > best;
    if (isBest) {
      best = score;
      engine.storage.write('pixelrocket.best', '$best');
    }
    hud.message(
      why,
      'Score  $score\nDistance  ${(distance / 10).round()} km\n\n'
          '${isBest ? 'NEW BEST!\n\n' : ''}Press SPACE to fly again',
      best: best,
    );
  }

  @override
  void fixedUpdate() {
    // Advance the world before fixedUpdate returns so Scene.physics._step()
    // tests triggers at the new positions in the same fixed tick.
    final dt = time.deltaTime;
    final t = time.time;

    switch (phase) {
      case GamePhase.playing:
        final wasBoosting = boosting;
        boosting = input.isDown('Boost') && fuel > 0;
        if (boosting && !wasBoosting) sfx.playOneShot(_boostClip);

        ship.stepSteering(dt);
        elapsed += dt;
        final cruise = math.min(maxCruise, cruiseSpeed + elapsed * 0.45);
        final targetSpeed = fuel > 0 ? cruise * (boosting ? boostFactor : 1.0) : 0.0;
        speed += (targetSpeed - speed) * damp(fuel > 0 ? 3.0 : 0.9, dt);
        invulnerable = math.max(0, invulnerable - dt);
        _burnFuel(dt);
      case GamePhase.title:
        ship.logicalPos = Vec3(math.sin(t * 0.6) * 3.0, math.sin(t * 0.9) * 1.2, 0);
        ship.velocity = Vec3(math.cos(t * 0.6) * 1.8, math.cos(t * 0.9) * 1.1, 0);
        ship.transform.localPosition = ship.logicalPos;
        speed = cruiseSpeed * 0.8;
      case GamePhase.over:
        _overTimer += dt;
        speed = math.max(0, speed - 30 * dt);
    }

    _advanceWorld(dt);
  }

  @override
  void update() {
    if (input.wasPressed('Submit')) {
      if (phase == GamePhase.title || (phase == GamePhase.over && _overTimer > 0.8)) {
        startGame();
      }
    }
    if (input.wasPressed('Retro')) {
      retro = !retro;
      scene.renderSettings.post = retro
          ? PostProcessState.stylizedPs1()
          : PostProcessState.cinematic(bloomStrength: 0.42, vignette: 0.3);
    }
    if (input.wasPressed('Mute')) {
      engine.audio.muted = !engine.audio.muted;
    }

    ship.pose(time.time);

    final speed01 = ((speed - cruiseSpeed) / (maxCruise * boostFactor - cruiseSpeed)).clamp(0.0, 1.0);
    chaseCamera
      ..target = ship.logicalPos
      ..speed01 = speed01;

    final dustSpeed = math.max(8.0, speed * 2.4);
    stars.emitter
      ..minSpeed = dustSpeed
      ..maxSpeed = dustSpeed * 1.15
      ..minLifetime = 100 / dustSpeed
      ..maxLifetime = 104 / dustSpeed
      ..rate = 30 + speed * 2.5;

    if (phase != GamePhase.over) {
      engineHum.pitch = 0.8 + speed01 * 1.1;
      if (!engineHum.isPlaying) engineHum.play(_engineClip);
    } else if (engineHum.isPlaying) {
      engineHum.stop();
    }

    hud.update(
      score: score,
      speed: speed,
      shields: shields,
      fuel: fuel,
      boosting: boosting,
    );
  }

  void _burnFuel(double dt) {
    fuel = math.max(0, fuel - (boosting ? boostDrain : fuelDrain) * dt);
    final step = speed * dt;
    distance += step;
    _scoreDebt += step * (boosting ? 2 : 1);
    final whole = _scoreDebt.floor();
    _scoreDebt -= whole;
    score += whole;
    if (fuel <= 0) {
      engineLit = false;
      if (speed < 1.5) _gameOver('OUT OF FUEL');
    }
  }

  void _advanceWorld(double dt) {
    final dz = speed * dt;
    for (final b in bodies) {
      final p = b.transform.localPosition;
      final nextZ = p.z + dz;
      if (nextZ > despawnZ) {
        b.spawn(rng, ship.logicalPos);
        continue;
      }
      b.transform
        ..localPosition = Vec3(p.x, p.y, nextZ)
        ..rotate(b.spinAxis, b.spinRate * dt);
    }
  }

  void _onHitBody(FieldBody b) {
    final pos = b.transform.position;
    switch (b.kind) {
      case BodyKind.meteor:
        if (invulnerable > 0) return;
        shields -= 1;
        blast.burst(70, position: (pos + ship.logicalPos) * 0.5);
        b.consume();
        if (shields <= 0) {
          blast.burst(220, position: ship.logicalPos);
          ship.visual.setActive(false);
          engineLit = false;
          mainCamera.shake(trauma: 1.0);
          sfx.playOneShot(_explodeClip);
          _gameOver('SHIP DESTROYED');
          return;
        }
        invulnerable = 1.6;
        mainCamera.shake(trauma: 0.6);
        sfx
          ..playOneShot(_hitClip)
          ..playOneShot(_crunchClip);
      case BodyKind.crystal:
        score += 250 * (boosting ? 2 : 1);
        sparkle.burst(28, position: pos);
        sfx.playOneShot(_crystalClip);
        b.consume();
      case BodyKind.fuel:
        fuel = math.min(100, fuel + 35);
        engineLit = true;
        sparkle.burst(40, position: pos);
        sfx.playOneShot(_fuelClip);
        b.consume();
    }
  }
}

/// Populates [engine.scene] with the complete Pixel Rocket hierarchy and
/// returns the [RocketDirector] driving it.
/// Registers custom [ComponentSpec]s for the Pixel Rocket scene.
void registerPixelRocketSpecs(ComponentRegistry registry) {
  registry
    ..register(FieldBody.spec)
    ..register(ShipController.spec)
    ..register(RocketDirector.spec);
}

RocketDirector buildPixelRocketScene(
  Engine engine, {
  required RocketHud hud,
  RocketVisualAssets? visuals,
  math.Random? random,
}) {
  final scene = engine.scene;
  final g = engine.graphics;

  scene.renderSettings
    ..skybox = const SkyboxDeclaration(
      assetId: 'deep_space',
      horizon: LinearColor(0.05, 0.03, 0.09),
      zenith: LinearColor(0.006, 0.008, 0.02),
      ground: LinearColor(0.01, 0.005, 0.02),
      horizonGlow: 0.25,
      starDensity: 0.03,
      cloudCoverage: 0.0,
      cloudDensity: 0.0,
    )
    ..clearColor = const LinearColor(0.005, 0.006, 0.015)
    ..ambientColor = const LinearColor(0.16, 0.13, 0.22)
    ..ambientIntensity = 1.0
    ..reflectionColor = const LinearColor(0.35, 0.3, 0.5)
    ..reflectionIntensity = 0.5
    ..reflectionConfidence = 0.7
    ..post = PostProcessState.cinematic(bloomStrength: 0.42, vignette: 0.3)
    ..fogEnabled = true
    ..fogColor = const LinearColor(0.012, 0.01, 0.03)
    ..fogStart = 70
    ..fogEnd = 165;

  // Directional sun light.
  scene.createGameObject(
    'Sun',
    rotation: lookRotation(const Vec3(-0.45, -0.8, -0.35)),
    components: [
      Light.directional(color: const LinearColor(1.0, 0.9, 0.78), intensity: 2.6),
    ],
  );

  final director = RocketDirector(hud: hud, random: random);
  final camComponent = Camera(customController: director.chaseCamera);
  scene.createGameObject('MainCamera', components: [camComponent]);
  director.mainCamera = camComponent;

  // Player ship hierarchy: Ship -> (Visual, FlamePivot -> FlameMesh, EngineLight).
  final shipGo = scene.createGameObject(
    'Ship',
    tag: 'Player',
    layer: kShipLayer,
    components: [
      SphereCollider(radius: shipRadius, collidesWithMask: 1 << kFieldLayer),
    ],
  );
  final shipVisual = scene.createGameObject(
    'Visual',
    parent: shipGo,
    scale: shipScale,
    rotation: _shipYaw,
    components: [
      if (visuals != null) ModelRenderer(visuals.ship, centerOrigin: true),
    ],
  );

  final coneData = Primitives.cone(radius: 0.15, height: flameLength, radialSegments: 14);
  final coneMesh = g.createMesh(coneData, debugLabel: 'engine_flame');
  final flameMat = g.createMaterial(
    const MaterialDefinition(
      key: 'engine_flame',
      tintR: 1.0,
      tintG: 0.38,
      tintB: 0.08,
      emissiveStrength: 1.6,
      roughness: 1,
      metallic: 0,
    ),
  );
  final flamePivot = scene.createGameObject(
    'FlamePivot',
    parent: shipGo,
    position: const Vec3(0, 0.02, 0.78),
    rotation: _flameAlong,
  );
  final flameMesh = scene.createGameObject(
    'FlameMesh',
    parent: flamePivot,
    position: const Vec3(0, flameLength / 2, 0),
    components: [
      MeshRenderer(
        mesh: coneMesh,
        meshData: coneData,
        material: flameMat,
        castsShadow: false,
      ),
    ],
  );

  final engineLight = Light.point(
    color: const LinearColor(1.0, 0.55, 0.2),
    intensity: 1.8,
    range: 6.0,
  );
  scene.createGameObject(
    'EngineLight',
    parent: shipGo,
    position: const Vec3(0, 0.05, 1.0),
    components: [engineLight],
  );

  final sfx = AudioSource();
  final engineHum = AudioSource(loop: true, volume: 1.0);
  shipGo
    ..addComponent(sfx)
    ..addComponent(engineHum);
  director
    ..sfx = sfx
    ..engineHum = engineHum;

  final shipCtrl = ShipController(
    director: director,
    visual: shipVisual,
    flamePivot: flamePivot,
    flameMesh: flameMesh,
    engineLight: engineLight,
  );
  shipGo.addComponent(shipCtrl);
  director.ship = shipCtrl;

  // Streamed field bodies built via Prefab + ObjectPool<FieldBody>.
  double radiusOf(ModelAsset? asset, double fallback) =>
      asset == null ? fallback : (asset.bounds.max - asset.bounds.min).length * 0.5;

  Prefab makeBodyPrefab(String name, BodyKind kind, ModelAsset? model, double baseRadius) =>
      Prefab(name, (go) {
        go.layer = kFieldLayer;
        if (model != null) go.addComponent(ModelRenderer(model, centerOrigin: true));
        go
          ..addComponent(SphereCollider(radius: baseRadius, collidesWithMask: 1 << kShipLayer))
          ..addComponent(FieldBody(kind, baseRadius: baseRadius));
      });

  for (var i = 0; i < meteorCount; i++) {
    final model = visuals?.meteors[i % visuals.meteors.length];
    final prefab = makeBodyPrefab('Meteor_$i', BodyKind.meteor, model, radiusOf(model, 0.85) * 0.72);
    final pool = ObjectPool<FieldBody>(scene: scene, prefab: prefab, initialCapacity: 1);
    director.bodies.add(pool.acquire());
  }
  for (var i = 0; i < crystalCount; i++) {
    final model = visuals?.crystal;
    final prefab = makeBodyPrefab('Crystal_$i', BodyKind.crystal, model, radiusOf(model, 0.45) * 1.4);
    final pool = ObjectPool<FieldBody>(scene: scene, prefab: prefab, initialCapacity: 1);
    director.bodies.add(pool.acquire());
  }
  for (var i = 0; i < fuelCount; i++) {
    final model = visuals?.fuel;
    final prefab = makeBodyPrefab('Fuel_$i', BodyKind.fuel, model, radiusOf(model, 0.45) * 1.4);
    final pool = ObjectPool<FieldBody>(scene: scene, prefab: prefab, initialCapacity: 1);
    director.bodies.add(pool.acquire());
  }

  // Particle systems.
  final quad = g.createMesh(Primitives.quad(width: 1, height: 1), debugLabel: 'particle_quad');
  MaterialHandle glow(String key, double r, double gr, double b, double e) =>
      g.createParticleMaterial(key: key, color: LinearColor(r, gr, b), glow: e);

  final blastSys = ParticleSystem(
    ParticleEmitter(
      mesh: quad,
      material: glow('fx_blast', 1.0, 0.42, 0.1, 2.4),
      shape: const SphereShape(radius: 0.4, directionMode: SphereDirectionMode.outward),
      minLifetime: 0.5,
      maxLifetime: 1.1,
      minSpeed: 6,
      maxSpeed: 18,
      minStartSize: 0.35,
      maxStartSize: 0.7,
      minEndSize: 0.02,
      maxEndSize: 0.05,
      dragCoefficient: 2.2,
      fadeOutFraction: 0.4,
      alignment: ParticleAlignment.velocityStretched,
      stretchFactor: 0.12,
      blendMode: BlendMode.additive,
      maxParticles: 400,
    ),
    followTransform: false,
  );
  final sparkleSys = ParticleSystem(
    ParticleEmitter(
      mesh: quad,
      material: glow('fx_sparkle', 0.3, 1.0, 0.6, 6.0),
      shape: const SphereShape(radius: 0.3, directionMode: SphereDirectionMode.outward),
      minLifetime: 0.35,
      maxLifetime: 0.7,
      minSpeed: 3,
      maxSpeed: 8,
      minStartSize: 0.25,
      maxStartSize: 0.4,
      minEndSize: 0.0,
      maxEndSize: 0.02,
      dragCoefficient: 3.0,
      blendMode: BlendMode.additive,
      maxParticles: 200,
    ),
    followTransform: false,
  );
  final starsSys = ParticleSystem(
    ParticleEmitter(
      mesh: quad,
      material: glow('fx_dust', 0.75, 0.82, 1.0, 2.5),
      shape: const BoxShape(halfExtents: Vec3(22, 13, 4), fixedDirection: Vec3.unitZ),
      rate: 90,
      minLifetime: 1.6,
      maxLifetime: 1.8,
      minSpeed: 60,
      maxSpeed: 70,
      minStartSize: 0.08,
      maxStartSize: 0.16,
      minEndSize: 0.12,
      maxEndSize: 0.2,
      fadeInFraction: 0.3,
      blendMode: BlendMode.additive,
      maxParticles: 400,
    ),
  );

  scene.createGameObject('Starfield', position: const Vec3(0, 0, -95), components: [starsSys]);
  scene.createGameObject('BlastFx', components: [blastSys]);
  scene.createGameObject('SparkleFx', components: [sparkleSys]);
  director
    ..blast = blastSys
    ..sparkle = sparkleSys
    ..stars = starsSys;

  scene.createGameObject('Director', components: [director]);
  director.toTitle();
  return director;
}
