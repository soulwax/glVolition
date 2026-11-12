/// Digital logic node kind supported by [CircuitGraphSolver].
enum CircuitGateKind {
  inputToggle,
  constantHigh,
  constantLow,
  and,
  or,
  xor,
  nand,
  nor,
  not,
  buffer,
  srLatch,
  dFlipFlop,
  clockPulse,
  outputLamp,
  splitterBus,
}

/// Terminal pin metadata on a digital logic gate.
final class CircuitPin {
  final String id;
  final String name;
  final bool isOutput;
  bool signal;
  int busValue;

  CircuitPin({
    required this.id,
    required this.name,
    this.isOutput = false,
    this.signal = false,
    this.busValue = 0,
  });
}

/// Immutable gate definition registered in a circuit graph.
final class CircuitGateDef {
  final String id;
  final CircuitGateKind kind;
  final String label;
  final int inputCount;
  final int outputCount;
  final int propagationDelayTicks;
  final int clockHalfPeriodTicks;
  final bool initialOutput;

  const CircuitGateDef({
    required this.id,
    required this.kind,
    this.label = '',
    this.inputCount = 2,
    this.outputCount = 1,
    this.propagationDelayTicks = 1,
    this.clockHalfPeriodTicks = 2,
    this.initialOutput = false,
  });

  factory CircuitGateDef.input(String id, {String label = '', bool initial = false}) =>
      CircuitGateDef(
        id: id,
        kind: CircuitGateKind.inputToggle,
        label: label.isEmpty ? id : label,
        inputCount: 0,
        outputCount: 1,
        propagationDelayTicks: 0,
        initialOutput: initial,
      );

  factory CircuitGateDef.gate(
    String id,
    CircuitGateKind kind, {
    String label = '',
    int inputCount = 2,
    int outputCount = 1,
    int propagationDelayTicks = 1,
  }) =>
      CircuitGateDef(
        id: id,
        kind: kind,
        label: label.isEmpty ? id : label,
        inputCount: inputCount,
        outputCount: outputCount,
        propagationDelayTicks: propagationDelayTicks,
      );

  factory CircuitGateDef.clock(
    String id, {
    int halfPeriodTicks = 2,
    String label = '',
  }) =>
      CircuitGateDef(
        id: id,
        kind: CircuitGateKind.clockPulse,
        label: label.isEmpty ? id : label,
        inputCount: 1,
        outputCount: 1,
        propagationDelayTicks: 0,
        clockHalfPeriodTicks: halfPeriodTicks,
      );

  factory CircuitGateDef.lamp(String id, {String label = ''}) => CircuitGateDef(
        id: id,
        kind: CircuitGateKind.outputLamp,
        label: label.isEmpty ? id : label,
        inputCount: 1,
        outputCount: 1,
        propagationDelayTicks: 1,
      );
}

/// Directed wire linking an upstream output pin to a downstream input pin.
final class CircuitWire {
  final String id;
  final String fromGateId;
  final int fromPinIndex;
  final String toGateId;
  final int toPinIndex;
  final int delayTicks;

  const CircuitWire({
    required this.id,
    required this.fromGateId,
    required this.fromPinIndex,
    required this.toGateId,
    required this.toPinIndex,
    this.delayTicks = 0,
  });
}
