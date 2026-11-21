part of '../../engine.dart';

/// Update mode for a [ReflectionProbeComponent] (`[S4-B]`).
enum ReflectionProbeMode { baked, onDemand, realtime }

/// Localized specular IBL reflection probe with box projection and priority
/// blending (`[S4-B]`).
final class ReflectionProbeComponent extends Component {
  ReflectionProbeMode mode;
  Vec3 size;
  bool boxProjection;
  double blendDistance;
  int importance;
  int resolution;
  double intensity;
  String cubemapGuid;

  ReflectionProbeComponent({
    this.mode = ReflectionProbeMode.baked,
    this.size = const Vec3(10, 10, 10),
    this.boxProjection = true,
    this.blendDistance = 1.0,
    this.importance = 1,
    this.resolution = 128,
    this.intensity = 1.0,
    this.cubemapGuid = '',
  });

  Vec3 get worldCenter => isAttached ? transform.position : Vec3.zero;
  Vec3 get boxMin => worldCenter - size * 0.5;
  Vec3 get boxMax => worldCenter + size * 0.5;

  /// Returns blend weight in `[0, 1]` for [worldPos] inside this probe's box
  /// (expanded by [blendDistance]). Returns `0` when outside.
  double weightAt(Vec3 worldPos) {
    final half = size * 0.5;
    final rel = worldPos - worldCenter;
    final dx = rel.x.abs() - half.x;
    final dy = rel.y.abs() - half.y;
    final dz = rel.z.abs() - half.z;
    final maxOutside = math.max(dx, math.max(dy, dz));
    if (maxOutside <= 0.0) return 1.0;
    if (blendDistance <= 1e-5 || maxOutside >= blendDistance) return 0.0;
    return (1.0 - maxOutside / blendDistance).clamp(0.0, 1.0);
  }

  /// Computes parallax-corrected box-projected reflection direction from
  /// [worldPos] along unit reflection vector [reflDir].
  Vec3 boxProject(Vec3 worldPos, Vec3 reflDir) {
    if (!boxProjection) return reflDir.normalized;
    final d = reflDir.normalized;
    final bMin = boxMin;
    final bMax = boxMax;

    double axisT(double origin, double dir, double minB, double maxB) {
      if (dir.abs() < 1e-6) return double.infinity;
      final t1 = (minB - origin) / dir;
      final t2 = (maxB - origin) / dir;
      return math.max(t1, t2);
    }

    final tx = axisT(worldPos.x, d.x, bMin.x, bMax.x);
    final ty = axisT(worldPos.y, d.y, bMin.y, bMax.y);
    final tz = axisT(worldPos.z, d.z, bMin.z, bMax.z);
    final dist = math.min(tx, math.min(ty, tz));
    if (!dist.isFinite || dist <= 0.0) return d;
    final hit = worldPos + d * dist;
    return (hit - worldCenter).normalized;
  }

  static final spec = ComponentSpec<ReflectionProbeComponent>(
    'ReflectionProbeComponent',
    ReflectionProbeComponent.new,
    [
      Field.enumValue<ReflectionProbeComponent, ReflectionProbeMode>(
        'mode',
        ReflectionProbeMode.values,
        (c) => c.mode,
        (c, v) => c.mode = v,
      ),
      Field.vec3('size', (c) => c.size, (c, v) => c.size = v),
      Field.boolean(
        'boxProjection',
        (c) => c.boxProjection,
        (c, v) => c.boxProjection = v,
      ),
      Field.number(
        'blendDistance',
        (c) => c.blendDistance,
        (c, v) => c.blendDistance = v,
      ),
      Field.integer(
        'importance',
        (c) => c.importance,
        (c, v) => c.importance = v,
      ),
      Field.integer(
        'resolution',
        (c) => c.resolution,
        (c, v) => c.resolution = v,
      ),
      Field.number('intensity', (c) => c.intensity, (c, v) => c.intensity = v),
      Field.text(
        'cubemapGuid',
        (c) => c.cubemapGuid,
        (c, v) => c.cubemapGuid = v,
      ),
    ],
  );
}

/// Result of selecting up to two overlapping reflection probes for a renderer.
final class BlendedReflectionProbes {
  final ReflectionProbeComponent? primary;
  final double primaryWeight;
  final ReflectionProbeComponent? secondary;
  final double secondaryWeight;

  const BlendedReflectionProbes({
    this.primary,
    this.primaryWeight = 0.0,
    this.secondary,
    this.secondaryWeight = 0.0,
  });
}

/// Selects and blends the top two overlapping [ReflectionProbeComponent]s at a
/// given world position by importance and proximity (`[S4-B]`).
abstract final class ReflectionProbeBlender {
  static BlendedReflectionProbes selectForPosition(
    Vec3 worldPos,
    Iterable<ReflectionProbeComponent> probes,
  ) {
    final candidates = <({ReflectionProbeComponent probe, double weight})>[];
    for (final p in probes) {
      if (!p.isActiveAndEnabled) continue;
      final w = p.weightAt(worldPos);
      if (w > 0.0) {
        candidates.add((probe: p, weight: w));
      }
    }
    if (candidates.isEmpty) return const BlendedReflectionProbes();

    candidates.sort((a, b) {
      final byImp = b.probe.importance.compareTo(a.probe.importance);
      if (byImp != 0) return byImp;
      return b.weight.compareTo(a.weight);
    });

    final first = candidates[0];
    if (candidates.length == 1) {
      return BlendedReflectionProbes(
        primary: first.probe,
        primaryWeight: first.weight,
      );
    }
    final second = candidates[1];
    final sum = first.weight + second.weight;
    final w0 = sum > 1.0 ? first.weight / sum : first.weight;
    final w1 = sum > 1.0 ? second.weight / sum : second.weight;
    return BlendedReflectionProbes(
      primary: first.probe,
      primaryWeight: w0,
      secondary: second.probe,
      secondaryWeight: w1,
    );
  }
}
