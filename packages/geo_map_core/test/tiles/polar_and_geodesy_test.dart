import 'dart:math' as math;

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  group('polar cap geometry', () {
    final grid = TileGrid.of(TileSchemeKind.webMercator, 4);

    test('runs from the mercator limit to the pole', () {
      final cap = PolarCapBuilder.build(grid: grid, x: 3, north: true);
      expect(cap.latDegrees.first, closeTo(mercatorMaxLatitude, 1e-9));
      expect(cap.latDegrees.last, closeTo(90, 1e-9));
    });

    test('south cap mirrors the north cap', () {
      final cap = PolarCapBuilder.build(grid: grid, x: 3, north: false);
      expect(cap.latDegrees.first, closeTo(-mercatorMaxLatitude, 1e-9));
      expect(cap.latDegrees.last, closeTo(-90, 1e-9));
    });

    test('all meridian vertices converge at the pole', () {
      final cap = PolarCapBuilder.build(grid: grid, x: 5, north: true);
      final n = (math.sqrt(cap.vertexCount) - 1).round();
      final lastRow = n * (n + 1);
      var maxGap = 0.0;
      for (var i = 1; i <= n; i++) {
        final ax = cap.unit[lastRow * 3];
        final ay = cap.unit[lastRow * 3 + 1];
        final az = cap.unit[lastRow * 3 + 2];
        final bx = cap.unit[(lastRow + i) * 3];
        final by = cap.unit[(lastRow + i) * 3 + 1];
        final bz = cap.unit[(lastRow + i) * 3 + 2];
        final d = math.sqrt(math.pow(ax - bx, 2) +
            math.pow(ay - by, 2) +
            math.pow(az - bz, 2));
        maxGap = math.max(maxGap, d);
      }
      expect(maxGap, lessThan(1e-9));
    });

    test('column spans the tile width', () {
      final cap = PolarCapBuilder.build(grid: grid, x: 2, north: true);
      // First row, first and last vertex longitudes differ by the tile width.
      final n = (math.sqrt(cap.vertexCount) - 1).round();
      final a = _lng(cap.unit[0], cap.unit[1]);
      final b = _lng(cap.unit[n * 3], cap.unit[n * 3 + 1]);
      expect((b - a).abs(), closeTo(grid.tileWidthDeg, 0.5));
    });

    test('visibility follows the camera hemisphere', () {
      CameraState c(double lat) => CameraState(
            center: LatLng(lat, 0),
            zoom: 3,
            size: const ViewportSize(800, 600),
          );
      expect(PolarCapBuilder.isVisible(camera: c(60), north: true), isTrue);
      expect(PolarCapBuilder.isVisible(camera: c(60), north: false), isFalse);
      expect(PolarCapBuilder.isVisible(camera: c(-60), north: true), isFalse);
      expect(PolarCapBuilder.isVisible(camera: c(-60), north: false), isTrue);
    });

    test('edge band picks the correct image row', () {
      final north = PolarCapBuilder.edgeBand(north: true, imageHeightPx: 256);
      final south = PolarCapBuilder.edgeBand(north: false, imageHeightPx: 256);
      expect(north.v0, 0);
      expect(south.v0, 255);
      expect(north.height, 1);
      expect(south.height, 1);
    });
  });

  group('geodesy', () {
    test('slerp midpoint sits on the great circle', () {
      final a = Vec3.of(const LatLng(0, 0));
      final b = Vec3.of(const LatLng(0, 90));
      final mid = slerp(a, b, 0.5).toLatLng();
      expect(mid.latitude, closeTo(0, 1e-9));
      expect(mid.longitude, closeTo(45, 1e-9));
    });

    test('slerp endpoints are exact', () {
      final a = Vec3.of(const LatLng(10, 20));
      final b = Vec3.of(const LatLng(-30, 160));
      expect(slerp(a, b, 0).toLatLng().latitude, closeTo(10, 1e-9));
      expect(slerp(a, b, 1).toLatLng().longitude, closeTo(160, 1e-9));
    });

    test('densify keeps the chord error under the tuned budget', () {
      const radius = 1200.0;
      final step = densifyStepForPixelError(radius, 0.5);
      final err = radius * (1 - math.cos(step / 2));
      expect(err, lessThanOrEqualTo(0.5 * 1.001));
    });

    test('densify adds intermediate points and preserves endpoints', () {
      final line = densifyGreatCircle(
        const [LatLng(0, 0), LatLng(0, 90)],
        stepRad: 0.1,
      );
      expect(line.length, greaterThan(10));
      expect(line.first.longitude, closeTo(0, 1e-9));
      expect(line.last.longitude, closeTo(90, 1e-9));
    });

    test('densify handles the antimeridian without jumps', () {
      final line = densifyGreatCircle(
        const [LatLng(10, 179), LatLng(10, -179)],
        stepRad: 0.05,
      );
      for (final p in line) {
        expect(p.longitude.abs(), lessThanOrEqualTo(180.0));
      }
      final total = angleBetween(line.first, line.last);
      expect(total, lessThan(0.1));
    });

    test('closed rings close back onto the first point', () {
      final ring = densifyGreatCircle(
        const [LatLng(0, 0), LatLng(0, 10), LatLng(10, 10), LatLng(10, 0)],
        stepRad: 0.5,
        closed: true,
      );
      expect(angleBetween(ring.first, ring.last), lessThan(0.6));
    });

    test('haversine matches a known distance', () {
      final d = haversine(const LatLng(0, 0), const LatLng(0, 1));
      expect(d, closeTo(111195, 500));
    });

    test('destinationPoint: north/east bearings land on the axes', () {
      final north = destinationPoint(const LatLng(0, 0), 0, rad(1));
      expect(north.latitude, closeTo(1, 1e-9));
      expect(north.longitude, closeTo(0, 1e-9));
      final east = destinationPoint(const LatLng(0, 0), math.pi / 2, rad(1));
      expect(east.latitude, closeTo(0, 1e-9));
      expect(east.longitude, closeTo(1, 1e-9));
    });

    test('destinationPoint at lat 60 keeps geodesic distance', () {
      final d = destinationPoint(const LatLng(60, 0), 0, rad(5));
      expect(angleBetween(const LatLng(60, 0), d) * 180 / math.pi,
          closeTo(5, 1e-9));
    });

    test('centroid of a small ring is inside the ring', () {
      final c = sphericalCentroid(const [
        LatLng(0, 0),
        LatLng(0, 10),
        LatLng(10, 10),
        LatLng(10, 0),
      ]);
      expect(c.latitude, inInclusiveRange(0, 10));
      expect(c.longitude, inInclusiveRange(0, 10));
    });
  });
}

double _lng(double x, double y) => math.atan2(y, x) * 180 / math.pi;
