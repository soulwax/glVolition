part of '../../engine.dart';

/// Component that embeds a pure-Dart `voxvfx` particle simulation on a [GameObject].
///
/// Supports complex physical force fields (gravity, linear drag, point attractor, vortex,
/// curl turbulence), customizable emitter shapes (point, cone, sphere, box, circle2d),
/// and continuous or burst emissions with size and color gradients.
final class VisualEffectComponent extends Behaviour {
  final vfx.VfxSimulation simulation;
  bool followTransform;

  VisualEffectComponent({
    vfx.VfxSimulation? simulation,
    this.followTransform = true,
  }) : simulation = simulation ?? vfx.VfxSimulation();

  /// Creates a bonfire/torch fire visual effect.
  factory VisualEffectComponent.fire({int maxParticles = 500, bool followTransform = true}) {
    final sim = vfx.VfxSimulation(
      maxParticles: maxParticles,
      config: vfx.VfxEmitterConfig.fire(),
    );
    sim.forces.add(const vfx.GravityForce(vfx.VfxVec3(0.0, 1.5, 0.0))); // upward buoyancy
    sim.forces.add(const vfx.TurbulenceForce(strength: 1.2, frequency: 0.8));
    return VisualEffectComponent(simulation: sim, followTransform: followTransform);
  }

  /// Creates a shower of glowing spark particles with gravity and drag.
  factory VisualEffectComponent.sparks({int maxParticles = 300, bool followTransform = true}) {
    final sim = vfx.VfxSimulation(
      maxParticles: maxParticles,
      config: vfx.VfxEmitterConfig.sparks(),
    );
    sim.forces.add(const vfx.GravityForce(vfx.VfxVec3(0.0, -9.81, 0.0)));
    sim.forces.add(const vfx.LinearDragForce(0.15));
    return VisualEffectComponent(simulation: sim, followTransform: followTransform);
  }

  /// Creates a swirling smoke column.
  factory VisualEffectComponent.smoke({int maxParticles = 400, bool followTransform = true}) {
    final sim = vfx.VfxSimulation(
      maxParticles: maxParticles,
      config: vfx.VfxEmitterConfig.smoke(),
    );
    sim.forces.add(const vfx.GravityForce(vfx.VfxVec3(0.0, 0.8, 0.0))); // gentle rising
    sim.forces.add(const vfx.LinearDragForce(0.3));
    return VisualEffectComponent(simulation: sim, followTransform: followTransform);
  }

  /// Creates an explosive particle shockwave.
  factory VisualEffectComponent.explosion({
    int particleCount = 150,
    bool followTransform = true,
  }) {
    final sim = vfx.VfxSimulation(
      maxParticles: particleCount * 2,
      config: vfx.VfxEmitterConfig.explosion(particleCount: particleCount),
    );
    sim.forces.add(const vfx.LinearDragForce(1.2));
    sim.forces.add(const vfx.GravityForce(vfx.VfxVec3(0.0, -4.0, 0.0)));
    return VisualEffectComponent(simulation: sim, followTransform: followTransform);
  }

  /// Manually triggers an instant burst of [count] particles.
  void burst(int count) => simulation.burst(count);

  /// Adds a physical force field to the particle simulation.
  void addForce(vfx.VfxForce force) => simulation.forces.add(force);

  /// Clears all active particles.
  void clear() => simulation.clear();

  @override
  void update() {
    step(time.deltaTime);
  }

  /// Manually advances the particle simulation forward by [dt] seconds.
  void step(double dt) {
    if (followTransform && isAttached) {
      final pos = transform.position;
      simulation.emitterPosition = vfx.VfxVec3(pos.x, pos.y, pos.z);
    }
    simulation.update(dt);
  }
}
