/// Volition Studio Lighting Window Model (`[S3-E]`):
/// Pure-Dart model for editing `RenderPipelineSettings`, physical EV100
/// exposure / tonemapping, environment ambient & sky settings, and physical
/// light unit conversion helpers (lux, lumens, Kelvin).
library;

import 'dart:math' as math;

import 'package:pixeldart/rendering/api/lights.dart';
import 'package:pixeldart/rendering/api/settings.dart';
import 'package:pixeldart/rendering/passes/exposure.dart';

/// Physical light unit conversion utilities for the Light Inspector (`[S3-E]`).
abstract final class LightUnitHelper {
  /// Converts illuminance in lux (lm/m²) for a directional light into linear
  /// engine intensity (normalized around 100,000 lux ≈ bright noon sun = 10.0).
  static double luxToIntensity(double lux) => math.max(lux, 0.0) / 10000.0;

  /// Converts luminous flux in lumens (lm) for an isotropic point light into
  /// radiant intensity (`lumens / (4π)`, normalized by 100).
  static double lumensToPointIntensity(double lumens) =>
      math.max(lumens, 0.0) / (4.0 * math.pi * 100.0);

  /// Converts luminous flux in lumens for a spot light with outer half-angle
  /// `outerConeRadians` into radiant intensity (`lumens / (2π(1 - cos θ))`).
  static double lumensToSpotIntensity(double lumens, double outerConeRadians) {
    final solidAngle = math.max(
      2.0 * math.pi * (1.0 - math.cos(outerConeRadians)),
      1e-3,
    );
    return math.max(lumens, 0.0) / (solidAngle * 100.0);
  }

  /// Approximates correlated color temperature in Kelvin (`1000K..15000K`) as a
  /// linear RGB tint (Tanner Helland fit converted to linear).
  static LinearColor kelvinToLinearRgb(double kelvin) {
    final temp = kelvin.clamp(1000.0, 15000.0) / 100.0;
    double r, g, b;
    if (temp <= 66.0) {
      r = 1.0;
      g = (99.4708025861 * math.log(temp) - 161.1195681661) / 255.0;
      b = temp <= 19.0
          ? 0.0
          : (138.5177312231 * math.log(temp - 10.0) - 305.0447927307) / 255.0;
    } else {
      r = (329.698727446 * math.pow(temp - 60.0, -0.1332047592)) / 255.0;
      g = (288.1221695283 * math.pow(temp - 60.0, -0.0755148492)) / 255.0;
      b = 1.0;
    }
    double toLinear(double c) {
      final v = c.clamp(0.0, 1.0);
      return math.pow(v, 2.2).toDouble();
    }

    return LinearColor(toLinear(r), toLinear(g), toLinear(b));
  }
}

/// Pure-Dart view model for the Studio Lighting window (`[S3-E]`).
final class LightingWindowModel {
  RenderPipelineSettings pipelineSettings;
  ExposureSettings exposureSettings;
  LinearColor ambientColor;
  double ambientIntensity;
  LinearColor skyZenithColor;
  LinearColor skyHorizonColor;

  final List<void Function(LightingWindowModel)> _listeners = [];

  LightingWindowModel({
    RenderPipelineSettings? pipelineSettings,
    this.exposureSettings = const ExposureSettings(),
    this.ambientColor = const LinearColor(0.18, 0.22, 0.30),
    this.ambientIntensity = 0.45,
    this.skyZenithColor = const LinearColor(0.12, 0.28, 0.62),
    this.skyHorizonColor = const LinearColor(0.65, 0.78, 0.92),
  }) : pipelineSettings = pipelineSettings ?? RenderPipelineSettings.high;

  void addListener(void Function(LightingWindowModel) listener) {
    _listeners.add(listener);
  }

  void _notify() {
    for (final l in _listeners) {
      l(this);
    }
  }

  void setExposure({
    double? manualEv100,
    bool? autoExposureEnabled,
    VrpTonemapper? tonemapper,
    double? bloomThreshold,
    double? bloomIntensity,
  }) {
    exposureSettings = ExposureSettings(
      manualEv100: manualEv100 ?? exposureSettings.manualEv100,
      autoExposureEnabled:
          autoExposureEnabled ?? exposureSettings.autoExposureEnabled,
      minEv100: exposureSettings.minEv100,
      maxEv100: exposureSettings.maxEv100,
      adaptationSpeedUp: exposureSettings.adaptationSpeedUp,
      adaptationSpeedDown: exposureSettings.adaptationSpeedDown,
      bloomThreshold: bloomThreshold ?? exposureSettings.bloomThreshold,
      bloomKnee: exposureSettings.bloomKnee,
      bloomIntensity: bloomIntensity ?? exposureSettings.bloomIntensity,
      tonemapper: tonemapper ?? exposureSettings.tonemapper,
    );
    _notify();
  }

  void setAmbient(LinearColor color, double intensity) {
    ambientColor = color;
    ambientIntensity = intensity.clamp(0.0, 10.0);
    _notify();
  }

  void setSkyGradient(LinearColor zenith, LinearColor horizon) {
    skyZenithColor = zenith;
    skyHorizonColor = horizon;
    _notify();
  }

  void setPipelineSettings(RenderPipelineSettings next) {
    next.validate();
    pipelineSettings = next;
    _notify();
  }

  Map<String, Object?> toJson() => {
    'pipeline': pipelineSettings.toJson(),
    'exposure': {
      'manualEv100': exposureSettings.manualEv100,
      'autoExposureEnabled': exposureSettings.autoExposureEnabled,
      'tonemapper': exposureSettings.tonemapper.name,
      'bloomThreshold': exposureSettings.bloomThreshold,
      'bloomIntensity': exposureSettings.bloomIntensity,
    },
    'ambient': {
      'r': ambientColor.r,
      'g': ambientColor.g,
      'b': ambientColor.b,
      'intensity': ambientIntensity,
    },
  };
}
