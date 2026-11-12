import 'dart:math' as math;

import 'package:gl_volition/gl_volition.dart';

/// Post-processing showcase preset selectable live from the HUD or inspector.
enum PrismPostPreset { cinematic, ps1, vhs, storm }

/// Player-controlled hovering Prism Craft equipped with a cyan ribbon [TrailRenderer],
/// shield halo, point light aura, and ground-plane/forward pulse cannons.
final class PulseCraftBehaviour extends Behaviour {
  double moveSpeed;
  double arenaRadius;
  double fireCooldown;
  double shield;
  double aimX;
  double aimZ;
  double invulnTimer;

  double _fireTimer = 0.0;
  double _heading = 0.0;

  PulseCraftBehaviour({
    this.moveSpeed = 11.5,
    this.arenaRadius = 15.5,
    this.fireCooldown = 0.22,
    this.shield = 1.0,
    this.aimX = 0.0,
    this.aimZ = -1.0,
    this.invulnTimer = 0.0,
  });

  static final spec = ComponentSpec<PulseCraftBehaviour>(
    'PulseCraftBehaviour',
    PulseCraftBehaviour.new,
    [
      Field.number('moveSpeed', (c) => c.moveSpeed, (c, v) => c.moveSpeed = v),
      Field.number('arenaRadius', (c) => c.arenaRadius, (c, v) => c.arenaRadius = v),
      Field.number('fireCooldown', (c) => c.fireCooldown, (c, v) => c.fireCooldown = v),
      Field.number('shield', (c) => c.shield, (c, v) => c.shield = v),
      Field.number('aimX', (c) => c.aimX, (c, v) => c.aimX = v),
      Field.number('aimZ', (c) => c.aimZ, (c, v) => c.aimZ = v),
      Field.number('invulnTimer', (c) => c.invulnTimer, (c, v) => c.invulnTimer = v),
    ],
  );

  void takeDamage(double amount) {
    if (invulnTimer > 0 || shield <= 0) return;
    shield = math.max(0.0, shield - amount);
    invulnTimer = 0.85;
    if (scene.isLoaded) {
      engine.graphics.shakeCamera(trauma: 0.45);
      scene.findObjectOfType<PrismArenaDirector>()?.spawnBurst(transform.position, isGold: false);
      if (shield <= 0.0) {
        scene.findObjectOfType<PrismArenaDirector>()?.markGameOver();
      }
    }
  }

  void restoreShield(double amount) {
    shield = math.min(1.0, shield + amount);
  }

  @override
  void update() {
    final director = scene.findObjectOfType<PrismArenaDirector>();
    if (director != null && director.gameOver) return;

    final dt = time.deltaTime;
    _fireTimer = math.max(0.0, _fireTimer - dt);
    invulnTimer = math.max(0.0, invulnTimer - dt);

    final hx = input.getAxis('Horizontal');
    final vz = -input.getAxis('Vertical');
    var move = Vec3(hx, 0.0, vz);
    if (move.lengthSquared > 1e-4) {
      move = move.normalized;
      final next = transform.position + move * (moveSpeed * dt);
      final flatLen = math.sqrt(next.x * next.x + next.z * next.z);
      final clamped = flatLen > arenaRadius
          ? Vec3(next.x * arenaRadius / flatLen, 0.7, next.z * arenaRadius / flatLen)
          : Vec3(next.x, 0.7, next.z);
      transform.position = clamped;
      _heading = math.atan2(-move.x, -move.z);
      aimX = move.x;
      aimZ = move.z;
    }

    // Hover bobbing + velocity banking roll
    final hoverY = 0.7 + math.sin(time.time * 4.5) * 0.12;
    transform.position = Vec3(transform.position.x, hoverY, transform.position.z);
    final bank = -hx * 0.24;
    transform.rotation =
        Quat.axisAngle(kUp, _heading) * Quat.axisAngle(Vec3.unitZ, bank);

    // Optional mouse-to-ground-plane aiming when pointer moves or presses
    final cam = Camera.of(scene);
    final raw = input.raw;
    var wantsFire = raw.isDown('Space') || input.isDown('Submit');
    if (cam != null && (raw.pointerPressed || raw.pointerDown)) {
      final groundHit = cam.screenToGroundPlane(raw.pointerX, raw.pointerY, 0.7);
      if (groundHit != null) {
        final dir = groundHit - transform.position;
        final flat = Vec3(dir.x, 0.0, dir.z);
        if (flat.lengthSquared > 1e-4) {
          final n = flat.normalized;
          aimX = n.x;
          aimZ = n.z;
        }
      }
      wantsFire = true;
    }

    if (wantsFire && _fireTimer <= 0.0) {
      _fireTimer = fireCooldown;
      director?.firePulseBolt(
        transform.position + Vec3(aimX * 1.1, 0.0, aimZ * 1.1),
        Vec3(aimX, 0.0, aimZ),
      );
    }

    // Pulse shield aura scale
    final shieldOrb = gameObject.find('ShieldAura');
    if (shieldOrb != null) {
      final pulse = 1.0 + math.sin(time.time * 6.0) * 0.04;
      shieldOrb.transform.localScale = shield > 0 ? pulse * (0.9 + shield * 0.35) : 0.01;
    }
  }
}

/// High-speed glowing energy projectile that intercepts Void Sentinels.
final class PulseBoltBehaviour extends Behaviour {
  Vec3 direction;
  double speed;
  double lifetime;
  double hitRadius;

  double _elapsed = 0.0;

  PulseBoltBehaviour({
    this.direction = const Vec3(0, 0, -1),
    this.speed = 28.0,
    this.lifetime = 1.35,
    this.hitRadius = 1.25,
  });

  static final spec = ComponentSpec<PulseBoltBehaviour>(
    'PulseBoltBehaviour',
    PulseBoltBehaviour.new,
    [
      Field.vec3('direction', (b) => b.direction, (b, v) => b.direction = v),
      Field.number('speed', (b) => b.speed, (b, v) => b.speed = v),
      Field.number('lifetime', (b) => b.lifetime, (b, v) => b.lifetime = v),
      Field.number('hitRadius', (b) => b.hitRadius, (b, v) => b.hitRadius = v),
    ],
  );

  @override
  void update() {
    final dt = time.deltaTime;
    _elapsed += dt;
    if (_elapsed >= lifetime) {
      gameObject.destroy();
      return;
    }
    final dirNorm = direction.lengthSquared > 1e-6 ? direction.normalized : Vec3.unitZ * -1;
    transform.translate(dirNorm * (speed * dt), relativeTo: Space.world);

    // Check hits against active Void Sentinels
    for (final sentinel in scene.findObjectsOfType<SentinelBehaviour>()) {
      if (sentinel.destroyed) continue;
      final diff = sentinel.transform.position - transform.position;
      if (diff.length <= hitRadius) {
        sentinel.shatter();
        gameObject.destroy();
        return;
      }
    }
  }
}

/// Levitating metallic/emissive energy prism collectible orbiting the sanctuary.
final class PrismCoreBehaviour extends Behaviour {
  double orbitAngle;
  double orbitRadius;
  double orbitSpeed;
  double pickupRadius;
  int pointValue;

  PrismCoreBehaviour({
    this.orbitAngle = 0.0,
    this.orbitRadius = 7.5,
    this.orbitSpeed = 0.55,
    this.pickupRadius = 1.65,
    this.pointValue = 100,
  });

  static final spec = ComponentSpec<PrismCoreBehaviour>(
    'PrismCoreBehaviour',
    PrismCoreBehaviour.new,
    [
      Field.number('orbitAngle', (p) => p.orbitAngle, (p, v) => p.orbitAngle = v),
      Field.number('orbitRadius', (p) => p.orbitRadius, (p, v) => p.orbitRadius = v),
      Field.number('orbitSpeed', (p) => p.orbitSpeed, (p, v) => p.orbitSpeed = v),
      Field.number('pickupRadius', (p) => p.pickupRadius, (p, v) => p.pickupRadius = v),
      Field.integer('pointValue', (p) => p.pointValue, (p, v) => p.pointValue = v),
    ],
  );

  @override
  void update() {
    final dt = time.deltaTime;
    orbitAngle += orbitSpeed * dt;
    final y = 1.15 + math.sin(time.time * 3.0 + orbitAngle) * 0.28;
    transform.position = Vec3(
      math.cos(orbitAngle) * orbitRadius,
      y,
      math.sin(orbitAngle) * orbitRadius,
    );
    transform.rotate(kUp, dt * 1.8);

    final player = scene.findObjectOfType<PulseCraftBehaviour>();
    if (player != null) {
      final flat = player.transform.position - transform.position;
      final flatDist = math.sqrt(flat.x * flat.x + flat.z * flat.z);
      if (flatDist <= pickupRadius) {
        scene.findObjectOfType<PrismArenaDirector>()?.onPrismCollected(this, player);
      }
    }
  }
}

/// Autonomous Void Sentinel hunter drone that converges on the player craft.
final class SentinelBehaviour extends Behaviour {
  double speed;
  double contactRadius;
  bool destroyed;

  SentinelBehaviour({
    this.speed = 4.2,
    this.contactRadius = 1.35,
    this.destroyed = false,
  });

  static final spec = ComponentSpec<SentinelBehaviour>(
    'SentinelBehaviour',
    SentinelBehaviour.new,
    [
      Field.number('speed', (s) => s.speed, (s, v) => s.speed = v),
      Field.number('contactRadius', (s) => s.contactRadius, (s, v) => s.contactRadius = v),
      Field.boolean('destroyed', (s) => s.destroyed, (s, v) => s.destroyed = v),
    ],
  );

  void shatter() {
    if (destroyed) return;
    destroyed = true;
    scene.findObjectOfType<PrismArenaDirector>()?.onSentinelShattered(transform.position);
    gameObject.destroy();
  }

  @override
  void update() {
    if (destroyed) return;
    final director = scene.findObjectOfType<PrismArenaDirector>();
    if (director != null && director.gameOver) return;

    final player = scene.findObjectOfType<PulseCraftBehaviour>();
    if (player == null) return;

    final pos = transform.position;
    final toPlayer = player.transform.position - pos;
    final flat = Vec3(toPlayer.x, 0.0, toPlayer.z);
    final dist = flat.length;
    if (dist <= contactRadius) {
      player.takeDamage(0.34);
      // Knock sentinel back away from the player
      final push = dist > 1e-4 ? flat * (-3.0 / dist) : const Vec3(0, 0, -3.0);
      transform.position = Vec3(pos.x + push.x, pos.y, pos.z + push.z);
      return;
    }

    if (dist > 1e-4) {
      final step = flat * (math.min(dist, speed * time.deltaTime) / dist);
      final bob = 1.05 + math.sin(time.time * 4.0 + instanceId) * 0.16;
      transform.position = Vec3(pos.x + step.x, bob, pos.z + step.z);
      transform.rotation = lookRotation(Vec3(flat.x, -0.15, flat.z));
    }
  }
}

/// Rotates the central spire spotlight so dynamic shadows sweep continuously across the floor.
final class BeaconSweepBehaviour extends Behaviour {
  double sweepSpeed;

  BeaconSweepBehaviour({this.sweepSpeed = 0.65});

  static final spec = ComponentSpec<BeaconSweepBehaviour>(
    'BeaconSweepBehaviour',
    BeaconSweepBehaviour.new,
    [
      Field.number('sweepSpeed', (b) => b.sweepSpeed, (b, v) => b.sweepSpeed = v),
    ],
  );

  @override
  void update() {
    final angle = time.time * sweepSpeed;
    final target = Vec3(math.cos(angle) * 11.0, 0.0, math.sin(angle) * 11.0);
    final dir = target - transform.position;
    if (dir.lengthSquared > 1e-6) {
      transform.rotation = lookRotation(dir);
    }
  }
}

/// Central arena director: synthesizes GPU procedural textures & PBR materials on boot,
/// orchestrates wave respawns, particle explosions, lighting/post presets, and scorekeeping.
final class PrismArenaDirector extends Behaviour {
  int score;
  int wave;
  int combo;
  int prismsCollected;
  int sentinelsDestroyed;
  double comboTimer;
  bool gameOver;
  PrismPostPreset postPreset;
  int skyPresetIndex;

  final math.Random _rng = math.Random(1337);

  TextureHandle? _gridTex;
  TextureHandle? _checkerTex;
  MeshHandle? _cubeMesh;
  MeshHandle? _sphereMesh;
  MeshHandle? _cylinderMesh;
  MeshHandle? _quadMesh;
  MaterialHandle? _plazaMat;
  MaterialHandle? _trimMat;
  MaterialHandle? _goldMat;
  MaterialHandle? _chromeMat;
  MaterialHandle? _ceramicMat;
  MaterialHandle? _shieldMat;
  MaterialHandle? _prismEmissiveMat;
  MaterialHandle? _boltEmissiveMat;
  MaterialHandle? _sentinelBodyMat;
  MaterialHandle? _sentinelEyeMat;
  MaterialHandle? _sparkParticleMat;
  MaterialHandle? _goldParticleMat;

  bool _assetsInitialized = false;

  PrismArenaDirector({
    this.score = 0,
    this.wave = 1,
    this.combo = 1,
    this.prismsCollected = 0,
    this.sentinelsDestroyed = 0,
    this.comboTimer = 0.0,
    this.gameOver = false,
    this.postPreset = PrismPostPreset.cinematic,
    this.skyPresetIndex = 0,
  });

  static final spec = ComponentSpec<PrismArenaDirector>(
    'PrismArenaDirector',
    PrismArenaDirector.new,
    [
      Field.integer('score', (d) => d.score, (d, v) => d.score = v),
      Field.integer('wave', (d) => d.wave, (d, v) => d.wave = v),
      Field.integer('combo', (d) => d.combo, (d, v) => d.combo = v),
      Field.integer('prismsCollected', (d) => d.prismsCollected, (d, v) => d.prismsCollected = v),
      Field.integer('sentinelsDestroyed', (d) => d.sentinelsDestroyed, (d, v) => d.sentinelsDestroyed = v),
      Field.number('comboTimer', (d) => d.comboTimer, (d, v) => d.comboTimer = v),
      Field.boolean('gameOver', (d) => d.gameOver, (d, v) => d.gameOver = v),
      Field.enumValue<PrismArenaDirector, PrismPostPreset>(
        'postPreset',
        PrismPostPreset.values,
        (d) => d.postPreset,
        (d, v) => d.postPreset = v,
      ),
      Field.integer('skyPresetIndex', (d) => d.skyPresetIndex, (d, v) => d.skyPresetIndex = v),
    ],
  );

  @override
  void onEnable() {
    _ensureGpuAssets();
    _applyPostPreset();
    _applySkyPreset();
  }

  void _ensureGpuAssets() {
    if (_assetsInitialized || !scene.isLoaded) return;
    _assetsInitialized = true;

    final g = engine.graphics;

    _gridTex = g.createTexture(
      width: 256,
      height: 256,
      pixels: ProceduralTextures.grid(
        width: 256,
        height: 256,
        cellSize: 32,
        lineWidth: 2,
        lineColor: const LinearColor(0.22, 0.78, 1.0),
        cellColor: const LinearColor(0.06, 0.08, 0.14),
      ),
      hasMips: true,
      minFilter: GpuTextureFilter.linearMipmapLinear,
      wrap: GpuTextureWrap.repeat,
      anisotropy: 4,
      debugLabel: 'prism_grid_albedo',
    );

    _checkerTex = g.createTexture(
      width: 128,
      height: 128,
      pixels: ProceduralTextures.checkerboard(
        width: 128,
        height: 128,
        checkSize: 16,
        colorA: const LinearColor(0.20, 0.24, 0.34),
        colorB: const LinearColor(0.08, 0.10, 0.16),
      ),
      hasMips: true,
      wrap: GpuTextureWrap.repeat,
      debugLabel: 'prism_plinth_checker',
    );

    _cubeMesh = g.createMesh(Primitives.cube(size: 1.0), debugLabel: 'prism_cube');
    _sphereMesh = g.createMesh(Primitives.sphere(radius: 0.5), debugLabel: 'prism_sphere');
    _cylinderMesh = g.createMesh(
      Primitives.cylinder(radius: 0.5, height: 1.0),
      debugLabel: 'prism_cylinder',
    );
    _quadMesh = g.createMesh(Primitives.quad(width: 0.45, height: 0.45), debugLabel: 'prism_quad');

    _plazaMat = g.createMaterial(
      MaterialDefinition(
        key: 'prism_plaza_pbr',
        albedoTexture: _gridTex,
        roughness: 0.20,
        metallic: 0.22,
        clearcoatStrength: 0.55,
        clearcoatRoughness: 0.10,
        uvScaleU: 8.0,
        uvScaleV: 8.0,
      ),
    );
    _trimMat = g.createMaterial(
      MaterialDefinition(
        key: 'prism_trim_checker',
        albedoTexture: _checkerTex,
        roughness: 0.32,
        metallic: 0.45,
        uvScaleU: 4.0,
        uvScaleV: 4.0,
      ),
    );
    _goldMat = g.createMaterial(MaterialDefinition.gold(key: 'prism_gold', roughness: 0.16));
    _chromeMat = g.createMaterial(MaterialDefinition.chrome(key: 'prism_chrome', roughness: 0.08));
    _ceramicMat = g.createMaterial(
      MaterialDefinition.ceramic(
        key: 'prism_craft_ceramic',
        color: const LinearColor(0.92, 0.96, 1.0),
        clearcoat: 0.9,
      ),
    );
    _shieldMat = g.createMaterial(
      const MaterialDefinition(
        key: 'prism_shield_glass',
        tintR: 0.25,
        tintG: 0.85,
        tintB: 1.0,
        roughness: 0.1,
        metallic: 0.1,
        emissiveStrength: 0.45,
        alphaMode: AlphaMode.blended,
      ),
    );
    _prismEmissiveMat = g.createMaterial(
      MaterialDefinition.emissive(
        key: 'prism_core_emissive',
        color: const LinearColor(0.25, 0.95, 1.0),
        strength: 3.4,
      ),
    );
    _boltEmissiveMat = g.createMaterial(
      MaterialDefinition.emissive(
        key: 'prism_bolt_emissive',
        color: const LinearColor(0.45, 1.0, 0.85),
        strength: 4.2,
      ),
    );
    _sentinelBodyMat = g.createMaterial(
      MaterialDefinition.plastic(
        key: 'prism_sentinel_body',
        color: const LinearColor(0.14, 0.13, 0.22),
        roughness: 0.24,
      ),
    );
    _sentinelEyeMat = g.createMaterial(
      MaterialDefinition.emissive(
        key: 'prism_sentinel_eye',
        color: const LinearColor(1.0, 0.22, 0.35),
        strength: 3.8,
      ),
    );
    _sparkParticleMat = g.createParticleMaterial(
      key: 'prism_spark_fx',
      color: const LinearColor(1.0, 0.35, 0.45),
      glow: 3.2,
    );
    _goldParticleMat = g.createParticleMaterial(
      key: 'prism_gold_fx',
      color: const LinearColor(0.35, 0.95, 1.0),
      glow: 3.0,
    );

    // Bind procedural textures & PBR materials onto authored arena geometry
    final plaza = scene.find('ArenaPlaza');
    if (plaza != null) {
      final mr = plaza.getComponent<MeshRenderer>();
      if (mr != null) {
        mr
          ..mesh = _cylinderMesh
          ..material = _plazaMat;
      }
    }
    final plinth = scene.find('BeaconPlinth');
    if (plinth != null) {
      plinth.getComponent<MeshRenderer>()
        ?..mesh = _cylinderMesh
        ..material = _trimMat;
    }
    final cap = scene.find('BeaconCap');
    if (cap != null) {
      cap.getComponent<MeshRenderer>()
        ?..mesh = _sphereMesh
        ..material = _goldMat;
    }
    final colonnade = scene.find('ColonnadePillars');
    if (colonnade != null) {
      final inst = colonnade.getComponent<InstancedMeshRenderer>();
      final node = inst?.instancedNode;
      if (node != null) {
        node
          ..mesh = _cubeMesh
          ..material = _chromeMat;
      }
    }

    // Attach Player meshes (Ceramic chassis + Translucent shield orb)
    final playerGo = scene.find('PlayerCraft');
    if (playerGo != null) {
      playerGo.getComponent<MeshRenderer>()
        ?..mesh = _sphereMesh
        ..material = _ceramicMat;
      playerGo.find('ShieldAura')?.getComponent<MeshRenderer>()
        ?..mesh = _sphereMesh
        ..material = _shieldMat;
    }

    // Bind PrismCore meshes
    for (final p in scene.findObjectsOfType<PrismCoreBehaviour>()) {
      p.gameObject.getComponent<MeshRenderer>()
        ?..mesh = _cubeMesh
        ..material = _prismEmissiveMat;
      p.gameObject.find('PrismRing')?.getComponent<MeshRenderer>()
        ?..mesh = _cylinderMesh
        ..material = _goldMat;
    }

    // Bind Sentinel meshes
    for (final s in scene.findObjectsOfType<SentinelBehaviour>()) {
      s.gameObject.getComponent<MeshRenderer>()
        ?..mesh = _cubeMesh
        ..material = _sentinelBodyMat;
      s.gameObject.find('SentinelEye')?.getComponent<MeshRenderer>()
        ?..mesh = _sphereMesh
        ..material = _sentinelEyeMat;
    }

    // Ambient sanctuary firefly particles
    if (scene.find('AmbientFireflies') == null) {
      scene.createGameObject(
        'AmbientFireflies',
        position: const Vec3(0, 1.8, 0),
        components: [
          ParticleSystem.fireflies(
            mesh: _quadMesh!,
            material: _goldParticleMat!,
            boundsHalfExtents: const Vec3(14, 3, 14),
            particleCount: 48,
            seed: 77,
          ),
        ],
      );
    }
  }

  void firePulseBolt(Vec3 origin, Vec3 direction) {
    _ensureGpuAssets();
    scene.createGameObject(
      'PulseBolt_${time.frameCount}',
      position: origin,
      rotation: lookRotation(direction),
      components: [
        MeshRenderer(
          mesh: _sphereMesh,
          material: _boltEmissiveMat,
          castsShadow: false,
        ),
        Light.point(
          color: const LinearColor(0.35, 0.95, 1.0),
          intensity: 2.2,
          range: 7.0,
        ),
        PulseBoltBehaviour(direction: direction),
      ],
    ).transform.localStretch = const Vec3(0.32, 0.32, 0.85);
  }

  void spawnBurst(Vec3 position, {required bool isGold}) {
    _ensureGpuAssets();
    final go = scene.createGameObject(
      'FxBurst_${time.frameCount}',
      position: position,
      components: [
        ParticleSystem.explosion(
          mesh: _quadMesh!,
          material: isGold ? _goldParticleMat! : _sparkParticleMat!,
          particleCount: 40,
          radius: 0.6,
          explosionSpeed: 9.0,
          seed: time.frameCount + 19,
        ),
      ],
    );
    go.getComponent<ParticleSystem>()?.burst(28);
    invoke(1.2, () {
      if (!go.isDestroyed) go.destroy();
    });
  }

  void onPrismCollected(PrismCoreBehaviour prism, PulseCraftBehaviour player) {
    prismsCollected++;
    score += prism.pointValue * combo;
    combo = math.min(8, combo + 1);
    comboTimer = 4.0;
    player.restoreShield(0.22);
    spawnBurst(prism.transform.position, isGold: true);

    // Relocate collectible onto a new orbit radius & angle
    prism
      ..orbitRadius = 5.5 + _rng.nextDouble() * 8.0
      ..orbitAngle = prism.orbitAngle + math.pi * (0.7 + _rng.nextDouble() * 0.6);
  }

  void onSentinelShattered(Vec3 position) {
    sentinelsDestroyed++;
    score += 150 * combo;
    combo = math.min(8, combo + 1);
    comboTimer = 4.0;
    engine.graphics.shakeCamera(trauma: 0.35);
    spawnBurst(position, isGold: false);

    if (sentinelsDestroyed % 3 == 0) {
      wave++;
    }
    _spawnSentinel();
  }

  void _spawnSentinel() {
    _ensureGpuAssets();
    final ang = _rng.nextDouble() * math.pi * 2.0;
    final r = 13.5;
    final go = scene.createGameObject(
      'Sentinel_${sentinelsDestroyed + 10}',
      position: Vec3(math.cos(ang) * r, 1.05, math.sin(ang) * r),
      components: [
        MeshRenderer(mesh: _cubeMesh, material: _sentinelBodyMat),
        Light.point(
          color: const LinearColor(1.0, 0.2, 0.3),
          intensity: 2.0,
          range: 7.5,
        ),
        SentinelBehaviour(speed: 3.8 + wave * 0.45),
      ],
    )..transform.localStretch = const Vec3(1.1, 1.1, 1.1);
    scene.createGameObject(
      'SentinelEye',
      parent: go,
      position: const Vec3(0, 0.1, 0.55),
      scale: 0.42,
      components: [
        MeshRenderer(
          mesh: _sphereMesh,
          material: _sentinelEyeMat,
          castsShadow: false,
        ),
      ],
    );
  }

  void markGameOver() {
    gameOver = true;
  }

  void cyclePostPreset() {
    final values = PrismPostPreset.values;
    postPreset = values[(values.indexOf(postPreset) + 1) % values.length];
    _applyPostPreset();
  }

  void _applyPostPreset() {
    final pp = scene.findObjectOfType<PostProcessVolume>();
    if (pp == null) return;
    switch (postPreset) {
      case PrismPostPreset.cinematic:
        pp
          ..exposure = 1.15
          ..bloomStrength = 0.48
          ..ssaoStrength = 0.72
          ..vignette = 0.22
          ..grain = 0.04
          ..ditherStrength = 0.0
          ..chromaticAberration = 0.0
          ..toneMapping = ToneMappingMode.aces;
      case PrismPostPreset.ps1:
        pp
          ..exposure = 1.05
          ..bloomStrength = 0.18
          ..ssaoStrength = 0.0
          ..vignette = 0.18
          ..grain = 0.06
          ..ditherStrength = 0.65
          ..chromaticAberration = 0.0
          ..toneMapping = ToneMappingMode.off;
      case PrismPostPreset.vhs:
        pp
          ..exposure = 1.10
          ..bloomStrength = 0.35
          ..ssaoStrength = 0.3
          ..vignette = 0.36
          ..grain = 0.25
          ..ditherStrength = 0.15
          ..chromaticAberration = 0.45
          ..toneMapping = ToneMappingMode.reinhard;
      case PrismPostPreset.storm:
        pp
          ..exposure = 0.95
          ..bloomStrength = 0.55
          ..ssaoStrength = 0.80
          ..vignette = 0.28
          ..grain = 0.10
          ..ditherStrength = 0.0
          ..chromaticAberration = 0.15
          ..toneMapping = ToneMappingMode.agx;
    }
    if (scene.isLoaded && postPreset == PrismPostPreset.storm) {
      scene.renderSettings.post = scene.renderSettings.post.copyWith(
        rainIntensity: 0.75,
        surfaceWetness: 0.85,
      );
    } else if (scene.isLoaded) {
      scene.renderSettings.post = scene.renderSettings.post.copyWith(
        rainIntensity: 0.0,
        surfaceWetness: 0.15,
      );
    }
  }

  void cycleTimeOfDay() {
    skyPresetIndex = (skyPresetIndex + 1) % 3;
    _applySkyPreset();
  }

  void _applySkyPreset() {
    final atmo = scene.findObjectOfType<AtmosphereVolume>();
    if (atmo == null) return;
    switch (skyPresetIndex) {
      case 0: // Golden Twilight
        atmo.timeOfDayHours = 18.2;
      case 1: // Neon Night
        atmo.timeOfDayHours = 22.5;
      default: // Crisp Noon
        atmo.timeOfDayHours = 13.5;
    }
  }

  String get skyLabel => switch (skyPresetIndex) {
        0 => 'Dusk',
        1 => 'Night',
        _ => 'Noon',
      };

  void restartArena() {
    if (scene.isLoaded) {
      engine.loadScene(buildPrismPulseScene());
    }
  }

  @override
  void update() {
    if (comboTimer > 0) {
      comboTimer -= time.deltaTime;
      if (comboTimer <= 0 && combo > 1) {
        combo = 1;
      }
    }
    if (postPreset == PrismPostPreset.storm) {
      scene.renderSettings.post = scene.renderSettings.post.copyWith(
        rainIntensity: 0.75,
        surfaceWetness: 0.85,
      );
    }
  }
}

/// Responsive `UICanvas` HUD built exclusively with [UIAnchor] offsets.
final class PrismHudController extends Behaviour {
  late UILabel _scoreLabel;
  late UILabel _waveLabel;
  late UIProgressBar _shieldBar;
  late UIButton _postButton;
  late UIButton _skyButton;
  late UIButton _restartButton;
  late UIPanel _gameOverPanel;
  late UILabel _gameOverLabel;

  bool _built = false;

  static final spec = ComponentSpec<PrismHudController>(
    'PrismHudController',
    PrismHudController.new,
  );

  @override
  void onEnable() {
    final canvas = getComponent<UICanvas>();
    if (canvas == null || _built) return;
    _built = true;

    // Top-Left: Score, Wave & Shield HUD
    canvas.elements.addAll([
      UIPanel(
        anchor: UIAnchor.topLeft,
        x: 12,
        y: 12,
        width: 224,
        height: 82,
        fillColor: 0x0A1020D8,
        borderColor: 0x38BDF8CC,
      ),
      UILabel(
        text: 'PRISM PULSE',
        anchor: UIAnchor.topLeft,
        x: 22,
        y: 18,
        scale: 1.25,
        color: 0x38BDF8FF,
      ),
      _scoreLabel = UILabel(
        text: 'SCORE 0   x1',
        anchor: UIAnchor.topLeft,
        x: 22,
        y: 38,
        scale: 1.0,
        color: 0xFFFFFFFF,
      ),
      _waveLabel = UILabel(
        text: 'WAVE 1 | PRISMS 0',
        anchor: UIAnchor.topLeft,
        x: 22,
        y: 54,
        scale: 0.9,
        color: 0x94A3B8FF,
      ),
      _shieldBar = UIProgressBar(
        anchor: UIAnchor.topLeft,
        x: 22,
        y: 72,
        width: 204,
        height: 12,
        value: 1.0,
        fillColor: 0x2DD4BFFF,
        lowFillColor: 0xF43F5EFF,
      ),
    ]);

    // Top-Right: Live Renderer PostFX & Atmosphere Switchers
    canvas.elements.addAll([
      _postButton = UIButton(
        label: 'FX: CINEMATIC',
        anchor: UIAnchor.topRight,
        x: -14,
        y: 12,
        width: 148,
        height: 26,
        normalColor: 0x10182AD8,
        hoverColor: 0x1E2944EE,
        onPressed: () => scene.findObjectOfType<PrismArenaDirector>()?.cyclePostPreset(),
      ),
      _skyButton = UIButton(
        label: 'SKY: Dusk',
        anchor: UIAnchor.topRight,
        x: -14,
        y: 44,
        width: 148,
        height: 26,
        normalColor: 0x10182AD8,
        hoverColor: 0x1E2944EE,
        onPressed: () => scene.findObjectOfType<PrismArenaDirector>()?.cycleTimeOfDay(),
      ),
    ]);

    // Bottom-Center: Controls Strip
    canvas.elements.add(
      UILabel(
        text: 'WASD Move | Space / Click Fire | F12 Inspector',
        anchor: UIAnchor.bottomCenter,
        x: 0,
        y: -14,
        scale: 0.9,
        color: 0xCBD5E1DD,
      ),
    );

    // Center Game Over overlay
    _gameOverPanel = UIPanel(
      anchor: UIAnchor.center,
      width: 260,
      height: 112,
      fillColor: 0x090D1AE8,
      borderColor: 0xF43F5EFF,
      visible: false,
    );
    _gameOverLabel = UILabel(
      text: 'SHIELD DEPLETED',
      anchor: UIAnchor.center,
      y: -22,
      scale: 1.3,
      color: 0xFB7185FF,
      visible: false,
    );
    _restartButton = UIButton(
      label: 'RESTART ARENA',
      anchor: UIAnchor.center,
      y: 22,
      width: 170,
      height: 28,
      normalColor: 0x0EA5E9EE,
      hoverColor: 0x38BDF8FF,
      visible: false,
      onPressed: () => scene.findObjectOfType<PrismArenaDirector>()?.restartArena(),
    );
    canvas.elements.addAll([_gameOverPanel, _gameOverLabel, _restartButton]);
  }

  @override
  void update() {
    final director = scene.findObjectOfType<PrismArenaDirector>();
    final player = scene.findObjectOfType<PulseCraftBehaviour>();
    if (director == null) return;

    _scoreLabel.text = 'SCORE ${director.score}   x${director.combo}';
    _waveLabel.text = 'WAVE ${director.wave} | PRISMS ${director.prismsCollected}';
    _shieldBar.value = player?.shield ?? 0.0;
    _postButton.label = 'FX: ${director.postPreset.name.toUpperCase()}';
    _skyButton.label = 'SKY: ${director.skyLabel}';

    final isOver = director.gameOver;
    _gameOverPanel.visible = isOver;
    _gameOverLabel.visible = isOver;
    _restartButton.visible = isOver;
  }
}

/// Registers every custom [ComponentSpec] for hot-state reload & InspectorOverlay (`F12`).
void registerPrismPulseSpecs(ComponentRegistry registry) {
  registry
    ..register(PulseCraftBehaviour.spec)
    ..register(PulseBoltBehaviour.spec)
    ..register(PrismCoreBehaviour.spec)
    ..register(SentinelBehaviour.spec)
    ..register(BeaconSweepBehaviour.spec)
    ..register(PrismArenaDirector.spec)
    ..register(PrismHudController.spec);
}

/// Builds the **Prism Pulse** 3D mini-game showcase scene exercising pixeldart's
/// PBR materials, procedural textures, instanced shadows, Gerstner water moat,
/// volumetric spire, bloom/SSAO/PS1/VHS post-processing, particles & ribbon trails.
Scene buildPrismPulseScene() {
  final scene = Scene('PrismPulse');

  // 1. Atmosphere, Solar Directional Shadows, PostProcessVolume & Director
  scene.createGameObject(
    'AtmosphereAndPostFX',
    components: [
      Light.directional(intensity: 1.4),
      AtmosphereVolume(
        timeOfDayHours: 18.2,
        hoursPerSecond: 0.08,
        cloudCoverage: 0.35,
      ),
      PostProcessVolume.cinematic(
        exposure: 1.15,
        bloomStrength: 0.48,
        ssaoStrength: 0.72,
        vignette: 0.22,
      ),
      DebugController(),
      PrismArenaDirector(),
    ],
  );

  // 2. Surrounding Animated Gerstner Water Moat
  scene.createGameObject(
    'SanctuaryMoatWater',
    components: [
      WaterSurfaceComponent(
        surface: WaterSurfaceMesh(
          width: 96,
          depth: 96,
          subdivisionsX: 20,
          subdivisionsZ: 20,
        ),
        waves: GerstnerWaveEvaluator.ocean(baseHeight: -0.65),
      ),
    ],
  );

  // 3. Textured Clearcoated PBR Sanctuary Courtyard & Stepped Beacon Plinth
  scene.createGameObject(
    'ArenaPlaza',
    position: const Vec3(0, -0.25, 0),
    components: [
      MeshRenderer(
        meshData: Primitives.cylinder(radius: 0.5, height: 1.0),
        castsShadow: false,
        receivesShadow: true,
      ),
    ],
  ).transform.localStretch = const Vec3(36.0, 0.5, 36.0);

  scene.createGameObject(
    'BeaconPlinth',
    position: const Vec3(0, 0.9, 0),
    components: [
      MeshRenderer(
        meshData: Primitives.cylinder(radius: 0.5, height: 1.0),
        castsShadow: true,
        receivesShadow: true,
      ),
    ],
  ).transform.localStretch = const Vec3(3.4, 1.8, 3.4);

  scene.createGameObject(
    'BeaconCap',
    position: const Vec3(0, 2.35, 0),
    scale: 1.4,
    components: [
      MeshRenderer(meshData: Primitives.sphere(radius: 0.5)),
      VolumetricLightSource(
        color: const LinearColor(0.35, 0.85, 1.0),
        luminousIntensity: 3.2,
        cutoffDistance: 32.0,
      ),
      Light.spot(
        color: const LinearColor(0.55, 0.92, 1.0),
        intensity: 5.0,
        range: 34.0,
        innerSpotAngle: 0.20,
        spotAngle: 0.52,
        castsShadow: true,
      ),
      BeaconSweepBehaviour(),
    ],
  );

  // 4. Instanced Chrome Colonnade Ring (Single GPU Instanced Draw Call + Shadows)
  final initialPillars = List<Transform>.generate(12, (i) {
    final a = (i / 12.0) * math.pi * 2.0;
    return Transform(
      translation: Vec3(math.cos(a) * 16.5, 2.2, math.sin(a) * 16.5),
      rotation: Quat.axisAngle(kUp, a),
      stretch: const Vec3(0.95, 4.4, 0.95),
    );
  });
  scene.createGameObject(
    'ColonnadePillars',
    components: [
      InstancedMeshRenderer(
        meshData: Primitives.cube(size: 1.0),
        transforms: initialPillars,
        castsShadow: true,
        receivesShadow: true,
      ),
    ],
  );

  // 5. Player Hover Craft + Translucent Shield Aura + TrailRenderer Wake
  final player = scene.createGameObject(
    'PlayerCraft',
    position: const Vec3(0, 0.7, 8.5),
    components: [
      MeshRenderer(meshData: Primitives.sphere(radius: 0.5)),
      Light.point(
        color: const LinearColor(0.25, 0.88, 1.0),
        intensity: 2.6,
        range: 10.0,
      ),
      TrailRenderer(
        timeLength: 0.7,
        minVertexDistance: 0.15,
        startWidth: 0.55,
        endWidth: 0.04,
        color: const LinearColor(0.25, 0.92, 1.0),
      ),
      PulseCraftBehaviour(),
    ],
  )..transform.localStretch = const Vec3(1.2, 0.55, 1.45);
  scene.createGameObject(
    'ShieldAura',
    parent: player,
    components: [
      MeshRenderer(
        meshData: Primitives.sphere(radius: 0.5),
        drawMode: DrawMode.blended,
        castsShadow: false,
      ),
    ],
  ).transform.localStretch = const Vec3(1.45, 1.7, 1.3);

  // 6. Three Orbiting Emissive Energy Prisms
  for (var i = 0; i < 3; i++) {
    final a = i * (math.pi * 2.0 / 3.0);
    final r = 6.5 + i * 2.2;
    final pGo = scene.createGameObject(
      'PrismCore_$i',
      position: Vec3(math.cos(a) * r, 1.15, math.sin(a) * r),
      scale: 0.85,
      components: [
        MeshRenderer(meshData: Primitives.cube(size: 1.0), castsShadow: true),
        Light.point(
          color: const LinearColor(0.25, 0.95, 1.0),
          intensity: 1.8,
          range: 7.5,
        ),
        PrismCoreBehaviour(orbitAngle: a, orbitRadius: r),
      ],
    );
    scene.createGameObject(
      'PrismRing',
      parent: pGo,
      components: [
        MeshRenderer(meshData: Primitives.cylinder(radius: 0.5, height: 1.0)),
      ],
    ).transform.localStretch = const Vec3(1.45, 0.18, 1.45);
  }

  // 7. Initial Void Sentinels
  for (var i = 0; i < 2; i++) {
    final ang = i == 0 ? 0.5 : 3.6;
    final sGo = scene.createGameObject(
      'Sentinel_$i',
      position: Vec3(math.cos(ang) * 13.0, 1.05, math.sin(ang) * 13.0),
      components: [
        MeshRenderer(meshData: Primitives.cube(size: 1.0)),
        Light.point(
          color: const LinearColor(1.0, 0.2, 0.3),
          intensity: 2.0,
          range: 7.5,
        ),
        SentinelBehaviour(speed: 3.8 + i * 0.4),
      ],
    )..transform.localStretch = const Vec3(1.1, 1.1, 1.1);
    scene.createGameObject(
      'SentinelEye',
      parent: sGo,
      position: const Vec3(0, 0.1, 0.55),
      scale: 0.42,
      components: [
        MeshRenderer(
          meshData: Primitives.sphere(radius: 0.5),
          castsShadow: false,
        ),
      ],
    );
  }

  // 8. Smooth Follow 3D Camera
  scene.createGameObject(
    'MainCamera',
    position: const Vec3(0, 12, 22),
    components: [
      Camera(fovYRadians: 0.85, near: 0.2, far: 180.0),
      SmoothFollowCamera(
        target: player,
        targetOffset: const Vec3(0, 0.6, 0),
        distance: 15.0,
        height: 10.5,
        positionDamping: 5.5,
        rotationDamping: 7.5,
      ),
    ],
  );

  // 9. Anchor-Responsive UICanvas HUD
  scene.createGameObject(
    'HudCanvas',
    components: [
      UICanvas(designWidth: 640, designHeight: 360),
      PrismHudController(),
    ],
  );

  return scene;
}
