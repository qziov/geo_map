/// Clips a polygon ring to the visible hemisphere of an orthographic globe.
///
/// Canvas fills a closed path with straight edges. A ring that crosses the
/// horizon would therefore be closed with a chord **through** the sphere: the
/// fill appears to pass inside the globe, and the region between the chord and
/// the silhouette is painted even though it is behind the camera.
///
/// This is the pure port of `GlobeVectorLayer._polygonPaths`: split the ring
/// into visible runs, then close each run along the limb so the fill stops at
/// the silhouette. Strokes use only the visible runs — adding the limb arc to a
/// stroke would draw a spurious line on the horizon.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../camera/camera_state.dart';
import '../math/geo_geometry.dart';
import '../math/geodesy.dart';
import '../projection/geo_projector.dart';
import '../tuning/geo_engine_tuning.dart';

class HorizonClippedRing {
  const HorizonClippedRing({required this.fill, required this.strokeRuns});

  /// One closed polygon (limb arcs included) for `Canvas.drawPath` fill.
  final List<Vec2> fill;

  /// Visible edge runs, for stroking without the synthetic limb arc.
  final List<List<Vec2>> strokeRuns;

  bool get isEmpty => fill.isEmpty;
}

/// Clips [ring] (already densified) against the horizon of [camera].
///
/// Returns `null` when nothing is visible or the camera has no radius.
HorizonClippedRing? clipRingToHorizon(
  List<LatLng> ring,
  CameraState camera,
) {
  if (ring.length < 3) return null;
  final radius = camera.radiusPx;
  if (radius <= 0) return null;

  final basis = cameraBasis(
    LatLng(camera.clampedLatitude, camera.center.longitude),
  );
  final center = camera.size.center;
  final eps = GeoEngineTuning.epsDepth;

  // View-space coordinates: x/y are the orthographic offsets, z the depth.
  final view = <Vec3>[for (final p in ring) Vec3.of(p)];
  final xs = <double>[];
  final ys = <double>[];
  final zs = <double>[];
  for (final v in view) {
    xs.add(v.dot(basis.east));
    ys.add(v.dot(basis.north));
    zs.add(v.dot(basis.forward));
  }

  Vec2 screenAt(int i) => Vec2(
        center.x + xs[i] * radius,
        center.y - ys[i] * radius,
      );

  // Start the walk on a hidden vertex (if any), so a run never straddles the
  // array boundary.
  final firstHidden = zs.indexWhere((z) => z <= eps);
  final order = <int>[
    for (var i = 0; i < ring.length; i++)
      firstHidden > 0 ? (i + firstHidden) % ring.length : i,
  ];

  final visible = zs.every((z) => z > eps);
  if (visible) {
    final points = [for (var i = 0; i < ring.length; i++) screenAt(i)];
    return HorizonClippedRing(fill: points, strokeRuns: [points]);
  }

  // Crossing of the z=0 plane, projected onto the limb.
  Vec2 crossing(int a, int b) {
    final t = zs[a] / (zs[a] - zs[b]);
    final x = xs[a] + (xs[b] - xs[a]) * t;
    final y = ys[a] + (ys[b] - ys[a]) * t;
    final len = math.sqrt(x * x + y * y);
    if (len < 1e-9) return Vec2(center.x + radius, center.y);
    return Vec2(
      center.x + x / len * radius,
      center.y - y / len * radius,
    );
  }

  final runs = <List<Vec2>>[];
  List<Vec2>? current;
  for (var k = 0; k < order.length; k++) {
    final a = order[k];
    final b = order[(k + 1) % order.length];
    final aIn = zs[a] > eps;
    final bIn = zs[b] > eps;
    if (aIn && bIn) {
      (current ??= <Vec2>[]).add(screenAt(a));
    } else if (aIn && !bIn) {
      (current ??= <Vec2>[]).add(screenAt(a));
      current.add(crossing(a, b));
      runs.add(current);
      current = null;
    } else if (!aIn && bIn) {
      current = [crossing(a, b), screenAt(b)];
    }
  }
  if (current != null && current.isNotEmpty) runs.add(current);
  if (runs.isEmpty) return null;

  final fill = <Vec2>[];
  for (var r = 0; r < runs.length; r++) {
    fill.addAll(runs[r]);
    final next = runs[(r + 1) % runs.length];
    _arcAlongLimb(fill, runs[r].last, next.first, center, radius);
  }

  return HorizonClippedRing(fill: fill, strokeRuns: runs);
}

/// Appends the shorter arc on the silhouette from [from] to [to].
void _arcAlongLimb(
  List<Vec2> out,
  Vec2 from,
  Vec2 to,
  Vec2 center,
  double radius,
) {
  final a0 = math.atan2(from.y - center.y, from.x - center.x);
  final a1 = math.atan2(to.y - center.y, to.x - center.x);
  var delta = a1 - a0;
  while (delta > math.pi) {
    delta -= 2 * math.pi;
  }
  while (delta < -math.pi) {
    delta += 2 * math.pi;
  }

  const steps = 24;
  for (var i = 1; i <= steps; i++) {
    final a = a0 + delta * i / steps;
    out.add(Vec2(
      center.x + math.cos(a) * radius,
      center.y + math.sin(a) * radius,
    ));
  }
}
