/// The pure draw-fallback decision behind `TileEngine.resolve`.
///
/// Given which tiles are already decoded, decide **what to draw** for one ideal
/// tile: the tile itself, a complete generation of its immediate children, a
/// loaded ancestor, or nothing. This is the "what to draw" half of resolution —
/// kept separate from "what to request" ([planTileRequest]) so both can be
/// unit-tested without `dart:ui`.
library;

import '../tuning/geo_engine_tuning.dart';
import 'tile_scheme.dart';

/// How a screen tile is going to be filled.
enum TileFallbackKind {
  /// The ideal tile itself is loaded.
  exact,

  /// A complete generation of immediate children covers the footprint.
  descendants,

  /// A coarser ancestor is stretched over the footprint.
  ancestor,

  /// Nothing is loaded yet — the caller keeps its previous frame underneath.
  none,
}

/// The resolved draw source for one ideal tile.
class TileFallbackDecision {
  const TileFallbackDecision._(
    this.kind, {
    this.children = const [],
    this.ancestor,
    this.dz = 0,
  });

  /// Draw the ideal tile itself.
  const TileFallbackDecision.exact() : this._(TileFallbackKind.exact);

  /// Draw a complete generation of children (same order as returned).
  TileFallbackDecision.descendants(List<TileKey> children)
      : this._(TileFallbackKind.descendants, children: children);

  /// Stretch [ancestor] (which lives [dz] levels up) over the footprint.
  TileFallbackDecision.ancestor(TileKey ancestor, int dz)
      : this._(TileFallbackKind.ancestor, ancestor: ancestor, dz: dz);

  /// Nothing drawable yet.
  const TileFallbackDecision.none() : this._(TileFallbackKind.none);

  final TileFallbackKind kind;

  /// The children to draw (only for [TileFallbackKind.descendants]).
  final List<TileKey> children;

  /// The ancestor to draw (only for [TileFallbackKind.ancestor]).
  final TileKey? ancestor;

  /// How many levels up [ancestor] is (only for [TileFallbackKind.ancestor]).
  final int dz;

  @override
  String toString() => 'TileFallbackDecision($kind, children: ${children.length}, '
      'ancestor: $ancestor, dz: $dz)';
}

/// Decide how to fill [ideal] from what is already loaded.
///
/// Precedence, matching MapLibre `_updateRetainedTiles` + `_retainLoadedChildren`:
///
/// 1. **exact** — the ideal tile is cached;
/// 2. **descendants** — all four immediate children are cached (a complete
///    generation is required: three of four would leave a visible notch);
/// 3. **ancestor** — the nearest cached ancestor (stretched, sub-rect UV);
/// 4. **none** — nothing, so the caller keeps the previous frame underneath.
///
/// The ideal tile is **not** required to be loaded: the ancestor chain is a
/// placeholder while it is in flight, never a substitute for fetching it.
TileFallbackDecision planTileResolution({
  required TileKey ideal,
  required int sourceMinZoom,
  required int sourceMaxZoom,
  required TileSchemeKind scheme,
  required bool Function(TileKey key) isLoaded,
}) {
  if (isLoaded(ideal)) return const TileFallbackDecision.exact();

  // ① A complete generation of immediate children (MapLibre
  //    `_retainLoadedChildren`). Three of four is not enough — the missing
  //    quarter would show the underlay through, i.e. a notch.
  if (ideal.z + 1 <= sourceMaxZoom) {
    final grid = TileGrid.of(scheme, ideal.z + 1);
    final children = grid.childrenOf(ideal);
    final complete = children.every(
      (c) => c.x < grid.cols && c.y < grid.rows && isLoaded(c),
    );
    if (complete) return TileFallbackDecision.descendants(children);
  }

  // ② The nearest loaded ancestor (coarse tile stretched over the footprint).
  for (var dz = 1;
      dz <= GeoEngineTuning.maxUnderzooming && ideal.z - dz >= sourceMinZoom;
      dz++) {
    final ancestor = TileKey(ideal.z - dz, ideal.x >> dz, ideal.y >> dz);
    if (isLoaded(ancestor)) {
      return TileFallbackDecision.ancestor(ancestor, dz);
    }
  }

  return const TileFallbackDecision.none();
}
