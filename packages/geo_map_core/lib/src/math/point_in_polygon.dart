/// Geographic point-in-polygon tests (pure Dart, no `dart:ui`).
///
/// These are the *decisions* behind a feature query: whether a tapped
/// coordinate falls inside a drawn area. They live in the core (not the
/// engine) so `dart test` can cover them — the engine depends on `dart:ui`
/// and cannot be unit-tested here.
///
/// Two properties make this non-trivial, and both are handled here:
///
/// * **The antimeridian.** A ring drawn across ±180° has its two halves in
///   different world copies. Longitudes are therefore unwrapped
///   ([unwrapLongitudes]) and the query longitude is lifted into *the one
///   copy that falls inside the ring's unwrapped window* — not "anchored to
///   the ring's first vertex", which silently misses the far end of a ring
///   wider than 180°.
/// * **Winding independence.** The test uses the **even-odd** rule, so a
///   hole listed with the same winding as its outer ring still reads as a
///   hole. MapLibre punches holes explicitly (earcut) and is likewise
///   winding-independent.
///
/// [normalizeRingWinding] is the counterpart used by the *renderer*: Canvas
/// fills with the nonzero rule, so a hole must be reversed to punch through.
/// The two are complementary — rendering needs the winding normalised,
/// querying does not — but both must read the same unwrapped ring, so that
/// "what you hit" is exactly "what you see".
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../tuning/geo_engine_tuning.dart';
import 'antimeridian.dart' show unwrapLongitudes;

/// Whether [point] lies inside the closed ring [ring].
///
/// Uses the even-odd rule, so the ring's winding does not matter.
/// [includeBoundary] decides whether a point exactly on an edge counts as
/// inside (default: yes).
///
/// Returns `false` for rings with fewer than three vertices.
bool pointInRing(
  List<LatLng> ring,
  LatLng point, {
  bool includeBoundary = true,
}) {
  if (ring.length < 3) return false;
  // A ring with no area (all vertices on one line) encloses nothing, and its
  // "boundary" is just a line — a point sitting on that line must not count
  // as inside, so the degenerate case is rejected before the boundary test.
  if (ringSignedArea(ring) == 0) return false;
  final unwrapped = _UnwrappedRing.of(ring);
  final tapLng = unwrapped.lift(point.longitude);
  // Outside the ring's longitude span → outside the ring, no test needed.
  if (tapLng == null) return false;
  if (includeBoundary && _onBoundary(unwrapped, tapLng, point.latitude)) {
    return true;
  }
  return _evenOdd(unwrapped, tapLng, point.latitude);
}

/// Whether [point] lies inside the polygon [rings] (first ring = outer ring,
/// the rest = holes).
///
/// The interior is "outer ring minus holes" (RFC 7946). Boundary handling:
/// a point on the **outer** boundary counts as inside; a point on a **hole's**
/// boundary counts as outside — the hole wins.
bool pointInPolygon(
  List<List<LatLng>> rings,
  LatLng point, {
  bool includeBoundary = true,
}) {
  if (rings.isEmpty) return false;
  final outer = rings.first;
  if (outer.length < 3) return false;

  if (includeBoundary) {
    for (var i = 1; i < rings.length; i++) {
      if (rings[i].length < 3) continue;
      final hole = _UnwrappedRing.of(rings[i]);
      final holeLng = hole.lift(point.longitude);
      if (holeLng != null && _onBoundary(hole, holeLng, point.latitude)) {
        // On a hole's edge → outside the polygon.
        return false;
      }
    }
    final outerRing = _UnwrappedRing.of(outer);
    final outerLng = outerRing.lift(point.longitude);
    if (outerLng != null && _onBoundary(outerRing, outerLng, point.latitude)) {
      return true;
    }
  }

  if (!_contains(outer, point)) return false;
  for (var i = 1; i < rings.length; i++) {
    if (rings[i].length < 3) continue;
    if (_contains(rings[i], point)) return false;
  }
  return true;
}

/// Whether [point] lies inside any sub-polygon of [polygons] (MultiPolygon).
///
/// The sub-polygons are evaluated independently (union semantics), which
/// matches how the renderer draws them — one `addPolygon` per ring.
bool pointInMultiPolygon(
  List<List<List<LatLng>>> polygons,
  LatLng point, {
  bool includeBoundary = true,
}) {
  for (final polygon in polygons) {
    if (pointInPolygon(polygon, point, includeBoundary: includeBoundary)) {
      return true;
    }
  }
  return false;
}

/// Signed area of [ring], measured on **unwrapped** longitudes.
///
/// Positive means counter-clockwise. Unwrapping matters: a ring near ±180°
/// would otherwise flip sign and silently change which ring is treated as the
/// outer one.
double ringSignedArea(List<LatLng> ring) {
  if (ring.length < 3) return 0;
  final lons = unwrapLongitudes([for (final p in ring) p.longitude]);
  var area = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final j = (i + 1) % ring.length;
    area += lons[i] * ring[j].latitude - lons[j] * ring[i].latitude;
  }
  return area * 0.5;
}

/// Reverse the rings whose winding matches the outer ring's.
///
/// Canvas fills with the nonzero rule, so a hole wound like its outer ring
/// does **not** punch through; reversing it restores the hole. The outer ring
/// keeps its orientation, and a single-ring polygon is returned unchanged.
List<List<LatLng>> normalizeRingWinding(List<List<LatLng>> rings) {
  if (rings.length < 2) return rings;
  final outerSign = ringSignedArea(rings.first) < 0 ? -1 : 1;
  final out = <List<LatLng>>[rings.first];
  for (var i = 1; i < rings.length; i++) {
    final sign = ringSignedArea(rings[i]) < 0 ? -1 : 1;
    out.add(
      sign == outerSign
          ? rings[i].reversed.toList(growable: false)
          : rings[i],
    );
  }
  return out;
}

// --- internals ----------------------------------------------------------------

/// A ring with its longitudes unwrapped into one continuous window.
class _UnwrappedRing {
  _UnwrappedRing(this.lons, this.lats);

  factory _UnwrappedRing.of(List<LatLng> ring) => _UnwrappedRing(
        unwrapLongitudes([for (final p in ring) p.longitude]),
        [for (final p in ring) p.latitude],
      );

  final List<double> lons;
  final List<double> lats;

  late final double minLon = lons.reduce(math.min);
  late final double maxLon = lons.reduce(math.max);

  /// The copy of [lng] that falls inside this ring's unwrapped window.
  ///
  /// Returns `null` when no copy does — i.e. the longitude is outside the
  /// ring's span entirely. When the span is narrower than a full turn there
  /// is at most one such copy, so the answer is unambiguous.
  double? lift(double lng) {
    final kLo = ((minLon - lng) / 360.0).ceil();
    final kHi = ((maxLon - lng) / 360.0).floor();
    if (kLo > kHi) return null;
    return lng + 360.0 * kLo;
  }
}

/// Even-odd crossing test in the unwrapped (lon, lat) plane.
///
/// The half-open interval rule `(yi > lat) != (yj > lat)` makes a vertex
/// sitting exactly on the query latitude count once, so no special case is
/// needed for it. There is no requirement that the ring be monotone in
/// latitude.
bool _evenOdd(_UnwrappedRing ring, double tapLng, double tapLat) {
  var inside = false;
  final n = ring.lons.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final xi = ring.lons[i];
    final yi = ring.lats[i];
    final xj = ring.lons[j];
    final yj = ring.lats[j];
    if ((yi > tapLat) != (yj > tapLat)) {
      final xCross = (xj - xi) * (tapLat - yi) / (yj - yi) + xi;
      if (tapLng < xCross) inside = !inside;
    }
  }
  return inside;
}

/// Whether the query point sits on one of the ring's edges.
bool _onBoundary(_UnwrappedRing ring, double tapLng, double tapLat) {
  final eps = GeoEngineTuning.featureBoundaryEpsilonDeg;
  final limit = eps * eps;
  final n = ring.lons.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final d2 = _pointSegmentDistanceSq(
      tapLng,
      tapLat,
      ring.lons[j],
      ring.lats[j],
      ring.lons[i],
      ring.lats[i],
    );
    if (d2 <= limit) return true;
  }
  return false;
}

/// Containment without the boundary special case (holes use it).
bool _contains(List<LatLng> ring, LatLng point) {
  if (ring.length < 3) return false;
  if (ringSignedArea(ring) == 0) return false;
  final unwrapped = _UnwrappedRing.of(ring);
  final tapLng = unwrapped.lift(point.longitude);
  if (tapLng == null) return false;
  return _evenOdd(unwrapped, tapLng, point.latitude);
}

double _pointSegmentDistanceSq(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax;
  final dy = by - ay;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) {
    final ex = px - ax;
    final ey = py - ay;
    return ex * ex + ey * ey;
  }
  var t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final cx = ax + t * dx;
  final cy = ay + t * dy;
  final ex = px - cx;
  final ey = py - cy;
  return ex * ex + ey * ey;
}
