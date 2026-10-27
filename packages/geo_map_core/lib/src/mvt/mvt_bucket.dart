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

import '../camera/camera_state.dart';
import '../math/geo_geometry.dart';
import '../projection/geo_projector.dart';
import 'mvt.dart';
import 'mvt_clip.dart';

/// A fill-ready polygon: `rings.first` is the outer ring, the rest are holes.
///
/// Winding is normalized: the outer ring keeps its own orientation and every
/// hole is wound the opposite way. That lets a renderer merge many polygons
/// into one `Path` and fill with `PathFillType.nonZero` without adjacent
/// polygons eating each other (even-odd would XOR overlaps).
class MvtFillPolygon {
  const MvtFillPolygon(this.rings, {this.properties = const {}});

  final List<List<Vec2>> rings;

  /// The source feature's properties, for data-driven paint evaluation.
  final Map<String, Object?> properties;
}

/// A stroke-ready polyline.
class MvtPolyline {
  const MvtPolyline(this.points, {this.properties = const {}});

  final List<Vec2> points;

  /// The source feature's properties, for data-driven paint evaluation.
  final Map<String, Object?> properties;
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
      final normalized = _normalizeWinding(polygon);
      out.add(MvtFillPolygon(
        [for (final ring in normalized) normalizeMvtRing(ring, extent)],
        properties: feature.properties,
      ));
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
      // Cut the tile buffer off: a line layer on a polygon source otherwise
      // strokes the buffer edge, drawing a grid of tile boundaries.
      for (final run in clipMvtPolylineToExtent(
        ring,
        extent,
        dropTileEdges: true,
      )) {
        out.add(MvtPolyline(
          normalizeMvtRing(run, extent),
          properties: feature.properties,
        ));
      }
    }
  }
  return out;
}

/// Outer ring keeps its orientation; holes are reversed to the opposite one.
List<List<Vec2>> _normalizeWinding(List<List<Vec2>> polygon) {
  if (polygon.isEmpty) return polygon;
  final outerSign = mvtRingSignedArea(polygon.first) < 0 ? -1 : 1;
  final out = <List<Vec2>>[polygon.first];
  for (var i = 1; i < polygon.length; i++) {
    final ring = polygon[i];
    final sign = mvtRingSignedArea(ring) < 0 ? -1 : 1;
    out.add(sign == outerSign ? ring.reversed.toList(growable: false) : ring);
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

/// Screen-space affine map for one tile, used by the flat (Mercator) renderer.
///
/// Web Mercator is linear in tile space, so a tile's `[0,1]` square maps to a
/// parallelogram on screen. Keeping the three corner vectors avoids a
/// projection (and trig) call per vertex; because the basis comes from the
/// projected corners it also handles camera rotation.
class TileAffine {
  const TileAffine({
    required this.origin,
    required this.ux,
    required this.uy,
    required this.vx,
    required this.vy,
  });

  /// Screen position of the tile's top-left corner (tile space 0,0).
  final Vec2 origin;
  final double ux;
  final double uy;
  final double vx;
  final double vy;

  Vec2 map(Vec2 point) => Vec2(
        origin.x + point.x * ux + point.y * vx,
        origin.y + point.x * uy + point.y * vy,
      );

  /// Basis for an axis-aligned tile: [spanPx] to the east and to the south.
  factory TileAffine.fromOrigin(Vec2 origin, double spanPx) => TileAffine(
        origin: origin,
        ux: spanPx,
        uy: 0,
        vx: 0,
        vy: spanPx,
      );
}

/// Builds the flat affine map for tile ([z], [x], [y]).
///
/// Only the north-west corner goes through [GeoProjector.project]. The east and
/// south edges are the **constant** on-screen span `worldSize / 2^z` (Mercator
/// tiles are square in world-t space).
///
/// Projecting the other corners independently is what used to break at the
/// antimeridian: `project` wraps longitude relative to the camera, so a tile
/// whose NW corner lands at +170° and NE at −170° produced a basis a whole
/// world wide and stretched the tile across the screen. A constant span cannot
/// cross the seam.
///
/// Returns `null` when the origin does not project (only possible on a
/// non-affine projector; Mercator always succeeds).
TileAffine? tileAffine(
  GeoProjector projector,
  CameraState camera, {
  required int z,
  required int x,
  required int y,
}) {
  final nw = projector.project(
    mvtTilePointToLatLng(
      const Vec2(0, 0),
      z: z,
      tileX: x,
      tileY: y,
      extent: 1,
    ),
    camera,
  );
  if (nw == null) return null;
  return TileAffine.fromOrigin(nw, camera.worldSize / (1 << z));
}
