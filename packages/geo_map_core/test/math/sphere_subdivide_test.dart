import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  group('subdivideSpherePolyline', () {
    test('a parallel stays on its parallel', () {
      // The tropics case: two vertices 180° apart at constant latitude. A great
      // circle between them passes over the pole, a lat/lng chord bows too;
      // Mercator-line interpolation must keep every sample at 23.5°.
      const lat = 23.5;
      final out = subdivideSpherePolyline(
        const [LatLng(lat, -180), LatLng(lat, 0), LatLng(lat, 180)],
      );
      expect(out.length, greaterThan(3));
      for (final p in out) {
        expect(p.latitude, closeTo(lat, 1e-9));
      }
      // Longitude must march eastwards in small steps, never jump a hemisphere.
      for (var i = 1; i < out.length; i++) {
        var step = out[i].longitude - out[i - 1].longitude;
        if (step < -180) step += 360; // the final sample wraps to -180
        expect(step, inInclusiveRange(0, 2),
            reason: 'sample $i jumps $step degrees');
      }
    });

    test('a meridian stays on its meridian', () {
      final out = subdivideSpherePolyline(
        const [LatLng(-80, 30), LatLng(80, 30)],
      );
      expect(out.length, greaterThan(2));
      for (final p in out) {
        expect(p.longitude, closeTo(30, 1e-9));
      }
    });

    test('samples are evenly spaced in Mercator, not in latitude', () {
      final out = subdivideSpherePolyline(
        const [LatLng(0, 0), LatLng(80, 0)],
        granularity: 8,
      );
      expect(out.length, greaterThan(2));
      for (var i = 1; i < out.length; i++) {
        expect(out[i].latitude, greaterThan(out[i - 1].latitude));
      }
      // Equal Mercator steps mean the latitude steps shrink towards the pole.
      expect(out.last.latitude - out[out.length - 2].latitude,
          lessThan(out[1].latitude - out[0].latitude));
    });

    test('keeps a segment continuous across the antimeridian', () {
      // +179 -> -179 is one short hop east, not a 358° sweep through 0°.
      final out = subdivideSpherePolyline(
        const [LatLng(10, 179), LatLng(10, -179)],
        granularity: 64,
      );
      expect(out.length, greaterThan(2));
      for (final p in out) {
        expect(p.longitude.abs(), greaterThan(178.9),
            reason: 'samples must stay next to the date line');
        expect(p.latitude, closeTo(10, 1e-9));
      }
    });

    test('already dense geometry is returned untouched', () {
      final points = [const LatLng(1, 1), const LatLng(1.001, 1.001)];
      expect(identical(subdivideSpherePolyline(points), points), isTrue);
    });

    test('a closed ring repeats its first point', () {
      final out = subdivideSpherePolyline(
        const [
          LatLng(0, 0),
          LatLng(0, 90),
          LatLng(90 / 2, 90),
          LatLng(0, 0),
        ],
        granularity: 8,
        closed: true,
      );
      expect(out.length, greaterThan(4));
      expect(out.first.latitude, closeTo(out.last.latitude, 1e-9));
      expect(out.first.longitude, closeTo(out.last.longitude, 1e-9));
    });

    test('degenerate input passes through', () {
      const single = [LatLng(0, 0)];
      expect(identical(subdivideSpherePolyline(single), single), isTrue);
      expect(identical(subdivideSpherePolyline(single, granularity: 1), single),
          isTrue);
    });
  });

  group('dashPhaseSeed', () {
    const worldSize = 1024.0;
    const radiusPx = 200.0;

    double flat(Vec2 p, {required int z, required int x, required int y, bool horizontal = true}) =>
        dashPhaseSeed(
          p,
          z: z,
          tileX: x,
          tileY: y,
          horizontal: horizontal,
          sphere: false,
          worldSize: worldSize,
          radiusPx: radiusPx,
        );

    double globe(Vec2 p, {required int z, required int x, required int y, bool horizontal = true}) =>
        dashPhaseSeed(
          p,
          z: z,
          tileX: x,
          tileY: y,
          horizontal: horizontal,
          sphere: true,
          worldSize: worldSize,
          radiusPx: radiusPx,
        );

    test('flat: the phase is the world coordinate in pixels', () {
      expect(flat(const Vec2(0, 0), z: 0, x: 0, y: 0), 0);
      expect(flat(const Vec2(0.5, 0), z: 0, x: 0, y: 0), 512);
      expect(flat(const Vec2(0.5, 0), z: 1, x: 1, y: 0), 768,
          reason: 'z1 tile 1 covers world x 0.5..1, so its middle is 0.75');
    });

    test('flat: two tiles agree at their shared vertical edge', () {
      final left = flat(const Vec2(1, 0.37), z: 3, x: 5, y: 2);
      final right = flat(const Vec2(0, 0.37), z: 3, x: 6, y: 2);
      expect(left, closeTo(right, 1e-12));
    });

    test('flat: two tiles agree at their shared horizontal edge', () {
      final above = flat(const Vec2(0.3, 1), z: 3, x: 5, y: 2, horizontal: false);
      final below = flat(const Vec2(0.3, 0), z: 3, x: 5, y: 3, horizontal: false);
      expect(above, closeTo(below, 1e-12));
    });

    test('globe: neighbours agree, and the equator scales with the radius', () {
      // z2 tile (1,1) spans world x 0.25..0.5, y 0.25..0.5; the sample is its
      // south-east corner, which is on the equator at world (0.5, 0.5).
      final left = globe(const Vec2(1, 1), z: 2, x: 1, y: 1);
      final right = globe(const Vec2(0, 1), z: 2, x: 2, y: 1);
      expect(left, closeTo(right, 1e-9));
      // At the equator the phase is worldX * 2*pi*R.
      expect(left, closeTo(0.5 * 2 * 3.141592653589793 * radiusPx, 1e-6));
    });

    test('globe: a meridian uses latitude, so stacked tiles agree', () {
      final upper = globe(const Vec2(0.4, 1), z: 2, x: 2, y: 1, horizontal: false);
      final lower = globe(const Vec2(0.4, 0), z: 2, x: 2, y: 2, horizontal: false);
      expect(upper, closeTo(lower, 1e-9));
    });

    test('globe: the phase shrinks towards the pole', () {
      final equator = globe(const Vec2(0.5, 0.5), z: 2, x: 1, y: 1);
      final north = globe(const Vec2(0.5, 0.05), z: 2, x: 1, y: 1);
      expect(north.abs(), lessThan(equator.abs()));
    });
  });
}
