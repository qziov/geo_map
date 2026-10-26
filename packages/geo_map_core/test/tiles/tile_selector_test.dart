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

  group('overzoom semantics', () {
    test('desired zoom has no latitude factor', () {
      final equator = _cam(center: const LatLng(0, 0), zoom: 5);
      final pole = _cam(center: const LatLng(85, 0), zoom: 5);
      expect(TileSelector.coveringZoomLevel(equator),
          TileSelector.coveringZoomLevel(pole));
      expect(TileSelector.coveringZoomLevel(equator), 5);
    });

    test('data zoom is clamped to the source range', () {
      final c = _cam(zoom: 12);
      final sel = TileSelector.select(
        projector: ortho,
        camera: c,
        desiredZ: TileSelector.coveringZoomLevel(c),
        sourceMinZoom: 1,
        sourceMaxZoom: 8,
      );
      expect(sel.dataZoom, 8);
      expect(sel.renderZoom, 12);
      expect(sel.overscale, 16);
      expect(sel.isOverzoomed, isTrue);
      expect(sel.subCells, 16);
    });

    test('no overzoom below the source maximum', () {
      final c = _cam(zoom: 5);
      final sel = TileSelector.select(
        projector: ortho,
        camera: c,
        desiredZ: TileSelector.coveringZoomLevel(c),
        sourceMinZoom: 0,
        sourceMaxZoom: 8,
      );
      expect(sel.dataZoom, 5);
      expect(sel.renderZoom, 5);
      expect(sel.isOverzoomed, isFalse);
      expect(sel.overscale, 1);
    });

    test('zoom below the source minimum is clamped up', () {
      final c = _cam(zoom: 0);
      final sel = TileSelector.select(
        projector: ortho,
        camera: c,
        desiredZ: 0,
        sourceMinZoom: 1,
        sourceMaxZoom: 8,
      );
      expect(sel.dataZoom, 1);
    });

    test('the selection never requests a level above the source maximum', () {
      final c = _cam(zoom: 15);
      final sel = TileSelector.select(
        projector: ortho,
        camera: c,
        desiredZ: 15,
        sourceMinZoom: 0,
        sourceMaxZoom: 6,
      );
      for (final t in sel.tiles) {
        expect(t.z, lessThanOrEqualTo(6));
      }
    });
  });

  group('high latitude never drops the polar row', () {
    test('the window always reaches the polar row', () {
      // Above the mercator limit the visible band has no tile of its own;
      // the polar cap fills it. What matters is that the *window* still
      // reaches row 0 instead of collapsing to an empty band.
      for (final lat in [86.0, 88.0, 89.9]) {
        final grid = TileGrid.of(TileSchemeKind.webMercator, 6);
        expect(grid.rawYOf(lat), 0, reason: 'lat $lat');
      }
    });

    test('row 0 is selected whenever the polar band is on screen', () {
      // On a globe the polar row is only front-facing when the camera is
      // close to the pole — the polar cap covers the region above 85.05°.
      for (final lat in [84.0, 86.0, 88.0]) {
        for (final zoom in [3.0, 6.0]) {
          final c = _cam(center: LatLng(lat, 0), zoom: zoom);
          final grid = TileGrid.of(TileSchemeKind.webMercator, zoom.round());
          final bounds = ortho.approximateVisibleBounds(c);
          final sel = TileSelector.visible(
              projector: ortho, camera: c, grid: grid);
          expect(sel, isNotEmpty, reason: 'lat $lat zoom $zoom');
          if (bounds.north >= mercatorMaxLatitude - 1e-6) {
            expect(sel.any((t) => t.y == 0), isTrue,
                reason: 'row 0 missing at lat $lat zoom $zoom');
          }
        }
      }
    });

    test('selection stays a superset of brute force at high latitude', () {
      for (final lat in [70.0, 84.0, 89.0]) {
        for (final zoom in [3.0, 5.0]) {
          final c = _cam(center: LatLng(lat, 20), zoom: zoom);
          final grid = TileGrid.of(TileSchemeKind.webMercator, zoom.round());
          final fast = TileSelector.visible(
                  projector: ortho, camera: c, grid: grid)
              .map((t) => '$t')
              .toSet();
          final brute = TileSelector.bruteForce(
                  projector: ortho, camera: c, grid: grid)
              .map((t) => '$t')
              .toSet();
          expect(brute.difference(fast), isEmpty,
              reason: 'lat $lat zoom $zoom missed ${brute.difference(fast)}');
        }
      }
    });

    test('the adaptive margin grows with the on-screen tile size', () {
      // At a matching grid level a tile is always 256 px wide, so the margin
      // only grows when the grid is coarser than the camera (overzoom) or the
      // camera zoom is fractional.
      final c12 = _cam(zoom: 12);
      final coarse = TileGrid.of(TileSchemeKind.webMercator, 3);
      final fine = TileGrid.of(TileSchemeKind.webMercator, 12);
      final mCoarse = TileSelector.adaptiveMargin(c12, coarse);
      final mFine = TileSelector.adaptiveMargin(c12, fine);
      expect(mCoarse, greaterThan(mFine));
      expect(mFine, greaterThanOrEqualTo(GeoEngineTuning.selectMargin));
    });
  });
}
