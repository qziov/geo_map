import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:test/test.dart';

void main() {
  group('unwrapLongitudes', () {
    test('crosses the antimeridian with a short step', () {
      final r = unwrapLongitudes(<double>[179.9, -179.9]);
      expect(r[0], equals(179.9));
      expect(r[1], closeTo(180.1, 1e-9));
    });

    test('leaves a normal sequence unchanged', () {
      expect(unwrapLongitudes(<double>[10, 20, 30]), equals(<double>[10, 20, 30]));
    });

    test('empty input', () {
      expect(unwrapLongitudes(const <double>[]), isEmpty);
    });
  });

  group('splitRingAtSeam', () {
    test('splits a ring crossing ±180 into two pieces', () {
      final ring = <LatLng>[
        const LatLng(10, 170),
        const LatLng(10, -170),
        const LatLng(-10, -170),
        const LatLng(-10, 170),
        const LatLng(10, 170),
      ];
      final pieces = splitRingAtSeam(ring, 180);
      expect(pieces.length, equals(2));
      for (final p in pieces) {
        expect(p.length, greaterThanOrEqualTo(3));
      }
    });

    test('returns the ring unchanged when the seam is outside it', () {
      final ring = <LatLng>[
        const LatLng(0, 10),
        const LatLng(0, 20),
        const LatLng(10, 20),
        const LatLng(0, 10),
      ];
      final pieces = splitRingAtSeam(ring, 180);
      expect(pieces.length, equals(1));
      expect(pieces.first, equals(ring));
    });
  });
}
