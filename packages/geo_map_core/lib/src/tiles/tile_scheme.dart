/// Tile grid definitions for both raster schemes.
library;

import 'package:latlong2/latlong.dart';

import '../math/projections.dart';

enum TileSchemeKind { webMercator, epsg4326, epsg4326wmts }

/// Row order used **on the wire**.
///
/// The internal (canonical) row order is always XYZ — row 0 is the northern
/// edge of the grid. Some services (TMS, MBTiles) number rows from the south,
/// so the row index must be flipped when a URL is built or a row is read from
/// a local file.
///
/// MapLibre does the same in one line: `tile_id.ts` L48
/// `y = scheme === 'tms' ? 2^z - y - 1 : y`.
enum TileRowOrder {
  /// Row 0 is north (OSM / XYZ / WMTS with `TileRow` counted from the top).
  xyzTopDown,

  /// Row 0 is south (TMS / MBTiles).
  tmsBottomUp,
}

/// Immutable tile grid for one zoom level.
class TileGrid {
  const TileGrid._(this.kind, this.zoom, this.order);

  factory TileGrid.of(
    TileSchemeKind kind,
    int zoom, {
    TileRowOrder order = TileRowOrder.xyzTopDown,
  }) =>
      TileGrid._(kind, zoom, order);

  final TileSchemeKind kind;

  final int zoom;

  /// Row order used when fetching bytes. Geometry always uses XYZ order.
  final TileRowOrder order;

  int get cols => switch (kind) {
        TileSchemeKind.webMercator || TileSchemeKind.epsg4326 => 1 << zoom,
        TileSchemeKind.epsg4326wmts => 2 << zoom,
      };

  int get rows => 1 << zoom;

  double get tileWidthDeg => 360 / cols;

  double west(int x) => -180 + 360 * x / cols;

  double east(int x) => -180 + 360 * (x + 1) / cols;

  double north(int y) => switch (kind) {
        TileSchemeKind.webMercator => mercatorLatitudeAt(y / rows),
        TileSchemeKind.epsg4326 || TileSchemeKind.epsg4326wmts =>
          90 - 180 * y / rows,
      };

  double south(int y) => switch (kind) {
        TileSchemeKind.webMercator => mercatorLatitudeAt((y + 1) / rows),
        TileSchemeKind.epsg4326 || TileSchemeKind.epsg4326wmts =>
          90 - 180 * (y + 1) / rows,
      };

  /// Latitude at `[0,1]` from the tile's north edge.
  double latitudeAt(int y, double t) {
    final northDeg = north(y);
    final southDeg = south(y);
    if (kind == TileSchemeKind.webMercator) {
      // Mercator rows are uniform in world-Y, not in latitude.
      final tNorth = y / rows;
      final tSouth = (y + 1) / rows;
      return mercatorLatitudeAt(tNorth + (tSouth - tNorth) * t);
    }
    return northDeg + (southDeg - northDeg) * t;
  }

  int wrapX(int x) => ((x % cols) + cols) % cols;

  /// Column [x] unwrapped to the world copy whose tile **centre** is nearest
  /// [centerLongitude].
  ///
  /// Rendering a tile at its canonical column breaks across the antimeridian:
  /// a tile east of it must be drawn on the right, not on the far left. Rounding
  /// the tile centre (not its left edge) keeps the world copy at
  /// `centerLongitude == 0` unchanged — rounding the edge would shift a z0 tile
  /// one whole world east.
  static int unwrapX(int x, int z, double centerLongitude) {
    final cols = 1 << z;
    final centerCol = (centerLongitude + 180) / 360 * cols;
    final k = ((centerCol - x - 0.5) / cols).round();
    return x + cols * k;
  }

  int xOf(double lng) => ((lng + 180) / 360 * cols).floor().clamp(0, cols - 1);

  /// Unclamped column index — callers wrap it (a ±180 window must not collapse).
  int rawXOf(double lng) => ((lng + 180) / 360 * cols).floor();

  /// Unclamped row index.
  int rawYOf(double lat) => switch (kind) {
        TileSchemeKind.webMercator => (mercatorTAt(lat) * rows).floor(),
        TileSchemeKind.epsg4326 || TileSchemeKind.epsg4326wmts =>
          ((90 - lat) / 180 * rows).floor(),
      };

  int yOf(double lat) => switch (kind) {
        TileSchemeKind.webMercator =>
          (mercatorTAt(lat) * rows).floor().clamp(0, rows - 1),
        TileSchemeKind.epsg4326 || TileSchemeKind.epsg4326wmts =>
          ((90 - lat) / 180 * rows).floor().clamp(0, rows - 1),
      };

  LatLng tileCenter(int x, int y) =>
      LatLng(latitudeAt(y, 0.5), (west(x) + east(x)) / 2);

  // --- wire row order -----------------------------------------------------------

  /// Row index to use when **fetching** bytes for the canonical row [y].
  int rowForFetch(int y) => switch (order) {
        TileRowOrder.xyzTopDown => y,
        TileRowOrder.tmsBottomUp => (1 << zoom) - 1 - y,
      };

  /// Inverse of [rowForFetch]: canonical row for a wire row.
  int yFromFetch(int row) => rowForFetch(row);

  // --- parent / child relations ------------------------------------------------

  /// The parent tile of [key] one level up, or `null` at the root.
  TileKey? parentOf(TileKey key) {
    if (key.z <= 0) return null;
    return TileKey(key.z - 1, key.x ~/ 2, key.y ~/ 2);
  }

  /// The grid of the children of this grid (one zoom level deeper).
  TileGrid childGrid() => TileGrid.of(kind, zoom + 1, order: order);

  /// The four children of [key] one level deeper.
  List<TileKey> childrenOf(TileKey key) => [
        for (var j = 0; j < 2; j++)
          for (var i = 0; i < 2; i++)
            TileKey(key.z + 1, key.x * 2 + i, key.y * 2 + j),
      ];

  @override
  String toString() =>
      'TileGrid(${kind.name}, z$zoom, ${cols}x$rows, ${order.name})';
}

class TileKey {
  const TileKey(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is TileKey && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}
