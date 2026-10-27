/// Clips decoded MVT polylines to the tile's visible extent.
///
/// Vector tiles are encoded with a buffer: geometry may extend past the tile's
/// `[0, extent]` square so that strokes and joins look continuous across the
/// boundary. A Canvas renderer that draws the whole buffer paints the **buffer
/// edge** as well — for a line layer on a polygon source (`countries-outline`)
/// that shows up as a grid of long straight lines along the tile boundaries.
///
/// MapLibre avoids this with a per-tile stencil. The Canvas equivalent is to
/// cut the geometry at the extent before it reaches `Path`: fills are
/// unaffected (adjacent tiles meet exactly), strokes stop at the boundary.
library;

import '../math/geo_geometry.dart';

/// Clips [points] (tile units) to the box `[0, extent] × [0, extent]`.
///
/// Returns the contiguous visible runs (each with at least two points). A
/// polyline that leaves and re-enters the box yields more than one run.
///
/// With [dropTileEdges], segments that lie **on a tile border** are removed.
/// A polygon clipped at the tile extent carries such an edge; stroking it draws
/// the tile grid (the white lines that appear over land). The neighbouring tile
/// owns that border, so dropping it loses nothing. Segments are tested one by
/// one, so an L-shaped run around a corner is split and each border piece is
/// dropped.
List<List<Vec2>> clipMvtPolylineToExtent(
  List<Vec2> points,
  double extent, {
  bool dropTileEdges = false,
}) {
  if (points.length < 2 || extent <= 0) return const [];

  final out = <List<Vec2>>[];
  List<Vec2>? run;

  void flush() {
    if (run != null && run!.length >= 2) out.add(run!);
    run = null;
  }

  for (var i = 0; i < points.length - 1; i++) {
    final segment = _clipSegment(points[i], points[i + 1], extent);
    if (segment == null) {
      flush();
      continue;
    }
    final (a, b) = segment;
    if (dropTileEdges && _segmentOnBorder(a, b, extent)) {
      flush();
      continue;
    }
    if (run == null) {
      run = [a, b];
    } else if (_samePoint(run!.last, a)) {
      run!.add(b);
    } else {
      flush();
      run = [a, b];
    }
  }
  flush();
  return out;
}

/// True when both endpoints lie on the same tile border.
bool _segmentOnBorder(Vec2 a, Vec2 b, double extent) {
  const eps = 1e-6;
  return (a.x.abs() < eps && b.x.abs() < eps) ||
      ((a.x - extent).abs() < eps && (b.x - extent).abs() < eps) ||
      (a.y.abs() < eps && b.y.abs() < eps) ||
      ((a.y - extent).abs() < eps && (b.y - extent).abs() < eps);
}

bool _samePoint(Vec2 a, Vec2 b) =>
    (a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9;

/// Liang–Barsky segment clip against `[0, extent]²`.
(Vec2, Vec2)? _clipSegment(Vec2 a, Vec2 b, double extent) {
  var t0 = 0.0;
  var t1 = 1.0;
  final dx = b.x - a.x;
  final dy = b.y - a.y;

  bool clip(double p, double q) {
    if (p == 0) return q >= 0;
    final r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
    return true;
  }

  if (!clip(-dx, a.x)) return null;
  if (!clip(dx, extent - a.x)) return null;
  if (!clip(-dy, a.y)) return null;
  if (!clip(dy, extent - a.y)) return null;

  final p0 = Vec2(a.x + t0 * dx, a.y + t0 * dy);
  final p1 = Vec2(a.x + t1 * dx, a.y + t1 * dy);
  if (_samePoint(p0, p1)) return null;
  return (p0, p1);
}

/// Clamp rather than clip: useful for points that must stay inside the tile.
Vec2 clampToExtent(Vec2 p, double extent) => Vec2(
      p.x.clamp(0.0, extent),
      p.y.clamp(0.0, extent),
    );
