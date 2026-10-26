import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('wire row order', () {
    test('xyz keeps the canonical row', () {
      final g = TileGrid.of(TileSchemeKind.webMercator, 3);
      for (var y = 0; y < g.rows; y++) {
        expect(g.rowForFetch(y), y);
      }
    });

    test('tms flips the row', () {
      final g =
          TileGrid.of(TileSchemeKind.webMercator, 3, order: TileRowOrder.tmsBottomUp);
      expect(g.rowForFetch(0), 7);
      expect(g.rowForFetch(7), 0);
      expect(g.rowForFetch(3), 4);
    });

    test('tms flip round-trips', () {
      final g =
          TileGrid.of(TileSchemeKind.webMercator, 5, order: TileRowOrder.tmsBottomUp);
      for (var y = 0; y < g.rows; y++) {
        expect(g.yFromFetch(g.rowForFetch(y)), y);
      }
    });
  });

  group('mercator row bounds', () {
    test('rows are bounded by the projection limit', () {
      final g = TileGrid.of(TileSchemeKind.webMercator, 4);
      expect(g.north(0), closeTo(85.05112878, 1e-6));
      expect(g.south(g.rows - 1), closeTo(-85.05112878, 1e-6));
    });

    test('a parent row is exactly bisected by its children', () {
      // This is what makes the parent-image UV sub-rectangle exact.
      for (var z = 1; z <= 6; z++) {
        final parent = TileGrid.of(TileSchemeKind.webMercator, z);
        final child = TileGrid.of(TileSchemeKind.webMercator, z + 1);
        for (var y = 0; y < parent.rows; y++) {
          final north = parent.north(y);
          final south = parent.south(y);
          expect(child.north(2 * y), closeTo(north, 1e-6));
          expect(child.south(2 * y + 1), closeTo(south, 1e-6));
          // The seam between the two children sits inside the parent row.
          expect(child.north(2 * y + 1), lessThan(north));
          expect(child.north(2 * y + 1), greaterThan(south));
        }
      }
    });

    test('latitude interpolation is monotonic', () {
      final g = TileGrid.of(TileSchemeKind.webMercator, 5);
      var last = g.latitudeAt(3, 0);
      for (var i = 1; i <= 10; i++) {
        final lat = g.latitudeAt(3, i / 10);
        expect(lat, lessThan(last));
        last = lat;
      }
    });
  });

  group('wmts 2:1 grid', () {
    test('epsg4326wmts has twice as many columns as rows', () {
      final g = TileGrid.of(TileSchemeKind.epsg4326wmts, 3);
      expect(g.cols, 16);
      expect(g.rows, 8);
      expect(g.tileWidthDeg, 22.5);
    });

    test('epsg4326 stays 1:1', () {
      final g = TileGrid.of(TileSchemeKind.epsg4326, 3);
      expect(g.cols, g.rows);
    });

    test('wmts rows are uniform in degrees', () {
      final g = TileGrid.of(TileSchemeKind.epsg4326wmts, 2);
      expect(g.rows, 4);
      expect(g.north(0), closeTo(90, 1e-9));
      expect(g.south(1), closeTo(0, 1e-9));
      expect(g.south(g.rows - 1), closeTo(-90, 1e-9));
    });
  });

  group('parent / child relations', () {
    test('parent halves the coordinates', () {
      expect(TileGrid.of(TileSchemeKind.webMercator, 5).parentOf(
        const TileKey(5, 17, 9),
      ), const TileKey(4, 8, 4));
      expect(TileGrid.of(TileSchemeKind.webMercator, 0).parentOf(
        const TileKey(0, 0, 0),
      ), isNull);
    });

    test('children are the four sub-rectangles', () {
      final kids = TileGrid.of(TileSchemeKind.webMercator, 4).childrenOf(
        const TileKey(4, 3, 5),
      );
      expect(kids, [
        const TileKey(5, 6, 10),
        const TileKey(5, 7, 10),
        const TileKey(5, 6, 11),
        const TileKey(5, 7, 11),
      ]);
    });

    test('child grid keeps the scheme and the row order', () {
      final g = TileGrid.of(TileSchemeKind.webMercator, 3,
          order: TileRowOrder.tmsBottomUp);
      final c = g.childGrid();
      expect(c.zoom, 4);
      expect(c.order, TileRowOrder.tmsBottomUp);
      expect(c.rowForFetch(0), 15);
    });
  });
}
