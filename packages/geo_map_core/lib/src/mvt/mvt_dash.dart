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

/// Cuts [points] into dash polylines.
///
/// [pattern] is in **screen pixels**, alternating dash/gap and repeating.
/// Returns the points of each dash (each with at least two points). A pattern
/// that is empty, contains a negative value, or sums to zero returns
/// `[points]` unchanged (i.e. draw a solid line).
List<List<Vec2>> dashPolyline(List<Vec2> points, List<double> pattern) {
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
  var remaining = pattern[0];
  var isDash = true;
  // A pattern always starts with a dash.
  List<Vec2>? current = [points.first];

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
