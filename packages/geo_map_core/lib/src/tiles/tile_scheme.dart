/// Tile grid definitions for both raster schemes.
library;

import 'package:latlong2/latlong.dart';

import '../math/projections.dart';

enum TileSchemeKind { webMercator, epsg4326 }

/// Immutable tile grid for one zoom level.
class TileGrid {
  const TileGrid._(this.kind, this.zoom);

  factory TileGrid.of(TileSchemeKind kind, int zoom) => TileGrid._(kind, zoom);

  final TileSchemeKind kind;
  final int zoom;

  int get cols => 1 << zoom;
  int get rows => 1 << zoom;

  double get tileWidthDeg => 360 / cols;

  double west(int x) => -180 + 360 * x / cols;
  double east(int x) => -180 + 360 * (x + 1) / cols;

  double north(int y) => kind == TileSchemeKind.webMercator
      ? mercatorLatitudeAt(y / rows)
      : 90 - 180 * y / rows;

  double south(int y) => kind == TileSchemeKind.webMercator
      ? mercatorLatitudeAt((y + 1) / rows)
      : 90 - 180 * (y + 1) / rows;

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

  int xOf(double lng) => ((lng + 180) / 360 * cols).floor().clamp(0, cols - 1);

  /// Unclamped column index — callers wrap it (a ±180 window must not collapse).
  int rawXOf(double lng) => ((lng + 180) / 360 * cols).floor();

  /// Unclamped row index.
  int rawYOf(double lat) => kind == TileSchemeKind.webMercator
      ? (mercatorTAt(lat) * rows).floor()
      : ((90 - lat) / 180 * rows).floor();

  int yOf(double lat) {
    if (kind == TileSchemeKind.webMercator) {
      return (mercatorTAt(lat) * rows).floor().clamp(0, rows - 1);
    }
    return ((90 - lat) / 180 * rows).floor().clamp(0, rows - 1);
  }

  LatLng tileCenter(int x, int y) => LatLng(latitudeAt(y, 0.5), (west(x) + east(x)) / 2);

  @override
  String toString() => 'TileGrid(${kind.name}, z$zoom, ${cols}x$rows)';
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
