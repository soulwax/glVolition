part of '../../engine.dart';

/// Attaches a pixeldart [ParticleEmitter] to a [GameObject]. When
/// [followTransform] is true the emitter's spawn transform tracks the
/// object's world transform each frame.
final class ParticleSystem extends Component {
  final ParticleEmitter emitter;
  bool followTransform;

  ParticleSystem(this.emitter, {this.followTransform = true});

  int burst(int count, {Vec3? position, Vec3? inheritedVelocity}) => emitter.burst(
        count,
        position: position ?? (followTransform ? transform.position : null),
        inheritedVelocity: inheritedVelocity,
      );

  void _syncTransform() {
    if (followTransform) emitter.transform = transform.world;
  }

  @override
  void _onEnableInternal() {
    _syncTransform();
    scene._particles.add(this);
    engine.graphics.addEmitter(emitter);
  }

  @override
  void _onDisableInternal() {
    scene._particles.remove(this);
    engine.graphics.removeEmitter(emitter);
  }
}
