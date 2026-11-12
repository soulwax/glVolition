import 'dart:io';
import 'dart:math' as math;

final class _Pt {
  final double x;
  final double y;

  const _Pt(this.x, this.y);

  _Pt operator +(_Pt o) => _Pt(x + o.x, y + o.y);
  _Pt operator -(_Pt o) => _Pt(x - o.x, y - o.y);
  _Pt operator *(double s) => _Pt(x * s, y * s);

  double dot(_Pt o) => x * o.x + y * o.y;
  double cross(_Pt o) => x * o.y - y * o.x;
  double get len => math.sqrt(x * x + y * y);

  _Pt get norm {
    final l = len;
    return l < 1e-9 ? const _Pt(0, 0) : _Pt(x / l, y / l);
  }
}

enum MotifKind {
  standard, // Flagship crisp 3-blade aperture
  waveFluid, // Smooth sinusoidal liquid waves on outer edges (voxfluid)
  clothDrape, // Gentle concave catenary drape on triangle edges (voxcloth)
  curveTween, // Graceful S-curve easing channels (voxtween, voxanim, voxextrude)
  fractureTris, // Clean barycentric tessellation into modular sub-triangles (voxecs)
  shatterShards, // Displaced angular Voronoi fragments (voxfracture)
  navMeshTris, // Faceted triangular polygon mesh shards (voxnav3d, voxgeom)
  terrainStrata, // Stepped horizontal geological contour tiers (voxbiome)
  htnTreeTiers, // Hierarchical top-down decomposition strata (voxhtn)
  voxelSteps, // Orthographic cubic staircase flanks (voxvox)
  sdfContour, // Organic rounded metaballs + SDF iso-contour halo (voxsdf)
  gridCrosshair, // Clean orthogonal cross-slit cells (voxgrid)
  archRooms, // BSP architectural room cut + doorway notch (voxarch, voxproc)
  buildSockets, // Square snap-fit locking pins along seams (voxbuild, voxpack)
  hexComb, // Hexagonal iris + chamfered honeycomb contour (voxhex)
  dspEq, // Bottom cutout gap with crisp equalizer wave bars (voxdsp)
  synthSaw, // Bold sawtooth inner wave teeth (voxsynth)
  reverbEcho, // Concentric outward acoustic diffraction shells (voxreverb)
  scoreStems, // Horizontal stacked adaptive stem slices (voxscore)
  seqTimeline, // Clean negative-space timeline rail + keyframe diamond (voxseq)
  statSteps, // Rising progression bars beside right slope (voxstat)
  talkBubble, // Speech-bubble base tail + centered '...' inside iris (voxtalk)
  pixelCorner, // Optical hex iris + detached square pixel accent (pixeldart)
  camViewfinder, // Hex iris + outer corner L-bracket viewfinder ticks (voxcam)
  lightRays, // Central light emitter + clean radiating beam cuts (voxlight)
  probeLobes, // 4-point Spherical Harmonics star inside open iris (voxprobe)
  skyHorizon, // Clean true-gap horizon split + amber solar disc (voxsky)
  vfxSparks, // Detached triangular particle sparks outside blade tips (voxvfx)
  decalPeel, // Folded corner decal peel flap at apex (voxdecal)
  foliageVeins, // Graceful curved leaf midrib cuts (voxfoliage)
  physImpulse, // Kinetic rebounding top-right blade + motion arc (voxphys)
  wheelCog, // Gear-beveled rim + hex hub ring (voxwheel, voxcraft)
  ragdollJoints, // Circular pivot ball-joints bridging seams (voxragdoll)
  crowdBoids, // 3 sleek delta-chevron boids flying inside iris (voxcrowd)
  trafficLanes, // Curved bypass lane guide + amber intersection pip (voxtraffic)
  aiNodes, // Synaptic circular nodes orbiting central core (voxai)
  pathCurve, // Clean negative-space waypoint dot trail (voxpath)
  flowPorts, // Left/right circular port sockets bridging flanks (voxflow)
  circuitTraces, // Crisp PCB trace + solder via inside open iris (voxcircuit)
  ruleShield, // Vertical symmetry verdict split + diamond crest (voxrule)
  questFork, // Clean Y-fork centered in wide iris toward twin pips (voxquest)
  netArcs, // Orbital wireless signal arcs outside triangle waist (voxnet)
  ghostEcho, // Layered dashed trailing echo silhouette behind triangle (voxrollback, voxsnap)
  padCluster, // Wide iris + crisp D-pad '+' core (voxpad)
  itemCells, // 2x2 inventory quadrants + central rarity hex (voxitem)
  locMeridian, // Swept globe latitude/meridian curves inside iris (voxloc)
  logChevron, // Crisp '>_ ' terminal prompt inside open iris (voxlog)
  uiWindow, // Title-bar horizontal header split inside outer frame (voxui)
  rhythmBeat, // Receptor bar + beat diamond + lane note pips (voxrhythm)
  gaitStrides, // Alternating left/right foot-step stride arcs (voxgait)
  atlasGrid, // Asymmetric MaxRects packed texture tiles (voxatlas)
  lensDolly, // 6-blade optical lens ring + curved camera dolly track (voxlens)
  broadSweep, // Spatial hash bounds + sweeping TOI arrow (voxbroad)
  ribbonSwirl, // Curl turbulence swirling double-ribbon stroke (voxribbon)
  steerWedge, // Wedge formation chevrons + vector heading arc (voxsteer)
  dagNodes, // Directed acyclic render-pass pipeline nodes + barrier edges (voxgraph)
  blendCross, // Overlapping blendspace wave curves + crossfade node (voxblend)
  shadowCascades, // 3 stepped frustum shadow cascade slices in iris (voxshadow)
  splineRibbon, // Banked cubic Hermite curve & orthogonal frame triads (voxspline3d)
  allocArena, // Segmented linear bump arena bars + telemetry pulse (voxalloc)
  batchClusters, // Merged instanced draw buckets converging into single indirect command (voxbatch)
  ikLimbs, // Articulated two-bone IK hinge segments + target reticle (voxik2d)
  curveWave, // Piecewise Hermite S-curve & ADSR control points inside iris (voxcurve)
  octreeBoxes, // Nested loose 3D octree bounding quadrants & frustum wedge (voxoctree)
}

final class LogoSpec {
  final String name;
  final String category;
  final MotifKind motif;
  final int blades;
  final double outerR;
  final double innerR;
  final double twistDeg;
  final double gap;
  final double cornerFillet;
  final double innerTipFillet;
  final double chamferCorners;
  final double outerRingR;
  final double outerRingStroke;
  final String? outerRingColor;
  final String centerShape;
  final double centerDotR;
  final String? centerColor;
  final List<String> colors;

  const LogoSpec({
    required this.name,
    required this.category,
    this.motif = MotifKind.standard,
    this.blades = 3,
    this.outerR = 56.0,
    this.innerR = 14.5,
    this.twistDeg = 28.0,
    this.gap = 4.4,
    this.cornerFillet = 7.0,
    this.innerTipFillet = 1.5,
    this.chamferCorners = 0.0,
    this.outerRingR = 0.0,
    this.outerRingStroke = 3.5,
    this.outerRingColor,
    this.centerShape = 'none',
    this.centerDotR = 0.0,
    this.centerColor,
    required this.colors,
  });
}

List<_Pt> _clipHalfPlane(List<_Pt> poly, _Pt origin, _Pt normal) {
  if (poly.isEmpty) return const [];
  final out = <_Pt>[];
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final da = (a - origin).dot(normal);
    final db = (b - origin).dot(normal);
    final inA = da >= -1e-7;
    final inB = db >= -1e-7;
    if (inA && inB) {
      out.add(b);
    } else if (inA && !inB) {
      final t = da / (da - db);
      out.add(a + (b - a) * t);
    } else if (!inA && inB) {
      final t = da / (da - db);
      out.add(a + (b - a) * t);
      out.add(b);
    }
  }
  return out;
}

double _polyArea(List<_Pt> poly) {
  if (poly.length < 3) return 0.0;
  var sum = 0.0;
  for (var i = 0; i < poly.length; i++) {
    sum += poly[i].cross(poly[(i + 1) % poly.length]);
  }
  return sum.abs() * 0.5;
}

_Pt _polyCentroid(List<_Pt> poly) {
  var sx = 0.0, sy = 0.0;
  for (final p in poly) {
    sx += p.x;
    sy += p.y;
  }
  return _Pt(sx / poly.length, sy / poly.length);
}

/// Shrinks a convex polygon cleanly around its centroid without ever flipping or creating slivers.
List<_Pt> _scaleAroundCentroid(List<_Pt> poly, double factor, {double maxPxInset = 2.2}) {
  final c = _polyCentroid(poly);
  return poly.map((p) {
    final v = p - c;
    final l = v.len;
    if (l < 1e-6) return p;
    final move = math.min(l * (1.0 - factor), maxPxInset);
    return p - v.norm * move;
  }).toList();
}

/// Partitions a clean convex blade polygon into balanced, non-sliver triangles!
List<List<_Pt>> _partitionIntoBalancedTris(
  List<_Pt> poly, {
  required double gapFactor,
  required double maxInsetPx,
  required bool recurseSmallest,
}) {
  final rawTris = <List<_Pt>>[];
  if (poly.length == 3) {
    rawTris.add(poly);
  } else if (poly.length == 4) {
    // Compare both diagonals, pick the split with LARGER minimum triangle area!
    final t1A = [poly[0], poly[1], poly[2]];
    final t1B = [poly[0], poly[2], poly[3]];
    final min1 = math.min(_polyArea(t1A), _polyArea(t1B));

    final t2A = [poly[1], poly[2], poly[3]];
    final t2B = [poly[1], poly[3], poly[0]];
    final min2 = math.min(_polyArea(t2A), _polyArea(t2B));

    if (min1 >= min2) {
      rawTris.addAll([t1A, t1B]);
    } else {
      rawTris.addAll([t2A, t2B]);
    }
  } else {
    // Pentagon+: fan from the midpoint of the shortest edge or best vertex
    var bestIdx = 0;
    var bestMinArea = -1.0;
    for (var pivot = 0; pivot < poly.length; pivot++) {
      var minA = double.infinity;
      for (var k = 1; k < poly.length - 1; k++) {
        final a = _polyArea([
          poly[pivot],
          poly[(pivot + k) % poly.length],
          poly[(pivot + k + 1) % poly.length],
        ]);
        if (a < minA) minA = a;
      }
      if (minA > bestMinArea) {
        bestMinArea = minA;
        bestIdx = pivot;
      }
    }
    for (var k = 1; k < poly.length - 1; k++) {
      rawTris.add([
        poly[bestIdx],
        poly[(bestIdx + k) % poly.length],
        poly[(bestIdx + k + 1) % poly.length],
      ]);
    }
  }

  // Optionally bisect the largest triangle along its longest side midpoint for crisp 3-shards per blade!
  final balanced = <List<_Pt>>[];
  for (final t in rawTris) {
    if (recurseSmallest && _polyArea(t) > 260.0) {
      // Find longest edge
      var maxLen = -1.0;
      var maxI = 0;
      for (var i = 0; i < 3; i++) {
        final l = (t[(i + 1) % 3] - t[i]).len;
        if (l > maxLen) {
          maxLen = l;
          maxI = i;
        }
      }
      final a = t[maxI];
      final b = t[(maxI + 1) % 3];
      final opp = t[(maxI + 2) % 3];
      final mid = (a + b) * 0.5;
      balanced.add([a, mid, opp]);
      balanced.add([mid, b, opp]);
    } else {
      balanced.add(t);
    }
  }

  return balanced
      .map((t) => _scaleAroundCentroid(t, gapFactor, maxPxInset: maxInsetPx))
      .where((t) => _polyArea(t) > 12.0)
      .toList();
}

String _polyToPath(
  List<_Pt> poly,
  List<_Pt> roundCorners,
  double cornerFillet, {
  double innerTipFillet = 0.0,
  bool outerWave = false,
  double waveAmp = 3.2,
  double catenarySag = 0.0,
  double curveS = 0.0,
  bool sawtoothInner = false,
  bool voxelStairs = false,
  _Pt center = const _Pt(64, 76),
}) {
  if (poly.length < 3) return '';
  final segs = <String>[];
  final n = poly.length;

  bool isOuter(_Pt p) {
    for (final c in roundCorners) {
      if ((p - c).len < 0.08) return true;
    }
    return false;
  }

  bool isOnOuterPerimeter(_Pt a, _Pt b, List<_Pt> triVerts) {
    for (var i = 0; i < triVerts.length; i++) {
      final p0 = triVerts[i];
      final p1 = triVerts[(i + 1) % triVerts.length];
      final en = (p1 - p0).norm;
      final perp = _Pt(-en.y, en.x);
      if ((a - p0).dot(perp).abs() < 0.45 && (b - p0).dot(perp).abs() < 0.45) {
        return true;
      }
    }
    return false;
  }

  String f(double v) => v.toStringAsFixed(2);

  for (var i = 0; i < n; i++) {
    final prev = poly[(i - 1 + n) % n];
    final curr = poly[i];
    final next = poly[(i + 1) % n];
    final dIn = prev - curr;
    final dOut = next - curr;
    final fillet = isOuter(curr) ? cornerFillet : innerTipFillet;

    var pStart = curr;
    if (fillet > 0.15 && dIn.len > 0.6 && dOut.len > 0.6) {
      final fIn = math.min(fillet, dIn.len * 0.36);
      final fOut = math.min(fillet, dOut.len * 0.36);
      final pBefore = curr + dIn.norm * fIn;
      final pAfter = curr + dOut.norm * fOut;
      segs.add(i == 0 ? 'M ${f(pBefore.x)} ${f(pBefore.y)}' : 'L ${f(pBefore.x)} ${f(pBefore.y)}');
      segs.add('Q ${f(curr.x)} ${f(curr.y)} ${f(pAfter.x)} ${f(pAfter.y)}');
      pStart = pAfter;
    } else {
      segs.add(i == 0 ? 'M ${f(curr.x)} ${f(curr.y)}' : 'L ${f(curr.x)} ${f(curr.y)}');
    }

    final nextNext = poly[(i + 2) % n];
    final nIn = curr - next;
    final nextFillet = isOuter(next) ? cornerFillet : innerTipFillet;
    var pEnd = next;
    if (nextFillet > 0.15 && nIn.len > 0.6 && (nextNext - next).len > 0.6) {
      final fIn = math.min(nextFillet, nIn.len * 0.36);
      pEnd = next + nIn.norm * fIn;
    }

    final span = pEnd - pStart;
    final spanLen = span.len;
    if (spanLen < 1.0) continue;

    final dir = span.norm;
    var outN = _Pt(dir.y, -dir.x);
    if (outN.dot((pStart + pEnd) * 0.5 - center) < 0) {
      outN = _Pt(-outN.x, -outN.y);
    }
    final onOuter = isOnOuterPerimeter(curr, next, roundCorners);

    if (voxelStairs && onOuter && spanLen > 16.0 && (dir.x.abs() > 0.2 && dir.y.abs() > 0.2)) {
      // Staircase pixel-step ONLY along sloped left/right outer triangle sides
      final steps = math.max(2, (spanLen / 13.0).floor());
      for (var s = 0; s < steps; s++) {
        final t1 = (s + 1) / steps;
        final prevPt = pStart + span * (s / steps);
        final nextPt = pStart + span * t1;
        final corner = (pStart.y < pEnd.y)
            ? _Pt(prevPt.x, nextPt.y)
            : _Pt(nextPt.x, prevPt.y);
        segs.add('L ${f(corner.x)} ${f(corner.y)} L ${f(nextPt.x)} ${f(nextPt.y)}');
      }
    } else if (outerWave && onOuter && spanLen > 20.0) {
      // Clean sweeping 2-half-wave or 4-half-wave liquid curves proportionally to edge length!
      final segCount = spanLen > 52.0 ? 4 : 2;
      for (var s = 0; s < segCount; s++) {
        final t0 = s / segCount;
        final t1 = (s + 1) / segCount;
        final tm = (t0 + t1) * 0.5;
        final env = math.sin(tm * math.pi);
        final sign = s.isEven ? 1.0 : -1.0;
        final ctrl = pStart + span * tm + outN * (waveAmp * sign * env);
        final dst = pStart + span * t1;
        segs.add('Q ${f(ctrl.x)} ${f(ctrl.y)} ${f(dst.x)} ${f(dst.y)}');
      }
    } else if (catenarySag > 0.1 && onOuter && spanLen > 20.0) {
      final ctrl = (pStart + pEnd) * 0.5 - outN * catenarySag;
      segs.add('Q ${f(ctrl.x)} ${f(ctrl.y)} ${f(pEnd.x)} ${f(pEnd.y)}');
    } else if (curveS.abs() > 0.1 && !onOuter && spanLen > 14.0) {
      final c1 = pStart + span * 0.33 + outN * curveS;
      final c2 = pStart + span * 0.67 - outN * curveS;
      segs.add('C ${f(c1.x)} ${f(c1.y)} ${f(c2.x)} ${f(c2.y)} ${f(pEnd.x)} ${f(pEnd.y)}');
    } else if (sawtoothInner && !onOuter && spanLen > 18.0) {
      const teeth = 2;
      for (var s = 0; s < teeth; s++) {
        final tPeak = (s + 0.5) / teeth;
        final tB = (s + 1) / teeth;
        final env = math.sin(tPeak * math.pi);
        final pk = pStart + span * tPeak + outN * (3.2 * env);
        final eb = pStart + span * tB;
        segs.add('L ${f(pk.x)} ${f(pk.y)} L ${f(eb.x)} ${f(eb.y)}');
      }
    }
  }
  segs.add('Z');
  return segs.join(' ');
}

String renderApertureSvg(LogoSpec spec) {
  const cx = 64.0;
  const cy = 76.0;
  const center = _Pt(cx, cy);
  String f(double v) => v.toStringAsFixed(2);

  final triVerts = <_Pt>[];
  for (var i = 0; i < 3; i++) {
    final ang = (-90.0 + i * 120.0) * math.pi / 180.0;
    triVerts.add(_Pt(cx + spec.outerR * math.cos(ang), cy + spec.outerR * math.sin(ang)));
  }

  var basePoly = List<_Pt>.from(triVerts);
  if (spec.chamferCorners > 0.1) {
    final clipR = spec.outerR - spec.chamferCorners;
    for (var i = 0; i < 3; i++) {
      final v = triVerts[i];
      final inward = (center - v).norm;
      final cutPt = center - inward * clipR;
      basePoly = _clipHalfPlane(basePoly, cutPt, inward);
    }
  }

  final inner = <_Pt>[];
  for (var k = 0; k < spec.blades; k++) {
    final ang = (-90.0 + spec.twistDeg + k * (360.0 / spec.blades)) * math.pi / 180.0;
    inner.add(_Pt(cx + spec.innerR * math.cos(ang), cy + spec.innerR * math.sin(ang)));
  }

  final bladePolys = <List<_Pt>>[];
  final halfGap = spec.gap * 0.5;
  final roundSet = spec.chamferCorners > 0.1 ? basePoly : triVerts;
  final effFillet = spec.chamferCorners > 0.1 ? spec.cornerFillet * 0.45 : spec.cornerFillet;

  for (var k = 0; k < spec.blades; k++) {
    final prevIdx = (k - 1 + spec.blades) % spec.blades;
    final nextIdx = (k + 1) % spec.blades;
    final ukPrev = inner[prevIdx];
    final uk = inner[k];
    final ukNext = inner[nextIdx];

    final dirK = (ukNext - uk).norm;
    var outK = _Pt(dirK.y, -dirK.x);
    if (outK.dot(uk - center) < 0) outK = _Pt(-outK.x, -outK.y);

    final dirPrev = (uk - ukPrev).norm;
    var outPrev = _Pt(dirPrev.y, -dirPrev.x);
    if (outPrev.dot(ukPrev - center) < 0) outPrev = _Pt(-outPrev.x, -outPrev.y);
    final inPrev = _Pt(-outPrev.x, -outPrev.y);

    var poly = List<_Pt>.from(basePoly);
    poly = _clipHalfPlane(poly, uk + outK * halfGap, outK);
    poly = _clipHalfPlane(poly, uk + inPrev * halfGap, inPrev);

    if (poly.length >= 3 && _polyArea(poly) > 10.0) {
      bladePolys.add(poly);
    }
  }

  final underLayer = <String>[];
  final bodyLayer = <String>[];
  final overLayer = <String>[];

  // True negative-space cutouts applied cleanly to blade polygons!
  List<List<_Pt>> applyNegativeSpaceBandCuts(List<List<_Pt>> polys, double yCut, double halfH) {
    final res = <List<_Pt>>[];
    for (final p in polys) {
      final top = _clipHalfPlane(p, _Pt(cx, yCut - halfH), const _Pt(0, -1));
      final bot = _clipHalfPlane(p, _Pt(cx, yCut + halfH), const _Pt(0, 1));
      if (top.length >= 3 && _polyArea(top) > 12.0) res.add(top);
      if (bot.length >= 3 && _polyArea(bot) > 12.0) res.add(bot);
    }
    return res;
  }

  // 1. Optional Ghost Echo Silhouette Behind (voxrollback, voxsnap)
  if (spec.motif == MotifKind.ghostEcho) {
    final shift = spec.name == 'voxrollback' ? const _Pt(-5.5, 4.0) : const _Pt(-5.0, -3.5);
    final ghostVerts = triVerts.map((v) => v + shift).toList();
    final gd = _polyToPath(ghostVerts, ghostVerts, effFillet);
    underLayer.add('<path d="$gd" fill="none" stroke="${spec.colors.first}" stroke-width="2.5" stroke-dasharray="6 4" opacity="0.58"/>');
  }

  // 2. Motif-driven Blade Rendering
  if (spec.motif == MotifKind.decalPeel) {
    for (var b = 0; b < bladePolys.length; b++) {
      var poly = bladePolys[b];
      if (b == 0) {
        // Clip the apex tip cleanly along the diagonal decal peel fold crease!
        poly = _clipHalfPlane(poly, const _Pt(64.0, 35.5), const _Pt(0.18, 0.984));
      }
      if (poly.length >= 3 && _polyArea(poly) > 12.0) {
        final d = _polyToPath(poly, roundSet, effFillet, innerTipFillet: spec.innerTipFillet);
        bodyLayer.add('<path d="$d" fill="${spec.colors[b % spec.colors.length]}"/>');
      }
    }
  } else if (spec.motif == MotifKind.fractureTris || spec.motif == MotifKind.navMeshTris || spec.motif == MotifKind.shatterShards) {
    final isEcs = spec.motif == MotifKind.fractureTris;
    final isShatter = spec.motif == MotifKind.shatterShards;
    var shardIdx = 0;
    for (var b = 0; b < bladePolys.length; b++) {
      final shards = _partitionIntoBalancedTris(
        bladePolys[b],
        gapFactor: isEcs ? 0.88 : (isShatter ? 0.90 : 0.91),
        maxInsetPx: isEcs ? 2.2 : 1.6,
        recurseSmallest: isEcs || spec.motif == MotifKind.navMeshTris,
      );
      for (final s in shards) {
        var moved = s;
        if (isShatter) {
          final sc = _polyCentroid(s);
          final push = (sc - center).norm * (1.8 + (shardIdx % 3) * 1.4);
          moved = s.map((p) => p + push).toList();
        }
        final d = _polyToPath(moved, roundSet, 2.0, innerTipFillet: 0.8);
        final fill = spec.colors[(b + shardIdx) % spec.colors.length];
        bodyLayer.add('<path d="$d" fill="$fill"/>');
        shardIdx++;
      }
    }
  } else if (spec.motif == MotifKind.terrainStrata || spec.motif == MotifKind.htnTreeTiers || spec.motif == MotifKind.scoreStems) {
    final bands = spec.motif == MotifKind.scoreStems ? 4 : 3;
    const minY = 20.0, maxY = 104.0;
    final bandH = (maxY - minY) / bands;
    const bandGap = 2.6;
    for (var b = 0; b < bladePolys.length; b++) {
      for (var row = 0; row < bands; row++) {
        final y0 = minY + row * bandH + (row == 0 ? 0.0 : bandGap * 0.5);
        final y1 = minY + (row + 1) * bandH - (row == bands - 1 ? 0.0 : bandGap * 0.5);
        var slice = _clipHalfPlane(bladePolys[b], _Pt(cx, y0), const _Pt(0, 1));
        slice = _clipHalfPlane(slice, _Pt(cx, y1), const _Pt(0, -1));
        if (slice.length >= 3 && _polyArea(slice) > 12.0) {
          final d = _polyToPath(slice, roundSet, effFillet * 0.7, innerTipFillet: 1.0);
          final colorIdx = spec.motif == MotifKind.terrainStrata ? row : b;
          bodyLayer.add('<path d="$d" fill="${spec.colors[colorIdx % spec.colors.length]}"/>');
        }
      }
    }
  } else if (spec.motif == MotifKind.gridCrosshair || spec.motif == MotifKind.itemCells || spec.motif == MotifKind.ruleShield) {
    final vSplits = spec.motif == MotifKind.ruleShield ? [64.0] : (spec.motif == MotifKind.itemCells ? [64.0] : [53.0, 75.0]);
    final hSplits = spec.motif == MotifKind.ruleShield ? <double>[] : (spec.motif == MotifKind.itemCells ? [72.0] : [60.0, 82.0]);
    const slitHalf = 1.4;
    for (var b = 0; b < bladePolys.length; b++) {
      var cells = [bladePolys[b]];
      for (final vx in vSplits) {
        final next = <List<_Pt>>[];
        for (final c in cells) {
          final left = _clipHalfPlane(c, _Pt(vx - slitHalf, cy), const _Pt(-1, 0));
          final right = _clipHalfPlane(c, _Pt(vx + slitHalf, cy), const _Pt(1, 0));
          if (left.length >= 3 && _polyArea(left) > 12.0) next.add(left);
          if (right.length >= 3 && _polyArea(right) > 12.0) next.add(right);
        }
        cells = next;
      }
      for (final hy in hSplits) {
        final next = <List<_Pt>>[];
        for (final c in cells) {
          final top = _clipHalfPlane(c, _Pt(cx, hy - slitHalf), const _Pt(0, -1));
          final bot = _clipHalfPlane(c, _Pt(cx, hy + slitHalf), const _Pt(0, 1));
          if (top.length >= 3 && _polyArea(top) > 12.0) next.add(top);
          if (bot.length >= 3 && _polyArea(bot) > 12.0) next.add(bot);
        }
        cells = next;
      }
      for (var ci = 0; ci < cells.length; ci++) {
        final d = _polyToPath(cells[ci], roundSet, effFillet * 0.7, innerTipFillet: 0.8);
        bodyLayer.add('<path d="$d" fill="${spec.colors[(b + ci) % spec.colors.length]}"/>');
      }
    }
  } else if (spec.motif == MotifKind.skyHorizon || spec.motif == MotifKind.seqTimeline || spec.motif == MotifKind.uiWindow || spec.motif == MotifKind.rhythmBeat) {
    // True transparent negative-space horizontal band slicing through blades!
    final yCut = spec.motif == MotifKind.skyHorizon
        ? 68.0
        : (spec.motif == MotifKind.seqTimeline || spec.motif == MotifKind.rhythmBeat ? 84.0 : 54.5);
    final halfH = spec.motif == MotifKind.skyHorizon
        ? 2.2
        : (spec.motif == MotifKind.seqTimeline || spec.motif == MotifKind.rhythmBeat ? 2.8 : 1.8);
    for (var b = 0; b < bladePolys.length; b++) {
      final parts = applyNegativeSpaceBandCuts([bladePolys[b]], yCut, halfH);
      for (final p in parts) {
        final d = _polyToPath(p, roundSet, effFillet, innerTipFillet: 1.0);
        bodyLayer.add('<path d="$d" fill="${spec.colors[b % spec.colors.length]}"/>');
      }
    }
  } else if (spec.motif == MotifKind.dspEq) {
    // Cut out a crisp centered bottom notch for equalizer bars!
    for (var b = 0; b < bladePolys.length; b++) {
      var poly = bladePolys[b];
      if (b == 1) {
        // Split bottom-ish blade around centered EQ window (x in 48..80, y >= 87)
        final left = _clipHalfPlane(poly, const _Pt(49.0, 90.0), const _Pt(-1, 0));
        final right = _clipHalfPlane(poly, const _Pt(79.0, 90.0), const _Pt(1, 0));
        for (final piece in [left, right]) {
          if (piece.length >= 3 && _polyArea(piece) > 10.0) {
            bodyLayer.add('<path d="${_polyToPath(piece, roundSet, effFillet, innerTipFillet: 1.0)}" fill="${spec.colors[b % spec.colors.length]}"/>');
          }
        }
        continue;
      }
      bodyLayer.add('<path d="${_polyToPath(poly, roundSet, effFillet, innerTipFillet: spec.innerTipFillet)}" fill="${spec.colors[b % spec.colors.length]}"/>');
    }
  } else {
    for (var b = 0; b < bladePolys.length; b++) {
      var poly = bladePolys[b];
      if (spec.motif == MotifKind.physImpulse && b == 0) {
        poly = poly.map((p) => p + const _Pt(4.2, -3.2)).toList();
      }
      final d = _polyToPath(
        poly,
        roundSet,
        effFillet,
        innerTipFillet: spec.innerTipFillet,
        outerWave: spec.motif == MotifKind.waveFluid,
        waveAmp: 4.3,
        catenarySag: spec.motif == MotifKind.clothDrape ? 5.5 : 0.0,
        curveS: spec.motif == MotifKind.curveTween ? 4.4 : 0.0,
        sawtoothInner: spec.motif == MotifKind.synthSaw,
        voxelStairs: spec.motif == MotifKind.voxelSteps,
        center: center,
      );
      bodyLayer.add('<path d="$d" fill="${spec.colors[b % spec.colors.length]}"/>');
    }
  }

  // 3. Outer Frame Ring / Echo Shells / Viewfinder Framing
  if (spec.outerRingR > spec.outerR + 1.0) {
    final ringVerts = List.generate(3, (i) {
      final ang = (-90.0 + i * 120.0) * math.pi / 180.0;
      return _Pt(cx + spec.outerRingR * math.cos(ang), cy + spec.outerRingR * math.sin(ang));
    });
    final ringD = _polyToPath(ringVerts, ringVerts, 7.5);
    overLayer.add(
      '<path d="$ringD" fill="none" stroke="${spec.outerRingColor ?? spec.colors.first}" '
      'stroke-width="${f(spec.outerRingStroke)}" stroke-linejoin="round"/>',
    );
  }

  if (spec.motif == MotifKind.reverbEcho) {
    for (final (rEcho, op) in [(47.5, '0.82'), (57.5, '0.45')]) {
      final ev = List.generate(3, (i) {
        final a = (-90.0 + i * 120.0) * math.pi / 180.0;
        return _Pt(cx + rEcho * math.cos(a), cy + rEcho * math.sin(a));
      });
      final ed = _polyToPath(ev, ev, 7.0);
      overLayer.add(
        '<path d="$ed" fill="none" stroke="${spec.colors.first}" stroke-width="2.9" '
        'stroke-dasharray="28 9" stroke-linecap="round" stroke-linejoin="round" opacity="$op"/>',
      );
    }
  }

  if (spec.motif == MotifKind.sdfContour) {
    overLayer.add(
      '<circle cx="$cx" cy="$cy" r="24.5" fill="none" stroke="${spec.colors.first}" '
      'stroke-width="2.2" stroke-dasharray="11 5.5" opacity="0.82"/>',
    );
  }

  if (spec.motif == MotifKind.camViewfinder) {
    const bR = 59.0;
    overLayer.add(
      '<path d="M ${cx - 10} ${cy - bR + 14} L $cx ${cy - bR - 2} L ${cx + 10} ${cy - bR + 14}" '
      'stroke="#38BDF8" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>',
    );
    overLayer.add(
      '<path d="M 11.0 95.0 L 9.0 108.5 L 22.5 108.5 M 117.0 95.0 L 119.0 108.5 L 105.5 108.5" '
      'stroke="#38BDF8" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>',
    );
  }

  if (spec.motif == MotifKind.netArcs) {
    // Clean wireless arcs hugging outside the 3 flanks without cutting blades!
    overLayer.add(
      '<path d="M 38 40 Q 26 58 21 78 M 90 40 Q 102 58 107 78 M 40 112 Q 64 119 88 112" '
      'stroke="#38BDF8" stroke-width="2.8" stroke-linecap="round"/>',
    );
  }

  // 4. Symbolic Intent Accents (clean geometric cutouts / center-iris symbols)
  switch (spec.motif) {
    case MotifKind.pixelCorner:
      overLayer.add('<rect x="102" y="96" width="11.5" height="11.5" rx="1.8" fill="#38BDF8"/>');
      overLayer.add('<rect x="108" y="83" width="6.5" height="6.5" rx="1.2" fill="#818CF8"/>');
    case MotifKind.decalPeel:
      overLayer.add('<polygon points="56.5,36.8 72.5,34.0 62.5,46.0" fill="#38BDF8"/>');
    case MotifKind.dspEq:
      overLayer.add('<rect x="52.5" y="90" width="4" height="13" rx="2" fill="#F59E0B"/>');
      overLayer.add('<rect x="59.0" y="84" width="4" height="19" rx="2" fill="#FBBF24"/>');
      overLayer.add('<rect x="65.5" y="87" width="4" height="16" rx="2" fill="#FB923C"/>');
      overLayer.add('<rect x="72.0" y="92" width="4" height="11" rx="2" fill="#EA580C"/>');
    case MotifKind.seqTimeline:
      // Horizontal rail cleanly inside the true transparent cutout band + keyframe diamond!
      overLayer.add('<line x1="25" y1="84" x2="103" y2="84" stroke="#F43F5E" stroke-width="2.4" stroke-linecap="round"/>');
      overLayer.add('<polygon points="64,77.5 70.5,84 64,90.5 57.5,84" fill="#FB923C"/>');
    case MotifKind.statSteps:
      overLayer.add('<rect x="93" y="96" width="5.5" height="8" rx="1.5" fill="#34D399"/>');
      overLayer.add('<rect x="101" y="90" width="5.5" height="14" rx="1.5" fill="#38BDF8"/>');
      overLayer.add('<rect x="109" y="83" width="5.5" height="21" rx="1.5" fill="#0EA5E9"/>');
    case MotifKind.talkBubble:
      overLayer.add('<polygon points="24,102 36,102 22,114" fill="${spec.colors[1]}"/>');
      overLayer.add('<circle cx="59.0" cy="75.0" r="1.9" fill="#7C3AED"/>');
      overLayer.add('<circle cx="64.0" cy="75.0" r="1.9" fill="#8B5CF6"/>');
      overLayer.add('<circle cx="69.0" cy="75.0" r="1.9" fill="#A78BFA"/>');
    case MotifKind.lightRays:
      overLayer.add('<line x1="64" y1="76" x2="64" y2="11" stroke="#FBBF24" stroke-width="2.5" stroke-linecap="round"/>');
      overLayer.add('<line x1="64" y1="76" x2="116" y2="106" stroke="#F59E0B" stroke-width="2.5" stroke-linecap="round"/>');
      overLayer.add('<line x1="64" y1="76" x2="12" y2="106" stroke="#F59E0B" stroke-width="2.5" stroke-linecap="round"/>');
    case MotifKind.probeLobes:
      overLayer.add('<path d="M 64 65.5 Q 66.2 73.8 74.5 76 Q 66.2 78.2 64 86.5 Q 61.8 78.2 53.5 76 Q 61.8 73.8 64 65.5 Z" fill="#F59E0B"/>');
    case MotifKind.skyHorizon:
      overLayer.add('<circle cx="64" cy="60.5" r="5.2" fill="#FBBF24"/>');
    case MotifKind.vfxSparks:
      overLayer.add('<polygon points="64,9 68.5,17 59.5,17" fill="#FB7185"/>');
      overLayer.add('<polygon points="118,108 110,109 114,101" fill="#F43F5E"/>');
      overLayer.add('<polygon points="10,108 18,109 14,101" fill="#FB923C"/>');
    case MotifKind.foliageVeins:
      overLayer.add(
        '<path d="M 64 56 Q 66 44 64 31 M 81 85 Q 92 91 101 98 M 47 85 Q 36 91 27 98" '
        'stroke="#6EE7B7" stroke-width="2.0" stroke-linecap="round" opacity="0.88"/>',
      );
    case MotifKind.physImpulse:
      overLayer.add('<path d="M 79 34 A 24 24 0 0 1 94 52" stroke="#34D399" stroke-width="2.5" stroke-linecap="round"/>');
    case MotifKind.wheelCog:
      overLayer.add('<circle cx="64" cy="76" r="7.0" fill="none" stroke="${spec.centerColor ?? spec.colors.first}" stroke-width="2.4"/>');
    case MotifKind.ragdollJoints:
      for (var k = 0; k < 3; k++) {
        final a = (-90.0 + spec.twistDeg + k * 120.0) * math.pi / 180.0;
        final px = cx + (spec.innerR + 6) * math.cos(a);
        final py = cy + (spec.innerR + 6) * math.sin(a);
        overLayer.add('<circle cx="${f(px)}" cy="${f(py)}" r="3.4" fill="#2DD4BF"/>');
      }
    case MotifKind.crowdBoids:
      overLayer.add('<polygon points="64,69.5 67.5,75 64,73.5 60.5,75" fill="#38BDF8"/>');
      overLayer.add('<polygon points="58.5,78 62.5,82 59.5,80.5 57.5,82" fill="#059669"/>');
      overLayer.add('<polygon points="69.5,78 70.5,82 68.5,80.5 65.5,82" fill="#2DD4BF"/>');
    case MotifKind.trafficLanes:
      overLayer.add('<circle cx="64" cy="70.5" r="2.0" fill="#F43F5E"/>');
      overLayer.add('<circle cx="64" cy="76.0" r="2.0" fill="#FBBF24"/>');
      overLayer.add('<circle cx="64" cy="81.5" r="2.0" fill="#10B981"/>');
    case MotifKind.aiNodes:
      for (var k = 0; k < 3; k++) {
        final a = (-90.0 + spec.twistDeg + k * 120.0) * math.pi / 180.0;
        overLayer.add('<circle cx="${f(cx + 21 * math.cos(a))}" cy="${f(cy + 21 * math.sin(a))}" r="3.2" fill="#38BDF8"/>');
      }
    case MotifKind.pathCurve:
      overLayer.add('<path d="M 59 73 Q 64 70.5 69 75.5 T 64 82.5" stroke="#818CF8" stroke-width="1.8" stroke-dasharray="2 2.4" stroke-linecap="round"/>');
      overLayer.add('<circle cx="58.5" cy="72.5" r="2.2" fill="#38BDF8"/>');
      overLayer.add('<circle cx="68.5" cy="75.5" r="2.2" fill="#38BDF8"/>');
      overLayer.add('<circle cx="64.0" cy="82.5" r="2.5" fill="#6366F1"/>');
    case MotifKind.flowPorts:
      overLayer.add('<path d="M 58.5 76.5 C 62 76.5 64 73.5 69.5 73.5" stroke="#38BDF8" stroke-width="2.0" stroke-linecap="round"/>');
      overLayer.add('<circle cx="58.5" cy="76.5" r="2.6" fill="#38BDF8"/>');
      overLayer.add('<circle cx="69.5" cy="73.5" r="2.6" fill="#A78BFA"/>');
    case MotifKind.circuitTraces:
      overLayer.add('<path d="M 64 69.5 L 64 75.5 L 68.5 79.5" stroke="#0EA5E9" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>');
      overLayer.add('<circle cx="64" cy="69.5" r="1.8" fill="#0EA5E9"/>');
      overLayer.add('<circle cx="68.5" cy="79.5" r="2.4" fill="#38BDF8"/>');
    case MotifKind.questFork:
      overLayer.add('<path d="M 64 84.5 L 64 77 M 64 77 L 58.5 71 M 64 77 L 69.5 71" stroke="#F59E0B" stroke-width="2.3" stroke-linecap="round"/>');
      overLayer.add('<circle cx="58.5" cy="71" r="2.2" fill="#F59E0B"/>');
      overLayer.add('<circle cx="69.5" cy="71" r="2.2" fill="#EC4899"/>');
    case MotifKind.archRooms:
      overLayer.add('<rect x="59" y="88" width="10" height="5" rx="1.2" fill="#38BDF8"/>');
    case MotifKind.buildSockets:
      overLayer.add('<rect x="61.5" y="53" width="5" height="5" rx="1" fill="#38BDF8"/>');
      overLayer.add('<rect x="75" y="82" width="5" height="5" rx="1" fill="#60A5FA"/>');
      overLayer.add('<rect x="48" y="82" width="5" height="5" rx="1" fill="#2563EB"/>');
    case MotifKind.locMeridian:
      overLayer.add('<circle cx="64" cy="76" r="6.4" stroke="#0EA5E9" stroke-width="1.8"/>');
      overLayer.add('<ellipse cx="64" cy="76" rx="3.0" ry="6.4" stroke="#0EA5E9" stroke-width="1.4"/>');
      overLayer.add('<line x1="57.6" y1="76" x2="70.4" y2="76" stroke="#0EA5E9" stroke-width="1.4"/>');
    case MotifKind.logChevron:
      overLayer.add('<path d="M 58.0 72.0 L 62.2 75.8 L 58.0 79.6" stroke="#0EA5E9" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>');
      overLayer.add('<line x1="64.2" y1="79.6" x2="69.8" y2="79.6" stroke="#38BDF8" stroke-width="2.3" stroke-linecap="round"/>');
    case MotifKind.uiWindow:
      break;
    case MotifKind.padCluster:
      overLayer.add('<path d="M 64 70.5 L 64 81.5 M 58.5 76 L 69.5 76" stroke="#3B82F6" stroke-width="3.0" stroke-linecap="round"/>');
    case MotifKind.rhythmBeat:
      overLayer.add('<line x1="25" y1="84" x2="103" y2="84" stroke="#F43F5E" stroke-width="2.4" stroke-linecap="round"/>');
      overLayer.add('<polygon points="64,77.5 70.5,84 64,90.5 57.5,84" fill="#FB923C"/>');
      overLayer.add('<circle cx="48" cy="84" r="2.8" fill="#F43F5E"/>');
      overLayer.add('<circle cx="80" cy="84" r="2.8" fill="#FB7185"/>');
    case MotifKind.gaitStrides:
      overLayer.add('<path d="M 52 79 Q 58 68 64 78" stroke="#10B981" stroke-width="2.2" stroke-linecap="round"/>');
      overLayer.add('<path d="M 64 79 Q 70 68 76 78" stroke="#34D399" stroke-width="2.2" stroke-linecap="round" stroke-dasharray="2.4 2.2"/>');
      overLayer.add('<circle cx="52" cy="79" r="2.2" fill="#059669"/>');
      overLayer.add('<circle cx="64" cy="79" r="2.2" fill="#10B981"/>');
      overLayer.add('<circle cx="76" cy="79" r="2.2" fill="#34D399"/>');
    case MotifKind.atlasGrid:
      overLayer.add('<rect x="55" y="67.5" width="10.2" height="7.5" rx="1.4" fill="#38BDF8"/>');
      overLayer.add('<rect x="66.8" y="67.5" width="6.4" height="10.8" rx="1.4" fill="#F59E0B"/>');
      overLayer.add('<rect x="55" y="76.8" width="10.2" height="6.2" rx="1.4" fill="#34D399"/>');
      overLayer.add('<rect x="66.8" y="79.8" width="6.4" height="3.2" rx="1.0" fill="#818CF8"/>');
    case MotifKind.lensDolly:
      overLayer.add('<circle cx="64" cy="76" r="8.2" stroke="#38BDF8" stroke-width="2.1"/>');
      overLayer.add('<path d="M 30 112 Q 64 103 98 112" stroke="#22D3EE" stroke-width="2.6" stroke-linecap="round" stroke-dasharray="6 4"/>');
      overLayer.add('<circle cx="64" cy="107.5" r="2.6" fill="#F59E0B"/>');
    case MotifKind.broadSweep:
      overLayer.add('<rect x="55" y="69" width="7.5" height="7.5" rx="1.2" stroke="#34D399" stroke-width="1.9"/>');
      overLayer.add('<rect x="65.5" y="75" width="7.5" height="7.5" rx="1.2" stroke="#22D3EE" stroke-width="1.9"/>');
      overLayer.add('<path d="M 54 83 L 74 68" stroke="#F59E0B" stroke-width="2.1" stroke-linecap="round"/>');
      overLayer.add('<circle cx="74" cy="68" r="2.1" fill="#F59E0B"/>');
    case MotifKind.ribbonSwirl:
      overLayer.add('<path d="M 55 83 C 58 70 70 82 73 69" stroke="#FB7185" stroke-width="2.6" stroke-linecap="round"/>');
      overLayer.add('<path d="M 55 76 C 58 63 70 75 73 62" stroke="#38BDF8" stroke-width="1.8" stroke-linecap="round" opacity="0.88"/>');
    case MotifKind.steerWedge:
      overLayer.add('<polygon points="64,67.5 68.5,75.5 64,73.5 59.5,75.5" fill="#34D399"/>');
      overLayer.add('<polygon points="56.5,77.5 60.5,83.5 56.5,81.8 52.5,83.5" fill="#10B981"/>');
      overLayer.add('<polygon points="71.5,77.5 75.5,83.5 71.5,81.8 67.5,83.5" fill="#2DD4BF"/>');
    case MotifKind.dagNodes:
      overLayer.add('<line x1="56.5" y1="71.5" x2="64" y2="81.5" stroke="#38BDF8" stroke-width="1.8"/>');
      overLayer.add('<line x1="71.5" y1="71.5" x2="64" y2="81.5" stroke="#818CF8" stroke-width="1.8"/>');
      overLayer.add('<circle cx="56.5" cy="71.5" r="2.7" fill="#38BDF8"/>');
      overLayer.add('<circle cx="71.5" cy="71.5" r="2.7" fill="#818CF8"/>');
      overLayer.add('<circle cx="64.0" cy="81.5" r="3.0" fill="#F59E0B"/>');
    case MotifKind.blendCross:
      overLayer.add('<path d="M 55 82 C 60 82 68 70 73 70" stroke="#F43F5E" stroke-width="2.2" stroke-linecap="round"/>');
      overLayer.add('<path d="M 55 70 C 60 70 68 82 73 82" stroke="#38BDF8" stroke-width="2.2" stroke-linecap="round"/>');
      overLayer.add('<circle cx="64.0" cy="76.0" r="2.6" fill="#F59E0B"/>');
    case MotifKind.shadowCascades:
      overLayer.add('<polygon points="64,67.5 68.5,73 59.5,73" fill="#FBBF24"/>');
      overLayer.add('<polygon points="57.5,75.5 70.5,75.5 72.5,79 55.5,79" fill="#94A3B8"/>');
      overLayer.add('<polygon points="54.5,81 73.5,81 75.5,84.5 52.5,84.5" fill="#475569"/>');
    case MotifKind.splineRibbon:
      overLayer.add('<path d="M 54 83 C 58 67 70 85 74 69" stroke="#38BDF8" stroke-width="2.4" stroke-linecap="round"/>');
      overLayer.add('<circle cx="54" cy="83" r="2.2" fill="#2DD4BF"/>');
      overLayer.add('<circle cx="64" cy="76" r="2.2" fill="#F59E0B"/>');
      overLayer.add('<circle cx="74" cy="69" r="2.2" fill="#38BDF8"/>');
    case MotifKind.allocArena:
      overLayer.add('<rect x="54.5" y="69.5" width="7" height="5" rx="1" fill="#34D399"/>');
      overLayer.add('<rect x="63.0" y="69.5" width="10.5" height="5" rx="1" fill="#38BDF8"/>');
      overLayer.add('<rect x="54.5" y="76.5" width="13" height="5" rx="1" fill="#F59E0B"/>');
      overLayer.add('<rect x="69.0" y="76.5" width="4.5" height="5" rx="1" fill="#475569"/>');
    case MotifKind.batchClusters:
      overLayer.add('<rect x="54.5" y="69.0" width="4.8" height="4.8" rx="1" fill="#38BDF8"/>');
      overLayer.add('<rect x="61.6" y="69.0" width="4.8" height="4.8" rx="1" fill="#38BDF8"/>');
      overLayer.add('<rect x="68.7" y="69.0" width="4.8" height="4.8" rx="1" fill="#38BDF8"/>');
      overLayer.add('<rect x="56.5" y="77.5" width="15.0" height="5.2" rx="1.4" fill="#F59E0B"/>');
    case MotifKind.ikLimbs:
      overLayer.add('<path d="M 55 82 L 64 70 L 73 79" stroke="#2DD4BF" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>');
      overLayer.add('<circle cx="55" cy="82" r="2.2" fill="#38BDF8"/>');
      overLayer.add('<circle cx="64" cy="70" r="2.4" fill="#F59E0B"/>');
      overLayer.add('<circle cx="73" cy="79" r="2.4" fill="#34D399"/>');
    case MotifKind.curveWave:
      overLayer.add('<path d="M 53.5 82 L 58.0 69.5 L 65.5 73.5 L 71.0 73.5 L 74.5 82" stroke="#F43F5E" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>');
      overLayer.add('<circle cx="58.0" cy="69.5" r="2.1" fill="#FBBF24"/>');
      overLayer.add('<circle cx="65.5" cy="73.5" r="2.0" fill="#FB923C"/>');
      overLayer.add('<circle cx="71.0" cy="73.5" r="2.0" fill="#38BDF8"/>');
    case MotifKind.octreeBoxes:
      overLayer.add('<rect x="54.0" y="67.5" width="20.0" height="17.0" rx="2.0" stroke="#38BDF8" stroke-width="1.9"/>');
      overLayer.add('<line x1="64.0" y1="67.5" x2="64.0" y2="84.5" stroke="#38BDF8" stroke-width="1.4" opacity="0.8"/>');
      overLayer.add('<line x1="54.0" y1="76.0" x2="74.0" y2="76.0" stroke="#38BDF8" stroke-width="1.4" opacity="0.8"/>');
      overLayer.add('<rect x="65.5" y="69.0" width="6.8" height="5.5" rx="1.0" fill="#34D399"/>');
    default:
      break;
  }

  // 5. Center Emblem
  if (spec.centerDotR > 0.1 && spec.centerShape != 'none') {
    final cCol = spec.centerColor ?? spec.colors.first;
    switch (spec.centerShape) {
      case 'circle':
        overLayer.add('<circle cx="$cx" cy="$cy" r="${f(spec.centerDotR)}" fill="$cCol"/>');
      case 'tri':
      case 'upTri':
        final baseDeg = spec.centerShape == 'upTri' ? -90.0 : 90.0;
        final pts = List.generate(3, (i) {
          final a = (baseDeg + i * 120.0) * math.pi / 180.0;
          return '${f(cx + spec.centerDotR * math.cos(a))},${f(cy + spec.centerDotR * math.sin(a))}';
        }).join(' ');
        overLayer.add('<polygon points="$pts" fill="$cCol"/>');
      case 'diamond':
        final d = spec.centerDotR;
        overLayer.add(
          '<polygon points="$cx,${f(cy - d)} ${f(cx + d)},$cy $cx,${f(cy + d)} ${f(cx - d)},$cy" fill="$cCol"/>',
        );
      case 'hex':
        final pts = List.generate(6, (i) {
          final a = (i * 60.0) * math.pi / 180.0;
          return '${f(cx + spec.centerDotR * math.cos(a))},${f(cy + spec.centerDotR * math.sin(a))}';
        }).join(' ');
        overLayer.add('<polygon points="$pts" fill="$cCol"/>');
    }
  }

  final allEls = [...underLayer, ...bodyLayer, ...overLayer];
  return '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" fill="none">
  <title>${spec.name}</title>
  ${allEls.join('\n  ')}
</svg>
''';
}

const List<LogoSpec> allLogoSpecs = [
  LogoSpec(
    name: 'glVolition',
    category: 'Flagship Engine',
    motif: MotifKind.standard,
    blades: 3,
    outerR: 56,
    innerR: 14.5,
    twistDeg: 28,
    gap: 4.6,
    cornerFillet: 7.0,
    colors: ['#38BDF8', '#0EA5E9', '#0284C7'],
  ),
  LogoSpec(
    name: 'pixeldart',
    category: 'Rendering',
    motif: MotifKind.pixelCorner,
    blades: 6,
    outerR: 55,
    innerR: 14.0,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 7.0,
    colors: ['#38BDF8', '#6366F1'],
  ),
  LogoSpec(
    name: 'voxvox',
    category: 'World & Geometry',
    motif: MotifKind.voxelSteps,
    blades: 3,
    outerR: 57,
    innerR: 15.5,
    twistDeg: 60,
    gap: 4.4,
    cornerFillet: 2.0,
    chamferCorners: 7.5,
    centerShape: 'hex',
    centerDotR: 4.8,
    centerColor: '#38BDF8',
    colors: ['#22D3EE', '#0EA5E9', '#0284C7'],
  ),
  LogoSpec(
    name: 'voxsdf',
    category: 'World & Geometry',
    motif: MotifKind.sdfContour,
    blades: 3,
    outerR: 57,
    innerR: 17.5,
    twistDeg: 24,
    gap: 4.4,
    cornerFillet: 12.0,
    innerTipFillet: 4.5,
    centerShape: 'circle',
    centerDotR: 4.6,
    centerColor: '#0284C7',
    colors: ['#22D3EE', '#06B6D4', '#0891B2'],
  ),
  LogoSpec(
    name: 'voxgeom',
    category: 'World & Geometry',
    motif: MotifKind.navMeshTris,
    blades: 3,
    outerR: 56,
    innerR: 16.0,
    twistDeg: 60,
    gap: 4.0,
    cornerFillet: 3.5,
    centerShape: 'upTri',
    centerDotR: 5.5,
    centerColor: '#38BDF8',
    colors: ['#0EA5E9', '#0284C7', '#0369A1'],
  ),
  LogoSpec(
    name: 'voxgrid',
    category: 'World & Geometry',
    motif: MotifKind.gridCrosshair,
    blades: 3,
    outerR: 56,
    innerR: 14.0,
    twistDeg: 28,
    gap: 3.6,
    cornerFillet: 5.0,
    centerShape: 'diamond',
    centerDotR: 4.0,
    centerColor: '#2563EB',
    colors: ['#60A5FA', '#3B82F6', '#1D4ED8'],
  ),
  LogoSpec(
    name: 'voxextrude',
    category: 'World & Geometry',
    motif: MotifKind.curveTween,
    blades: 3,
    outerR: 57,
    innerR: 15.5,
    twistDeg: 22,
    gap: 4.4,
    cornerFillet: 7.5,
    chamferCorners: 6.5,
    colors: ['#38BDF8', '#2DD4BF', '#0EA5E9'],
  ),
  LogoSpec(
    name: 'voxfracture',
    category: 'World & Geometry',
    motif: MotifKind.shatterShards,
    blades: 3,
    outerR: 54,
    innerR: 14.5,
    twistDeg: 26,
    gap: 4.8,
    cornerFillet: 2.0,
    centerShape: 'tri',
    centerDotR: 4.5,
    centerColor: '#F43F5E',
    colors: ['#38BDF8', '#0EA5E9', '#586982'],
  ),
  LogoSpec(
    name: 'voxdecal',
    category: 'World & Geometry',
    motif: MotifKind.decalPeel,
    blades: 3,
    outerR: 56,
    innerR: 14.5,
    twistDeg: 30,
    gap: 4.2,
    cornerFillet: 6.5,
    colors: ['#38BDF8', '#72839B', '#586982'],
  ),
  LogoSpec(
    name: 'voxbiome',
    category: 'World & Geometry',
    motif: MotifKind.terrainStrata,
    blades: 3,
    outerR: 56,
    innerR: 15.0,
    twistDeg: 26,
    gap: 4.0,
    cornerFillet: 7.5,
    colors: ['#34D399', '#22D3EE', '#0EA5E9'],
  ),
  LogoSpec(
    name: 'voxarch',
    category: 'World & Geometry',
    motif: MotifKind.archRooms,
    blades: 3,
    outerR: 56,
    innerR: 17.5,
    twistDeg: 60,
    gap: 4.4,
    cornerFillet: 4.0,
    centerShape: 'upTri',
    centerDotR: 5.0,
    centerColor: '#60A5FA',
    colors: ['#60A5FA', '#3B82F6', '#1D4ED8'],
  ),
  LogoSpec(
    name: 'voxbuild',
    category: 'World & Geometry',
    motif: MotifKind.buildSockets,
    blades: 3,
    outerR: 57,
    innerR: 17.0,
    twistDeg: 58,
    gap: 4.4,
    cornerFillet: 4.0,
    chamferCorners: 7.5,
    centerShape: 'diamond',
    centerDotR: 4.4,
    centerColor: '#0EA5E9',
    colors: ['#3B82F6', '#2563EB', '#586982'],
  ),
  LogoSpec(
    name: 'voxfoliage',
    category: 'World & Geometry',
    motif: MotifKind.foliageVeins,
    blades: 3,
    outerR: 56,
    innerR: 14.5,
    twistDeg: 26,
    gap: 4.4,
    cornerFillet: 9.0,
    colors: ['#34D399', '#10B981', '#059669'],
  ),
  LogoSpec(
    name: 'voxprobe',
    category: 'Lighting & Optics',
    motif: MotifKind.probeLobes,
    blades: 6,
    outerR: 56,
    innerR: 16.0,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 7.0,
    colors: ['#38BDF8', '#0284C7'],
  ),
  LogoSpec(
    name: 'voxlight',
    category: 'Lighting & Optics',
    motif: MotifKind.lightRays,
    blades: 6,
    outerR: 56,
    innerR: 14.0,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 7.0,
    centerShape: 'circle',
    centerDotR: 4.4,
    centerColor: '#EA580C',
    colors: ['#FBBF24', '#F59E0B'],
  ),
  LogoSpec(
    name: 'voxcam',
    category: 'Lighting & Optics',
    motif: MotifKind.camViewfinder,
    blades: 6,
    outerR: 52,
    innerR: 14.5,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 7.0,
    centerShape: 'circle',
    centerDotR: 4.2,
    centerColor: '#38BDF8',
    colors: ['#586982', '#72839B'],
  ),
  LogoSpec(
    name: 'voxlens',
    category: 'Lighting & Optics',
    motif: MotifKind.lensDolly,
    blades: 6,
    outerR: 53,
    innerR: 15.5,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 7.0,
    centerShape: 'circle',
    centerDotR: 3.4,
    centerColor: '#38BDF8',
    colors: ['#0EA5E9', '#3B82F6'],
  ),
  LogoSpec(
    name: 'voxatlas',
    category: 'Rendering',
    motif: MotifKind.atlasGrid,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 6.5,
    colors: ['#0EA5E9', '#6366F1', '#38BDF8'],
  ),
  LogoSpec(
    name: 'voxbroad',
    category: 'Physics & Motion',
    motif: MotifKind.broadSweep,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 6.0,
    colors: ['#10B981', '#14B8A6', '#0D9488'],
  ),
  LogoSpec(
    name: 'voxribbon',
    category: 'Rendering',
    motif: MotifKind.ribbonSwirl,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 8.5,
    colors: ['#F43F5E', '#FB7185', '#EC4899'],
  ),
  LogoSpec(
    name: 'voxsteer',
    category: 'AI & Logic',
    motif: MotifKind.steerWedge,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 7.0,
    colors: ['#10B981', '#2DD4BF', '#059669'],
  ),
  LogoSpec(
    name: 'voxgraph',
    category: 'Rendering',
    motif: MotifKind.dagNodes,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 6.0,
    colors: ['#38BDF8', '#6366F1', '#0284C7'],
  ),
  LogoSpec(
    name: 'voxblend',
    category: 'Physics & Motion',
    motif: MotifKind.blendCross,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 7.5,
    colors: ['#EC4899', '#8B5CF6', '#38BDF8'],
  ),
  LogoSpec(
    name: 'voxshadow',
    category: 'Lighting & Optics',
    motif: MotifKind.shadowCascades,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 5.5,
    colors: ['#475569', '#64748B', '#0EA5E9'],
  ),
  LogoSpec(
    name: 'voxspline3d',
    category: 'World & Geometry',
    motif: MotifKind.splineRibbon,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 8.0,
    colors: ['#06B6D4', '#38BDF8', '#2DD4BF'],
  ),
  LogoSpec(
    name: 'voxalloc',
    category: 'Core & Systems',
    motif: MotifKind.allocArena,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 5.5,
    colors: ['#10B981', '#0EA5E9', '#6366F1'],
  ),
  LogoSpec(
    name: 'voxbatch',
    category: 'Rendering',
    motif: MotifKind.batchClusters,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 6.0,
    colors: ['#0EA5E9', '#3B82F6', '#6366F1'],
  ),
  LogoSpec(
    name: 'voxik2d',
    category: 'Physics & Motion',
    motif: MotifKind.ikLimbs,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 7.0,
    colors: ['#2DD4BF', '#10B981', '#059669'],
  ),
  LogoSpec(
    name: 'voxcurve',
    category: 'Physics & Motion',
    motif: MotifKind.curveWave,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 7.5,
    colors: ['#FB7185', '#F43F5E', '#E11D48'],
  ),
  LogoSpec(
    name: 'voxoctree',
    category: 'World & Geometry',
    motif: MotifKind.octreeBoxes,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 5.5,
    colors: ['#38BDF8', '#0EA5E9', '#0284C7'],
  ),
  LogoSpec(
    name: 'voxsky',
    category: 'Lighting & Optics',
    motif: MotifKind.skyHorizon,
    blades: 3,
    outerR: 41,
    innerR: 12.0,
    twistDeg: 28,
    gap: 3.6,
    cornerFillet: 4.5,
    outerRingR: 55,
    outerRingStroke: 3.5,
    outerRingColor: '#38BDF8',
    colors: ['#38BDF8', '#818CF8', '#0EA5E9'],
  ),
  LogoSpec(
    name: 'voxphys',
    category: 'Physics & Motion',
    motif: MotifKind.physImpulse,
    blades: 3,
    outerR: 54,
    innerR: 14.5,
    twistDeg: 26,
    gap: 4.4,
    cornerFillet: 6.5,
    colors: ['#34D399', '#10B981', '#059669'],
  ),
  LogoSpec(
    name: 'voxcloth',
    category: 'Physics & Motion',
    motif: MotifKind.clothDrape,
    blades: 3,
    outerR: 56,
    innerR: 15.5,
    twistDeg: 24,
    gap: 4.4,
    cornerFillet: 9.0,
    colors: ['#2DD4BF', '#14B8A6', '#0D9488'],
  ),
  LogoSpec(
    name: 'voxfluid',
    category: 'Physics & Motion',
    motif: MotifKind.waveFluid,
    blades: 3,
    outerR: 55,
    innerR: 16.5,
    twistDeg: 26,
    gap: 4.6,
    cornerFillet: 7.0,
    centerShape: 'circle',
    centerDotR: 4.2,
    centerColor: '#0EA5E9',
    colors: ['#2DD4BF', '#14B8A6', '#0D9488'],
  ),
  LogoSpec(
    name: 'voxwheel',
    category: 'Physics & Motion',
    motif: MotifKind.wheelCog,
    blades: 6,
    outerR: 57,
    innerR: 14.5,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 5.0,
    chamferCorners: 7.0,
    centerShape: 'circle',
    centerDotR: 3.5,
    centerColor: '#10B981',
    colors: ['#10B981', '#586982'],
  ),
  LogoSpec(
    name: 'voxragdoll',
    category: 'Physics & Motion',
    motif: MotifKind.ragdollJoints,
    blades: 3,
    outerR: 57,
    innerR: 15.0,
    twistDeg: 24,
    gap: 4.4,
    cornerFillet: 6.0,
    chamferCorners: 7.5,
    centerShape: 'circle',
    centerDotR: 4.0,
    centerColor: '#2DD4BF',
    colors: ['#10B981', '#0D9488', '#0F766E'],
  ),
  LogoSpec(
    name: 'voxgait',
    category: 'Physics & Motion',
    motif: MotifKind.gaitStrides,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 7.0,
    colors: ['#34D399', '#10B981', '#059669'],
  ),
  LogoSpec(
    name: 'voxcrowd',
    category: 'Physics & Motion',
    motif: MotifKind.crowdBoids,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 7.0,
    colors: ['#2DD4BF', '#0EA5E9', '#059669'],
  ),
  LogoSpec(
    name: 'voxtraffic',
    category: 'Physics & Motion',
    motif: MotifKind.trafficLanes,
    blades: 3,
    outerR: 56,
    innerR: 22.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 6.0,
    colors: ['#10B981', '#586982', '#72839B'],
  ),
  LogoSpec(
    name: 'voxanim',
    category: 'Physics & Motion',
    motif: MotifKind.curveTween,
    blades: 3,
    outerR: 56,
    innerR: 16.0,
    twistDeg: 24,
    gap: 4.4,
    cornerFillet: 8.5,
    colors: ['#34D399', '#22D3EE', '#38BDF8'],
  ),
  LogoSpec(
    name: 'voxtween',
    category: 'Physics & Motion',
    motif: MotifKind.curveTween,
    blades: 3,
    outerR: 40,
    innerR: 12.0,
    twistDeg: 26,
    gap: 3.6,
    cornerFillet: 5.0,
    outerRingR: 55,
    outerRingStroke: 3.4,
    outerRingColor: '#2DD4BF',
    colors: ['#2DD4BF', '#06B6D4', '#0891B2'],
  ),
  LogoSpec(
    name: 'voxai',
    category: 'AI & Logic',
    motif: MotifKind.aiNodes,
    blades: 3,
    outerR: 57,
    innerR: 18.0,
    twistDeg: 58,
    gap: 4.4,
    cornerFillet: 4.0,
    chamferCorners: 8.0,
    centerShape: 'diamond',
    centerDotR: 4.8,
    centerColor: '#38BDF8',
    colors: ['#818CF8', '#6366F1', '#4F46E5'],
  ),
  LogoSpec(
    name: 'voxhtn',
    category: 'AI & Logic',
    motif: MotifKind.htnTreeTiers,
    blades: 3,
    outerR: 56,
    innerR: 15.5,
    twistDeg: 24,
    gap: 4.2,
    cornerFillet: 6.5,
    centerShape: 'tri',
    centerDotR: 5.0,
    centerColor: '#6366F1',
    colors: ['#A78BFA', '#8B5CF6', '#7C3AED'],
  ),
  LogoSpec(
    name: 'voxpath',
    category: 'AI & Logic',
    motif: MotifKind.pathCurve,
    blades: 3,
    outerR: 56,
    innerR: 21.5,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 6.5,
    colors: ['#818CF8', '#6366F1', '#4338CA'],
  ),
  LogoSpec(
    name: 'voxnav3d',
    category: 'AI & Logic',
    motif: MotifKind.navMeshTris,
    blades: 6,
    outerR: 56,
    innerR: 14.5,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 5.5,
    centerShape: 'tri',
    centerDotR: 4.4,
    centerColor: '#6366F1',
    colors: ['#818CF8', '#7C3AED', '#A78BFA'],
  ),
  LogoSpec(
    name: 'voxflow',
    category: 'AI & Logic',
    motif: MotifKind.flowPorts,
    blades: 3,
    outerR: 57,
    innerR: 21.5,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 6.0,
    chamferCorners: 6.5,
    colors: ['#A78BFA', '#6366F1', '#4F46E5'],
  ),
  LogoSpec(
    name: 'voxcircuit',
    category: 'AI & Logic',
    motif: MotifKind.circuitTraces,
    blades: 3,
    outerR: 56,
    innerR: 21.5,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 3.0,
    colors: ['#818CF8', '#38BDF8', '#4F46E5'],
  ),
  LogoSpec(
    name: 'voxrule',
    category: 'AI & Logic',
    motif: MotifKind.ruleShield,
    blades: 3,
    outerR: 56,
    innerR: 15.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 6.0,
    centerShape: 'diamond',
    centerDotR: 4.6,
    centerColor: '#F472B6',
    colors: ['#A855F7', '#586982', '#72839B'],
  ),
  LogoSpec(
    name: 'voxquest',
    category: 'AI & Logic',
    motif: MotifKind.questFork,
    blades: 3,
    outerR: 56,
    innerR: 21.5,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 7.0,
    colors: ['#A78BFA', '#8B5CF6', '#EC4899'],
  ),
  LogoSpec(
    name: 'voxtalk',
    category: 'AI & Logic',
    motif: MotifKind.talkBubble,
    blades: 3,
    outerR: 55,
    innerR: 21.0,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 8.5,
    colors: ['#C084FC', '#A78BFA', '#7C3AED'],
  ),
  LogoSpec(
    name: 'voxhex',
    category: 'AI & Logic',
    motif: MotifKind.hexComb,
    blades: 6,
    outerR: 58,
    innerR: 15.0,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 4.5,
    chamferCorners: 9.0,
    centerShape: 'hex',
    centerDotR: 4.8,
    centerColor: '#6366F1',
    colors: ['#818CF8', '#7C3AED'],
  ),
  LogoSpec(
    name: 'voxproc',
    category: 'AI & Logic',
    motif: MotifKind.archRooms,
    blades: 3,
    outerR: 58,
    innerR: 15.5,
    twistDeg: 28,
    gap: 4.2,
    cornerFillet: 4.0,
    chamferCorners: 8.0,
    colors: ['#A78BFA', '#7C3AED', '#5B21B6'],
  ),
  LogoSpec(
    name: 'voxdsp',
    category: 'Audio & VFX',
    motif: MotifKind.dspEq,
    blades: 3,
    outerR: 41,
    innerR: 11.5,
    twistDeg: 26,
    gap: 3.5,
    cornerFillet: 4.5,
    outerRingR: 55,
    outerRingStroke: 3.5,
    outerRingColor: '#FB923C',
    colors: ['#FBBF24', '#F59E0B', '#D97706'],
  ),
  LogoSpec(
    name: 'voxsynth',
    category: 'Audio & VFX',
    motif: MotifKind.synthSaw,
    blades: 3,
    outerR: 56,
    innerR: 15.5,
    twistDeg: 26,
    gap: 4.4,
    cornerFillet: 3.0,
    centerShape: 'diamond',
    centerDotR: 4.4,
    centerColor: '#EA580C',
    colors: ['#FBBF24', '#F59E0B', '#EA580C'],
  ),
  LogoSpec(
    name: 'voxreverb',
    category: 'Audio & VFX',
    motif: MotifKind.reverbEcho,
    blades: 3,
    outerR: 37,
    innerR: 11.0,
    twistDeg: 60,
    gap: 3.4,
    cornerFillet: 5.0,
    centerShape: 'circle',
    centerDotR: 3.6,
    centerColor: '#EC4899',
    colors: ['#F472B6', '#EC4899', '#DB2777'],
  ),
  LogoSpec(
    name: 'voxscore',
    category: 'Audio & VFX',
    motif: MotifKind.scoreStems,
    blades: 3,
    outerR: 41,
    innerR: 11.5,
    twistDeg: 28,
    gap: 3.6,
    cornerFillet: 4.5,
    outerRingR: 55,
    outerRingStroke: 3.6,
    outerRingColor: '#F97316',
    centerShape: 'circle',
    centerDotR: 3.6,
    centerColor: '#EA580C',
    colors: ['#FB923C', '#F97316', '#EA580C'],
  ),
  LogoSpec(
    name: 'voxrhythm',
    category: 'Audio & VFX',
    motif: MotifKind.rhythmBeat,
    blades: 3,
    outerR: 41,
    innerR: 12.0,
    twistDeg: 60,
    gap: 3.6,
    cornerFillet: 4.5,
    outerRingR: 55,
    outerRingStroke: 3.5,
    outerRingColor: '#F43F5E',
    colors: ['#FB7185', '#F43F5E', '#E11D48'],
  ),
  LogoSpec(
    name: 'voxvfx',
    category: 'Audio & VFX',
    motif: MotifKind.vfxSparks,
    blades: 6,
    outerR: 54,
    innerR: 14.5,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 7.0,
    centerShape: 'diamond',
    centerDotR: 4.2,
    centerColor: '#E11D48',
    colors: ['#FB7185', '#F43F5E'],
  ),
  LogoSpec(
    name: 'voxseq',
    category: 'Audio & VFX',
    motif: MotifKind.seqTimeline,
    blades: 3,
    outerR: 56,
    innerR: 15.0,
    twistDeg: 30,
    gap: 4.2,
    cornerFillet: 6.5,
    colors: ['#FB923C', '#F43F5E', '#E11D48'],
  ),
  LogoSpec(
    name: 'voxecs',
    category: 'Core & Systems',
    motif: MotifKind.fractureTris,
    blades: 3,
    outerR: 56,
    innerR: 16.5,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 3.5,
    centerShape: 'upTri',
    centerDotR: 5.4,
    centerColor: '#38BDF8',
    colors: ['#60A5FA', '#52627A', '#72839B'],
  ),
  LogoSpec(
    name: 'voxui',
    category: 'Core & Systems',
    motif: MotifKind.uiWindow,
    blades: 3,
    outerR: 40,
    innerR: 11.5,
    twistDeg: 24,
    gap: 3.5,
    cornerFillet: 5.0,
    outerRingR: 55,
    outerRingStroke: 3.5,
    outerRingColor: '#60A5FA',
    colors: ['#60A5FA', '#3B82F6', '#2563EB'],
  ),
  LogoSpec(
    name: 'voxlog',
    category: 'Core & Systems',
    motif: MotifKind.logChevron,
    blades: 3,
    outerR: 56,
    innerR: 21.5,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 7.0,
    colors: ['#38BDF8', '#72839B', '#52627A'],
  ),
  LogoSpec(
    name: 'voxnet',
    category: 'Core & Systems',
    motif: MotifKind.netArcs,
    blades: 6,
    outerR: 50,
    innerR: 13.5,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 6.5,
    centerShape: 'circle',
    centerDotR: 4.0,
    centerColor: '#0EA5E9',
    colors: ['#60A5FA', '#06B6D4'],
  ),
  LogoSpec(
    name: 'voxrollback',
    category: 'Core & Systems',
    motif: MotifKind.ghostEcho,
    blades: 3,
    outerR: 55,
    innerR: 16.5,
    twistDeg: 54,
    gap: 4.4,
    cornerFillet: 6.5,
    centerShape: 'circle',
    centerDotR: 4.4,
    centerColor: '#38BDF8',
    colors: ['#38BDF8', '#818CF8', '#4F46E5'],
  ),
  LogoSpec(
    name: 'voxsnap',
    category: 'Core & Systems',
    motif: MotifKind.ghostEcho,
    blades: 3,
    outerR: 55,
    innerR: 15.5,
    twistDeg: 24,
    gap: 4.2,
    cornerFillet: 7.0,
    centerShape: 'circle',
    centerDotR: 4.0,
    centerColor: '#0EA5E9',
    colors: ['#38BDF8', '#60A5FA', '#2563EB'],
  ),
  LogoSpec(
    name: 'voxpack',
    category: 'Core & Systems',
    motif: MotifKind.buildSockets,
    blades: 3,
    outerR: 58,
    innerR: 15.5,
    twistDeg: 60,
    gap: 4.4,
    cornerFillet: 4.0,
    chamferCorners: 8.5,
    colors: ['#0EA5E9', '#72839B', '#52627A'],
  ),
  LogoSpec(
    name: 'voxpad',
    category: 'Core & Systems',
    motif: MotifKind.padCluster,
    blades: 3,
    outerR: 56,
    innerR: 21.5,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 8.5,
    colors: ['#60A5FA', '#818CF8', '#3B82F6'],
  ),
  LogoSpec(
    name: 'voxitem',
    category: 'Core & Systems',
    motif: MotifKind.itemCells,
    blades: 3,
    outerR: 57,
    innerR: 15.5,
    twistDeg: 60,
    gap: 4.0,
    cornerFillet: 5.0,
    chamferCorners: 6.5,
    centerShape: 'hex',
    centerDotR: 4.6,
    centerColor: '#F59E0B',
    colors: ['#F59E0B', '#52627A', '#72839B'],
  ),
  LogoSpec(
    name: 'voxcraft',
    category: 'Core & Systems',
    motif: MotifKind.wheelCog,
    blades: 6,
    outerR: 57,
    innerR: 15.0,
    twistDeg: 30,
    gap: 3.4,
    cornerFillet: 4.5,
    chamferCorners: 7.5,
    centerShape: 'hex',
    centerDotR: 4.5,
    centerColor: '#EA580C',
    colors: ['#F59E0B', '#52627A'],
  ),
  LogoSpec(
    name: 'voxloc',
    category: 'Core & Systems',
    motif: MotifKind.locMeridian,
    blades: 3,
    outerR: 56,
    innerR: 21.5,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 7.5,
    colors: ['#38BDF8', '#2DD4BF', '#0EA5E9'],
  ),
  LogoSpec(
    name: 'voxstat',
    category: 'Core & Systems',
    motif: MotifKind.statSteps,
    blades: 3,
    outerR: 54,
    innerR: 14.5,
    twistDeg: 60,
    gap: 4.2,
    cornerFillet: 6.5,
    centerShape: 'diamond',
    centerDotR: 4.6,
    centerColor: '#34D399',
    colors: ['#34D399', '#38BDF8', '#0284C7'],
  ),
];

void _updateReadmeLogo(String readmePath, String title, String description) {
  final file = File(readmePath);
  const blockStart = '<p align="center">';
  final header =
      '<p align="center">\n  <img src="assets/logo.svg" width="88" alt="$title logo"/>\n</p>\n\n';

  if (!file.existsSync()) {
    file.writeAsStringSync('$header# $title\n\n$description\n');
    return;
  }

  final raw = file.readAsStringSync();
  final eol = raw.contains('\r\n') ? '\r\n' : '\n';
  final normalized = header.replaceAll('\n', eol);

  if (raw.startsWith(blockStart) && raw.contains('assets/logo.svg')) {
    const endTag = '</p>';
    final idx = raw.indexOf(endTag);
    if (idx != -1) {
      var rest = raw.substring(idx + endTag.length);
      rest = rest.replaceFirst(RegExp(r'^[\r\n]+'), '');
      file.writeAsStringSync('$normalized$rest');
      return;
    }
  }
  file.writeAsStringSync('$normalized$raw');
}

String _buildGalleryHtml() {
  final cards = allLogoSpecs.map((spec) {
    final svg = renderApertureSvg(spec);
    return '''<div class="card">
  <div class="swatches">
    <div class="preview dark">$svg</div>
    <div class="preview light">$svg</div>
  </div>
  <div class="meta">
    <strong>${spec.name}</strong>
    <span>${spec.motif.name}</span>
  </div>
</div>''';
  }).join('\n');

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>glVolition &amp; Submodule Symbolic Aperture Logos</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; font-family: system-ui, -apple-system, sans-serif; background: #0d1117; color: #e2e8f0; padding: 24px; }
  header { display: flex; align-items: center; gap: 16px; margin-bottom: 20px; border-bottom: 1px solid #30363d; padding-bottom: 16px; }
  header svg { width: 56px; height: 56px; }
  h1 { margin: 0; font-size: 20px; font-weight: 600; }
  p { margin: 4px 0 0; font-size: 13px; color: #94a3b8; }
  .grid { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 12px; }
  .card { background: #161b22; border: 1px solid #30363d; border-radius: 10px; padding: 10px; display: flex; flex-direction: column; gap: 8px; }
  .swatches { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }
  .preview { display: flex; align-items: center; justify-content: center; border-radius: 7px; padding: 8px; height: 64px; }
  .preview.dark { background: #0d1117; border: 1px solid #21262d; }
  .preview.light { background: #ffffff; border: 1px solid #d0d7de; }
  .preview svg { width: 52px; height: 52px; }
  .meta { display: flex; justify-content: space-between; align-items: baseline; font-size: 11px; }
  .meta strong { color: #f8fafc; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  .meta span { color: #94a3b8; font-size: 10px; }
</style>
</head>
<body>
<header>
  ${renderApertureSvg(allLogoSpecs.first)}
  <div>
    <h1>glVolition Symbolic Aperture Triangle System (${allLogoSpecs.length} Marks)</h1>
    <p>Each submodule expresses its architectural intent (waves, fractured sub-triangles, voxel stairs, diffraction echoes, stems, sockets) within the aperture triangle silhouette.</p>
  </div>
</header>
<div class="grid">$cards</div>
</body>
</html>
''';
}

void main(List<String> args) {
  final doApply = args.contains('--apply');
  String? previewPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--preview' && i + 1 < args.length) {
      previewPath = args[i + 1];
    }
  }

  final vendorDir = Directory('vendor');
  final vendorNames = vendorDir.existsSync()
      ? vendorDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toSet()
      : <String>{};
  final specNames = allLogoSpecs.skip(1).map((s) => s.name).toSet();
  final missing = vendorNames.difference(specNames);
  if (missing.isNotEmpty) {
    stderr.writeln('Missing logo specs for submodules: ${missing.join(', ')}');
    exitCode = 1;
    return;
  }

  if (previewPath != null) {
    final file = File(previewPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_buildGalleryHtml());
    stdout.writeln('Generated preview HTML (${allLogoSpecs.length} marks) -> $previewPath');
  }

  if (doApply) {
    final rootLogo = File('assets/logo.svg');
    rootLogo.parent.createSync(recursive: true);
    rootLogo.writeAsStringSync(renderApertureSvg(allLogoSpecs.first));
    _updateReadmeLogo(
      'README.md',
      'glVolition',
      'Unity-style pure-Dart game engine built on pixeldart.',
    );

    for (final spec in allLogoSpecs.skip(1)) {
      final dir = Directory('vendor/${spec.name}');
      if (!dir.existsSync()) continue;
      final outLogo = File('vendor/${spec.name}/assets/logo.svg');
      outLogo.parent.createSync(recursive: true);
      outLogo.writeAsStringSync(renderApertureSvg(spec));
      _updateReadmeLogo(
        'vendor/${spec.name}/README.md',
        spec.name,
        'Pure Dart ${spec.category.toLowerCase()} library for glVolition.',
      );
    }
    stdout.writeln('Applied ${allLogoSpecs.length} symbolic SVG logos across root and ./vendor submodules.');
  } else if (previewPath == null) {
    stdout.writeln('Usage: dart run tool/generate_logos.dart [--preview <out.html>] [--apply]');
  }
}
