/// Engine-wide numeric contract. Every magic number lives here so that tests can
/// assert it and call sites cannot drift (tile size used to exist twice).
library;

class GeoEngineTuning {
  const GeoEngineTuning._();

  /// Depth below which a vertex counts as "behind the horizon".
  static const double epsDepth = 0.02;

  /// Camera latitude clamp — keeps the orthographic camera out of the exact pole
  /// (avoids NaN in `1/cos(lat)` compensation and degenerate tangents).
  static const double maxCameraLatitude = 89.999;

  /// Floor for `cos(lat)` when picking a tile zoom near the poles.
  static const double pickZoomCosFloor = 0.2;

  /// Raster tile edge in pixels. Single source of truth.
  static const int tileSize = 256;

  /// [tileSize] as a double (const-usable default parameter).
  static const double tileSizeD = tileSize * 1.0;

  /// Maximum chord error allowed when densifying great circles (screen px).
  static const double densifyPixelError = 0.5;

  /// Extra margin (px) used when testing whether a tile touches the viewport.
  static const double selectMargin = 64;

  /// Mesh subdivision bounds per tile / image quad.
  static const int subdivMin = 6;
  static const int subdivMax = 16;

  /// Target number of screen pixels per subdivision cell.
  static const double subdivPx = 20;

  /// Raster cache budget (bytes) — replaces the old "384 images" count cap.
  static const int cacheBudgetBytes = 96 << 20; // 96 MiB

  /// Default estimated bytes per decoded tile, used before a real measurement.
  static const int defaultTileBytes = 256 * 1024;

  /// Tap slop and fling thresholds for the gesture layer.
  static const double tapSlopPx = 12;
  static const int tapMaxMillis = 400;
  static const int doubleTapMaxMillis = 320;
  static const double flingMinVelocityPxPerSec = 600;

  /// Debounce before issuing new tile requests while the camera is moving.
  static const int tileRequestDebounceMillis = 120;

  // --- retained-tile semantics (MapLibre `tile_manager.ts`) --------------------

  /// How many zoom levels up the ancestor chain may be used as a fallback.
  ///
  /// MapLibre: `maxUnderzooming` (default 10). The chain stops at
  /// `source.minzoom`.
  static const int maxUnderzooming = 10;

  /// How many zoom levels down the descendant chain may be used as a fallback.
  ///
  /// MapLibre: `maxOverzooming` (default 3). The whole generation must be
  /// present before it is drawn.
  static const int maxOverzooming = 3;

  /// Zoom levels kept in the cache (MapLibre `MAX_TILE_CACHE_ZOOM_LEVELS`).
  static const int tileCacheZoomLevels = 5;

  // --- request layer -----------------------------------------------------------

  /// Maximum concurrent raster tile requests (MapLibre
  /// `MAX_PARALLEL_IMAGE_REQUESTS`).
  static const int maxParallelRequests = 16;

  /// Concurrent requests for a sqlite-backed source — a single file handle
  /// does not benefit from more.
  static const int sqliteParallelRequests = 4;

  /// TCP connect timeout for tile requests.
  static const int requestTimeoutMs = 15000;

  /// Timeout for reading the response body of a tile request.
  static const int bodyTimeoutMs = 30000;

  /// A pending request that never completed within this window is reclaimed.
  static const int pendingTimeoutMs = 45000;

  /// Upper bound on the number of tracked request/failure keys.
  static const int maxTrackedTileKeys = 4096;

  // --- failure TTLs (milliseconds) ---------------------------------------------

  /// Network / timeout failures are transient — retry quickly.
  static const int networkFailureTtlMs = 3000;

  /// A missing tile (HTTP 404) stays missing for longer: MapLibre does not
  /// blacklist it, it just falls back to parent/child tiles.
  static const int notFoundTtlMs = 30000;

  /// Decode failures (corrupt payload) — retry, but not immediately.
  static const int decodeFailureTtlMs = 8000;

  /// Exponential backoff base for repeated failures of the same tile
  /// (MapLibre `tile.ts`: `1000 * 2^(n-1)`).
  static const int failureBackoffBaseMs = 1000;

  /// Cap for the exponential backoff.
  static const int failureBackoffMaxMs = 30000;

  // --- polar cap ---------------------------------------------------------------

  /// Upper bound on the number of **separate meshes** used to draw one polar
  /// cap.
  ///
  /// Two regimes exist and this constant is the switch between them:
  ///
  /// * **wedge regime** (`columns ≤ maxPolarCapColumns`) — every visible grid
  ///   column gets its own strip textured with that column's own tile. This is
  ///   the crisp path and it is what a cap seen from *outside* looks like.
  /// * **smeared regime** (`columns > maxPolarCapColumns`) — the whole visible
  ///   arc is drawn as **one** strip with a single texture. The camera is
  ///   inside the cap here, the arc wraps all the way around the pole, and a
  ///   per-column wedge would mean thousands of meshes each sampling a
  ///   different image: that is precisely the radial sunburst that used to
  ///   fill the viewport.
  ///
  /// The bound therefore has to stay small enough that the wedge regime stays
  /// cheap, and the smeared regime is only reached where the cap is a
  /// featureless blob anyway.
  static const int maxPolarCapColumns = 64;
}
