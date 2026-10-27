import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

/// Count of points strictly between the endpoints that lie on a grid axis.
int _offAxisCount(List<Vec2> pts, double cell) {
  var n = 0;
  for (final p in pts) {
    final onX = ((p.x / cell) - (p.x / cell).roundToDouble()).abs() < 1e-9;
    final onY = ((p.y / cell) - (p.y / cell).roundToDouble()).abs() < 1e-9;
    if (onX || onY) n++;
  }
  return n;
}

void main() {
  group('mvtSubdivisionGranularity', () {
    test('lines halve per zoom level, like MapLibre', () {
      expect(mvtSubdivisionGranularity(0), 512);
      expect(mvtSubdivisionGranularity(1), 256);
      expect(mvtSubdivisionGranularity(4), 32);
      expect(mvtSubdivisionGranularity(9), 1);
      expect(mvtSubdivisionGranularity(12), 1, reason: 'clamped to 1');
    });

    test('fills halve but never below 2', () {
      int fill(int z) => mvtSubdivisionGranularity(
            z,
            base: mvtFillBaseGranularity,
            min: mvtFillMinGranularity,
          );
      expect(fill(0), 128);
      expect(fill(3), 16);
      expect(fill(10), 2);
      expect(fill(18), 2);
    });

    test('nonsense zoom does not explode', () {
      expect(mvtSubdivisionGranularity(-5), 512);
      expect(mvtSubdivisionGranularity(99), 1);
    });
  });

  group('subdivideTilePolyline', () {
    test('granularity 1 returns the input list itself', () {
      final pts = [const Vec2(0, 0), const Vec2(1, 1)];
      expect(identical(subdivideTilePolyline(pts), pts), isTrue);
    });

    test('inserts vertices on every crossed grid axis', () {
      final out = subdivideTilePolyline(
        [const Vec2(0, 0), const Vec2(1, 0)],
        granularity: 8,
      );
      // 8 cells along x -> origin, 7 interior crossings, endpoint.
      expect(out.length, 9);
      expect(out.first.x, 0);
      expect(out.last.x, 1);
      for (var i = 0; i < out.length; i++) {
        expect(out[i].x, closeTo(i / 8, 1e-12));
        expect(out[i].y, 0);
      }
    });

    test('walks diagonals at cell corners', () {
      final out = subdivideTilePolyline(
        [const Vec2(0, 0), const Vec2(1, 1)],
        granularity: 4,
      );
      expect(out.length, 5);
      for (var i = 0; i < out.length; i++) {
        expect(out[i].x, closeTo(i / 4, 1e-12));
        expect(out[i].y, closeTo(i / 4, 1e-12));
      }
    });

    test('keeps endpoints exact', () {
      const a = Vec2(0.03, 0.31);
      const b = Vec2(0.62, 0.777);
      final out = subdivideTilePolyline([a, b], granularity: 32);
      expect(out.first.x, a.x);
      expect(out.first.y, a.y);
      expect(out.last.x, b.x);
      expect(out.last.y, b.y);
    });

    test('a constant-latitude segment stays on its parallel', () {
      // This is the tropics regression: a 180° span at constant y. Densifying
      // it along a great circle bows it polewards (at 180° it goes over the
      // pole); subdividing in tile space keeps every sample on the parallel.
      const y = 0.62;
      final out = subdivideTilePolyline(
        [const Vec2(0, y), const Vec2(1, y)],
        granularity: 64,
      );
      expect(out.length, greaterThan(2));
      double latAt(Vec2 p) => mvtTilePointToLatLng(
            p,
            z: 1,
            tileX: 0,
            tileY: 0,
            extent: 1,
          ).latitude;
      final expected = latAt(const Vec2(0, y));
      for (final p in out) {
        expect(p.y, y, reason: 'tile-space y must not move');
        expect(latAt(p), closeTo(expected, 1e-9),
            reason: 'latitude must not bow towards the pole');
      }
    });

    test('a meridian segment stays on its meridian', () {
      const x = 0.37;
      final out = subdivideTilePolyline(
        [const Vec2(x, 0), const Vec2(x, 1)],
        granularity: 16,
      );
      expect(out.length, 17);
      for (final p in out) {
        expect(p.x, x);
      }
    });

    test('closed ring appends the first point and closes the loop', () {
      final ring = [
        const Vec2(0, 0),
        const Vec2(1, 0),
        const Vec2(1, 1),
        const Vec2(0, 1),
      ];
      final out = subdivideTilePolyline(ring, granularity: 4, closed: true);
      expect(out.first.x, out.last.x);
      expect(out.first.y, out.last.y);
      // 4 edges x 4 cells = 16 spans, plus the repeated first point.
      expect(out.length, 17);
      expect(_offAxisCount(out, 0.25), out.length);
    });

    test('degenerate input is left alone', () {
      const single = [Vec2(0.5, 0.5)];
      expect(identical(subdivideTilePolyline(single, granularity: 8), single),
          isTrue);
      const repeated = [Vec2(0.5, 0.5), Vec2(0.5, 0.5)];
      expect(subdivideTilePolyline(repeated, granularity: 8).length, 1);
    });

    test('a segment already inside one cell gains nothing', () {
      final out = subdivideTilePolyline(
        [const Vec2(0.51, 0.51), const Vec2(0.6, 0.6)],
        granularity: 8,
      );
      expect(out.length, 2);
    });
  });
}
