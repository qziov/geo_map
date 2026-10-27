/// Splits a screen-space polyline into dashes.
///
/// Canvas has no native dash pattern (`Paint` has no `dashPathEffect`), so the
/// geometry is cut here, before it reaches the painter. MapLibre instead bakes
/// the dash into a texture atlas and lets the line shader scale it
/// (`line_atlas.ts:getDashRanges` / `addDash`), which is why its pattern is
/// expressed in **line-width multiples**; callers multiply by the resolved
/// line width before calling this function.
///
/// Odd-length patterns are legal: element `i` is a dash when `i` is even, so
/// the last element and the first are both dashes and meet at a vertex — the
/// same "first and last dash join seamlessly" rule as MapLibre.
library;

import 'dart:math' as math;

import '../math/geo_geometry.dart';
import '../math/geodesy.dart';
import 'mvt_bucket.dart';

/// Cuts [points] into dash polylines.
///
/// [pattern] is in **screen pixels**, alternating dash/gap and repeating.
/// Returns the points of each dash (each with at least two points). A pattern
/// that is empty, contains a negative value, or sums to zero returns
/// `[points]` unchanged (i.e. draw a solid line).
///
/// [phase] is the screen distance already consumed by the pattern before
/// [points] starts, so a caller can continue a dash across a break in the
/// geometry instead of restarting it. It is reduced modulo the pattern length
/// and may be negative.
List<List<Vec2>> dashPolyline(
  List<Vec2> points,
  List<double> pattern, {
  double phase = 0,
}) {
  if (points.length < 2) return [points];
  if (pattern.isEmpty) return [points];

  var total = 0.0;
  for (final value in pattern) {
    if (value < 0) return [points];
    total += value;
  }
  if (total <= 1e-9) return [points];

  final out = <List<Vec2>>[];
  var index = 0;
  var isDash = true;
  var remaining = pattern[0];

  if (phase != 0) {
    var consumed = phase % total;
    if (consumed < 0) consumed += total;
    while (consumed > pattern[index]) {
      consumed -= pattern[index];
      index = (index + 1) % pattern.length;
    }
    remaining = pattern[index] - consumed;
    isDash = index.isEven;
  }

  // A pattern starts with a dash; mid-pattern a run may start inside a gap.
  List<Vec2>? current = isDash ? [points.first] : null;

  for (var i = 0; i < points.length - 1; i++) {
    var a = points[i];
    final b = points[i + 1];
    var segLen = a.distanceTo(b);
    if (segLen <= 1e-9) continue;

    while (segLen > 1e-9) {
      if (remaining <= 1e-9) {
        // Zero-length element (or this one just ran out): advance the pattern.
        index = (index + 1) % pattern.length;
        remaining = pattern[index];
        isDash = index.isEven;
        if (isDash) current = [a];
        continue;
      }

      final step = math.min(segLen, remaining);
      final t = step / segLen;
      final next = Vec2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
      if (isDash) {
        (current ??= [a]).add(next);
      }
      a = next;
      segLen -= step;
      remaining -= step;

      if (remaining <= 1e-9) {
        if (isDash && current != null && current.length >= 2) {
          out.add(current);
        }
        current = null;
        index = (index + 1) % pattern.length;
        remaining = pattern[index];
        isDash = index.isEven;
        if (isDash) current = [a];
      }
    }
  }

  if (isDash && current != null && current.length >= 2) out.add(current);
  return out;
}

/// Screen-space dash phase (px) for a run starting at [tilePoint].
///
/// A dash pattern is a function of arc length, so a run that starts where another
/// tile's run ended must inherit its phase. Tiles are decoded independently and
/// cannot know how much line lies behind them, so the phase is anchored to a
/// **global** origin instead of to the run's own start:
///
/// * flat map — Web Mercator is linear in world space, so
///   `phase = world * worldSize` is exactly the screen arc length.
/// * globe — true arc length on the sphere is `radiusPx · Δφ` along a meridian
///   and `radiusPx · cos φ · Δλ` along a parallel, so use those metrics with the
///   unwrapped world coordinate (never the wrapped longitude: that would jump a
///   whole world at the antimeridian).
///
/// Both are computed from the *point's own* global position, so two tiles that
/// meet at a boundary compute the same value and the dash continues.
///
/// MapLibre has no equivalent: `line_bucket.ts:292-294` resets `distance` per
/// tile-clipped feature, so its dashes restart at every tile edge.
///
/// [horizontal] picks the axis by the run's dominant direction; a run that is
/// neither axis-aligned gets the axis it mostly follows, which keeps the phase
/// continuous but measures it with a slightly wrong metric.
double dashPhaseSeed(
  Vec2 tilePoint, {
  required int z,
  required int tileX,
  required int tileY,
  required bool horizontal,
  required bool sphere,
  required double worldSize,
  required double radiusPx,
}) {
  final scale = 1 << z;
  if (!sphere) {
    final unit = horizontal ? tileX + tilePoint.x : tileY + tilePoint.y;
    return unit / scale * worldSize;
  }
  final latRad = rad(mvtTilePointToLatLng(
    tilePoint,
    z: z,
    tileX: tileX,
    tileY: tileY,
    extent: 1,
  ).latitude);
  if (horizontal) {
    final worldX = (tileX + tilePoint.x) / scale;
    return worldX * 2 * math.pi * radiusPx * math.cos(latRad);
  }
  return latRad * radiusPx;
}
