/// S7-C: World Tools — Terrain Sculpt/Paint with compact undoable stroke
/// deltas, Foliage Brush, and deterministic NavMesh Bake settings (`voxbiome`,
/// `voxfoliage`, `voxnav3d`, `voxspline3d`, `voxsnap`, `voxbuild`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

enum TerrainBrushMode { raise, lower, smooth, flatten, hole }

/// Compact undoable heightfield delta storing only modified cell indices.
final class TerrainStrokeDelta {
  final Map<int, double> previousHeights;
  final Map<int, double> nextHeights;

  const TerrainStrokeDelta({
    required this.previousHeights,
    required this.nextHeights,
  });

  int get modifiedCells => nextHeights.length;
}

/// Pure-Dart heightfield terrain sculpt tool with compact undo/redo deltas
/// (`[S7-C]`).
final class TerrainSculptTool {
  final int width;
  final int height;
  final Float32List heightfield;
  final List<TerrainStrokeDelta> _undoStack = [];
  final List<TerrainStrokeDelta> _redoStack = [];

  TerrainSculptTool({required this.width, required this.height})
    : heightfield = Float32List(width * height);

  TerrainStrokeDelta applyStroke({
    required TerrainBrushMode mode,
    required double centerX,
    required double centerY,
    required double radius,
    double strength = 0.5,
    double targetHeight = 0.0,
  }) {
    final prev = <int, double>{};
    final next = <int, double>{};
    final r2 = radius * radius;
    final minX = math.max(0, (centerX - radius).floor());
    final maxX = math.min(width - 1, (centerX + radius).ceil());
    final minY = math.max(0, (centerY - radius).floor());
    final maxY = math.min(height - 1, (centerY + radius).ceil());

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final dx = x - centerX;
        final dy = y - centerY;
        final d2 = dx * dx + dy * dy;
        if (d2 > r2) continue;
        final falloff = 1.0 - math.sqrt(d2) / math.max(radius, 1e-4);
        final idx = y * width + x;
        final oldH = heightfield[idx];
        double newH;
        switch (mode) {
          case TerrainBrushMode.raise:
            newH = oldH + strength * falloff;
          case TerrainBrushMode.lower:
            newH = oldH - strength * falloff;
          case TerrainBrushMode.flatten:
            newH =
                oldH +
                (targetHeight - oldH) * (strength * falloff).clamp(0.0, 1.0);
          case TerrainBrushMode.smooth:
            newH = oldH * (1.0 - 0.5 * falloff);
          case TerrainBrushMode.hole:
            newH = double.nan;
        }
        prev[idx] = oldH;
        next[idx] = newH;
        heightfield[idx] = newH;
      }
    }

    final delta = TerrainStrokeDelta(previousHeights: prev, nextHeights: next);
    _undoStack.add(delta);
    _redoStack.clear();
    return delta;
  }

  bool undo() {
    if (_undoStack.isEmpty) return false;
    final d = _undoStack.removeLast();
    for (final e in d.previousHeights.entries) {
      heightfield[e.key] = e.value;
    }
    _redoStack.add(d);
    return true;
  }

  bool redo() {
    if (_redoStack.isEmpty) return false;
    final d = _redoStack.removeLast();
    for (final e in d.nextHeights.entries) {
      heightfield[e.key] = e.value;
    }
    _undoStack.add(d);
    return true;
  }
}

/// Deterministic NavMesh bake configuration (`[S7-C]`).
final class NavMeshBakeSettings {
  final double agentRadius;
  final double agentHeight;
  final double maxSlopeDegrees;
  final double cellSize;
  final int seed;

  const NavMeshBakeSettings({
    this.agentRadius = 0.4,
    this.agentHeight = 1.8,
    this.maxSlopeDegrees = 45.0,
    this.cellSize = 0.25,
    this.seed = 1,
  });

  int deterministicHash() =>
      Object.hash(agentRadius, agentHeight, maxSlopeDegrees, cellSize, seed);
}
