/// Symbol bucket: point features turned into placement candidates.
///
/// This is the **bucketing** half of label support — geometry only, no glyphs and
/// no style. MapLibre splits the same work across `symbol_bucket.ts` (which owns
/// the glyph quads after layout) and `symbol_layout.ts` (which turns a feature
/// into one or more `SymbolInstance`s). We keep the split at the same seam but
/// stop earlier: a bucket here is a list of anchors plus the feature's
/// properties, and everything style-dependent (the actual text, font size,
/// colour) is resolved per frame by the painter.
///
/// Why not bake the text in at decode time: buckets are cached per tile and
/// reused across style changes, so a `text-field` expression evaluated at decode
/// would freeze the first style forever. MapLibre gets away with baking it
/// because its bucket belongs to one layer, not to one tile.
library;

import 'dart:math' as math;

import '../math/geo_geometry.dart';
import '../mvt/mvt.dart';

/// One label anchor from a tile.
class MvtSymbol {
  const MvtSymbol({
    required this.anchor,
    this.properties = const {},
    this.tilePriority = 0,
    this.angle = 0,
    this.placement = MvtSymbolPlacement.point,
    this.crossTileKey,
  });

  /// Normalized tile-space position (`[0,1]²`), like every other bucket.
  final Vec2 anchor;

  /// Feature properties, for `text-field` / `['get', ...]` evaluation.
  final Map<String, Object?> properties;

  /// Tie-breaker among symbols of the same `symbol-sort-key`: MapLibre keeps the
  /// feature index so the order is stable across frames
  /// (`symbol_layout.ts` assigns it while walking features). Without a stable
  /// order, two candidates that cannot both fit would flicker.
  final int tilePriority;

  /// Local segment angle in radians (tile space, y down). Non-zero only for
  /// `symbol-placement: line`; the painter rotates the label to the line.
  final double angle;

  /// Whether this anchor came from a point or a line feature.
  final MvtSymbolPlacement placement;

  /// Stable cross-tile identity: the anchor's **world** longitude/latitude,
  /// quantized to ~1e-5° (~1 m). Same logical feature duplicated across
  /// neighbouring tiles' buffer overlap shares a key, so the placer can keep one.
  /// Null when [z]/[x]/[y] were not supplied (e.g. synthetic tests).
  final String? crossTileKey;
}

/// How a symbol anchor was produced.
enum MvtSymbolPlacement {
  /// One anchor per point feature (or per point of a MultiPoint).
  point,

  /// One anchor per line-segment midpoint, rotated to the segment.
  line,
}

/// Builds symbol anchors for every point feature in [layer].
///
/// Multi-point geometries yield one symbol per point, matching MapLibre: a
/// `MultiPoint` is laid out as one instance per point, not one per feature.
///
/// Points are **not** filtered by tile edges: a label anchored just outside the
/// tile (the MVT buffer) is legitimate — its box may still overlap the tile, and
/// the collision step is what decides. Lines and polygons are skipped; converting
/// them to labels needs [buildMvtLineSymbolBucket].
///
/// [z]/[x]/[y] are the tile's coordinates; they feed [MvtSymbol.crossTileKey] so
/// the same POI drawn from two tiles collapses to one. Pass 0 when there is no
/// tile (unit tests).
List<MvtSymbol> buildMvtSymbolBucket(
  MvtLayer layer, {
  required int z,
  required int x,
  required int y,
}) {
  final extent = layer.extent.toDouble();
  if (extent <= 0) return const [];
  final out = <MvtSymbol>[];
  var priority = 0;
  for (final feature in layer.features) {
    if (feature.type != MvtGeomType.point) {
      // Keep the counter stable even when features are skipped.
      priority++;
      continue;
    }
    for (final ring in feature.geometry) {
      for (final point in ring) {
        out.add(MvtSymbol(
          anchor: Vec2(point.x / extent, point.y / extent),
          properties: feature.properties,
          tilePriority: priority,
          crossTileKey: _worldKey(point, z, x, y, extent),
        ));
      }
    }
    priority++;
  }
  return out;
}

/// Builds one symbol per line-segment midpoint in [layer], rotated to the
/// local segment angle — the M3 `symbol-placement: line` path
/// (`get_anchors.ts` samples along the line; we place one label per segment,
/// which MapLibre also does at the default `symbol-spacing`).
///
/// Polygons are still skipped; [spacing] is reserved for finer sampling.
List<MvtSymbol> buildMvtLineSymbolBucket(
  MvtLayer layer, {
  required int z,
  required int x,
  required int y,
  double spacing = 0,
}) {
  final extent = layer.extent.toDouble();
  if (extent <= 0) return const [];
  final out = <MvtSymbol>[];
  var priority = 0;
  for (final feature in layer.features) {
    if (feature.type != MvtGeomType.lineString) {
      priority++;
      continue;
    }
    for (final ring in feature.geometry) {
      for (var i = 1; i < ring.length; i++) {
        final a = ring[i - 1];
        final b = ring[i];
        final mx = (a.x + b.x) / 2;
        final my = (a.y + b.y) / 2;
        final angle = math.atan2(b.y - a.y, b.x - a.x);
        out.add(MvtSymbol(
          anchor: Vec2(mx / extent, my / extent),
          properties: feature.properties,
          tilePriority: priority,
          angle: angle,
          placement: MvtSymbolPlacement.line,
          crossTileKey: _worldKey(Vec2(mx, my), z, x, y, extent),
        ));
      }
    }
    priority++;
  }
  return out;
}

/// World longitude/latitude of [point] (raw extent coordinates) quantized to a
/// stable key. Mirrors `mvtTilePointToLatLng` in `mvt_bucket.dart` so a feature
/// at the same place in two tiles produces the same string.
String? _worldKey(Vec2 point, int z, int x, int y, double extent) {
  if (z == 0 && x == 0 && y == 0) return null;
  final size = extent * (1 << z);
  final x0 = extent * x;
  final y0 = extent * y;
  final lon = (point.x + x0) * 360.0 / size - 180.0;
  final y2 = 180.0 - (point.y + y0) * 360.0 / size;
  final lat = math.atan(math.exp(y2 * math.pi / 180.0)) * 360.0 / math.pi - 90.0;
  return '${lon.toStringAsFixed(5)}:${lat.toStringAsFixed(5)}';
}
