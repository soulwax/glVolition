/// Pure-Dart Progressive Lightmapper (`[S4-C]`):
/// UV2 chart packing, deterministic seeded direct + 1-bounce indirect path
/// tracing, edge-aware A-trous denoising, and chart gutter dilation.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pixeldart/rendering/math/vec.dart';

/// A rectangular UV2 chart requested for lightmap atlas packing.
final class UvChart {
  final String id;
  final int width;
  final int height;

  const UvChart({required this.id, required this.width, required this.height});
}

/// A packed chart placement inside a lightmap atlas.
final class PackedUvChart {
  final String id;
  final int x;
  final int y;
  final int width;
  final int height;
  final int atlasSize;

  const PackedUvChart({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.atlasSize,
  });

  double get scaleU => width / atlasSize;
  double get scaleV => height / atlasSize;
  double get offsetU => x / atlasSize;
  double get offsetV => y / atlasSize;

  bool overlaps(PackedUvChart other) =>
      x < other.x + other.width &&
      x + width > other.x &&
      y < other.y + other.height &&
      y + height > other.y;
}

/// Deterministic shelf-based UV2 atlas packer (`[S4-C]`).
abstract final class UvAtlasPacker {
  static List<PackedUvChart> pack(
    List<UvChart> charts, {
    int atlasSize = 256,
    int padding = 2,
  }) {
    final sorted = [...charts]
      ..sort((a, b) {
        final byH = b.height.compareTo(a.height);
        if (byH != 0) return byH;
        final byW = b.width.compareTo(a.width);
        return byW != 0 ? byW : a.id.compareTo(b.id);
      });

    final out = <PackedUvChart>[];
    var cursorX = padding;
    var cursorY = padding;
    var rowHeight = 0;

    for (final c in sorted) {
      if (cursorX + c.width + padding > atlasSize) {
        cursorX = padding;
        cursorY += rowHeight + padding;
        rowHeight = 0;
      }
      if (cursorY + c.height + padding > atlasSize) {
        throw StateError(
          'UV2 chart "${c.id}" (${c.width}x${c.height}) does not fit in '
          '${atlasSize}x$atlasSize atlas',
        );
      }
      out.add(
        PackedUvChart(
          id: c.id,
          x: cursorX,
          y: cursorY,
          width: c.width,
          height: c.height,
          atlasSize: atlasSize,
        ),
      );
      cursorX += c.width + padding;
      if (c.height > rowHeight) rowHeight = c.height;
    }
    return out;
  }
}

/// Simple planar quad emitter/receiver for deterministic Cornell-box &
/// progressive lightmap baking tests.
final class BakeQuad {
  final Vec3 center;
  final Vec3 normal;
  final Vec3 tangentU;
  final Vec3 tangentV;
  final double halfWidth;
  final double halfHeight;
  final Vec3 albedo;
  final Vec3 emission;

  const BakeQuad({
    required this.center,
    required this.normal,
    required this.tangentU,
    required this.tangentV,
    required this.halfWidth,
    required this.halfHeight,
    required this.albedo,
    this.emission = Vec3.zero,
  });
}

/// Progressive pure-Dart lightmap baker with deterministic seeding, edge-aware
/// A-trous denoising, and gutter dilation (`[S4-C]`).
final class ProgressiveLightmapper {
  final int width;
  final int height;
  final int seed;
  final Float32List _accumRgb;
  int _passesCompleted = 0;

  ProgressiveLightmapper({
    required this.width,
    required this.height,
    this.seed = 42,
  }) : _accumRgb = Float32List(width * height * 3);

  int get passesCompleted => _passesCompleted;

  /// Bakes one progressive direct + 1-bounce indirect pass onto [receiver]
  /// illuminated by [emitters] and bounce [surfaces].
  void stepPass({
    required BakeQuad receiver,
    required List<BakeQuad> emitters,
    List<BakeQuad> bounceSurfaces = const [],
    int samplesPerTexel = 4,
  }) {
    final rng = math.Random(seed + _passesCompleted * 7919);
    for (var ty = 0; ty < height; ty++) {
      final v = ((ty + 0.5) / height) * 2.0 - 1.0;
      for (var tx = 0; tx < width; tx++) {
        final u = ((tx + 0.5) / width) * 2.0 - 1.0;
        final worldPos =
            receiver.center +
            receiver.tangentU * (u * receiver.halfWidth) +
            receiver.tangentV * (v * receiver.halfHeight);
        final n = receiver.normal.normalized;

        var r = receiver.emission.x;
        var g = receiver.emission.y;
        var b = receiver.emission.z;

        // Direct lighting from area emitters
        for (final em in emitters) {
          for (var s = 0; s < samplesPerTexel; s++) {
            final eu = (rng.nextDouble() * 2.0 - 1.0) * em.halfWidth;
            final ev = (rng.nextDouble() * 2.0 - 1.0) * em.halfHeight;
            final emPos = em.center + em.tangentU * eu + em.tangentV * ev;
            final toEm = emPos - worldPos;
            final distSq = math.max(toEm.lengthSquared, 1e-4);
            final dir = toEm * (1.0 / math.sqrt(distSq));
            final ndotl = math.max(n.dot(dir), 0.0);
            final emDot = math.max(em.normal.normalized.dot(-dir), 0.0);
            final area = (em.halfWidth * 2.0) * (em.halfHeight * 2.0);
            final factor =
                (ndotl * emDot * area) / (math.pi * distSq * samplesPerTexel);
            r += em.emission.x * receiver.albedo.x * factor;
            g += em.emission.y * receiver.albedo.y * factor;
            b += em.emission.z * receiver.albedo.z * factor;
          }
        }

        // One-bounce indirect diffuse contribution from bounce surfaces
        for (final surf in bounceSurfaces) {
          final toSurf = surf.center - worldPos;
          final distSq = math.max(toSurf.lengthSquared, 0.25);
          final dir = toSurf * (1.0 / math.sqrt(distSq));
          final ndotl = math.max(n.dot(dir), 0.0);
          final factor = (ndotl * 0.15) / (1.0 + distSq);
          r += surf.albedo.x * receiver.albedo.x * factor;
          g += surf.albedo.y * receiver.albedo.y * factor;
          b += surf.albedo.z * receiver.albedo.z * factor;
        }

        final idx = (ty * width + tx) * 3;
        _accumRgb[idx + 0] += r;
        _accumRgb[idx + 1] += g;
        _accumRgb[idx + 2] += b;
      }
    }
    _passesCompleted++;
  }

  /// Resolves the averaged RGB lightmap buffer.
  Float32List resolve() {
    final out = Float32List(_accumRgb.length);
    if (_passesCompleted == 0) return out;
    final inv = 1.0 / _passesCompleted;
    for (var i = 0; i < out.length; i++) {
      out[i] = _accumRgb[i] * inv;
    }
    return out;
  }

  /// Edge-aware 3x3 A-trous wavelet denoise pass preserving sharp luminance
  /// discontinuities.
  static Float32List denoiseAtrous(
    Float32List rgb,
    int width,
    int height, {
    int stepSize = 1,
    double colorSigma = 0.25,
  }) {
    final out = Float32List(rgb.length);
    const kernel = <double>[0.25, 0.5, 0.25];
    final invSigma2 = 1.0 / math.max(colorSigma * colorSigma, 1e-5);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final ci = (y * width + x) * 3;
        final cr = rgb[ci + 0];
        final cg = rgb[ci + 1];
        final cb = rgb[ci + 2];

        var sr = 0.0, sg = 0.0, sb = 0.0, wSum = 0.0;
        for (var ky = -1; ky <= 1; ky++) {
          final sy = (y + ky * stepSize).clamp(0, height - 1);
          for (var kx = -1; kx <= 1; kx++) {
            final sx = (x + kx * stepSize).clamp(0, width - 1);
            final si = (sy * width + sx) * 3;
            final nr = rgb[si + 0];
            final ng = rgb[si + 1];
            final nb = rgb[si + 2];
            final diff2 =
                (nr - cr) * (nr - cr) +
                (ng - cg) * (ng - cg) +
                (nb - cb) * (nb - cb);
            final w =
                kernel[kx + 1] * kernel[ky + 1] * math.exp(-diff2 * invSigma2);
            sr += nr * w;
            sg += ng * w;
            sb += nb * w;
            wSum += w;
          }
        }
        final invW = wSum > 1e-6 ? 1.0 / wSum : 1.0;
        out[ci + 0] = sr * invW;
        out[ci + 1] = sg * invW;
        out[ci + 2] = sb * invW;
      }
    }
    return out;
  }

  /// Dilates non-empty chart pixels into adjacent empty gutter pixels to
  /// prevent bilinear seam bleeding.
  static Float32List dilateGutter(
    Float32List rgb,
    Uint8List coverageMask,
    int width,
    int height,
  ) {
    final out = Float32List.fromList(rgb);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pi = y * width + x;
        if (coverageMask[pi] != 0) continue;
        var sr = 0.0, sg = 0.0, sb = 0.0, count = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= width) continue;
            final npi = ny * width + nx;
            if (coverageMask[npi] != 0) {
              sr += rgb[npi * 3 + 0];
              sg += rgb[npi * 3 + 1];
              sb += rgb[npi * 3 + 2];
              count++;
            }
          }
        }
        if (count > 0) {
          out[pi * 3 + 0] = sr / count;
          out[pi * 3 + 1] = sg / count;
          out[pi * 3 + 2] = sb / count;
        }
      }
    }
    return out;
  }
}
