/// Regression tests for flicker / discrete topology jumps at the horizon.
///
/// The old `clipRingToHorizon` used a hard `epsDepth` visibility band plus a
/// `firstHidden`-driven array rotation. Both made the clipped fill topology
/// flip discontinuously as the camera drifted a fraction of a degree, which the
/// user saw as "闪跳" (flicker/jump) on meteorological polygons near the limb.
library;

import 'dart:math' as math;

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

/// Nonzero-winding point-in-polygon over a single closed sub-path.
bool _covers(List<Vec2> pts, double x, double y) {
  var winding = 0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    if (a.y <= y) {
      if (b.y > y && _isLeft(a, b, x, y) > 0) winding++;
    } else {
      if (b.y <= y && _isLeft(a, b, x, y) < 0) winding--;
    }
  }
  return winding != 0;
}

double _isLeft(Vec2 a, Vec2 b, double x, double y) =>
    (b.x - a.x) * (y - a.y) - (x - a.x) * (b.y - a.y);

double _hausdorff(List<Vec2> a, List<Vec2> b) {
  double h(List<Vec2> x, List<Vec2> y) {
    var maxD = 0.0;
    for (final p in x) {
      var minD = double.infinity;
      for (final q in y) {
        final d = (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y);
        if (d < minD) minD = d;
      }
      if (minD > maxD) maxD = minD;
    }
    return math.sqrt(maxD);
  }

  return math.max(h(a, b), h(b, a));
}

List<LatLng> _straddling() => subdivideSpherePolyline(
      const [
        LatLng(-30, 40),
        LatLng(30, 40),
        LatLng(30, 130),
        LatLng(-30, 130),
      ],
      closed: true,
    );

CameraState _cam(double centerLng) => CameraState(
      center: LatLng(0, centerLng),
      zoom: 2,
      size: const ViewportSize(600, 420),
    );

void main() {
  group('clipRingToHorizon — no flicker at the limb', () {
    test('stroke run count is stable across a tiny camera sweep', () {
      final ring = _straddling();
      final counts = <int>[];
      for (var i = 0; i <= 10; i++) {
        final cam = _cam(-0.1 + i * 0.02);
        final clipped = clipRingToHorizon(ring, cam)!;
        counts.add(clipped.strokeRuns.length);
      }
      // No discrete run-count flip — the old firstHidden rotation caused this.
      final first = counts.first;
      expect(counts.every((c) => c == first), isTrue,
          reason: 'run counts varied: $counts');
    });

    test('fill shape changes continuously across a tiny camera sweep', () {
      final ring = _straddling();
      List<Vec2>? prev;
      for (var i = 0; i <= 10; i++) {
        final cam = _cam(-0.1 + i * 0.02);
        final clipped = clipRingToHorizon(ring, cam)!;
        if (prev != null) {
          // A discrete topology jump would produce a Hausdorff distance in the
          // tens of pixels; continuous drift stays well under this.
          expect(_hausdorff(prev, clipped.fill), lessThan(3.0),
              reason: 'frame $i jumped by more than 3px');
        }
        prev = clipped.fill;
      }
    });

    test('fill stays continuous across the whole horizon sweep', () {
      // A wide straddling polygon — the realistic SIGMET shape. The old
      // firstHidden-rotation code jumped by ~160px as the camera drifted a
      // fraction of a degree; here the fill must move continuously frame to
      // frame across the entire horizon, not just near the centre.
      final ring = _straddling();
      var prev = clipRingToHorizon(ring, _cam(-10))!;
      for (var i = 1; i <= 200; i++) {
        final cam = _cam(-10 + i * 0.1);
        final clipped = clipRingToHorizon(ring, cam)!;
        expect(_hausdorff(prev.fill, clipped.fill), lessThan(3.0),
            reason: 'frame $i (lng ${(-10 + i * 0.1).toStringAsFixed(1)}) '
                'jumped by more than 3px');
        prev = clipped;
      }
    });

    test('limb seal follows the occluded (major) gap, not the front', () {
      // A thin crescent whose visible part hugs the east limb and whose closure
      // runs the long way around the back. With the seal drawn the short way the
      // fill would wrap across the front and cover the disc centre.
      final ring = <LatLng>[
        const LatLng(5, 85),
        const LatLng(-5, 85),
        const LatLng(-5, 90),
        const LatLng(5, 90),
        const LatLng(5, 95),
        const LatLng(5, 120),
        const LatLng(5, 150),
        const LatLng(5, 179),
        const LatLng(5, -150),
        const LatLng(5, -120),
        const LatLng(5, -95),
        const LatLng(-5, -95),
        const LatLng(-5, -120),
        const LatLng(-5, -150),
        const LatLng(-5, 179),
        const LatLng(-5, 150),
        const LatLng(-5, 120),
        const LatLng(-5, 95),
      ];
      final cam = _cam(0);
      final clipped = clipRingToHorizon(ring, cam)!;
      final c = cam.size.center;
      // The thin limb crescent must not enclose the front of the globe.
      expect(_covers(clipped.fill, c.x, c.y), isFalse);
    });
  });
}
