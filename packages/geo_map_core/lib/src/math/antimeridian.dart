/// Antimeridian helpers for geometries drawn **without tiles** (the GeoJSON
/// style path in `geo_map`).
///
/// The Mercator projector wraps longitude **per vertex** (relative to the
/// camera). That is correct for points and lines, but it splits a *ring* whose
/// consecutive vertices fall on opposite sides of the seam: the halves land in
/// different world copies and a straight chord is drawn across the whole
/// screen, filling a screen-wide band. These helpers let the renderer keep a
/// ring/line continuous (see `StyleVectorLayer`).
library;

import 'package:latlong2/latlong.dart';

import 'projections.dart' show wrapLongitude;

/// Sequentially unwrap [lons] so every consecutive delta stays in (-180, 180].
///
/// `out[0] == lons[0]`; `out[i] = out[i-1] + wrapLongitude(lons[i] - lons[i-1])`.
/// A ring that "jumps" from +179° to −179° becomes +179° → +181° (a 2° step)
/// instead of a −358° step, so it can be projected continuously.
List<double> unwrapLongitudes(List<double> lons) {
  if (lons.isEmpty) return const <double>[];
  final out = List<double>.filled(lons.length, 0);
  out[0] = lons[0];
  for (var i = 1; i < lons.length; i++) {
    out[i] = out[i - 1] + wrapLongitude(lons[i] - lons[i - 1]);
  }
  return out;
}

/// Split [ring] on the meridian [seamLng], returning one or two closed pieces.
///
/// The ring is unwrapped first, so a +179°/−179° edge is recognised as crossing
/// the seam. If the ring lies entirely on one side, `[ring]` is returned
/// unchanged. Pieces with fewer than three vertices are dropped.
///
/// This mirrors how MapLibre splits GeoJSON at ±180° during tiling. The
/// renderer itself only needs [unwrapLongitudes] plus world copies; this helper
/// keeps that behaviour testable and lets callers clip explicitly.
List<List<LatLng>> splitRingAtSeam(List<LatLng> ring, double seamLng) {
  if (ring.length < 3) return const <List<LatLng>>[];

  final lons = unwrapLongitudes([for (final p in ring) p.longitude]);
  final pts = <(double, double)>[
    for (var i = 0; i < ring.length; i++) (lons[i], ring[i].latitude),
  ];

  var minL = lons.first;
  var maxL = lons.first;
  for (final l in lons) {
    if (l < minL) minL = l;
    if (l > maxL) maxL = l;
  }

  // Move the seam into the ring's unwrapped window.
  var seam = seamLng;
  while (seam < minL) {
    seam += 360;
  }
  while (seam > maxL) {
    seam -= 360;
  }
  if (seam < minL || seam > maxL) return <List<LatLng>>[ring];

  final left = _clipHalf(pts, seam, keepLeft: true);
  final right = _clipHalf(pts, seam, keepLeft: false);

  final pieces = <List<LatLng>>[];
  for (final poly in [left, right]) {
    if (poly.length < 3) continue;
    pieces.add([
      for (final (lng, lat) in poly) LatLng(lat, wrapLongitude(lng)),
    ]);
  }
  return pieces.isEmpty ? <List<LatLng>>[ring] : pieces;
}

List<(double, double)> _clipHalf(
  List<(double, double)> poly,
  double seam, {
  required bool keepLeft,
}) {
  final out = <(double, double)>[];
  bool inside((double, double) p) => keepLeft ? p.$1 <= seam : p.$1 >= seam;

  for (var i = 0; i < poly.length; i++) {
    final cur = poly[i];
    final prev = poly[(i - 1 + poly.length) % poly.length];
    final curIn = inside(cur);
    final prevIn = inside(prev);
    if (curIn) {
      if (!prevIn) out.add(_intersect(prev, cur, seam));
      out.add(cur);
    } else if (prevIn) {
      out.add(_intersect(prev, cur, seam));
    }
  }
  return out;
}

(double, double) _intersect(
  (double, double) a,
  (double, double) b,
  double seam,
) {
  final denom = b.$1 - a.$1;
  if (denom == 0) return (seam, a.$2);
  final t = (seam - a.$1) / denom;
  return (seam, a.$2 + (b.$2 - a.$2) * t);
}
