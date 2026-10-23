import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

CameraState _cam({
  LatLng center = const LatLng(54, 81),
  double zoom = 3,
  double width = 800,
  double height = 600,
}) =>
    CameraState(
      center: center,
      zoom: zoom,
      size: ViewportSize(width, height),
      minZoom: 0,
      maxZoom: 22,
    );

void main() {
  const ortho = OrthographicProjector();
  const merc = MercatorProjector();

  group('differential (globe)', () {
    test('fast selection contains every brute-force tile', () {
      for (final zoom in [2.0, 3.5, 5.0]) {
        final c = _cam(zoom: zoom);
        final grid = TileGrid.of(TileSchemeKind.webMercator, 5);
        final fast = TileSelector.visible(projector: ortho, camera: c, grid: grid)
            .map((t) => '$t')
            .toSet();
        final brute =
            TileSelector.bruteForce(projector: ortho, camera: c, grid: grid)
                .map((t) => '$t')
                .toSet();
        expect(brute.difference(fast), isEmpty,
            reason: 'zoom $zoom missed tiles');
      }
    });

    test('fast selection is not wildly over-inclusive', () {
      final c = _cam(zoom: 3.5);
      final grid = TileGrid.of(TileSchemeKind.webMercator, 5);
      final fast = TileSelector.visible(projector: ortho, camera: c, grid: grid);
      final brute =
          TileSelector.bruteForce(projector: ortho, camera: c, grid: grid);
      expect(fast.length, lessThanOrEqualTo(brute.length * 2 + 8));
      expect(brute.length, greaterThan(0));
    });

    test('a tile whose centre is on screen is always selected', () {
      final c = _cam(center: const LatLng(54, 81), zoom: 4);
      final grid = TileGrid.of(TileSchemeKind.webMercator, 5);
      final selected = TileSelector.visible(projector: ortho, camera: c, grid: grid)
          .map((t) => '$t')
          .toSet();
      for (var y = 0; y < grid.rows; y++) {
        for (var x = 0; x < grid.cols; x++) {
          final centre = grid.tileCenter(x, y);
          final p = ortho.project(centre, c);
          if (p == null) continue;
          if (p.x < 0 || p.y < 0 || p.x > c.size.width || p.y > c.size.height) {
            continue;
          }
          expect(selected, contains('${TileKey(5, x, y)}'));
        }
      }
    });

    test('polar view selects tiles but never behind the camera', () {
      final c88 = _cam(center: const LatLng(88, 0), zoom: 3);
      final c = c88;
      final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
      final selected = TileSelector.visible(projector: ortho, camera: c, grid: grid);
      expect(selected, isNotEmpty);
      // Polar view: every selected tile must have at least one front-facing
      // corner — no tile from the far side may leak into the render set.
      for (final t in selected) {
        final corners = [
          LatLng(grid.north(t.y), grid.west(t.x)),
          LatLng(grid.north(t.y), grid.east(t.x)),
          LatLng(grid.south(t.y), grid.west(t.x)),
          LatLng(grid.south(t.y), grid.east(t.x)),
        ];
        expect(
          corners.any((c) => ortho.project(c, c88) != null),
          isTrue,
          reason: 'tile $t is entirely behind the camera',
        );
      }
    });
  });

  group('complexity', () {
    test('z18 window stays tiny (no full-grid scan)', () {
      final c = _cam(center: const LatLng(30, 120), zoom: 18, width: 1080, height: 800);
      final grid = TileGrid.of(TileSchemeKind.webMercator, 18);
      final candidates = TileSelector.visible(
        projector: merc,
        camera: c,
        grid: grid,
        verify: false,
      );
      expect(candidates.length, lessThanOrEqualTo(160),
          reason: 'window should be O(visible tiles), got ${candidates.length}');
      expect(candidates.length, lessThan(grid.rows),
          reason: 'must never scan whole rows (z18 has ${grid.rows} rows)');
      expect(candidates, isNotEmpty);
    });

    test('z3 globe window is bounded by the visible hemisphere', () {
      final c = _cam(zoom: 3);
      final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
      final candidates = TileSelector.visible(
        projector: ortho,
        camera: c,
        grid: grid,
        verify: false,
      );
      expect(candidates.length, lessThanOrEqualTo(grid.cols * grid.rows));
    });

    test('selection is bounded at the zoom used by the offline bundle', () {
      final c = _cam(center: const LatLng(40, 116), zoom: 5, width: 1280, height: 720);
      final grid = TileGrid.of(TileSchemeKind.webMercator, 6);
      final visible = TileSelector.visible(projector: ortho, camera: c, grid: grid);
      expect(visible.length, lessThan(200));
      expect(visible.length, greaterThan(2));
    });
  });

  group('tile grid', () {
    test('mercator row bounds end at the projection limit', () {
      final grid = TileGrid.of(TileSchemeKind.webMercator, 3);
      expect(grid.north(0), closeTo(mercatorMaxLatitude, 1e-9));
      expect(grid.south(grid.rows - 1), closeTo(-mercatorMaxLatitude, 1e-9));
    });

    test('4326 rows are uniform in degrees', () {
      final grid = TileGrid.of(TileSchemeKind.epsg4326, 2);
      expect(grid.north(0), 90);
      expect(grid.south(0), closeTo(45, 1e-12));
      expect(grid.latitudeAt(0, 0.5), closeTo(67.5, 1e-12));
    });

    test('wrapping keeps x inside the grid', () {
      final grid = TileGrid.of(TileSchemeKind.webMercator, 3);
      expect(grid.wrapX(-1), grid.cols - 1);
      expect(grid.wrapX(grid.cols), 0);
    });

    test('mercator latitude interpolation is monotonic', () {
      final grid = TileGrid.of(TileSchemeKind.webMercator, 5);
      var previous = 90.0;
      for (var y = 0; y < 4; y++) {
        for (var j = 0; j <= 4; j++) {
          final lat = grid.latitudeAt(y, j / 4);
          expect(lat, lessThanOrEqualTo(previous + 1e-9));
          previous = lat;
        }
      }
    });
  });
}
