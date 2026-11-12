import 'package:test/test.dart';
import 'package:voxcircuit/voxcircuit.dart';

void main() {
  test('Combinational half-adder computes sum (XOR) and carry (AND) truth table', () {
    final solver = CircuitGraphSolver()
      ..addGate(CircuitGateDef.input('a'))
      ..addGate(CircuitGateDef.input('b'))
      ..addGate(CircuitGateDef.gate('sum', CircuitGateKind.xor))
      ..addGate(CircuitGateDef.gate('carry', CircuitGateKind.and))
      ..connect('a', 0, 'sum', 0)
      ..connect('b', 0, 'sum', 1)
      ..connect('a', 0, 'carry', 0)
      ..connect('b', 0, 'carry', 1);

    for (final (aVal, bVal, expSum, expCarry) in const [
      (false, false, false, false),
      (true, false, true, false),
      (false, true, true, false),
      (true, true, false, true),
    ]) {
      solver.setInput('a', aVal);
      solver.setInput('b', bVal);
      solver.settleCombinational();
      expect(solver.readOutput('sum'), expSum);
      expect(solver.readOutput('carry'), expCarry);
    }
  });

  test('Sequential SR latch and clocked D flip-flop toggle & hold state across cycles', () {
    final solver = CircuitGraphSolver()
      ..addGate(CircuitGateDef.clock('clk', halfPeriodTicks: 1))
      ..addGate(CircuitGateDef.gate('dff', CircuitGateKind.dFlipFlop, inputCount: 3, outputCount: 2))
      ..connect('clk', 0, 'dff', 1)
      ..connect('dff', 1, 'dff', 0);

    // Tick 1: clk rises high -> output available on Tick 2 wire propagation
    // Tick 2: dff samples rising clk edge and latches !Q (true) -> Q becomes true
    solver.stepTicks(2);
    expect(solver.readOutput('dff', pinIndex: 0), isTrue);
    expect(solver.readOutput('dff', pinIndex: 1), isFalse);

    // Tick 3: clk goes low -> holds state
    solver.stepTicks(1);
    expect(solver.readOutput('dff', pinIndex: 0), isTrue);

    // Tick 4: second rising clock edge sampled -> dff latches !Q (false) -> Q becomes false
    solver.stepTicks(1);
    expect(solver.readOutput('dff', pinIndex: 0), isFalse);

    // Separate SR Latch check
    solver
      ..addGate(CircuitGateDef.input('s'))
      ..addGate(CircuitGateDef.input('r'))
      ..addGate(CircuitGateDef.gate('sr', CircuitGateKind.srLatch, inputCount: 2, outputCount: 2))
      ..connect('s', 0, 'sr', 0)
      ..connect('r', 0, 'sr', 1);

    solver.setInput('s', true);
    solver.setInput('r', false);
    solver.stepTicks(1);
    expect(solver.readOutput('sr', pinIndex: 0), isTrue);

    // Clear S -> latch holds Q=true
    solver.setInput('s', false);
    solver.stepTicks(1);
    expect(solver.readOutput('sr', pinIndex: 0), isTrue);

    // Assert R -> latch resets Q=false
    solver.setInput('r', true);
    solver.stepTicks(1);
    expect(solver.readOutput('sr', pinIndex: 0), isFalse);
  });

  test('Bus splitter unpacks bitmasks and wire delay pipeline stages signals across ticks', () {
    final solver = CircuitGraphSolver()
      ..addGate(CircuitGateDef.input('bus_src'))
      ..addGate(CircuitGateDef.gate('split', CircuitGateKind.splitterBus, inputCount: 1, outputCount: 4, propagationDelayTicks: 1))
      ..addGate(CircuitGateDef.lamp('lamp2'))
      ..connect('bus_src', 0, 'split', 0)
      ..connect('split', 2, 'lamp2', 0, delayTicks: 2);

    // Binary 5 = 0101 (bits 0 and 2 are high)
    solver.setInput('bus_src', true, busValue: 5);
    solver.stepTicks(1);
    expect(solver.readOutput('split', pinIndex: 0), isTrue);
    expect(solver.readOutput('split', pinIndex: 1), isFalse);
    expect(solver.readOutput('split', pinIndex: 2), isTrue);
    // Lamp has not received delayed bit 2 yet (2-tick wire latency)
    expect(solver.readOutput('lamp2'), isFalse);

    solver.stepTicks(3);
    expect(solver.readOutput('lamp2'), isTrue);
  });
}
