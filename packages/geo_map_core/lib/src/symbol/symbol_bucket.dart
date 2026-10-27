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

import '../math/geo_geometry.dart';
import '../mvt/mvt.dart';

/// One label anchor from a tile.
class MvtSymbol {
  const MvtSymbol({
    required this.anchor,
    this.properties = const {},
    this.tilePriority = 0,
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
}

/// Builds symbol anchors for every point feature in [layer].
///
/// Multi-point geometries yield one symbol per point, matching MapLibre: a
/// `MultiPoint` is laid out as one instance per point, not one per feature.
///
/// Points are **not** filtered by tile edges: a label anchored just outside the
/// tile (the MVT buffer) is legitimate — its box may still overlap the tile, and
/// the collision step is what decides. Lines and polygons are skipped; converting
/// them to labels needs `symbol-placement: line` and its own shaping path.
List<MvtSymbol> buildMvtSymbolBucket(MvtLayer layer) {
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
        ));
      }
    }
    priority++;
  }
  return out;
}
