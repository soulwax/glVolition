part of '../../engine.dart';

/// Global or spatial post-processing volume that blends exposure, bloom, SSAO,
/// vignette, film grain, depth of field, and tone mapping into
/// `scene.renderSettings.post` (E8-2).
///
/// When [isGlobal] is `true`, [weight] (`0..1`) applies everywhere in the scene.
/// When [isGlobal] is `false`, the volume applies inside [radius] around its
/// `transform.position` and feathers smoothly over [blendDistance].
final class PostProcessVolume extends Behaviour {
  bool isGlobal;
  double radius;
  double blendDistance;
  double weight;
  int priority;

  double exposure;
  double bloomStrength;
  double ssaoStrength;
  double vignette;
  double grain;
  double depthOfFieldStrength;
  double ditherStrength;
  double colorGradeStrength;
  double chromaticAberration;
  ToneMappingMode toneMapping;

  PostProcessVolume({
    this.isGlobal = true,
    this.radius = 16.0,
    this.blendDistance = 4.0,
    this.weight = 1.0,
    this.priority = 0,
    this.exposure = 1.0,
    this.bloomStrength = 0.25,
    this.ssaoStrength = 0.0,
    this.vignette = 0.0,
    this.grain = 0.0,
    this.depthOfFieldStrength = 0.0,
    this.ditherStrength = 0.0,
    this.colorGradeStrength = 0.0,
    this.chromaticAberration = 0.0,
    this.toneMapping = ToneMappingMode.aces,
  });

  /// Factory creating a retro CRT / VHS stylized aesthetic volume (E22-2).
  factory PostProcessVolume.retro({
    bool isGlobal = true,
    double weight = 1.0,
    double grain = 0.4,
    double vignette = 0.35,
    double dither = 0.5,
    double chromaticAberration = 0.3,
  }) => PostProcessVolume(
    isGlobal: isGlobal,
    weight: weight,
    grain: grain,
    vignette: vignette,
    ditherStrength: dither,
    chromaticAberration: chromaticAberration,
    bloomStrength: 0.3,
  );

  /// Factory creating a cinematic high-contrast dramatic volume (E22-2).
  factory PostProcessVolume.cinematic({
    bool isGlobal = true,
    double weight = 1.0,
    double exposure = 1.15,
    double bloomStrength = 0.45,
    double ssaoStrength = 0.6,
    double vignette = 0.2,
  }) => PostProcessVolume(
    isGlobal: isGlobal,
    weight: weight,
    exposure: exposure,
    bloomStrength: bloomStrength,
    ssaoStrength: ssaoStrength,
    vignette: vignette,
    toneMapping: ToneMappingMode.aces,
  );

  static final spec = ComponentSpec<PostProcessVolume>(
    'PostProcessVolume',
    PostProcessVolume.new,
    [
      Field.boolean(
        'isGlobal',
        (v) => v.isGlobal,
        (v, val) => v.isGlobal = val,
      ),
      Field.number('radius', (v) => v.radius, (v, val) => v.radius = val),
      Field.number(
        'blendDistance',
        (v) => v.blendDistance,
        (v, val) => v.blendDistance = val,
      ),
      Field.number('weight', (v) => v.weight, (v, val) => v.weight = val),
      Field.integer(
        'priority',
        (v) => v.priority,
        (v, val) => v.priority = val,
      ),
      Field.number('exposure', (v) => v.exposure, (v, val) => v.exposure = val),
      Field.number(
        'bloomStrength',
        (v) => v.bloomStrength,
        (v, val) => v.bloomStrength = val,
      ),
      Field.number(
        'ssaoStrength',
        (v) => v.ssaoStrength,
        (v, val) => v.ssaoStrength = val,
      ),
      Field.number('vignette', (v) => v.vignette, (v, val) => v.vignette = val),
      Field.number('grain', (v) => v.grain, (v, val) => v.grain = val),
      Field.number(
        'depthOfFieldStrength',
        (v) => v.depthOfFieldStrength,
        (v, val) => v.depthOfFieldStrength = val,
      ),
      Field.number(
        'ditherStrength',
        (v) => v.ditherStrength,
        (v, val) => v.ditherStrength = val,
      ),
      Field.number(
        'colorGradeStrength',
        (v) => v.colorGradeStrength,
        (v, val) => v.colorGradeStrength = val,
      ),
      Field.number(
        'chromaticAberration',
        (v) => v.chromaticAberration,
        (v, val) => v.chromaticAberration = val,
      ),
      Field.enumValue<PostProcessVolume, ToneMappingMode>(
        'toneMapping',
        ToneMappingMode.values,
        (v) => v.toneMapping,
        (v, val) => v.toneMapping = val,
      ),
    ],
  );

  /// Computes the effective blend factor `0..1` for a camera/listener at [observerPos].
  double evaluateWeight(Vec3 observerPos) {
    final baseW = weight.clamp(0.0, 1.0);
    if (baseW <= 0) return 0.0;
    if (isGlobal) return baseW;

    final dist = (observerPos - transform.position).length;
    if (dist <= radius) return baseW;
    final feather = math.max(0.001, blendDistance);
    if (dist >= radius + feather) return 0.0;
    final t = 1.0 - (dist - radius) / feather;
    return baseW * t.clamp(0.0, 1.0);
  }

  /// Blends this volume's parameters onto [current] with factor [alpha] (`0..1`).
  PostProcessState blendOnto(PostProcessState current, double alpha) {
    final a = alpha.clamp(0.0, 1.0);
    if (a <= 0) return current;
    double mix(double from, double to) => from + (to - from) * a;
    return current.copyWith(
      exposure: mix(current.exposure, exposure),
      bloomStrength: mix(current.bloomStrength, bloomStrength),
      ssaoStrength: mix(current.ssaoStrength, ssaoStrength),
      vignette: mix(current.vignette, vignette),
      grain: mix(current.grain, grain),
      depthOfFieldStrength: mix(
        current.depthOfFieldStrength,
        depthOfFieldStrength,
      ),
      ditherStrength: mix(current.ditherStrength, ditherStrength),
      colorGradeStrength: mix(current.colorGradeStrength, colorGradeStrength),
      vhsChromaWeight: mix(current.vhsChromaWeight, chromaticAberration),
      toneMapping: a >= 0.5 ? toneMapping : current.toneMapping,
    );
  }

  @override
  void lateUpdate() {
    final cam = Camera.of(scene);
    final observerPos = cam != null ? cam.transform.position : Vec3.zero;
    final w = evaluateWeight(observerPos);
    if (w > 0) {
      scene.renderSettings.post = blendOnto(scene.renderSettings.post, w);
    }
  }
}

/// Global or localized VRP v2 post-processing volume component (`[S4-D]`).
final class PostProcessVolumeComponent extends Component {
  bool isGlobal;
  double priority;
  double weight;
  double blendDistance;
  Vec3 size;
  PostProcessVolumeProfile profile;

  PostProcessVolumeComponent({
    this.isGlobal = true,
    this.priority = 0.0,
    this.weight = 1.0,
    this.blendDistance = 2.0,
    this.size = const Vec3(10, 10, 10),
    this.profile = const PostProcessVolumeProfile(),
  });

  /// Effective blend factor `[0, 1]` at [cameraPos].
  double effectiveWeightAt(Vec3 cameraPos) {
    if (!isActiveAndEnabled || weight <= 0.0) return 0.0;
    if (isGlobal) return weight.clamp(0.0, 1.0);
    final center = isAttached ? transform.position : Vec3.zero;
    final half = size * 0.5;
    final rel = cameraPos - center;
    final dx = rel.x.abs() - half.x;
    final dy = rel.y.abs() - half.y;
    final dz = rel.z.abs() - half.z;
    final outside = math.max(dx, math.max(dy, dz));
    if (outside <= 0.0) return weight.clamp(0.0, 1.0);
    if (blendDistance <= 1e-5 || outside >= blendDistance) return 0.0;
    return ((1.0 - outside / blendDistance) * weight).clamp(0.0, 1.0);
  }

  /// Evaluates the blended [PostProcessVolumeProfile] across all active volumes
  /// sorted by ascending [priority].
  static PostProcessVolumeProfile evaluateStack(
    Vec3 cameraPos,
    Iterable<PostProcessVolumeComponent> volumes, {
    PostProcessVolumeProfile base = PostProcessVolumeProfile.defaults,
  }) {
    final sorted = volumes.where((v) => v.isActiveAndEnabled).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    var current = base;
    for (final v in sorted) {
      final w = v.effectiveWeightAt(cameraPos);
      if (w > 0.0) {
        current = current.blendWith(v.profile, w);
      }
    }
    return current;
  }

  static final spec = ComponentSpec<PostProcessVolumeComponent>(
    'PostProcessVolumeComponent',
    PostProcessVolumeComponent.new,
    [
      Field.boolean('isGlobal', (c) => c.isGlobal, (c, v) => c.isGlobal = v),
      Field.number('priority', (c) => c.priority, (c, v) => c.priority = v),
      Field.number('weight', (c) => c.weight, (c, v) => c.weight = v),
      Field.number(
        'blendDistance',
        (c) => c.blendDistance,
        (c, v) => c.blendDistance = v,
      ),
      Field.vec3('size', (c) => c.size, (c, v) => c.size = v),
    ],
  );
}
