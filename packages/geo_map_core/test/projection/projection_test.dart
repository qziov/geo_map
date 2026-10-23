import 'dart:math' as math;

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

CameraState cam({
  LatLng center = const LatLng(20, 100),
  double zoom = 4,
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
  group('orthographic projector', () {
    const projector = OrthographicProjector();

    test('camera centre maps to viewport centre', () {
      final c = cam();
      final p = projector.project(c.center, c)!;
      expect(p.x, closeTo(400, 1e-9));
      expect(p.y, closeTo(300, 1e-9));
      expect(projector.depthOf(c.center, c), closeTo(1.0, 1e-12));
    });

    test('round-trips geodetic points inside the disc', () {
      final c = cam(center: const LatLng(35, 110));
      for (var i = 0; i < 120; i++) {
        final lat = 35 + (i % 12) * 2.0 - 11;
        final lng = 110 + (i ~/ 12) * 2.0 - 10;
        final geo = LatLng(lat, lng);
        final screen = projector.project(geo, c);
        if (screen == null) continue;
        final back = projector.unproject(screen, c);
        expect(back, isNotNull);
        expect(angleBetween(geo, back!) * 180 / math.pi, lessThan(1e-5));
      }
    });

    test('returns null behind the horizon', () {
      final c = cam(center: const LatLng(30, 90));
      expect(projector.project(const LatLng(-40, -90), c), isNull);
      expect(projector.depthOf(const LatLng(-40, -90), c), lessThan(0));
    });

    test('unproject is null outside the disc', () {
      final c = cam(zoom: 2);
      final r = c.radiusPx;
      expect(projector.unproject(Vec2(400 + r * 1.5, 300), c), isNull);
      expect(projector.unproject(Vec2(400 + r * 0.5, 300), c), isNotNull);
    });

    test('clip circle matches the disc', () {
      final c = cam(zoom: 3);
      final clip = projector.clipCircle(c)!;
      expect(clip.radius, closeTo(c.worldSize / (2 * math.pi), 1e-9));
      expect(clip.center.x, 400);
    });

    test('is stateless across cameras', () {
      final a = cam(center: const LatLng(10, 10), zoom: 3);
      final b = cam(center: const LatLng(-40, 170), zoom: 6);
      final ga = projector.project(const LatLng(12, 14), a);
      final gb1 = projector.project(const LatLng(-38, 168), b);
      final ga2 = projector.project(const LatLng(12, 14), a);
      expect(ga!.x, ga2!.x);
      expect(ga.y, ga2.y);
      expect(gb1, isNotNull);
    });

    test('polar camera stays finite', () {
      final c = cam(center: const LatLng(89.999, 0), zoom: 5);
      final p = projector.project(const LatLng(89.999, 0), c)!;
      expect(p.x.isFinite && p.y.isFinite, isTrue);
      expect(p.x.abs() <= 1e7, isTrue);
    });

    test('densify step shrinks as the sphere grows', () {
      final near = projector.densifyStepRad(cam(zoom: 3));
      final far = projector.densifyStepRad(cam(zoom: 8));
      expect(far, lessThan(near));
      expect(far, greaterThan(0));
      // chord error bound: R·(1-cos(step/2)) ≤ tuned pixel error
      final c = cam(zoom: 8);
      final err = c.radiusPx * (1 - math.cos(far / 2));
      expect(err, lessThanOrEqualTo(GeoEngineTuning.densifyPixelError * 1.001));
    });
  });

  group('mercator projector', () {
    const projector = MercatorProjector();

    test('camera centre maps to viewport centre', () {
      final c = cam();
      final p = projector.project(c.center, c)!;
      expect(p.x, closeTo(400, 1e-9));
      expect(p.y, closeTo(300, 1e-9));
    });

    test('round-trips inside the world', () {
      final c = cam(center: const LatLng(0, 0), zoom: 5);
      for (final geo in const [
        LatLng(0, 0),
        LatLng(45, 90),
        LatLng(-60, -120),
        LatLng(80, 10),
      ]) {
        final s = projector.project(geo, c)!;
        final back = projector.unproject(s, c)!;
        expect(back.latitude, closeTo(geo.latitude, 1e-6));
        expect(back.longitude, closeTo(geo.longitude, 1e-6));
      }
    });

    test('clamps latitude at the mercator limit', () {
      final c = cam(center: const LatLng(0, 0), zoom: 3);
      final top = projector.project(LatLng(90, 0), c)!;
      final lim = projector.project(LatLng(mercatorMaxLatitude, 0), c)!;
      expect(top.y, closeTo(lim.y, 1e-9));
    });

    test('depth is constant and there is no circular clip', () {
      final c = cam();
      expect(projector.depthOf(const LatLng(0, 0), c), 1.0);
      expect(projector.clipCircle(c), isNull);
      expect(projector.densifyStepRad(c), 0);
    });
  });

  group('limit consistency (globe ↔ mercator)', () {
    const ortho = OrthographicProjector();
    const merc = MercatorProjector();

    test('identical first order at the equator', () {
      final c1 = cam(center: const LatLng(0, 0), zoom: 5);
      final c2 = cam(center: const LatLng(0, 0), zoom: 5);
      const theta = 1e-4;
      final a = ortho.project(const LatLng(0, theta * rad2deg), c1)!;
      final b = merc.project(const LatLng(0, theta * rad2deg), c2)!;
      final dOrtho = a.x - 400;
      final dMerc = b.x - 400;
      expect((dOrtho - dMerc).abs() / dMerc, lessThan(1e-6));
    });

    test('longitude scale ratio is cos(lat), latitude ratio is 1/cos²', () {
      final c1 = cam(center: const LatLng(60, 0), zoom: 6);
      final c2 = cam(center: const LatLng(60, 0), zoom: 6);
      const theta = 1e-4;

      final geoLng = LatLng(60, theta * rad2deg);
      final dOrthoLng = ortho.project(geoLng, c1)!.x - 400;
      final dMercLng = merc.project(geoLng, c2)!.x - 400;
      expect(dOrthoLng / dMercLng, closeTo(math.cos(60 * math.pi / 180), 1e-6));

      final geoLat = LatLng(60 + theta * rad2deg, 0);
      final dOrthoLat = ortho.project(geoLat, c1)!.y - 300;
      final dMercLat = merc.project(geoLat, c2)!.y - 300;
      // Both axes scale by 1/cos(lat): Mercator is conformal, the globe
      // compresses both axes equally.
      final cosLat = math.cos(60 * math.pi / 180);
      expect(dMercLat.abs() / dOrthoLat.abs(), closeTo(1 / cosLat, 1e-2));
    });

    test('orthographic converges to affine as theta → 0', () {
      final c = cam(center: const LatLng(0, 20), zoom: 6);
      final r = c.radiusPx;
      var previous = double.infinity;
      for (final theta in [1e-1, 1e-2, 1e-3, 1e-4]) {
        final p = ortho.project(LatLng(0, 20 + theta * rad2deg), c)!;
        final d = p.x - 400;
        final rel = ((d / r) - theta).abs() / theta;
        expect(rel, lessThanOrEqualTo(theta * theta / 6 * 1.05 + 1e-12));
        expect(rel, lessThan(previous));
        previous = rel;
      }
    });
  });
}
