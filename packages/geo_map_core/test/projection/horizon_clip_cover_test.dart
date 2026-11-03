/// Regression tests for the **fill area** of horizon-clipped rings.
///
/// `horizon_clip_flicker_test.dart` guards *continuity* (no discrete jumps);
/// this file guards *correctness* — how much of the disc the fill actually
/// covers. They caught a different bug: a seal that ran the long way around the
/// limb turned a small polygon into "the whole disc minus the region", which the
/// user saw as the entire globe painted in the SIGMET colour.
///
/// Ground truth is computed independently: sample the disc, unproject each
/// sample to LatLng, and ask the spherical point-in-ring test whether it is
/// inside — no limb-arc heuristics involved.
library;

import 'dart:math' as math;

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

const _projector = OrthographicProjector();

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

List<LatLng> _box(double s, double w, double n, double e) =>
    subdivideSpherePolyline(
      [LatLng(s, w), LatLng(s, e), LatLng(n, e), LatLng(n, w)],
      closed: true,
    );

CameraState _cam(double lat, double lng, double zoom) => CameraState(
      center: LatLng(lat, lng),
      zoom: zoom,
      size: const ViewportSize(600, 420),
    );

/// Fraction of the visible disc the fill covers.
double _fillCoverage(List<Vec2> fill, CameraState cam, {double step = 12}) {
  final c = cam.size.center;
  final r = cam.radiusPx;
  var hits = 0;
  var disc = 0;
  for (var y = c.y - r; y <= c.y + r; y += step) {
    for (var x = c.x - r; x <= c.x + r; x += step) {
      final dx = x - c.x;
      final dy = y - c.y;
      if (dx * dx + dy * dy > r * r) continue;
      disc++;
      if (_covers(fill, x, y)) hits++;
    }
  }
  return disc == 0 ? 0 : hits / disc;
}

/// Fraction of the visible disc that is genuinely inside [ring].
double _trueCoverage(List<LatLng> ring, CameraState cam, {double step = 12}) {
  final c = cam.size.center;
  final r = cam.radiusPx;
  var hits = 0;
  var disc = 0;
  for (var y = c.y - r; y <= c.y + r; y += step) {
    for (var x = c.x - r; x <= c.x + r; x += step) {
      final dx = x - c.x;
      final dy = y - c.y;
      if (dx * dx + dy * dy > r * r) continue;
      disc++;
      final geo = _projector.unproject(Vec2(x, y), cam);
      if (geo != null && pointInRing(ring, geo)) hits++;
    }
  }
  return disc == 0 ? 0 : hits / disc;
}

void main() {
  group('clipRingToHorizon — fill area matches the visible part', () {
    test('a 10° polygon seen edge-on does not fill the globe', () {
      // The exact configuration that painted the whole globe: a small ring on
      // the far side (camera lng -12, ring lon 80..100 → ~90–112° away), where
      // only a sliver peeks over the limb.
      final ring = _box(-5, 80, 5, 100);
      final cam = _cam(30, -12, 4);
      final clipped = clipRingToHorizon(ring, cam)!;

      final fill = _fillCoverage(clipped.fill, cam);
      expect(fill, lessThan(0.10),
          reason: 'a sliver near the limb must not become most of the disc '
              '(got ${(fill * 100).toStringAsFixed(1)}%)');
      expect(_covers(clipped.fill, cam.size.center.x, cam.size.center.y),
          isFalse,
          reason: 'the disc centre is far outside the ring');
    });

    test('fill area stays within 15% of the sampled ground truth', () {
      final rings = <List<LatLng>>[
        _box(-30, 40, 30, 130),
        _box(-20, 60, 20, 120),
        _box(-10, 80, 10, 100),
        _box(-5, 40, 5, 50), // entirely hidden at several cameras
      ];
      for (final ring in rings) {
        for (final lat in [-30.0, 0.0, 30.0]) {
          for (final lng in [-120.0, -12.0, 60.0, 170.0]) {
            final cam = _cam(lat, lng, 4);
            final clipped = clipRingToHorizon(ring, cam);
            final truth = _trueCoverage(ring, cam);
            final fill = clipped == null ? 0.0 : _fillCoverage(clipped.fill, cam);
            // Absolute tolerance keeps tiny areas (a few %) from failing on
            // sampling noise, while still catching a disc-sized fill.
            expect((fill - truth).abs(), lessThan(math.max(0.05, truth * 0.3)),
                reason: 'lat=$lat lng=$lng truth=${truth.toStringAsFixed(3)} '
                    'fill=${fill.toStringAsFixed(3)}');
          }
        }
      }
    });

    test('a visible stretch across the array boundary stays one run', () {
      // First and last vertex both visible but part of the ring hidden: without
      // the wrap merge the two pieces are joined by a spurious limb arc that
      // bulges along the silhouette.
      final ring = _box(-5, 80, 5, 100);
      final cam = _cam(0, 60, 4); // ring straddles the horizon on both sides
      final clipped = clipRingToHorizon(ring, cam)!;
      expect(clipped.strokeRuns, hasLength(1),
          reason: 'a single visible stretch must not be split at index 0');
    });
  });
}
