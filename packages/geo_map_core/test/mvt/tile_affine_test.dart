import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  group('visibleWorldCopies', () {
    test('a world wider than the viewport needs one copy', () {
      // At z2.6 the world is ~1552 px and the viewport 1080 px.
      expect(
        visibleWorldCopies(
          baseX: 0,
          spanPx: 194,
          worldSize: 1552,
          viewportWidth: 1080,
        ),
        (0, 0),
      );
    });

    test('a world narrower than the viewport repeats', () {
      // At z0.5 the world is ~362 px: three copies fit in 1080 px.
      expect(
        visibleWorldCopies(
          baseX: 359,
          spanPx: 362,
          worldSize: 362,
          viewportWidth: 1080,
        ),
        (-1, 1),
      );
    });

    test('a tile near the west seam is drawn on its east copy', () {
      // baseX=-700 is off-screen left; the +1 copy lands at 852 and is visible.
      expect(
        visibleWorldCopies(
          baseX: -700,
          spanPx: 194,
          worldSize: 1552,
          viewportWidth: 1080,
        ),
        (1, 1),
      );
    });

    test('a tile entirely away from the viewport yields an empty range', () {
      final (start, end) = visibleWorldCopies(
        baseX: -5000,
        spanPx: 194,
        worldSize: 1552,
        viewportWidth: 1080,
      );
      expect(start, greaterThan(end));
    });

    test('degenerate inputs fall back to the base copy', () {
      expect(
        visibleWorldCopies(
          baseX: 0,
          spanPx: 0,
          worldSize: 0,
          viewportWidth: 0,
        ),
        (0, 0),
      );
    });
  });

  group('tileAffine', () {
    const projector = MercatorProjector();
    final state = CameraState(
      center: const LatLng(0, 0),
      zoom: 2,
      size: const ViewportSize(512, 512),
    );

    test('origin is the projected north-west corner', () {
      final affine = tileAffine(projector, state, z: 2, x: 1, y: 1)!;
      final expected = projector.project(
        mvtTilePointToLatLng(const Vec2(0, 0),
            z: 2, tileX: 1, tileY: 1, extent: 1),
        state,
      )!;
      expect(affine.origin.x, closeTo(expected.x, 1e-9));
      expect(affine.origin.y, closeTo(expected.y, 1e-9));
    });

    test('basis is the constant tile span and stays exact', () {
      // Mercator is affine in tile space, so this is exact for every point.
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

    test('a tile across the camera seam keeps a normal span', () {
      // Camera at 72.4E, tile x=0 at z3. Its NW corner projects to the +copy
      // while its NE corner would wrap to the -copy; deriving the basis from
      // three projected corners used to stretch it across the whole world.
      final seamState = CameraState(
        center: const LatLng(0, 72.4),
        zoom: 3,
        size: const ViewportSize(1080, 720),
      );
      final affine = tileAffine(projector, seamState, z: 3, x: 0, y: 3)!;
      final span = seamState.worldSize / 8;

      expect(affine.ux, closeTo(span, 1e-9));
      expect(affine.uy, 0);
      expect(affine.vx, 0);
      expect(affine.vy, closeTo(span, 1e-9));
      expect(affine.ux, lessThan(seamState.worldSize));
    });

    test('returns null when the origin is on the far side of the globe', () {
      const globe = OrthographicProjector();
      // z3 x=7 covers [135,180], far from a camera at lng 0.
      expect(tileAffine(globe, state, z: 3, x: 7, y: 3), isNull);
    });

    test('unbounded camera longitude keeps the nearest copy under the centre', () {
      // Option A: the camera may sit at lng 190 (== -170). `project` wraps
      // relative to it, so the tile covering that meridian must straddle the
      // screen centre and need only its base copy — the same placement the
      // raster layer's ±1 copy loop produces.
      final eastState = CameraState(
        center: const LatLng(0, 190),
        zoom: 3,
        size: const ViewportSize(1080, 720),
      );
      final affine = tileAffine(projector, eastState, z: 3, x: 0, y: 3)!;

      expect(affine.origin.x, lessThan(540));
      expect(affine.origin.x + affine.ux, greaterThan(540));
      expect(
        visibleWorldCopies(
          baseX: affine.origin.x,
          spanPx: affine.ux,
          worldSize: eastState.worldSize,
          viewportWidth: eastState.size.width,
        ),
        (0, 0),
      );
    });
  });
}
