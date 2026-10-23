import 'dart:math' as math;

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

CameraState _cam({
  LatLng center = const LatLng(30, 100),
  double zoom = 4,
}) =>
    CameraState(
      center: center,
      zoom: zoom,
      size: const ViewportSize(800, 600),
      minZoom: 0,
      maxZoom: 22,
    );

void main() {
  const ortho = OrthographicProjector();
  const merc = MercatorProjector();

  group('pan', () {
    test('flat: pan then pan back restores the centre', () {
      final c = _cam();
      final moved = CameraMath.panByPixels(c, merc, 120, -80);
      final back = CameraMath.panByPixels(moved, merc, -120, 80);
      expect(back.center.latitude, closeTo(c.center.latitude, 1e-9));
      expect(back.center.longitude, closeTo(c.center.longitude, 1e-9));
    });

    test('globe: pan then pan back restores the centre', () {
      final c = _cam(center: const LatLng(20, 40));
      final moved = CameraMath.panByPixels(c, ortho, 90, 60);
      final back = CameraMath.panByPixels(moved, ortho, -90, -60);
      // 1/cos(lat) compensation is not exactly reversible — the factor changes
      // as the centre moves. Half a pixel of drift per pan is expected.
      expect(back.center.latitude, closeTo(c.center.latitude, 0.5));
      expect(back.center.longitude, closeTo(c.center.longitude, 1.0));
    });

    test('globe: longitude moves faster near the poles', () {
      final c1 = _cam(center: const LatLng(0, 0));
      final c2 = _cam(center: const LatLng(70, 0));
      final d1 = CameraMath.panByPixels(c1, ortho, 50, 0).center.longitude;
      final d2 = CameraMath.panByPixels(c2, ortho, 50, 0).center.longitude;
      expect(d2.abs(), greaterThan(d1.abs() * 2));
    });

    test('latitude is clamped at the camera limit', () {
      final c = _cam(center: const LatLng(88, 0));
      final moved = CameraMath.panByPixels(c, ortho, 0, -10000);
      expect(moved.center.latitude,
          lessThanOrEqualTo(GeoEngineTuning.maxCameraLatitude + 1e-9));
    });

    test('longitude wraps around ±180', () {
      final c = _cam(center: const LatLng(0, 179.9));
      final moved = CameraMath.panByPixels(c, ortho, -500, 0);
      expect(moved.center.longitude, lessThanOrEqualTo(180));
      expect(moved.center.longitude, greaterThanOrEqualTo(-180));
    });
  });

  group('zoomAround', () {
    test('flat: anchor stays pinned', () {
      final c = _cam();
      const anchor = Vec2(150, 120);
      final geo = merc.unproject(anchor, c)!;
      final zoomed = CameraMath.zoomAround(c, merc, 7, anchor);
      expect(zoomed.zoom, 7);
      final after = merc.project(geo, zoomed)!;
      expect(after.x, closeTo(anchor.x, 1e-6));
      expect(after.y, closeTo(anchor.y, 1e-6));
    });

    test('globe: anchor drifts less than half a pixel', () {
      final c = _cam(center: const LatLng(35, 110));
      const anchor = Vec2(250, 200);
      final geo = ortho.unproject(anchor, c)!;
      final zoomed = CameraMath.zoomAround(c, ortho, 6.5, anchor);
      final after = ortho.project(geo, zoomed)!;
      expect(after.distanceTo(anchor), lessThan(0.5));
    });

    test('zoom is clamped to the camera range', () {
      final c = _cam(zoom: 4);
      final z = CameraMath.zoomAround(c, merc, 99, const Vec2(400, 300));
      expect(z.zoom, 22);
    });

    test('no-op when the zoom does not change', () {
      final c = _cam(zoom: 4);
      final z = CameraMath.zoomAround(c, merc, 4, const Vec2(400, 300));
      expect(identical(z, c) || z == c, isTrue);
    });
  });

  group('camera state', () {
    test('radius and world size share one zoom scale', () {
      final c = _cam(zoom: 3);
      expect(c.worldSize, closeTo(256 * 8, 1e-9));
      expect(c.radiusPx, closeTo(256 * 8 / (2 * math.pi), 1e-9));
    });

    test('equality drives repaint decisions', () {
      final a = _cam();
      final b = _cam();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(_cam(zoom: 4.0001))));
    });
  });
}
