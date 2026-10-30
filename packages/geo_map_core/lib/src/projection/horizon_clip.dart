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
///
/// ## Flicker-free by construction
///
/// The horizon is taken at the true depth `z == 0`, **not** a small positive
/// band. A vertex is visible iff its depth `z > 0`, and the crossing between a
/// visible and a hidden vertex is the `z == 0` intersection projected onto the
/// silhouette — the *same* plane the visibility test uses. There is therefore
/// no dropped band that would pop in and out as the camera drifts a fraction of
/// a degree (the old `epsDepth` band was the source of the flicker).
///
/// Runs are collected in ring order with **no rotation** to "start on a hidden
/// vertex", so the order in which runs are concatenated never changes between
/// frames. Each gap between consecutive runs (including the wrap from the last
/// run back to the first) is sealed with a limb arc that follows the *occluded*
/// side of the silhouette — chosen from the hidden vertices in that gap — which
/// is stable for both minor and major arcs.
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

  // View-space coords: x/y orthographic offsets, z depth. Horizon at z == 0.
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

  final visible = zs.every((z) => z > 0);
  if (visible) {
    final points = [for (var i = 0; i < ring.length; i++) screenAt(i)];
    return HorizonClippedRing(fill: points, strokeRuns: [points]);
  }

  // z == 0 crossing between two view points, projected onto the limb.
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

  // Visible edge runs, in ring order. For each run we also remember the source
  // index of its first and last *real* (visible) vertex so we can locate the
  // hidden gap between consecutive runs.
  final runs = <List<Vec2>>[];
  final runStartSrc = <int>[];
  final runEndSrc = <int>[];
  List<Vec2>? current;
  int? lastRealSrc;

  void startRun(int firstRealIdx) {
    current = <Vec2>[];
    runStartSrc.add(firstRealIdx);
    lastRealSrc = firstRealIdx;
  }

  void endRun() {
    runs.add(current!);
    runEndSrc.add(lastRealSrc!);
    current = null;
    lastRealSrc = null;
  }

  for (var i = 0; i < ring.length; i++) {
    final a = i;
    final b = (i + 1) % ring.length;
    final aIn = zs[a] > 0;
    final bIn = zs[b] > 0;
    if (aIn && bIn) {
      if (current == null) startRun(a);
      current!.add(screenAt(a));
      lastRealSrc = a;
    } else if (aIn && !bIn) {
      if (current == null) startRun(a);
      current!.add(screenAt(a));
      current!.add(crossing(a, b));
      lastRealSrc = a;
      endRun();
    } else if (!aIn && bIn) {
      startRun(b);
      current!.add(crossing(a, b));
      current!.add(screenAt(b));
      lastRealSrc = b;
    }
    // both hidden: nothing.
  }
  if (current != null && current!.isNotEmpty) endRun();
  if (runs.isEmpty) return null;

  // Seal each gap (including the wrap from the last run back to the first) with
  // a limb arc that follows the occluded side of the silhouette.
  final fill = <Vec2>[];
  for (var r = 0; r < runs.length; r++) {
    fill.addAll(runs[r]);
    final next = (r + 1) % runs.length;

    // Hidden vertices strictly between run r's last real vertex and run next's
    // first real vertex, walking forward in ring order.
    final hiddenAngles = <double>[];
    var k = (runEndSrc[r] + 1) % ring.length;
    final gapEnd = runStartSrc[next];
    var guard = 0;
    while (k != gapEnd && guard <= ring.length) {
      hiddenAngles.add(math.atan2(-ys[k], xs[k]));
      k = (k + 1) % ring.length;
      guard++;
    }

    _arcAlongLimb(fill, runs[r].last, runs[next].first, center, radius,
        hiddenAngles);
  }

  return HorizonClippedRing(fill: fill, strokeRuns: runs);
}

/// Appends the arc on the silhouette from [from] to [to] that passes through
/// the occluded gap (given by the angular positions of the hidden vertices in
/// that gap).
///
/// It picks the minor or major arc from the *circular mean* of the hidden
/// vertices' limb angles, so a single noisy projection (a far-behind vertex can
/// wrap past the run endpoint) cannot flip the seal to the wrong side. The mean
/// is stable frame to frame, so the seal never jumps direction as the camera
/// drifts — which is what produced the flicker.
void _arcAlongLimb(
  List<Vec2> out,
  Vec2 from,
  Vec2 to,
  Vec2 center,
  double radius,
  List<double> hiddenAngles,
) {
  final a0 = math.atan2(from.y - center.y, from.x - center.x);
  final a1 = math.atan2(to.y - center.y, to.x - center.x);

  double norm(double d) {
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }

  final deltaShort = norm(a1 - a0);
  final deltaLong =
      deltaShort > 0 ? deltaShort - 2 * math.pi : deltaShort + 2 * math.pi;

  bool shortContains(double target) {
    final d = norm(target - a0);
    return deltaShort > 0 ? (d >= 0 && d <= deltaShort) : (d <= 0 && d >= deltaShort);
  }

  // The occluded gap lies on the side of the limb where the hidden vertices
  // cluster. Use their circular mean — robust to a stray out-of-range angle —
  // to decide short vs long arc.
  final meanAngle = hiddenAngles.isEmpty
      ? a0
      : math.atan2(
          hiddenAngles.fold(0.0, (s, h) => s + math.sin(h)),
          hiddenAngles.fold(0.0, (s, h) => s + math.cos(h)),
        );
  final useLong = !shortContains(meanAngle);
  final delta = useLong ? deltaLong : deltaShort;

  const steps = 24;
  for (var i = 1; i <= steps; i++) {
    final a = a0 + delta * i / steps;
    out.add(Vec2(
      center.x + math.cos(a) * radius,
      center.y + math.sin(a) * radius,
    ));
  }
}
