/// Which tiles must be requested for one ideal tile — the pure decision behind
/// `TileEngine.resolve`.
library;

import '../tuning/geo_engine_tuning.dart';
import 'tile_cache_policy.dart';
import 'tile_scheme.dart';

/// The requests a single ideal tile implies for one frame.
///
/// MapLibre `_updateRetainedTiles` does two different things, and it matters
/// that they stay different:
///
/// * the **ideal** tile is added to the request queue unconditionally
///   (`_addTile(idealID)`), whatever is already drawable;
/// * the **ancestor chain** escalates one level per round, and only after the
///   level below has failed (`parentWasRequested`).
///
/// Conflating them — "request something only when nothing at all is cached" —
/// pins the view to the coarse level forever, because the previous level *is*
/// always cached right after a zoom-in.
///
/// Keeping the decision here (pure Dart, no `dart:ui`) is what makes it
/// testable at all: the engine itself cannot run under `dart test`.
class TileRequestPlan {
  const TileRequestPlan({this.ideal, this.ancestors = const []});

  /// The ideal tile, when it still has to be fetched (`null` when already
  /// decoded).
  final TileKey? ideal;

  /// Ancestor tiles to fetch, **closest first**.
  final List<TileKey> ancestors;

  bool get isEmpty => ideal == null && ancestors.isEmpty;

  @override
  String toString() => 'TileRequestPlan(ideal: $ideal, ancestors: $ancestors)';
}

/// Decide what [ideal] implies: always itself, plus the ancestor chain that
/// has already failed its way up.
TileRequestPlan planTileRequest({
  required TileKey ideal,
  required int sourceMinZoom,
  required bool Function(TileKey key) isLoaded,
  required TileFailureKind? Function(TileKey key) failureOf,
  int maxUnderzooming = GeoEngineTuning.maxUnderzooming,
}) {
  if (isLoaded(ideal)) return const TileRequestPlan();

  final ancestors = <TileKey>[];
  var child = ideal;
  for (var dz = 1; dz <= maxUnderzooming; dz++) {
    final z = ideal.z - dz;
    if (z < sourceMinZoom) break;
    // The level below must have failed for good — otherwise we would
    // speculatively fetch a whole pyramid of tiles that may not be needed
    // (and that is what produced the request storms).
    if (failureOf(child) == null) break;
    final ancestor = TileKey(z, ideal.x >> dz, ideal.y >> dz);
    if (isLoaded(ancestor)) break;
    ancestors.add(ancestor);
    child = ancestor;
  }

  return TileRequestPlan(ideal: ideal, ancestors: ancestors);
}
