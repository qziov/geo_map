import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

CameraState _camera() => CameraState(
      center: const LatLng(0, 0),
      zoom: 4,
      size: const ViewportSize(800, 800),
    );

void main() {
  group('clipRingToHorizon', () {
    test('a fully visible ring passes through unchanged', () {
      final ring = [
        const LatLng(-10, -10),
        const LatLng(-10, 10),
        const LatLng(10, 10),
        const LatLng(10, -10),
      ];
      final clipped = clipRingToHorizon(ring, _camera())!;

      expect(clipped.fill, hasLength(ring.length));
      expect(clipped.strokeRuns, hasLength(1));
      expect(clipped.strokeRuns.single, hasLength(ring.length));
    });

    test('a ring crossing the horizon closes along the limb', () {
      // Three corners are in front, the lon=100° corner is behind the horizon.
      final ring = densifyGreatCircle(
        [
          const LatLng(0, -60),
          const LatLng(0, 100),
          const LatLng(60, 100),
          const LatLng(60, -60),
        ],
        stepRad: 5 * 3.141592653589793 / 180,
        closed: true,
      );
      final camera = _camera();
      final clipped = clipRingToHorizon(ring, camera)!;

      expect(clipped.fill.length, greaterThan(ring.length));
      expect(clipped.strokeRuns, isNotEmpty);

      // Every fill point sits on or inside the disc.
      final center = camera.size.center;
      for (final p in clipped.fill) {
        final d = (p.x - center.x) * (p.x - center.x) +
            (p.y - center.y) * (p.y - center.y);
        expect(d, lessThanOrEqualTo(camera.radiusPx * camera.radiusPx + 1e-6));
      }

      // The limb arc contributed points exactly on the silhouette.
      final onLimb = clipped.fill.where((p) {
        final d = (p.x - center.x) * (p.x - center.x) +
            (p.y - center.y) * (p.y - center.y);
        return (d - camera.radiusPx * camera.radiusPx).abs() < 1e-3;
      });
      expect(onLimb.length, greaterThan(10));
    });

    test('a ring entirely behind the horizon is dropped', () {
      final ring = [
        const LatLng(-20, 170),
        const LatLng(20, 170),
        const LatLng(20, 179),
        const LatLng(-20, 179),
      ];
      expect(clipRingToHorizon(ring, _camera()), isNull);
    });

    test('degenerate inputs are rejected', () {
      expect(clipRingToHorizon(const [], _camera()), isNull);
      expect(
        clipRingToHorizon(
          [const LatLng(0, 0), const LatLng(1, 1)],
          _camera(),
        ),
        isNull,
      );
    });
  });
}
