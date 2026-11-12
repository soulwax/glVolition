import 'dart:collection';
import 'dart:math' as math;

import 'types.dart';

final class _GateRuntime {
  final CircuitGateDef def;
  final List<CircuitPin> inputs;
  final List<CircuitPin> outputs;
  final Queue<({List<bool> signals, List<int> buses})> _pipeline = Queue();

  bool manualState;
  int manualBusValue = 0;
  bool prevClock = false;
  bool storedQ = false;
  int clockCounter = 0;

  _GateRuntime(this.def)
      : manualState = def.initialOutput,
        storedQ = def.initialOutput,
        inputs = List<CircuitPin>.generate(
          def.inputCount,
          (i) => CircuitPin(id: '${def.id}_in$i', name: 'in$i', isOutput: false),
        ),
        outputs = List<CircuitPin>.generate(
          def.outputCount,
          (i) => CircuitPin(
            id: '${def.id}_out$i',
            name: 'out$i',
            isOutput: true,
            signal: i == 0 ? def.initialOutput : (def.kind == CircuitGateKind.srLatch || def.kind == CircuitGateKind.dFlipFlop ? !def.initialOutput : false),
          ),
        );

  void reset() {
    manualState = def.initialOutput;
    manualBusValue = 0;
    prevClock = false;
    storedQ = def.initialOutput;
    clockCounter = 0;
    _pipeline.clear();
    for (final p in inputs) {
      p.signal = false;
      p.busValue = 0;
    }
    for (var i = 0; i < outputs.length; i++) {
      outputs[i].signal = i == 0
          ? def.initialOutput
          : (def.kind == CircuitGateKind.srLatch || def.kind == CircuitGateKind.dFlipFlop
              ? !def.initialOutput
              : false);
      outputs[i].busValue = 0;
    }
  }
}

final class _WireRuntime {
  final CircuitWire wire;
  final Queue<({bool signal, int bus})> pipeline = Queue();

  _WireRuntime(this.wire);

  ({bool signal, int bus}) advance(({bool signal, int bus}) sample) {
    if (wire.delayTicks <= 0) return sample;
    pipeline.addLast(sample);
    while (pipeline.length <= wire.delayTicks) {
      return (signal: false, bus: 0);
    }
    return pipeline.removeFirst();
  }
}

/// Deterministic discrete-tick solver for cyclic & combinational logic circuits.
final class CircuitGraphSolver {
  final Map<String, _GateRuntime> _gates = {};
  final List<_WireRuntime> _wires = [];
  int _tickCount = 0;
  int _wireAutoId = 0;

  int get tickCount => _tickCount;
  int get gateCount => _gates.length;
  int get wireCount => _wires.length;

  Iterable<CircuitGateDef> get gateDefs => _gates.values.map((g) => g.def);
  Iterable<CircuitWire> get wires => _wires.map((w) => w.wire);

  int get activeHighGates {
    var count = 0;
    for (final g in _gates.values) {
      if (g.outputs.isNotEmpty && g.outputs.first.signal) {
        count++;
      }
    }
    return count;
  }

  void addGate(CircuitGateDef def) {
    _gates[def.id] = _GateRuntime(def);
  }

  void connect(
    String fromGateId,
    int fromPinIndex,
    String toGateId,
    int toPinIndex, {
    String? wireId,
    int delayTicks = 0,
  }) {
    final wire = CircuitWire(
      id: wireId ?? 'w_${_wireAutoId++}',
      fromGateId: fromGateId,
      fromPinIndex: fromPinIndex,
      toGateId: toGateId,
      toPinIndex: toPinIndex,
      delayTicks: delayTicks,
    );
    _wires.add(_WireRuntime(wire));
    final dst = _gates[toGateId];
    if (dst != null && toPinIndex >= 0 && toPinIndex < dst.inputs.length) {
      dst.inputs[toPinIndex].isDriven = true;
    }
  }

  void setInput(String gateId, bool value, {int busValue = 0}) {
    final g = _gates[gateId];
    if (g == null) return;
    g.manualState = value;
    g.manualBusValue = busValue;
    if (g.def.kind == CircuitGateKind.inputToggle && g.outputs.isNotEmpty) {
      g.outputs[0].signal = value;
      g.outputs[0].busValue = busValue != 0 ? busValue : (value ? 1 : 0);
    }
  }

  bool toggleInput(String gateId) {
    final g = _gates[gateId];
    if (g == null) return false;
    final next = !g.manualState;
    setInput(gateId, next, busValue: next ? 1 : 0);
    return next;
  }

  bool readOutput(String gateId, {int pinIndex = 0}) {
    final g = _gates[gateId];
    if (g == null || pinIndex < 0 || pinIndex >= g.outputs.length) return false;
    return g.outputs[pinIndex].signal;
  }

  int readBusOutput(String gateId, {int pinIndex = 0}) {
    final g = _gates[gateId];
    if (g == null || pinIndex < 0 || pinIndex >= g.outputs.length) return 0;
    return g.outputs[pinIndex].busValue;
  }

  List<bool> readInputs(String gateId) {
    final g = _gates[gateId];
    if (g == null) return const [];
    return g.inputs.map((p) => p.signal).toList(growable: false);
  }

  void reset() {
    _tickCount = 0;
    for (final g in _gates.values) {
      g.reset();
    }
    for (final w in _wires) {
      w.pipeline.clear();
    }
  }

  /// Advances circuit propagation & stateful clocks/latches by [ticks] cycles.
  void stepTicks([int ticks = 1]) {
    for (var step = 0; step < ticks; step++) {
      _stepSingleTick();
    }
  }

  /// Steps combinational chains until outputs stop changing (or hits [maxTicks]).
  int settleCombinational({int maxTicks = 32}) {
    var taken = 0;
    for (var i = 0; i < maxTicks; i++) {
      final before = _captureOutputSnapshot();
      _stepSingleTick();
      taken++;
      if (_snapshotsEqual(before, _captureOutputSnapshot())) {
        return taken;
      }
    }
    return taken;
  }

  List<int> _captureOutputSnapshot() {
    final snap = <int>[];
    for (final g in _gates.values) {
      for (final p in g.outputs) {
        snap.add(p.signal ? 1 : 0);
        snap.add(p.busValue);
      }
    }
    return snap;
  }

  bool _snapshotsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _stepSingleTick() {
    _tickCount++;

    // 1. Clear input accumulators prior to wire delivery
    for (final g in _gates.values) {
      for (final p in g.inputs) {
        p.signal = false;
        p.busValue = 0;
      }
    }

    // 2. Deliver current output states across wires (with optional wire latency)
    for (final w in _wires) {
      final src = _gates[w.wire.fromGateId];
      final dst = _gates[w.wire.toGateId];
      if (src == null || dst == null) continue;
      if (w.wire.fromPinIndex < 0 || w.wire.fromPinIndex >= src.outputs.length) continue;
      if (w.wire.toPinIndex < 0 || w.wire.toPinIndex >= dst.inputs.length) continue;

      final outPin = src.outputs[w.wire.fromPinIndex];
      final transmitted = w.advance((signal: outPin.signal, bus: outPin.busValue));
      final inPin = dst.inputs[w.wire.toPinIndex];
      if (transmitted.signal) inPin.signal = true;
      inPin.busValue |= transmitted.bus;
    }

    // 3. Evaluate next outputs per gate
    final nextStates = <String, ({List<bool> signals, List<int> buses})>{};
    for (final entry in _gates.entries) {
      nextStates[entry.key] = _evaluateGate(entry.value);
    }

    // 4. Push through propagation delay buffer and commit
    for (final entry in _gates.entries) {
      final g = entry.value;
      final next = nextStates[entry.key]!;
      final delay = math.max(0, g.def.propagationDelayTicks - 1);
      g._pipeline.addLast(next);
      ({List<bool> signals, List<int> buses}) committed;
      if (g._pipeline.length > delay) {
        committed = g._pipeline.removeFirst();
      } else {
        committed = (
          signals: g.outputs.map((p) => p.signal).toList(),
          buses: g.outputs.map((p) => p.busValue).toList(),
        );
      }
      for (var i = 0; i < g.outputs.length && i < committed.signals.length; i++) {
        g.outputs[i].signal = committed.signals[i];
        g.outputs[i].busValue = committed.buses[i];
      }
    }
  }

  ({List<bool> signals, List<int> buses}) _evaluateGate(_GateRuntime g) {
    final ins = g.inputs.map((p) => p.signal).toList();
    final inBuses = g.inputs.map((p) => p.busValue).toList();
    final outCount = math.max(1, g.outputs.length);
    final outSigs = List<bool>.filled(outCount, false);
    final outBuses = List<int>.filled(outCount, 0);

    bool inAt(int idx) => idx >= 0 && idx < ins.length ? ins[idx] : false;

    switch (g.def.kind) {
      case CircuitGateKind.inputToggle:
        outSigs[0] = g.manualState;
        outBuses[0] = g.manualBusValue != 0 ? g.manualBusValue : (g.manualState ? 1 : 0);
      case CircuitGateKind.constantHigh:
        outSigs[0] = true;
        outBuses[0] = 1;
      case CircuitGateKind.constantLow:
        outSigs[0] = false;
        outBuses[0] = 0;
      case CircuitGateKind.not:
        outSigs[0] = !inAt(0);
      case CircuitGateKind.buffer:
      case CircuitGateKind.outputLamp:
        outSigs[0] = inAt(0);
        outBuses[0] = inBuses.isNotEmpty ? inBuses[0] : (outSigs[0] ? 1 : 0);
      case CircuitGateKind.and:
        outSigs[0] = ins.isNotEmpty && ins.every((v) => v);
      case CircuitGateKind.or:
        outSigs[0] = ins.any((v) => v);
      case CircuitGateKind.xor:
        outSigs[0] = ins.where((v) => v).length.isOdd;
      case CircuitGateKind.nand:
        outSigs[0] = !(ins.isNotEmpty && ins.every((v) => v));
      case CircuitGateKind.nor:
        outSigs[0] = !ins.any((v) => v);
      case CircuitGateKind.srLatch:
        final s = inAt(0);
        final r = inAt(1);
        if (s && !r) {
          g.storedQ = true;
        } else if (r && !s) {
          g.storedQ = false;
        }
        outSigs[0] = g.storedQ;
        if (outCount > 1) outSigs[1] = !g.storedQ;
      case CircuitGateKind.dFlipFlop:
        final d = inAt(0);
        final clk = inAt(1);
        final rst = inAt(2);
        if (rst) {
          g.storedQ = false;
        } else if (clk && !g.prevClock) {
          g.storedQ = d;
        }
        g.prevClock = clk;
        outSigs[0] = g.storedQ;
        if (outCount > 1) outSigs[1] = !g.storedQ;
      case CircuitGateKind.clockPulse:
        final hasEnableWire = g.inputs.isNotEmpty && g.inputs[0].isDriven;
        final enabled = !hasEnableWire || inAt(0);
        final half = math.max(1, g.def.clockHalfPeriodTicks);
        if (enabled) {
          g.clockCounter++;
          outSigs[0] = ((g.clockCounter - 1) ~/ half).isEven;
        } else {
          outSigs[0] = false;
        }
      case CircuitGateKind.splitterBus:
        if (g.inputs.length == 1 && outCount > 1) {
          final bus = inBuses[0];
          for (var i = 0; i < outCount; i++) {
            outSigs[i] = ((bus >> i) & 1) == 1;
            outBuses[i] = outSigs[i] ? 1 : 0;
          }
        } else {
          var combined = 0;
          for (var i = 0; i < ins.length; i++) {
            if (ins[i]) combined |= (1 << i);
          }
          outSigs[0] = combined != 0;
          outBuses[0] = combined;
        }
    }
    return (signals: outSigs, buses: outBuses);
  }
}
