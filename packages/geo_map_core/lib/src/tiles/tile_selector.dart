/// Tile visibility selection.
///
/// Replaces the old "scan every row of the grid" approach (O(rows·cols)) with a
/// window derived from the projected viewport bounds, then per-tile verification
/// — O(visible tiles).
///
/// The selection also carries the **overzoom** state (MapLibre
/// `covering_tiles.ts`): the level we *render* at may be higher than the level
/// we *fetch* at, because a source stops at `maxZoom` and the remaining
/// magnification is done by scaling the deepest available tile.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../camera/camera_state.dart';
import '../projection/geo_projector.dart';
import '../tuning/geo_engine_tuning.dart';
import 'tile_scheme.dart';

/// The outcome of a tile selection pass.
///
/// * [desiredZ] — the zoom the camera asks for (`coveringZoomLevel`, no
///   latitude factor, exactly like MapLibre).
/// * [dataZoom] — the level we actually **fetch**; clamped to
///   `source.minZoom..source.maxZoom` (`z = min(desiredZ, maxZoom)` in
///   MapLibre).
/// * [renderZoom] — the level we **render** at; never clamped, so it can be
///   above [dataZoom]. The difference is the overzoom factor.
class TileSelection {
  const TileSelection({
    required this.desiredZ,
    required this.dataZoom,
    required this.renderZoom,
    required this.tiles,
  });

  /// Zoom level the camera asks for.
  final int desiredZ;

  /// Zoom level used for network requests.
  final int dataZoom;

  /// Zoom level used for drawing geometry.
  final int renderZoom;

  /// Tiles at [dataZoom] that cover the viewport.
  final List<TileKey> tiles;

  /// `2^(renderZoom - dataZoom)` — how much the fetched image is magnified.
  double get overscale => math.pow(2, renderZoom - dataZoom).toDouble();

  /// True when the source has no data deeper than [dataZoom] and the renderer
  /// magnifies it (MapLibre `OverscaledTileID.overscaledZ`).
  bool get isOverzoomed => renderZoom > dataZoom;

  /// Number of sub-cells the fetched tile is split into when overzooming.
  int get subCells => 1 << (renderZoom - dataZoom);

  @override
  String toString() => 'TileSelection(desired: $desiredZ, data: $dataZoom, '
      'render: $renderZoom, tiles: ${tiles.length})';
}

class TileSelector {
  const TileSelector._();

  /// Boundary samples per tile edge used when testing screen intersection.
  ///
  /// Four samples per edge (12 boundary points + centre) catch the crescent
  /// projection of high-latitude tiles near the limb — the historic source of
  /// black tile gaps at z5+.
  static const int boundarySamples = 4;

  /// The zoom level the camera asks for.
  ///
  /// MapLibre `coveringZoomLevel`:
  /// `floor/round(transform.zoom + scaleZoom(tileSize / options.tileSize))`.
  /// There is deliberately **no latitude factor** — the globe would otherwise
  /// shrink when the camera moves towards the poles.
  static int coveringZoomLevel(
    CameraState camera, {
    int sourceTileSize = GeoEngineTuning.tileSize,
  }) {
    final scale =
        math.log(sourceTileSize / GeoEngineTuning.tileSize) / math.ln2;
    return (camera.zoom + scale).round();
  }

  /// Full selection pass with overzoom state.
  ///
  /// [sourceMinZoom] / [sourceMaxZoom] describe the data the source can
  /// deliver; [desiredZ] is the level the camera asks for. When
  /// [desiredZ] > [sourceMaxZoom] the source data is magnified (overzoom),
  /// exactly like MapLibre's `OverscaledTileID`.
  static TileSelection select({
    required GeoProjector projector,
    required CameraState camera,
    required int desiredZ,
    required int sourceMinZoom,
    required int sourceMaxZoom,
    TileSchemeKind scheme = TileSchemeKind.webMercator,
    int? renderZoom,
    double? margin,
    bool verify = true,
  }) {
    final dataZoom = desiredZ.clamp(sourceMinZoom, sourceMaxZoom);
    final render = renderZoom ?? desiredZ;
    final grid = TileGrid.of(scheme, dataZoom);
    final tiles = visible(
      projector: projector,
      camera: camera,
      grid: grid,
      margin: margin ?? adaptiveMargin(camera, grid),
      verify: verify,
    );
    return TileSelection(
      desiredZ: desiredZ,
      dataZoom: dataZoom,
      renderZoom: render,
      tiles: tiles,
    );
  }

  /// Screen size of one tile at the camera's zoom level.
  ///
  /// The globe's circumference in pixels is exactly `worldSize`, so the same
  /// formula holds for both projections.
  static double tileScreenPx(CameraState camera, TileGrid grid) =>
      camera.worldSize / grid.cols;

  /// Margin that grows with the on-screen size of a tile.
  ///
  /// A fixed 64 px margin is not enough once a tile covers more than 128 px:
  /// the projection of a high-latitude tile is a thin crescent whose extreme
  /// point can be far outside the tile's centre.
  static double adaptiveMargin(CameraState camera, TileGrid grid) {
    final px = tileScreenPx(camera, grid);
    return math.max(GeoEngineTuning.selectMargin, px / 2);
  }

  /// Tiles covering the viewport.
  static List<TileKey> visible({
    required GeoProjector projector,
    required CameraState camera,
    required TileGrid grid,
    double? margin,
    bool verify = true,
  }) {
    final m = margin ?? adaptiveMargin(camera, grid);
    final bounds = projector.approximateVisibleBounds(camera);
    // A window wider than the world (common on the globe near the limb) must
    // cover every column — otherwise the wrap-around leaves a hole near ±180.
    final worldSpan = bounds.east - bounds.west;
    final coversAllColumns = worldSpan >= 360;
    // The margin is expressed in pixels; the window must be widened by the same
    // amount in tiles, otherwise tiles that only reach into the margin are
    // never even tested.
    final extra = (m / tileScreenPx(camera, grid)).ceil();
    final x0 = coversAllColumns ? 0 : grid.rawXOf(bounds.west) - 1 - extra;
    final x1 =
        coversAllColumns ? grid.cols - 1 : grid.rawXOf(bounds.east) + 1 + extra;
    // `yOf` clamps to the grid, so a camera above the mercator limit (85.05°)
    // still yields row 0 instead of an empty band.
    final y0 = (grid.rawYOf(bounds.north) - 1 - extra).clamp(0, grid.rows - 1);
    final y1 = (grid.rawYOf(bounds.south) + 1 + extra).clamp(0, grid.rows - 1);

    final out = <TileKey>[];
    final seen = <TileKey>{};
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final key = TileKey(grid.zoom, grid.wrapX(x), y);
        if (!seen.add(key)) continue;
        if (!verify || _intersectsViewport(key, grid, projector, camera, m)) {
          out.add(key);
        }
      }
    }
    // Request from the screen centre outward (MapLibre sorts by `distanceSq`),
    // so the view fills in the middle first instead of marching north→south.
    final cx = camera.size.width / 2;
    final cy = camera.size.height / 2;
    out.sort((a, b) {
      final ca = grid.tileCenter(a.x, a.y);
      final cb = grid.tileCenter(b.x, b.y);
      final pa = projector.project(ca, camera);
      final pb = projector.project(cb, camera);
      final da = pa == null
          ? double.infinity
          : (pa.x - cx) * (pa.x - cx) + (pa.y - cy) * (pa.y - cy);
      final db = pb == null
          ? double.infinity
          : (pb.x - cx) * (pb.x - cx) + (pb.y - cy) * (pb.y - cy);
      return da.compareTo(db);
    });
    return out;
  }

  /// Walk every tile in the grid (reference implementation for differential tests).
  static List<TileKey> bruteForce({
    required GeoProjector projector,
    required CameraState camera,
    required TileGrid grid,
    double? margin,
    int samplesPerEdge = 4,
  }) {
    final m = margin ?? adaptiveMargin(camera, grid);
    final out = <TileKey>[];
    for (var y = 0; y < grid.rows; y++) {
      for (var x = 0; x < grid.cols; x++) {
        final key = TileKey(grid.zoom, x, y);
        if (_intersectsViewport(key, grid, projector, camera, m,
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
