/// S7-A: Animator Controller Asset & 1D Blend Tree Model (`voxanim`,
/// `voxblend`, `voxseq`, `voxcurve`, `voxtween`).
library;

/// Conditional transition between two Animator Controller states.
final class AnimatorTransitionDef {
  final String fromState;
  final String toState;
  final String parameter;
  final double greaterThan;
  final double crossFadeSeconds;

  const AnimatorTransitionDef({
    required this.fromState,
    required this.toState,
    required this.parameter,
    required this.greaterThan,
    this.crossFadeSeconds = 0.15,
  });
}

/// 1D Blend Tree entry mapping a clip GUID to a threshold value.
final class BlendTree1DEntry {
  final String clipGuid;
  final double threshold;

  const BlendTree1DEntry({required this.clipGuid, required this.threshold});
}

/// Pure-Dart Animator Controller state machine + 1D blend tree model (`[S7-A]`).
final class AnimatorControllerModel {
  final String name;
  final List<String> states;
  final List<AnimatorTransitionDef> transitions;
  final Map<String, double> parameters;
  String activeState;

  AnimatorControllerModel({
    required this.name,
    required this.states,
    this.transitions = const [],
    Map<String, double>? parameters,
    String? initialState,
  }) : parameters = parameters != null ? Map.of(parameters) : {},
       activeState = initialState ?? (states.isNotEmpty ? states.first : '');

  /// Evaluates transitions from [activeState] against current [parameters] and
  /// returns the resulting active state (for live play-mode highlighting).
  String evaluateStep() {
    for (final tr in transitions) {
      if (tr.fromState == activeState) {
        final v = parameters[tr.parameter] ?? 0.0;
        if (v > tr.greaterThan) {
          activeState = tr.toState;
          break;
        }
      }
    }
    return activeState;
  }

  /// Evaluates normalized 1D blend tree weights for [paramValue].
  static Map<String, double> evaluateBlendTree1D(
    List<BlendTree1DEntry> entries,
    double paramValue,
  ) {
    if (entries.isEmpty) return const {};
    final sorted = [...entries]
      ..sort((a, b) => a.threshold.compareTo(b.threshold));
    if (paramValue <= sorted.first.threshold) {
      return {sorted.first.clipGuid: 1.0};
    }
    if (paramValue >= sorted.last.threshold) {
      return {sorted.last.clipGuid: 1.0};
    }
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (paramValue >= a.threshold && paramValue <= b.threshold) {
        final span = b.threshold - a.threshold;
        final t = span <= 1e-6 ? 0.0 : (paramValue - a.threshold) / span;
        return {a.clipGuid: 1.0 - t, b.clipGuid: t};
      }
    }
    return {sorted.last.clipGuid: 1.0};
  }
}
