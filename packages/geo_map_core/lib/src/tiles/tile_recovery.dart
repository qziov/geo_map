/// Recovery from tile load failures.
///
/// A vector tile that 404s or gets rate-limited leaves a hole: there is nothing
/// to draw for that footprint. MapLibre's answer is to **ask for the parent** so
/// a coarser tile can be stretched over the gap — `_updateRetainedTiles`
/// (`src/tile/tile_manager.ts:697-730`):
///
/// ```js
/// // for remaining missing tiles with incomplete child coverage, seek a loaded parent tile
/// let parentWasRequested = tile?.wasRequested();
/// for (let overscaledZ = tileID.overscaledZ - 1; overscaledZ >= minCoveringZoom; --overscaledZ) {
///     const parentId = tileID.scaledTo(overscaledZ);
///     if (checked[parentId.key]) break;
///     checked[parentId.key] = true;
///     tile = this.getTile(parentId);
///     if (!tile && parentWasRequested) tile = this._addTile(parentId);
///     ...
/// }
/// ```
///
/// Two details are worth copying: the ascent is **bounded** by
/// `zoom - maxUnderzooming` and `source.minzoom`, and a parent is only requested
/// when the child was actually requested (`parentWasRequested`) — a tile still
/// queued behind the concurrency cap is not yet "missing", it is "not here yet".
///
/// MapLibre does **not** retry an errored tile at all; it stays errored until a
/// reload or a zoom change. We do retry (a transient 429 should heal by itself),
/// but with exponential backoff so a rate-limited server is not hammered once a
/// second — [tileRetryDelay] is that curve.
library;

import '../tuning/geo_engine_tuning.dart';
import 'tile_scheme.dart';

/// Coarser tiles to fetch so every gap can be covered by an ancestor.
///
/// [missing] are ideal tiles with nothing drawable (no exact tile, no complete
/// child generation, no loaded ancestor). [isAvailable] must be `true` for keys
/// that are decoded **or already in flight**.
///
/// Escalates **one level per call**: if the parent also fails, the next pass
/// sees it as missing and asks for the grandparent. Climbing the whole chain in
/// one pass (what MapLibre does) turns a region-wide 404 into a parent-chain
/// storm; one level per pass with backoff converges just as surely.
List<TileKey> planAncestorRequests({
  required Iterable<TileKey> missing,
  required bool Function(TileKey key) isAvailable,
  required int sourceMinZoom,
  int maxUnderzoom = GeoEngineTuning.maxUnderzooming,
}) {
  // Climbing is disabled (like MapLibre's `maxUnderzooming = 0`).
  if (maxUnderzoom < 1) return const [];
  final out = <TileKey>[];
  final claimed = <TileKey>{};
  for (final ideal in missing) {
    final z = ideal.z - 1;
    // Never climb below the source's own minimum zoom.
    if (z < 0 || z < sourceMinZoom) continue;
    final ancestor = TileKey(z, ideal.x >> 1, ideal.y >> 1);
    // Another ideal already asked for this ancestor: its ascent is done.
    if (!claimed.add(ancestor)) continue;
    // An available ancestor already covers the footprint (or is on its way).
    if (isAvailable(ancestor)) continue;
    out.add(ancestor);
  }
  return out;
}

/// Delay before the next attempt for a tile that has failed [attempts] times.
///
/// Doubles per attempt (`base`, `2×`, `4×`, …) and stops at [capMs], so a
/// collapsed or rate-limited server gets progressively more room instead of a
/// request per second forever.
Duration tileRetryDelay(
  int attempts, {
  required int baseMs,
  int capMs = 60000,
}) {
  final steps = attempts <= 1 ? 0 : (attempts - 1).clamp(0, 8);
  final ms = baseMs * (1 << steps);
  return Duration(milliseconds: ms > capMs ? capMs : ms);
}
