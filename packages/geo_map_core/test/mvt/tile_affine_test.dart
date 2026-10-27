import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  group('TileGrid.unwrapX', () {
    test('z0 at the prime meridian stays on the single world copy', () {
      expect(TileGrid.unwrapX(0, 0, 0), 0);
    });

    test('z0 off-centre also stays put', () {
      expect(TileGrid.unwrapX(0, 0, -170), 0);
      expect(TileGrid.unwrapX(0, 0, 170), 0);
    });

    test('a tile east of the antimeridian moves to the east copy', () {
      // z2 has 4 columns; x=0 covers [-180,-90]. At lng 170 the nearest copy
      // starts at 180, i.e. column 4.
      expect(TileGrid.unwrapX(0, 2, 170), 4);
    });

    test('a tile west of the antimeridian moves to the west copy', () {
      // z2 x=3 covers [90,180]; at lng -170 the nearest copy starts at -270.
      expect(TileGrid.unwrapX(3, 2, -170), -1);
    });

    test('a tile containing the camera keeps its canonical column', () {
      expect(TileGrid.unwrapX(1, 2, 0), 1); // x=1 covers [-90,0]
      expect(TileGrid.unwrapX(2, 2, 0), 2); // x=2 covers [0,90]
    });
  });

  group('tileAffine', () {
    const projector = MercatorProjector();
    final state = CameraState(
      center: const LatLng(0, 0),
      zoom: 2,
      size: const ViewportSize(512, 512),
    );

    test('maps the tile corner to its projected screen position', () {
      final affine = tileAffine(projector, state, z: 2, x: 1, y: 1)!;
      final mapped = affine.map(const Vec2(0, 0));
      final expected = projector.project(
        mvtTilePointToLatLng(const Vec2(0, 0),
            z: 2, tileX: 1, tileY: 1, extent: 1),
        state,
      )!;
      expect(mapped.x, closeTo(expected.x, 1e-9));
      expect(mapped.y, closeTo(expected.y, 1e-9));
    });

    test('is exact for interior points (Mercator is affine in tile space)', () {
      final affine = tileAffine(projector, state, z: 2, x: 1, y: 1)!;
      const points = [
        Vec2(0.25, 0.75),
        Vec2(0.5, 0.5),
        Vec2(0.9, 0.1),
      ];
      for (final p in points) {
        final mapped = affine.map(p);
        final projected = projector.project(
          mvtTilePointToLatLng(p, z: 2, tileX: 1, tileY: 1, extent: 1),
          state,
        )!;
        expect(mapped.x, closeTo(projected.x, 1e-6));
        expect(mapped.y, closeTo(projected.y, 1e-6));
      }
    });

    test('returns null when a corner is on the far side of the globe', () {
      const globe = OrthographicProjector();
      // z3 x=7 covers [135,180], far from a camera at lng 0.
      expect(tileAffine(globe, state, z: 3, x: 7, y: 3), isNull);
    });
  });
}
