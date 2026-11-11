part of '../engine.dart';

const LinearColor kColorRed = LinearColor(1, 0, 0);
const LinearColor kColorGreen = LinearColor(0, 1, 0);
const LinearColor kColorBlue = LinearColor(0, 0, 1);
const LinearColor kColorYellow = LinearColor(1, 1, 0);
const LinearColor kColorCyan = LinearColor(0, 1, 1);
const LinearColor kColorMagenta = LinearColor(1, 0, 1);
const LinearColor kColorOrange = LinearColor(1, 0.5, 0);
const LinearColor kColorPurple = LinearColor(0.5, 0, 1);

/// Color utility extensions for [LinearColor] (E26-2).
extension LinearColorExt on LinearColor {
  /// Linearly interpolates between this color and [other] by parameter [t] (`0..1`).
  LinearColor lerp(LinearColor other, double t) {
    final clamped = t.clamp(0.0, 1.0);
    return LinearColor(
      r + (other.r - r) * clamped,
      g + (other.g - g) * clamped,
      b + (other.b - b) * clamped,
    );
  }

  /// Scales color components by [factor].
  LinearColor withIntensity(double factor) =>
      LinearColor(r * factor, g * factor, b * factor);

  /// Converts this color to an integer packed 32-bit RGBA color (`0xRRGGBBAA`).
  int toRgba([double alpha = 1.0]) {
    final ir = (r.clamp(0.0, 1.0) * 255.0).round();
    final ig = (g.clamp(0.0, 1.0) * 255.0).round();
    final ib = (b.clamp(0.0, 1.0) * 255.0).round();
    final ia = (alpha.clamp(0.0, 1.0) * 255.0).round();
    return (ir << 24) | (ig << 16) | (ib << 8) | ia;
  }

  /// Converts this color to an integer packed 32-bit ARGB color (`0xAARRGGBB`).
  int toArgb([double alpha = 1.0]) {
    final ir = (r.clamp(0.0, 1.0) * 255.0).round();
    final ig = (g.clamp(0.0, 1.0) * 255.0).round();
    final ib = (b.clamp(0.0, 1.0) * 255.0).round();
    final ia = (alpha.clamp(0.0, 1.0) * 255.0).round();
    return (ia << 24) | (ir << 16) | (ig << 8) | ib;
  }

  /// Converts this color to a `#RRGGBB` hex string.
  String toHex() {
    final ir = (r.clamp(0.0, 1.0) * 255.0).round().toRadixString(16).padLeft(2, '0');
    final ig = (g.clamp(0.0, 1.0) * 255.0).round().toRadixString(16).padLeft(2, '0');
    final ib = (b.clamp(0.0, 1.0) * 255.0).round().toRadixString(16).padLeft(2, '0');
    return '#$ir$ig$ib'.toUpperCase();
  }

  /// Converts this color to HSV `(hue: 0..360, saturation: 0..1, value: 0..1)`.
  ({double h, double s, double v}) toHsv() {
    final cr = r.clamp(0.0, 1.0);
    final cg = g.clamp(0.0, 1.0);
    final cb = b.clamp(0.0, 1.0);

    final maxVal = math.max(cr, math.max(cg, cb));
    final minVal = math.min(cr, math.min(cg, cb));
    final delta = maxVal - minVal;

    var h = 0.0;
    if (delta > 1e-5) {
      if (maxVal == cr) {
        h = 60.0 * (((cg - cb) / delta) % 6);
      } else if (maxVal == cg) {
        h = 60.0 * (((cb - cr) / delta) + 2);
      } else {
        h = 60.0 * (((cr - cg) / delta) + 4);
      }
      if (h < 0.0) h += 360.0;
    }

    final s = maxVal <= 1e-5 ? 0.0 : delta / maxVal;
    return (h: h, s: s, v: maxVal);
  }
}

/// Parses a hex color string (e.g. `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `0xRRGGBB`) into a [LinearColor].
LinearColor linearColorFromHex(String hex) {
  var clean = hex.trim().replaceFirst('#', '').replaceFirst('0x', '');
  if (clean.length == 3) {
    clean = '${clean[0]}${clean[0]}${clean[1]}${clean[1]}${clean[2]}${clean[2]}';
  }
  if (clean.length >= 6) {
    final r = int.parse(clean.substring(0, 2), radix: 16) / 255.0;
    final g = int.parse(clean.substring(2, 4), radix: 16) / 255.0;
    final b = int.parse(clean.substring(4, 6), radix: 16) / 255.0;
    return LinearColor(r, g, b);
  }
  return LinearColor.white;
}

/// Creates a [LinearColor] from HSV coordinates `(h in 0..360, s in 0..1, v in 0..1)`.
LinearColor linearColorFromHsv(double h, double s, double v) {
  final clampedH = (h % 360.0 + 360.0) % 360.0;
  final clampedS = s.clamp(0.0, 1.0);
  final clampedV = v.clamp(0.0, 1.0);

  final c = clampedV * clampedS;
  final x = c * (1.0 - ((clampedH / 60.0) % 2 - 1.0).abs());
  final m = clampedV - c;

  double r1 = 0, g1 = 0, b1 = 0;
  if (clampedH < 60) {
    r1 = c;
    g1 = x;
  } else if (clampedH < 120) {
    r1 = x;
    g1 = c;
  } else if (clampedH < 180) {
    g1 = c;
    b1 = x;
  } else if (clampedH < 240) {
    g1 = x;
    b1 = c;
  } else if (clampedH < 300) {
    r1 = x;
    b1 = c;
  } else {
    r1 = c;
    b1 = x;
  }

  return LinearColor(r1 + m, g1 + m, b1 + m);
}
