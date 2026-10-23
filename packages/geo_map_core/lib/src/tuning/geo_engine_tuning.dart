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
}
