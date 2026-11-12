part of '../../engine.dart';

final class _EmptySpecResources implements ResourceLibrary {
  const _EmptySpecResources();

  @override
  MaterialHandle registerMaterial(MaterialDefinition definition) =>
      MaterialHandle.invalid;

  @override
  MeshHandle registerMesh(MeshData data, {String? debugLabel}) =>
      MeshHandle.invalid;

  @override
  dynamic noSuchMethod(Object invocation) =>
      super.noSuchMethod(invocation as dynamic);
}

ModelAsset _defaultEmptyModelAsset() => ModelAsset.fromGlb(
      GlbResult(
        rootNode: SceneNode.group(name: 'empty'),
        meshes: const [],
        materials: const [],
      ),
      const _EmptySpecResources(),
      name: 'empty',
    );

/// Registers [ComponentSpec] descriptors for all extended engine components
/// beyond the core built-ins in `component_spec.dart` (E103).
void registerExtendedDefaultSpecs(ComponentRegistry registry) {
  // 1. StateMachine
  registry.register<StateMachine<dynamic>>(
    ComponentSpec<StateMachine<dynamic>>(
      'StateMachine',
      () => StateMachine<dynamic>('idle'),
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
      ],
    ),
  );

  // 2. ModelRenderer
  registry.register<ModelRenderer>(
    ComponentSpec<ModelRenderer>(
      'ModelRenderer',
      () => ModelRenderer(_defaultEmptyModelAsset()),
      const [],
    ),
  );

  // 3. InstancedMeshRenderer
  registry.register<InstancedMeshRenderer>(
    ComponentSpec<InstancedMeshRenderer>(
      'InstancedMeshRenderer',
      InstancedMeshRenderer.new,
      [
        Field.boolean(
          'castsShadow',
          (c) => c.castsShadow,
          (c, v) => c.castsShadow = v,
        ),
        Field.boolean(
          'receivesShadow',
          (c) => c.receivesShadow,
          (c, v) => c.receivesShadow = v,
        ),
      ],
    ),
  );

  // 4. ParticleSystem
  registry.register<ParticleSystem>(
    ComponentSpec<ParticleSystem>(
      'ParticleSystem',
      () => ParticleSystem(
        ParticleEmitter(
          mesh: const MeshHandle(0, 0, 'spec_default'),
          material: const MaterialHandle(0, 0, 'spec_default'),
        ),
      ),
      [
        Field.boolean(
          'followTransform',
          (c) => c.followTransform,
          (c, v) => c.followTransform = v,
        ),
        Field.number('rate', (c) => c.emitter.rate, (c, v) => c.emitter.rate = v),
        Field.number(
          'duration',
          (c) => c.emitter.duration,
          (c, v) => c.emitter.duration = v,
        ),
        Field.boolean(
          'isLooping',
          (c) => c.emitter.isLooping,
          (c, v) => c.emitter.isLooping = v,
        ),
        Field.boolean(
          'isEmitting',
          (c) => c.emitter.isEmitting,
          (c, v) => c.emitter.isEmitting = v,
        ),
        Field.number(
          'startDelay',
          (c) => c.emitter.startDelay,
          (c, v) => c.emitter.startDelay = v,
        ),
        Field.number(
          'minLifetime',
          (c) => c.emitter.minLifetime,
          (c, v) => c.emitter.minLifetime = v,
        ),
        Field.number(
          'maxLifetime',
          (c) => c.emitter.maxLifetime,
          (c, v) => c.emitter.maxLifetime = v,
        ),
        Field.number(
          'minSpeed',
          (c) => c.emitter.minSpeed,
          (c, v) => c.emitter.minSpeed = v,
        ),
        Field.number(
          'maxSpeed',
          (c) => c.emitter.maxSpeed,
          (c, v) => c.emitter.maxSpeed = v,
        ),
        Field.number(
          'minStartSize',
          (c) => c.emitter.minStartSize,
          (c, v) => c.emitter.minStartSize = v,
        ),
        Field.number(
          'maxStartSize',
          (c) => c.emitter.maxStartSize,
          (c, v) => c.emitter.maxStartSize = v,
        ),
        Field.number(
          'minEndSize',
          (c) => c.emitter.minEndSize,
          (c, v) => c.emitter.minEndSize = v,
        ),
        Field.number(
          'maxEndSize',
          (c) => c.emitter.maxEndSize,
          (c, v) => c.emitter.maxEndSize = v,
        ),
        Field.vec3(
          'gravity',
          (c) => c.emitter.gravity,
          (c, v) => c.emitter.gravity = v,
        ),
        Field.number(
          'gravityModifier',
          (c) => c.emitter.gravityModifier,
          (c, v) => c.emitter.gravityModifier = v,
        ),
        Field.number(
          'dragCoefficient',
          (c) => c.emitter.dragCoefficient,
          (c, v) => c.emitter.dragCoefficient = v,
        ),
      ],
    ),
  );

  // 5. VisualEffectComponent
  registry.register<VisualEffectComponent>(
    ComponentSpec<VisualEffectComponent>(
      'VisualEffectComponent',
      VisualEffectComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.boolean(
          'followTransform',
          (c) => c.followTransform,
          (c, v) => c.followTransform = v,
        ),
        Field.boolean(
          'isEmitting',
          (c) => c.simulation.isEmitting,
          (c, v) => c.simulation.isEmitting = v,
        ),
        Field.boolean(
          'isLooping',
          (c) => c.simulation.isLooping,
          (c, v) => c.simulation.isLooping = v,
        ),
      ],
    ),
  );

  // 6. SplinePath
  registry.register<SplinePath>(
    ComponentSpec<SplinePath>(
      'SplinePath',
      () => SplinePath.fromPoints(const [Vec3.zero, Vec3(0, 0, -5)]),
      const [],
    ),
  );

  // 7. SplineMeshRenderer
  registry.register<SplineMeshRenderer>(
    ComponentSpec<SplineMeshRenderer>(
      'SplineMeshRenderer',
      () => SplineMeshRenderer(
        path: SplinePath.fromPoints(const [Vec3.zero, Vec3(0, 0, -5)]),
      ),
      [
        Field.integer(
          'sampleCount',
          (c) => c.sampleCount,
          (c, v) => c.sampleCount = v,
        ),
        Field.number(
          'startWidth',
          (c) => c.startWidth,
          (c, v) => c.startWidth = v,
        ),
        Field.number(
          'endWidth',
          (c) => c.endWidth,
          (c, v) => c.endWidth = v,
        ),
        Field.color('color', (c) => c.color, (c, v) => c.color = v),
      ],
    ),
  );

  // 8. TerrainComponent
  registry.register<TerrainComponent>(
    ComponentSpec<TerrainComponent>(
      'TerrainComponent',
      () => TerrainComponent(TerrainGenerator()),
      const [],
    ),
  );

  // 9. TilemapComponent
  registry.register<TilemapComponent>(
    ComponentSpec<TilemapComponent>(
      'TilemapComponent',
      () => TilemapComponent(
        TileLayer(
          columns: 16,
          rows: 16,
          tileWidth: 1.0,
          tileHeight: 1.0,
          tileset: const [],
        ),
      ),
      const [],
    ),
  );

  // 10. VoxelTerrainComponent
  registry.register<VoxelTerrainComponent>(
    ComponentSpec<VoxelTerrainComponent>(
      'VoxelTerrainComponent',
      VoxelTerrainComponent.new,
      [
        Field.number(
          'voxelScale',
          (c) => c.voxelScale,
          (c, v) => c.voxelScale = v,
        ),
      ],
    ),
  );

  // 11. RigidBody2D
  registry.register<RigidBody2D>(
    ComponentSpec<RigidBody2D>(
      'RigidBody2D',
      RigidBody2D.new,
      [
        Field.enumValue<RigidBody2D, phys.BodyType>(
          'bodyType',
          phys.BodyType.values,
          (c) => c.bodyType,
          (c, v) => c.bodyType = v,
        ),
        Field.number(
          'linearVelocityX',
          (c) => c.linearVelocity.x,
          (c, v) => c.linearVelocity = Vec2(v, c.linearVelocity.y),
        ),
        Field.number(
          'linearVelocityY',
          (c) => c.linearVelocity.y,
          (c, v) => c.linearVelocity = Vec2(c.linearVelocity.x, v),
        ),
        Field.number(
          'angularVelocity',
          (c) => c.angularVelocity,
          (c, v) => c.angularVelocity = v,
        ),
        Field.number(
          'linearDamping',
          (c) => c.linearDamping,
          (c, v) => c.linearDamping = v,
        ),
        Field.number(
          'angularDamping',
          (c) => c.angularDamping,
          (c, v) => c.angularDamping = v,
        ),
        Field.number(
          'gravityScale',
          (c) => c.gravityScale,
          (c, v) => c.gravityScale = v,
        ),
        Field.boolean(
          'fixedRotation',
          (c) => c.fixedRotation,
          (c, v) => c.fixedRotation = v,
        ),
        Field.boolean('bullet', (c) => c.bullet, (c, v) => c.bullet = v),
      ],
    ),
  );

  // 12. BoxCollider2D
  registry.register<BoxCollider2D>(
    ComponentSpec<BoxCollider2D>(
      'BoxCollider2D',
      BoxCollider2D.new,
      [
        Field.number('sizeX', (c) => c.size.x, (c, v) => c.size = Vec2(v, c.size.y)),
        Field.number('sizeY', (c) => c.size.y, (c, v) => c.size = Vec2(c.size.x, v)),
        Field.number(
          'offsetX',
          (c) => c.offset.x,
          (c, v) => c.offset = Vec2(v, c.offset.y),
        ),
        Field.number(
          'offsetY',
          (c) => c.offset.y,
          (c, v) => c.offset = Vec2(c.offset.x, v),
        ),
        Field.number('density', (c) => c.density, (c, v) => c.density = v),
        Field.number('friction', (c) => c.friction, (c, v) => c.friction = v),
        Field.number(
          'restitution',
          (c) => c.restitution,
          (c, v) => c.restitution = v,
        ),
        Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
        Field.integer(
          'categoryBits',
          (c) => c.categoryBits,
          (c, v) => c.categoryBits = v,
        ),
        Field.integer('maskBits', (c) => c.maskBits, (c, v) => c.maskBits = v),
      ],
    ),
  );

  // 13. CircleCollider2D
  registry.register<CircleCollider2D>(
    ComponentSpec<CircleCollider2D>(
      'CircleCollider2D',
      CircleCollider2D.new,
      [
        Field.number('radius', (c) => c.radius, (c, v) => c.radius = v),
        Field.number(
          'offsetX',
          (c) => c.offset.x,
          (c, v) => c.offset = Vec2(v, c.offset.y),
        ),
        Field.number(
          'offsetY',
          (c) => c.offset.y,
          (c, v) => c.offset = Vec2(c.offset.x, v),
        ),
        Field.number('density', (c) => c.density, (c, v) => c.density = v),
        Field.number('friction', (c) => c.friction, (c, v) => c.friction = v),
        Field.number(
          'restitution',
          (c) => c.restitution,
          (c, v) => c.restitution = v,
        ),
        Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
        Field.integer(
          'categoryBits',
          (c) => c.categoryBits,
          (c, v) => c.categoryBits = v,
        ),
        Field.integer('maskBits', (c) => c.maskBits, (c, v) => c.maskBits = v),
      ],
    ),
  );

  // 14. PolygonCollider2D
  registry.register<PolygonCollider2D>(
    ComponentSpec<PolygonCollider2D>(
      'PolygonCollider2D',
      () => PolygonCollider2D(
        points: const [
          Vec2(-0.5, -0.5),
          Vec2(0.5, -0.5),
          Vec2(0.5, 0.5),
          Vec2(-0.5, 0.5),
        ],
      ),
      [
        Field.number(
          'offsetX',
          (c) => c.offset.x,
          (c, v) => c.offset = Vec2(v, c.offset.y),
        ),
        Field.number(
          'offsetY',
          (c) => c.offset.y,
          (c, v) => c.offset = Vec2(c.offset.x, v),
        ),
        Field.number('density', (c) => c.density, (c, v) => c.density = v),
        Field.number('friction', (c) => c.friction, (c, v) => c.friction = v),
        Field.number(
          'restitution',
          (c) => c.restitution,
          (c, v) => c.restitution = v,
        ),
        Field.boolean('isTrigger', (c) => c.isTrigger, (c, v) => c.isTrigger = v),
        Field.integer(
          'categoryBits',
          (c) => c.categoryBits,
          (c, v) => c.categoryBits = v,
        ),
        Field.integer('maskBits', (c) => c.maskBits, (c, v) => c.maskBits = v),
      ],
    ),
  );

  // 15. DistanceJoint2D
  registry.register<DistanceJoint2D>(
    ComponentSpec<DistanceJoint2D>(
      'DistanceJoint2D',
      DistanceJoint2D.new,
      [
        Field.number(
          'anchorX',
          (c) => c.anchor.x,
          (c, v) => c.anchor = Vec2(v, c.anchor.y),
        ),
        Field.number(
          'anchorY',
          (c) => c.anchor.y,
          (c, v) => c.anchor = Vec2(c.anchor.x, v),
        ),
        Field.number(
          'connectedAnchorX',
          (c) => c.connectedAnchor.x,
          (c, v) => c.connectedAnchor = Vec2(v, c.connectedAnchor.y),
        ),
        Field.number(
          'connectedAnchorY',
          (c) => c.connectedAnchor.y,
          (c, v) => c.connectedAnchor = Vec2(c.connectedAnchor.x, v),
        ),
        Field.number(
          'frequencyHz',
          (c) => c.frequencyHz,
          (c, v) => c.frequencyHz = v,
        ),
        Field.number(
          'dampingRatio',
          (c) => c.dampingRatio,
          (c, v) => c.dampingRatio = v,
        ),
        Field.boolean(
          'collideConnected',
          (c) => c.collideConnected,
          (c, v) => c.collideConnected = v,
        ),
      ],
    ),
  );

  // 16. RevoluteJoint2D
  registry.register<RevoluteJoint2D>(
    ComponentSpec<RevoluteJoint2D>(
      'RevoluteJoint2D',
      RevoluteJoint2D.new,
      [
        Field.number(
          'anchorX',
          (c) => c.anchor.x,
          (c, v) => c.anchor = Vec2(v, c.anchor.y),
        ),
        Field.number(
          'anchorY',
          (c) => c.anchor.y,
          (c, v) => c.anchor = Vec2(c.anchor.x, v),
        ),
        Field.number(
          'connectedAnchorX',
          (c) => c.connectedAnchor.x,
          (c, v) => c.connectedAnchor = Vec2(v, c.connectedAnchor.y),
        ),
        Field.number(
          'connectedAnchorY',
          (c) => c.connectedAnchor.y,
          (c, v) => c.connectedAnchor = Vec2(c.connectedAnchor.x, v),
        ),
        Field.boolean(
          'enableMotor',
          (c) => c.enableMotor,
          (c, v) => c.enableMotor = v,
        ),
        Field.number(
          'motorSpeed',
          (c) => c.motorSpeed,
          (c, v) => c.motorSpeed = v,
        ),
        Field.number(
          'maxMotorTorque',
          (c) => c.maxMotorTorque,
          (c, v) => c.maxMotorTorque = v,
        ),
        Field.boolean(
          'enableLimit',
          (c) => c.enableLimit,
          (c, v) => c.enableLimit = v,
        ),
        Field.number(
          'lowerAngle',
          (c) => c.lowerAngle,
          (c, v) => c.lowerAngle = v,
        ),
        Field.number(
          'upperAngle',
          (c) => c.upperAngle,
          (c, v) => c.upperAngle = v,
        ),
        Field.boolean(
          'collideConnected',
          (c) => c.collideConnected,
          (c, v) => c.collideConnected = v,
        ),
      ],
    ),
  );

  // 17. PrismaticJoint2D
  registry.register<PrismaticJoint2D>(
    ComponentSpec<PrismaticJoint2D>(
      'PrismaticJoint2D',
      PrismaticJoint2D.new,
      [
        Field.number(
          'anchorX',
          (c) => c.anchor.x,
          (c, v) => c.anchor = Vec2(v, c.anchor.y),
        ),
        Field.number(
          'anchorY',
          (c) => c.anchor.y,
          (c, v) => c.anchor = Vec2(c.anchor.x, v),
        ),
        Field.number(
          'connectedAnchorX',
          (c) => c.connectedAnchor.x,
          (c, v) => c.connectedAnchor = Vec2(v, c.connectedAnchor.y),
        ),
        Field.number(
          'connectedAnchorY',
          (c) => c.connectedAnchor.y,
          (c, v) => c.connectedAnchor = Vec2(c.connectedAnchor.x, v),
        ),
        Field.number(
          'axisX',
          (c) => c.axis.x,
          (c, v) => c.axis = Vec2(v, c.axis.y),
        ),
        Field.number(
          'axisY',
          (c) => c.axis.y,
          (c, v) => c.axis = Vec2(c.axis.x, v),
        ),
        Field.boolean(
          'enableMotor',
          (c) => c.enableMotor,
          (c, v) => c.enableMotor = v,
        ),
        Field.number(
          'motorSpeed',
          (c) => c.motorSpeed,
          (c, v) => c.motorSpeed = v,
        ),
        Field.number(
          'maxMotorForce',
          (c) => c.maxMotorForce,
          (c, v) => c.maxMotorForce = v,
        ),
        Field.boolean(
          'enableLimit',
          (c) => c.enableLimit,
          (c, v) => c.enableLimit = v,
        ),
        Field.number(
          'lowerTranslation',
          (c) => c.lowerTranslation,
          (c, v) => c.lowerTranslation = v,
        ),
        Field.number(
          'upperTranslation',
          (c) => c.upperTranslation,
          (c, v) => c.upperTranslation = v,
        ),
        Field.boolean(
          'collideConnected',
          (c) => c.collideConnected,
          (c, v) => c.collideConnected = v,
        ),
      ],
    ),
  );

  // 18. Light2DComponent
  registry.register<Light2DComponent>(
    ComponentSpec<Light2DComponent>(
      'Light2DComponent',
      Light2DComponent.new,
      [
        Field.enumValue<Light2DComponent, vlight.Light2DType>(
          'lightType',
          vlight.Light2DType.values,
          (c) => c.type,
          (c, v) => c.type = v,
        ),
        Field.color('color', (c) => c.color, (c, v) => c.color = v),
        Field.number('intensity', (c) => c.intensity, (c, v) => c.intensity = v),
        Field.number('radius', (c) => c.radius, (c, v) => c.radius = v),
        Field.number(
          'innerRadius',
          (c) => c.innerRadius,
          (c, v) => c.innerRadius = v,
        ),
        Field.number('spotAngle', (c) => c.spotAngle, (c, v) => c.spotAngle = v),
        Field.number(
          'innerSpotAngle',
          (c) => c.innerSpotAngle,
          (c, v) => c.innerSpotAngle = v,
        ),
        Field.boolean(
          'castsShadows',
          (c) => c.castsShadows,
          (c, v) => c.castsShadows = v,
        ),
      ],
    ),
  );

  // 19. ShadowCaster2DComponent
  registry.register<ShadowCaster2DComponent>(
    ComponentSpec<ShadowCaster2DComponent>(
      'ShadowCaster2DComponent',
      ShadowCaster2DComponent.new,
      [
        Field.boolean(
          'useCollider',
          (c) => c.useCollider,
          (c, v) => c.useCollider = v,
        ),
      ],
    ),
  );

  // 20. FogOfWar2DComponent
  registry.register<FogOfWar2DComponent>(
    ComponentSpec<FogOfWar2DComponent>(
      'FogOfWar2DComponent',
      () => FogOfWar2DComponent(width: 32, height: 32),
      const [],
    ),
  );

  // 21. NavAgent2D
  registry.register<NavAgent2D>(
    ComponentSpec<NavAgent2D>(
      'NavAgent2D',
      NavAgent2D.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.number('speed', (c) => c.speed, (c, v) => c.speed = v),
        Field.number(
          'stoppingDistance',
          (c) => c.stoppingDistance,
          (c, v) => c.stoppingDistance = v,
        ),
        Field.number(
          'acceleration',
          (c) => c.acceleration,
          (c, v) => c.acceleration = v,
        ),
        Field.boolean(
          'rotateTowardsTarget',
          (c) => c.rotateTowardsTarget,
          (c, v) => c.rotateTowardsTarget = v,
        ),
      ],
    ),
  );

  // 22. FlowField2DComponent
  registry.register<FlowField2DComponent>(
    ComponentSpec<FlowField2DComponent>(
      'FlowField2DComponent',
      () => FlowField2DComponent(grid: NavGrid(16, 16)),
      const [],
    ),
  );

  // 23. AudioReverbZone
  registry.register<AudioReverbZone>(
    ComponentSpec<AudioReverbZone>(
      'AudioReverbZone',
      AudioReverbZone.new,
      [
        Field.number(
          'minDistance',
          (c) => c.minDistance,
          (c, v) => c.minDistance = v,
        ),
        Field.number(
          'maxDistance',
          (c) => c.maxDistance,
          (c, v) => c.maxDistance = v,
        ),
        Field.number('roomSize', (c) => c.roomSize, (c, v) => c.roomSize = v),
        Field.number('damp', (c) => c.damp, (c, v) => c.damp = v),
        Field.number('wet', (c) => c.wet, (c, v) => c.wet = v),
      ],
    ),
  );

  // 24. AudioLowPassFilterComponent
  registry.register<AudioLowPassFilterComponent>(
    ComponentSpec<AudioLowPassFilterComponent>(
      'AudioLowPassFilterComponent',
      AudioLowPassFilterComponent.new,
      [
        Field.number(
          'cutoffFrequency',
          (c) => c.cutoffFrequency,
          (c, v) => c.cutoffFrequency = v,
        ),
        Field.number('q', (c) => c.q, (c, v) => c.q = v),
      ],
    ),
  );

  // 25. BehaviorTreeComponent
  registry.register<BehaviorTreeComponent>(
    ComponentSpec<BehaviorTreeComponent>(
      'BehaviorTreeComponent',
      () => BehaviorTreeComponent(
        tree: BehaviorTree(root: ActionNode((_) => NodeStatus.success)),
      ),
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.boolean(
          'fixedStep',
          (c) => c.fixedStep,
          (c, v) => c.fixedStep = v,
        ),
      ],
    ),
  );

  // 26. AiFsmComponent
  registry.register<AiFsmComponent<dynamic>>(
    ComponentSpec<AiFsmComponent<dynamic>>(
      'AiFsmComponent',
      AiFsmComponent<dynamic>.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
      ],
    ),
  );

  // 27. StatusEffectComponent
  registry.register<StatusEffectComponent>(
    ComponentSpec<StatusEffectComponent>(
      'StatusEffectComponent',
      StatusEffectComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.number('maxHp', (c) => c.maxHp, (c, v) => c.maxHp = v),
        Field.number('currentHp', (c) => c.currentHp, (c, v) => c.currentHp = v),
        Field.number(
          'armor',
          (c) => c.defense.armor,
          (c, v) => c.defense.armor = v,
        ),
        Field.number(
          'dodgeChance',
          (c) => c.defense.dodgeChance,
          (c, v) => c.defense.dodgeChance = v,
        ),
        Field.number(
          'blockChance',
          (c) => c.defense.blockChance,
          (c, v) => c.defense.blockChance = v,
        ),
        Field.number(
          'blockReduction',
          (c) => c.defense.blockReduction,
          (c, v) => c.defense.blockReduction = v,
        ),
      ],
    ),
  );

  // 28. TurnEncounterComponent
  registry.register<TurnEncounterComponent>(
    ComponentSpec<TurnEncounterComponent>(
      'TurnEncounterComponent',
      TurnEncounterComponent.new,
      const [],
    ),
  );

  // 29. CutsceneDirectorComponent
  registry.register<CutsceneDirectorComponent>(
    ComponentSpec<CutsceneDirectorComponent>(
      'CutsceneDirectorComponent',
      CutsceneDirectorComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.boolean('autoPlay', (c) => c.autoPlay, (c, v) => c.autoPlay = v),
        Field.boolean(
          'autoTriggerAudio',
          (c) => c.autoTriggerAudio,
          (c, v) => c.autoTriggerAudio = v,
        ),
        Field.number(
          'speed',
          (c) => c.sequence.speed,
          (c, v) => c.sequence.speed = v,
        ),
        Field.enumValue<CutsceneDirectorComponent, seq.SequenceWrapMode>(
          'wrapMode',
          seq.SequenceWrapMode.values,
          (c) => c.sequence.wrapMode,
          (c, v) => c.sequence.wrapMode = v,
        ),
      ],
    ),
  );

  // 30. DialogueComponent
  registry.register<DialogueComponent>(
    ComponentSpec<DialogueComponent>(
      'DialogueComponent',
      () => DialogueComponent(
        graph: talk.DialogueGraph(
          entryNodeId: 'start',
          initialNodes: const [
            talk.DialogueNode(id: 'start', speaker: 'NPC', text: ''),
          ],
        ),
      ),
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.number(
          'typewriterSpeed',
          (c) => c.runner.typewriterSpeed,
          (c, v) => c.runner.typewriterSpeed = v,
        ),
      ],
    ),
  );

  // 31. QuestManagerComponent
  registry.register<QuestManagerComponent>(
    ComponentSpec<QuestManagerComponent>(
      'QuestManagerComponent',
      QuestManagerComponent.new,
      const [],
    ),
  );

  // 32. FlowGraphComponent
  registry.register<FlowGraphComponent>(
    ComponentSpec<FlowGraphComponent>(
      'FlowGraphComponent',
      () => FlowGraphComponent(flow.FlowGraph()),
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.boolean('autoStart', (c) => c.autoStart, (c, v) => c.autoStart = v),
        Field.boolean(
          'autoUpdate',
          (c) => c.autoUpdate,
          (c, v) => c.autoUpdate = v,
        ),
      ],
    ),
  );

  // 33. HexGridComponent
  registry.register<HexGridComponent>(
    ComponentSpec<HexGridComponent>(
      'HexGridComponent',
      HexGridComponent.new,
      const [],
    ),
  );

  // 34. TwoBoneIkComponent
  registry.register<TwoBoneIkComponent>(
    ComponentSpec<TwoBoneIkComponent>(
      'TwoBoneIkComponent',
      TwoBoneIkComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.number('weight', (c) => c.weight, (c, v) => c.weight = v),
      ],
    ),
  );

  // 35. AimIkComponent
  registry.register<AimIkComponent>(
    ComponentSpec<AimIkComponent>(
      'AimIkComponent',
      AimIkComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.vec3(
          'localAimAxis',
          (c) => c.localAimAxis,
          (c, v) => c.localAimAxis = v,
        ),
        Field.number(
          'maxAngleRadians',
          (c) => c.maxAngleRadians,
          (c, v) => c.maxAngleRadians = v,
        ),
        Field.number('weight', (c) => c.weight, (c, v) => c.weight = v),
      ],
    ),
  );

  // 36. BlendTreeComponent
  registry.register<BlendTreeComponent>(
    ComponentSpec<BlendTreeComponent>(
      'BlendTreeComponent',
      BlendTreeComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
      ],
    ),
  );

  // 37. InputManagerComponent
  registry.register<InputManagerComponent>(
    ComponentSpec<InputManagerComponent>(
      'InputManagerComponent',
      InputManagerComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
      ],
    ),
  );

  // 38. StatsComponent
  registry.register<StatsComponent>(
    ComponentSpec<StatsComponent>(
      'StatsComponent',
      StatsComponent.new,
      const [],
    ),
  );

  // 39. InventoryComponent
  registry.register<InventoryComponent>(
    ComponentSpec<InventoryComponent>(
      'InventoryComponent',
      InventoryComponent.new,
      const [],
    ),
  );

  // 40. ProceduralDungeonComponent
  registry.register<ProceduralDungeonComponent>(
    ComponentSpec<ProceduralDungeonComponent>(
      'ProceduralDungeonComponent',
      ProceduralDungeonComponent.new,
      [
        Field.integer('width', (c) => c.width, (c, v) => c.width = v),
        Field.integer('height', (c) => c.height, (c, v) => c.height = v),
        Field.integer(
          'minRoomSize',
          (c) => c.minRoomSize,
          (c, v) => c.minRoomSize = v,
        ),
        Field.integer(
          'maxRoomSize',
          (c) => c.maxRoomSize,
          (c, v) => c.maxRoomSize = v,
        ),
        Field.number('tileSize', (c) => c.tileSize, (c, v) => c.tileSize = v),
      ],
    ),
  );

  // 41. PoissonScatterComponent
  registry.register<PoissonScatterComponent>(
    ComponentSpec<PoissonScatterComponent>(
      'PoissonScatterComponent',
      PoissonScatterComponent.new,
      [
        Field.number('areaWidth', (c) => c.areaWidth, (c, v) => c.areaWidth = v),
        Field.number(
          'areaHeight',
          (c) => c.areaHeight,
          (c, v) => c.areaHeight = v,
        ),
        Field.number(
          'minDistance',
          (c) => c.minDistance,
          (c, v) => c.minDistance = v,
        ),
      ],
    ),
  );

  // 42. ProgressionStatsComponent
  registry.register<ProgressionStatsComponent>(
    ComponentSpec<ProgressionStatsComponent>(
      'ProgressionStatsComponent',
      ProgressionStatsComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.boolean(
          'autoEvaluateAchievements',
          (c) => c.autoEvaluateAchievements,
          (c, v) => c.autoEvaluateAchievements = v,
        ),
        Field.number(
          'toastDisplayDuration',
          (c) => c.toastDisplayDuration,
          (c, v) => c.toastDisplayDuration = v,
        ),
      ],
    ),
  );

  // 43. TimeRewindComponent
  registry.register<TimeRewindComponent>(
    ComponentSpec<TimeRewindComponent>(
      'TimeRewindComponent',
      TimeRewindComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.number(
          'rewindSpeed',
          (c) => c.rewindSpeed,
          (c, v) => c.rewindSpeed = v,
        ),
        Field.boolean(
          'isRecording',
          (c) => c.isRecording,
          (c, v) => c.isRecording = v,
        ),
      ],
    ),
  );

  // 44. GhostRecorderComponent
  registry.register<GhostRecorderComponent>(
    ComponentSpec<GhostRecorderComponent>(
      'GhostRecorderComponent',
      GhostRecorderComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.boolean(
          'isRecording',
          (c) => c.isRecording,
          (c, v) => c.isRecording = v,
        ),
      ],
    ),
  );

  // 45. GhostPlaybackComponent
  registry.register<GhostPlaybackComponent>(
    ComponentSpec<GhostPlaybackComponent>(
      'GhostPlaybackComponent',
      () => GhostPlaybackComponent(snap.GhostTrack()),
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.number(
          'playbackSpeed',
          (c) => c.player.playbackSpeed,
          (c, v) => c.player.playbackSpeed = v,
        ),
        Field.boolean(
          'loop',
          (c) => c.player.loop,
          (c, v) => c.player.loop = v,
        ),
      ],
    ),
  );

  // 46. LocalizationComponent
  registry.register<LocalizationComponent>(
    ComponentSpec<LocalizationComponent>(
      'LocalizationComponent',
      LocalizationComponent.new,
      [
        Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
        Field.text(
          'activeLocale',
          (c) => c.activeLocale,
          (c, v) => c.setLocale(v),
        ),
      ],
    ),
  );

  // 47. NetworkIdentity
  registry.register<NetworkIdentity>(
    ComponentSpec<NetworkIdentity>(
      'NetworkIdentity',
      () => NetworkIdentity(netId: 0),
      [
        Field.integer('netId', (c) => c.netId, (c, v) => c.netId = v),
        Field.integer(
          'ownerPeerId',
          (c) => c.ownerPeerId,
          (c, v) => c.ownerPeerId = v,
        ),
      ],
    ),
  );

  // 48. NetworkTransform
  registry.register<NetworkTransform>(
    ComponentSpec<NetworkTransform>(
      'NetworkTransform',
      NetworkTransform.new,
      [
        Field.number(
          'interpolationDelaySeconds',
          (c) => c.interpolationDelaySeconds,
          (c, v) => c.interpolationDelaySeconds = v,
        ),
        Field.boolean(
          'synchronizePosition',
          (c) => c.synchronizePosition,
          (c, v) => c.synchronizePosition = v,
        ),
        Field.boolean(
          'synchronizeRotation',
          (c) => c.synchronizeRotation,
          (c, v) => c.synchronizeRotation = v,
        ),
        Field.boolean(
          'enablePrediction',
          (c) => c.enablePrediction,
          (c, v) => c.enablePrediction = v,
        ),
      ],
    ),
  );
}
