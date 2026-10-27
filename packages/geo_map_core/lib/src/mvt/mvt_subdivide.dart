/// Tile-space subdivision of MVT geometry, ported from MapLibre GL JS.
///
/// **Why this exists.** The globe renderer projects *per vertex*
/// (`shaders/glsl/_projection_globe.vertex.glsl:57-96`, `projectToSphere`), so a
/// segment becomes a chord on screen unless it has intermediate vertices. Two
/// sparse vertices that are far apart therefore cut straight across the sphere,
/// and since every tile subdivides its **own** copy of a shared edge, adjacent
/// tiles meet at a visible step.
///
/// **How MapLibre solves it.** Not by densifying in lat/lng and never along a
/// great circle — `grep -ri densif` finds nothing in the GL JS tree. Instead
/// `render/subdivision.ts:757-868` (`subdivideVertexLine`) splits every segment
/// at a regular grid of `EXTENT / granularity` cells, interpolating **linearly in
/// tile space**. The grid is a function of the tile's zoom only
/// (`render/subdivision_granularity_settings.ts:36-39`:
/// `max(floor(base / 2^z), min, 1)`), which keeps the vertex density roughly
/// constant in world space and makes the result cacheable per tile.
///
/// That space matters. Linear-in-tile-space keeps a constant-latitude segment on
/// its parallel; interpolating along a great circle instead bows it polewards —
/// a 180° span goes straight *over* the pole. That was the kink users saw on the
/// tropics.
///
/// Presets copied from `geo/projection/vertical_perspective_projection.ts:16-29`
/// (the globe projection); Mercator uses `SubdivisionGranularitySetting.noSubdivision`.
library;

import 'dart:math' as math;

import '../math/geo_geometry.dart';

/// Granularity MapLibre uses for `line` layers on the globe (base at z0).
const int mvtLineBaseGranularity = 512;

/// Granularity MapLibre uses for `fill` layers on the globe (base at z0).
const int mvtFillBaseGranularity = 128;

/// MapLibre never subdivides fills below granularity 2 (half tile).
const int mvtFillMinGranularity = 2;

/// Subdivision granularity for a tile at [z]: cells of `1 / result` tile units.
///
/// Port of `SubdivisionGranularityExpression.getGranularityForZoomLevel`
/// (`subdivision_granularity_settings.ts:36-39`): the base granularity halves
/// with every zoom level and never drops below [min] (or below 1, which means
/// "no subdivision").
int mvtSubdivisionGranularity(
  int z, {
  int base = mvtLineBaseGranularity,
  int min = 1,
}) {
  // Guard the shift: tiles never go past z~24, but a nonsensical input should
  // not turn into a negative shift (which would multiply).
  final shift = z < 0 ? 0 : (z > 30 ? 30 : z);
  return math.max(math.max(base >> shift, min), 1);
}

/// Splits a normalized tile-space polyline onto a `1/granularity` grid.
///
/// Every segment is walked and a vertex is inserted each time it crosses a
/// vertical or horizontal grid axis, with the crossing point interpolated
/// **linearly in tile space**. [closed] adds the segment from the last point
/// back to the first (polygon rings) and repeats the first point at the end.
///
/// [granularity] below 2 returns [points] unchanged (same instance) — MapLibre's
/// `noSubdivision` path.
List<Vec2> subdivideTilePolyline(
  List<Vec2> points, {
  int granularity = 1,
  bool closed = false,
}) {
  if (points.length < 2) return points;
  final first = points.first;
  final needsClosing = closed && !_same(first, points.last);
  if (granularity < 2) {
    return needsClosing ? [...points, first] : points;
  }
  final cell = 1.0 / granularity;
  final count = points.length;
  final segments = needsClosing ? count : count - 1;
  final out = <Vec2>[first];
  // A single segment can cross at most `2 * granularity` axes; the bound only
  // guards against a degenerate input looping forever.
  final maxSteps = 4 * granularity + 8;
  for (var i = 0; i < segments; i++) {
    final a = points[i];
    final b = i + 1 < count ? points[i + 1] : first;
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    var t = 0.0;
    for (var step = 0; step < maxSteps; step++) {
      final tNext = _nextAxisCrossing(a, dx, dy, t, cell);
      if (tNext >= 1 || tNext <= t) break;
      _push(out, Vec2(a.x + dx * tNext, a.y + dy * tNext));
      t = tNext;
    }
    _push(out, b);
  }
  return out;
}

/// Parameter along `a -> a + d` of the first grid axis crossed after [t].
///
/// Returns [double.infinity] for an axis-parallel segment (nothing to cross).
double _nextAxisCrossing(Vec2 a, double dx, double dy, double t, double cell) {
  var best = double.infinity;
  if (dx != 0) {
    final here = (a.x + dx * t) / cell;
    final axis = dx > 0 ? here.floor() + 1 : here.ceil() - 1;
    final crossing = (axis * cell - a.x) / dx;
    if (crossing < best) best = crossing;
  }
  if (dy != 0) {
    final here = (a.y + dy * t) / cell;
    final axis = dy > 0 ? here.floor() + 1 : here.ceil() - 1;
    final crossing = (axis * cell - a.y) / dy;
    if (crossing < best) best = crossing;
  }
  return best;
}

void _push(List<Vec2> out, Vec2 p) {
  if (_same(out.last, p)) return;
  out.add(p);
}

bool _same(Vec2 a, Vec2 b) => a.x == b.x && a.y == b.y;
