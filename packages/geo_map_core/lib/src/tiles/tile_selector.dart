/// Tile visibility selection.
///
/// Replaces the old "scan every row of the grid" approach (O(rows·cols)) with a
/// window derived from the projected viewport bounds, then per-tile verification
/// — O(visible tiles).
library;

import 'package:latlong2/latlong.dart';

import '../camera/camera_state.dart';
import '../projection/geo_projector.dart';
import '../tuning/geo_engine_tuning.dart';
import 'tile_scheme.dart';

class TileSelector {
  const TileSelector._();

  /// Boundary samples per tile edge used when testing screen intersection.
  ///
  /// Four samples per edge (12 boundary points + centre) catch the crescent
  /// projection of high-latitude tiles near the limb — the historic source of
  /// black tile gaps at z5+.
  static const int boundarySamples = 4;

  static List<TileKey> visible({
    required GeoProjector projector,
    required CameraState camera,
    required TileGrid grid,
    double margin = GeoEngineTuning.selectMargin,
    bool verify = true,
  }) {
    final bounds = projector.approximateVisibleBounds(camera);
    // A window wider than the world (common on the globe near the limb) must
    // cover every column — otherwise the wrap-around leaves a hole near ±180.
    final worldSpan = bounds.east - bounds.west;
    final coversAllColumns = worldSpan >= 360;
    final x0 = coversAllColumns ? 0 : grid.rawXOf(bounds.west) - 1;
    final x1 = coversAllColumns ? grid.cols - 1 : grid.rawXOf(bounds.east) + 1;
    final y0 = (grid.yOf(bounds.north) - 1).clamp(0, grid.rows - 1);
    final y1 = (grid.yOf(bounds.south) + 1).clamp(0, grid.rows - 1);

    final out = <TileKey>[];
    final seen = <TileKey>{};
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final key = TileKey(grid.zoom, grid.wrapX(x), y);
        if (!seen.add(key)) continue;
        if (!verify || _intersectsViewport(key, grid, projector, camera, margin)) {
          out.add(key);
        }
      }
    }
    return out;
  }

  /// Walk every tile in the grid (reference implementation for differential tests).
  static List<TileKey> bruteForce({
    required GeoProjector projector,
    required CameraState camera,
    required TileGrid grid,
    double margin = GeoEngineTuning.selectMargin,
    int samplesPerEdge = 4,
  }) {
    final out = <TileKey>[];
    for (var y = 0; y < grid.rows; y++) {
      for (var x = 0; x < grid.cols; x++) {
        final key = TileKey(grid.zoom, x, y);
        if (_intersectsViewport(key, grid, projector, camera, margin,
            samplesPerEdge: samplesPerEdge)) {
          out.add(key);
        }
      }
    }
    return out;
  }

  static bool _intersectsViewport(
    TileKey key,
    TileGrid grid,
    GeoProjector projector,
    CameraState camera,
    double margin, {
    int samplesPerEdge = boundarySamples,
  }) {
    final west = grid.west(key.x);
    final east = grid.east(key.x);
    final north = grid.north(key.y);
    final south = grid.south(key.y);

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    var anyVisible = false;

    void include(double lng, double lat) {
      final p = projector.project(LatLng(lat, lng), camera);
      if (p == null) return;
      anyVisible = true;
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    void edge(double lngA, double latA, double lngB, double latB) {
      for (var k = 0; k <= samplesPerEdge; k++) {
        final t = k / samplesPerEdge;
        include(lngA + (lngB - lngA) * t, latA + (latB - latA) * t);
      }
    }

    edge(west, north, east, north);
    edge(east, north, east, south);
    edge(east, south, west, south);
    edge(west, south, west, north);
    include((west + east) / 2, (north + south) / 2);

    if (!anyVisible) return false;
    if (maxX < -margin || maxY < -margin) return false;
    if (minX > camera.size.width + margin) return false;
    if (minY > camera.size.height + margin) return false;
    return true;
  }
}
