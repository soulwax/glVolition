part of '../engine.dart';

/// Eased tweening utilities built on `pixeldart`'s [Curve] / [Curves] and
/// [Behaviour.startCoroutine] (E9-2).
extension BehaviourTweenExt on Behaviour {
  /// Tweens a scalar from [from] to [to] over [duration] seconds using [curve].
  Coroutine tween(
    double from,
    double to, {
    required double duration,
    required void Function(double value) onUpdate,
    Curve curve = Curves.easeInOutQuad,
    double delay = 0.0,
    bool pingPong = false,
    int loops = 1,
    bool unscaledTime = false,
    void Function()? onComplete,
  }) => startCoroutine(() sync* {
    if (delay > 0) {
      yield unscaledTime ? WaitForRealtime(delay) : WaitForSeconds(delay);
    }
    final dur = math.max(1e-6, duration);
    var loopIndex = 0;
    while (loops <= 0 || loopIndex < loops) {
      var elapsed = 0.0;
      while (elapsed < dur) {
        yield const NextFrame();
        final dt = unscaledTime ? time.unscaledDeltaTime : time.deltaTime;
        elapsed = math.min(dur, elapsed + dt);
        final rawT = elapsed / dur;
        final eased = curve.transform(rawT);
        onUpdate(from + (to - from) * eased);
      }
      if (pingPong) {
        var backElapsed = 0.0;
        while (backElapsed < dur) {
          yield const NextFrame();
          final dt = unscaledTime ? time.unscaledDeltaTime : time.deltaTime;
          backElapsed = math.min(dur, backElapsed + dt);
          final rawT = 1.0 - (backElapsed / dur);
          final eased = curve.transform(rawT);
          onUpdate(from + (to - from) * eased);
        }
      }
      loopIndex++;
    }
    onComplete?.call();
  });

  /// Tweens a [Vec3] from [from] to [to] over [duration] seconds.
  Coroutine tweenVec3(
    Vec3 from,
    Vec3 to, {
    required double duration,
    required void Function(Vec3 value) onUpdate,
    Curve curve = Curves.easeOutCubic,
    double delay = 0.0,
    bool pingPong = false,
    int loops = 1,
    bool unscaledTime = false,
    void Function()? onComplete,
  }) => tween(
    0.0,
    1.0,
    duration: duration,
    curve: curve,
    delay: delay,
    pingPong: pingPong,
    loops: loops,
    unscaledTime: unscaledTime,
    onUpdate: (t) => onUpdate(Vec3.lerp(from, to, t)),
    onComplete: onComplete,
  );

  /// Tweens this [GameObject]'s `transform.localPosition` to [targetLocalPos].
  Coroutine tweenPosition(
    Vec3 targetLocalPos, {
    required double duration,
    Curve curve = Curves.easeOutCubic,
    double delay = 0.0,
    bool pingPong = false,
    int loops = 1,
    void Function()? onComplete,
  }) {
    final startPos = transform.localPosition;
    return tweenVec3(
      startPos,
      targetLocalPos,
      duration: duration,
      curve: curve,
      delay: delay,
      pingPong: pingPong,
      loops: loops,
      onUpdate: (p) => transform.localPosition = p,
      onComplete: onComplete,
    );
  }

  /// Tweens this [GameObject]'s uniform `transform.localScale` to [targetScale].
  Coroutine tweenScale(
    double targetScale, {
    required double duration,
    Curve curve = Curves.easeOutCubic,
    double delay = 0.0,
    bool pingPong = false,
    int loops = 1,
    void Function()? onComplete,
  }) {
    final startScale = transform.localScale;
    return tween(
      startScale,
      targetScale,
      duration: duration,
      curve: curve,
      delay: delay,
      pingPong: pingPong,
      loops: loops,
      onUpdate: (s) => transform.localScale = s,
      onComplete: onComplete,
    );
  }

  /// Tweens this [GameObject]'s `transform.localRotation` to [targetLocalRot]
  /// using spherical linear interpolation ([Quat.slerp]) (P12-W20-D).
  Coroutine tweenRotation(
    Quat targetLocalRot, {
    required double duration,
    Curve curve = Curves.easeOutCubic,
    double delay = 0.0,
    bool pingPong = false,
    int loops = 1,
    bool unscaledTime = false,
    void Function()? onComplete,
  }) {
    final startRot = transform.localRotation;
    return tween(
      0.0,
      1.0,
      duration: duration,
      curve: curve,
      delay: delay,
      pingPong: pingPong,
      loops: loops,
      unscaledTime: unscaledTime,
      onUpdate: (t) =>
          transform.localRotation = Quat.slerp(startRot, targetLocalRot, t),
      onComplete: onComplete,
    );
  }

  /// Tweens a [LinearColor] from [from] to [to] over [duration] seconds
  /// (P12-W20-D).
  Coroutine tweenColor(
    LinearColor from,
    LinearColor to, {
    required double duration,
    required void Function(LinearColor value) onUpdate,
    Curve curve = Curves.easeInOutQuad,
    double delay = 0.0,
    bool pingPong = false,
    int loops = 1,
    bool unscaledTime = false,
    void Function()? onComplete,
  }) => tween(
    0.0,
    1.0,
    duration: duration,
    curve: curve,
    delay: delay,
    pingPong: pingPong,
    loops: loops,
    unscaledTime: unscaledTime,
    onUpdate: (t) => onUpdate(
      LinearColor(
        from.r + (to.r - from.r) * t,
        from.g + (to.g - from.g) * t,
        from.b + (to.b - from.b) * t,
      ),
    ),
    onComplete: onComplete,
  );

  /// Executes a list of coroutine/tween step factories sequentially, awaiting
  /// each step via [WaitForCoroutine] before starting the next (P12-W20-D).
  Coroutine tweenSequence(
    List<Coroutine Function()> steps, {
    void Function()? onComplete,
  }) => startCoroutine(() sync* {
    for (final step in steps) {
      final co = step();
      yield WaitForCoroutine(co);
    }
    onComplete?.call();
  });
}
