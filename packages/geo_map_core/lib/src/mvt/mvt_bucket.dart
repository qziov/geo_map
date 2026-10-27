/// Bucket geometry: turns decoded MVT features into render-ready shapes.
///
/// Two deliberate simplifications vs. maplibre-native, both driven by geo_map
/// rendering with Flutter `Canvas` instead of WebGL:
///
/// * **Fill** — native triangulates every polygon with earcut and writes a
///   vertex buffer (`fill_bucket.cpp`); Canvas fills subpaths directly, so we
///   only need the rings grouped into outer + holes. `classifyMvtPolygonRings`
///   provides that grouping and `PathFillType.evenOdd` handles the holes.
/// * **Line** — native bakes miter/bevel/round joins and caps into an extruded
///   vertex buffer (`line_bucket.cpp`); Canvas `stroke` does joins and caps for
///   free, so we only need the polylines.
///
/// Coordinates are normalized to the tile's `[0,1]` square here. The renderer
/// keeps tile geometry in unit space so the same bucket works for 2D and 3D,
/// where a tile is an arbitrary screen quad rather than an axis-aligned box.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../math/geo_geometry.dart';
import 'mvt.dart';

/// A fill-ready polygon: `rings.first` is the outer ring, the rest are holes.
class MvtFillPolygon {
  const MvtFillPolygon(this.rings);

  final List<List<Vec2>> rings;
}

/// A stroke-ready polyline.
class MvtPolyline {
  const MvtPolyline(this.points);

  final List<Vec2> points;
}

/// Converts a ring from layer extent units to the `[0,1]` tile square.
List<Vec2> normalizeMvtRing(List<Vec2> ring, double extent) {
  if (extent == 0) return const [];
  return [for (final p in ring) Vec2(p.x / extent, p.y / extent)];
}

/// Builds fill polygons for every feature in [layer].
///
/// Faithful to MapLibre: rings are classified regardless of the feature's
/// declared type, so a `fill` layer pointed at a line source-layer yields
/// degenerate polygons rather than silently dropping them. Callers pick the
/// right source-layer.
List<MvtFillPolygon> buildMvtFillBucket(MvtLayer layer) {
  final extent = layer.extent.toDouble();
  final out = <MvtFillPolygon>[];
  for (final feature in layer.features) {
    for (final polygon in classifyMvtPolygonRings(feature.geometry)) {
      out.add(
        MvtFillPolygon([for (final ring in polygon) normalizeMvtRing(ring, extent)]),
      );
    }
  }
  return out;
}

/// Builds polylines for every ring in [layer] (>= 2 points).
List<MvtPolyline> buildMvtLineBucket(MvtLayer layer) {
  final extent = layer.extent.toDouble();
  final out = <MvtPolyline>[];
  for (final feature in layer.features) {
    for (final ring in feature.geometry) {
      if (ring.length < 2) continue;
      out.add(MvtPolyline(normalizeMvtRing(ring, extent)));
    }
  }
  return out;
}

/// Maps a tile-space point (in `extent` units) to geographic coordinates.
///
/// Direct port of maplibre-native `convertGeometry`
/// (`geometry_tile_data.cpp:129-140`):
///   size = EXTENT * 2^z ; x0 = EXTENT * tileX ; y0 = EXTENT * tileY
///   lon  = (px + x0) * 360 / size - 180
///   y2   = 180 - (py + y0) * 360 / size
///   lat  = atan(exp(y2 * pi / 180)) * 360 / pi - 90
///
/// The formula is scale-invariant in `extent`, so passing the layer's own
/// extent (4096 by default) gives the same result as native's normalized 8192.
LatLng mvtTilePointToLatLng(
  Vec2 point, {
  required int z,
  required int tileX,
  required int tileY,
  required double extent,
}) {
  final size = extent * (1 << z);
  final x0 = extent * tileX;
  final y0 = extent * tileY;
  final lon = (point.x + x0) * 360.0 / size - 180.0;
  final y2 = 180.0 - (point.y + y0) * 360.0 / size;
  final lat = math.atan(math.exp(y2 * math.pi / 180.0)) * 360.0 / math.pi - 90.0;
  return LatLng(lat, lon);
}
