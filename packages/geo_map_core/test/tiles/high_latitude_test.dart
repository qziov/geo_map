import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

/// The high-latitude black-tile regressions, locked down.
///
/// The old production path scanned **every row** of the grid and used a grid
/// whose latitudes were **linear** for Web Mercator. Both are wrong:
///
/// * the linear latitude put a z5 tile at the wrong latitude band, so the
///   screen asked for tiles that do not exist (HTTP 404) and the hole stayed
///   black;
/// * the full-row scan issued a request per column of the polar cap, which at
///   z8 is 256 columns — a request storm that starved the real tiles.
void main() {
  const ortho = OrthographicProjector();
  const merc = MercatorProjector();

  CameraState cam(
    double lat,
    double zoom, {
    double lng = 0,
    double width = 800,
    double height = 600,
  }) =>
      CameraState(
        center: LatLng(lat, lng),
        zoom: zoom,
        size: ViewportSize(width, height),
        minZoom: 0,
        maxZoom: 22,
      );

  group('mercator row geometry (the black-tile root cause)', () {
    test('the northern row ends at the projection limit, not at 90°', () {
      final grid = TileGrid.of(TileSchemeKind.webMercator, 5);
      // A linear grid would say 90.0 / 78.75 here — the whole point.
      expect(grid.north(0), closeTo(mercatorMaxLatitude, 1e-9));
      expect(grid.north(0), lessThan(90.0));
      expect(grid.south(0), closeTo(83.9792594988, 1e-6));
    });

    test('the row bands are monotonic and cover the whole range', () {
      for (final z in [0, 1, 5, 8, 12]) {
        final grid = TileGrid.of(TileSchemeKind.webMercator, z);
        expect(grid.north(0), closeTo(mercatorMaxLatitude, 1e-9));
        expect(grid.south(grid.rows - 1), closeTo(-mercatorMaxLatitude, 1e-9));
        var previous = double.infinity;
        for (var y = 0; y < grid.rows; y++) {
          expect(grid.north(y), lessThanOrEqualTo(previous + 1e-9));
          expect(grid.south(y), lessThan(grid.north(y)));
          previous = grid.north(y);
        }
      }
    });

    test('a parent row is exactly two child rows', () {
      // The split is exact in **mercator-y** space — that is the space the
      // image rows live in, and the space the UV sub-rect relies on. In
      // *latitude* the same split is not symmetric, because mercator is
      // conformal: the northern half of a row covers more degrees.
      final parent = TileGrid.of(TileSchemeKind.webMercator, 4);
      final child = TileGrid.of(TileSchemeKind.webMercator, 5);
      for (var y = 0; y < parent.rows; y++) {
        // Same mercator-y ⇒ same latitude at the shared edges.
        expect(child.north(2 * y), closeTo(parent.north(y), 1e-9));
        expect(child.south(2 * y + 1), closeTo(parent.south(y), 1e-9));
        // The middle edge lies strictly inside the parent row.
        final middle = child.north(2 * y + 1);
        expect(middle, lessThan(parent.north(y)));
        expect(middle, greaterThan(parent.south(y)));
        // And the row *indices* nest exactly.
        expect(parent.parentOf(TileKey(5, 3, 2 * y + 1)), TileKey(4, 1, y));
      }
    });

    test('the parent of a tile is the tile above it', () {
      final grid = TileGrid.of(TileSchemeKind.webMercator, 6);
      for (var y = 1; y < grid.rows; y++) {
        for (var x = 1; x < grid.cols; x++) {
          final parent = grid.parentOf(TileKey(6, x, y));
          expect(parent, isNotNull);
          expect(parent!.z, 5);
          expect(parent.x, x >> 1);
          expect(parent.y, y >> 1);
        }
      }
    });
  });

  group('high latitude selection', () {
    test('the polar row is reachable from a polar camera', () {
      for (final lat in [60.0, 70.0, 80.0, 85.0, 88.0, 89.5]) {
        for (final zoom in [3.0, 5.0, 8.0]) {
          final c = cam(lat, zoom);
          final grid = TileGrid.of(TileSchemeKind.webMercator, zoom.round());
          final selected =
              TileSelector.visible(projector: ortho, camera: c, grid: grid);
          // Row 0 is the row the polar cap stretches from. It must be
          // selected whenever the row itself reaches the viewport — i.e.
          // whenever the row is on screen at all.
          final row0 = TileKey(grid.zoom, 0, 0);
          if (_touchesScreen(ortho, c, grid, row0)) {
            expect(
              selected.map((t) => '$t'),
              contains('$row0'),
              reason: 'row 0 missing at lat $lat zoom $zoom',
            );
          }
        }
      }
    });

    test('above the mercator limit the polar cap takes over', () {
      // Above ±85.05° there is no mercator tile at all — the cap fills the
      // region. The *tiles* below the limit must still be selected when the
      // viewport reaches them, and the cap must cover the rest.
      for (final lat in [88.0, 89.0, 89.9]) {
        for (final zoom in [3.0, 6.0, 8.0]) {
          final c = cam(lat, zoom);
          final grid = TileGrid.of(TileSchemeKind.webMercator, zoom.round());
          final capColumns = PolarCapBuilder.visibleColumns(
            grid: grid,
            camera: c,
            north: true,
          );
          expect(capColumns, isNotEmpty,
              reason: 'no cap at lat $lat zoom $zoom');
        }
      }
    });

    test('the selection never includes a tile from behind the camera', () {
      for (final lat in [0.0, 45.0, 80.0, 88.0]) {
        final c = cam(lat, 4);
        final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
        final selected =
            TileSelector.visible(projector: ortho, camera: c, grid: grid);
        for (final t in selected) {
          final corners = [
            LatLng(grid.north(t.y), grid.west(t.x)),
            LatLng(grid.north(t.y), grid.east(t.x)),
            LatLng(grid.south(t.y), grid.west(t.x)),
            LatLng(grid.south(t.y), grid.east(t.x)),
          ];
          expect(
            corners.any((p) => ortho.project(p, c) != null),
            isTrue,
            reason: 'tile $t is entirely behind the camera',
          );
        }
      }
    });

    test('the window stays a superset of the brute-force result', () {
      // Compared against the brute-force scan *restricted to the tiles that
      // really touch the screen*: the scan's bounding-box test also accepts
      // tiles whose corners project to two far-apart places (a tile
      // straddling the antimeridian), which are false positives.
      for (final lat in [55.0, 70.0, 85.0, 89.0]) {
        for (final zoom in [3.0, 5.0, 7.0]) {
          final c = cam(lat, zoom, lng: 30);
          final grid = TileGrid.of(TileSchemeKind.webMercator, zoom.round());
          final fast = TileSelector.visible(
                  projector: ortho, camera: c, grid: grid)
              .map((t) => '$t')
              .toSet();
          final brute = TileSelector.bruteForce(
                  projector: ortho, camera: c, grid: grid, margin: 0)
              .map((t) => '$t')
              .toSet();
          final onScreen = brute
              .where((k) => _touchesScreen(ortho, c, grid, _keyOf(k)))
              .toSet();
          expect(
            onScreen.difference(fast),
            isEmpty,
            reason: 'lat $lat zoom $zoom missed ${onScreen.difference(fast)}',
          );
        }
      }
    });

    test('no tile that touches the screen is ever dropped', () {
      // The safety property that matters: every tile with a point inside the
      // viewport must be selected. It is checked against a geometric ground
      // truth (not against the bounding-box heuristic), so a tile straddling
      // the antimeridian — whose corners project to two far-apart places —
      // cannot fool the check.
      for (final projector in [ortho, merc]) {
        for (final lat in [-88.0, -70.0, 0.0, 70.0, 88.0]) {
          for (final zoom in [3.0, 5.0, 7.0]) {
            for (final lng in [0.0, 179.0, -179.0]) {
              final c = cam(lat, zoom, lng: lng);
              final grid =
                  TileGrid.of(TileSchemeKind.webMercator, zoom.round());
              final selected = TileSelector.visible(
                      projector: projector, camera: c, grid: grid)
                  .map((t) => '$t')
                  .toSet();
              for (var y = 0; y < grid.rows; y++) {
                for (var x = 0; x < grid.cols; x++) {
                  final key = TileKey(grid.zoom, x, y);
                  if (!_touchesScreen(projector, c, grid, key)) continue;
                  expect(
                    selected,
                    contains('$key'),
                    reason: '${projector.kind} lat $lat zoom $zoom '
                        'lng $lng dropped $key',
                  );
                }
              }
            }
          }
        }
      }
    });

    test('a high-zoom polar camera does not scan the whole grid', () {
      // The old implementation walked every row of the grid and asked for
      // every polar-cap column. At z8 that is 256 columns — a request storm.
      final c = cam(88, 8);
      final grid = TileGrid.of(TileSchemeKind.webMercator, 8);
      final selected =
          TileSelector.visible(projector: ortho, camera: c, grid: grid);
      expect(selected.length, lessThan(64),
          reason: 'got ${selected.length} tiles');
    });
  });

  group('overzoom', () {
    test('the magnification is exactly 2^(render - data)', () {
      // MapLibre: `scale = worldSize / zoomScale(canonical.z)` — the tile is
      // stretched by the zoom difference, the texture is not re-cut.
      const tileSize = GeoEngineTuning.tileSize;
      for (final render in [6, 8, 10]) {
        for (final data in [3, 5]) {
          final world = tileSize * (1 << render);
          final onScreen = world / (1 << data);
          expect(
            onScreen / tileSize,
            closeTo((1 << (render - data)).toDouble(), 1e-9),
          );
        }
      }
    });

    test('the data level is clamped, the render level is not', () {
      final c = cam(40, 12);
      final sel = TileSelector.select(
        projector: ortho,
        camera: c,
        desiredZ: TileSelector.coveringZoomLevel(c),
        sourceMinZoom: 1,
        sourceMaxZoom: 5,
      );
      expect(sel.dataZoom, 5);
      expect(sel.renderZoom, 12);
      expect(sel.isOverzoomed, isTrue);
      expect(sel.overscale, 128);
      for (final t in sel.tiles) {
        expect(t.z, 5, reason: 'a tile above the source maximum was selected');
      }
    });

    test('the parent UV sub-rect matches the fine tile exactly', () {
      // The fallback must show the parent's pixels for *this* tile only —
      // the classic "mosaic block" bug is getting this wrong.
      const parentWidth = 256.0;
      const parentHeight = 256.0;
      for (var dz = 1; dz <= 3; dz++) {
        for (var cx = 0; cx < (1 << dz); cx++) {
          for (var cy = 0; cy < (1 << dz); cy++) {
            final rect = parentUvRect(
              childX: cx,
              childY: cy,
              dz: dz,
              parentWidth: parentWidth,
              parentHeight: parentHeight,
            );
            expect(rect.spanU, closeTo(parentWidth / (1 << dz), 1e-9));
            expect(rect.spanV, closeTo(parentHeight / (1 << dz), 1e-9));
            expect(rect.u0, closeTo(cx * rect.spanU, 1e-9));
            expect(rect.v0, closeTo(cy * rect.spanV, 1e-9));
            // The sub-rect must stay inside the parent image.
            expect(rect.u0 + rect.spanU, lessThanOrEqualTo(parentWidth + 1e-9));
            expect(rect.v0 + rect.spanV, lessThanOrEqualTo(parentHeight + 1e-9));
          }
        }
      }
    });

    test('the sub-rect of the last child touches the parent edge', () {
      final rect = parentUvRect(
        childX: 1,
        childY: 1,
        dz: 1,
        parentWidth: 256,
        parentHeight: 256,
      );
      expect(rect.u0 + rect.spanU, closeTo(256, 1e-9));
      expect(rect.v0 + rect.spanV, closeTo(256, 1e-9));
    });
  });

  group('row order on the wire', () {
    test('TMS flips the row, XYZ keeps it', () {
      final xyz = TileGrid.of(TileSchemeKind.webMercator, 3);
      final tms = TileGrid.of(TileSchemeKind.webMercator, 3,
          order: TileRowOrder.tmsBottomUp);
      for (var y = 0; y < xyz.rows; y++) {
        expect(xyz.rowForFetch(y), y);
        expect(tms.rowForFetch(y), (1 << 3) - 1 - y);
      }
    });

    test('the flip is its own inverse', () {
      final tms = TileGrid.of(TileSchemeKind.webMercator, 5,
          order: TileRowOrder.tmsBottomUp);
      for (var y = 0; y < tms.rows; y++) {
        expect(tms.rowForFetch(tms.rowForFetch(y)), y);
      }
    });
  });
}

/// Parse a `"z/x/y"` key back into a [TileKey].
TileKey _keyOf(String key) {
  final parts = key.split('/');
  return TileKey(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// Geometric ground truth: does any sampled point of the tile land inside the
/// viewport?
///
/// This is deliberately independent of the selection's bounding-box logic — a
/// tile straddling the antimeridian has corners that project to two far-apart
/// places, so a bbox test alone would either hide it or invent it.
bool _touchesScreen(
  GeoProjector projector,
  CameraState camera,
  TileGrid grid,
  TileKey key, [
  int samples = 4,
]) {
  for (var j = 0; j <= samples; j++) {
    for (var i = 0; i <= samples; i++) {
      final lat = grid.latitudeAt(key.y, j / samples);
      final lng =
          grid.west(key.x) + (grid.east(key.x) - grid.west(key.x)) * (i / samples);
      final p = projector.project(LatLng(lat, lng), camera);
      if (p == null) continue;
      if (p.x >= 0 &&
          p.x <= camera.size.width &&
          p.y >= 0 &&
          p.y <= camera.size.height) {
        return true;
      }
    }
  }
  return false;
}
