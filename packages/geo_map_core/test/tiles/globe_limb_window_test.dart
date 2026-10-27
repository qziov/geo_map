import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

/// Regression for the right-edge column disappearing at some globe zooms.
///
/// `TileSelector.visible` is the fast window path; `bruteForce` checks every
/// tile against the viewport. The window must always be a **superset** — a
/// tile that brute force says is visible may be culled later, but it must at
/// least enter the candidate set.
void main() {
  const projector = OrthographicProjector();
  const size = ViewportSize(1080, 611);

  group('globe window covers the limb', () {
    test('every brute-force visible tile is inside the window', () {
      // 3.75 was the zoom where the 8-point bounds undershot the east limb and
      // dropped columns 14/15/0; nearby zooms guard the analytic bound.
      for (final zoom in [3.70, 3.75, 3.88, 4.03, 4.30]) {
        final camera = CameraState(
          center: const LatLng(19.0, 91.3),
          zoom: zoom,
          size: size,
        );
        final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
        final margin = TileSelector.adaptiveMargin(camera, grid);

        final window = TileSelector.visible(
          projector: projector,
          camera: camera,
          grid: grid,
          margin: margin,
        ).toSet();
        final brute = TileSelector.bruteForce(
          projector: projector,
          camera: camera,
          grid: grid,
          margin: margin,
        );

        expect(
          window.containsAll(brute),
          isTrue,
          reason: 'z=$zoom window=${window.length} brute=${brute.length} '
              'missing=${brute.where((k) => !window.contains(k)).toList()}',
        );
      }
    });

    test('the analytic bound reaches the east limb at z3.75', () {
      final camera = CameraState(
        center: const LatLng(19.0, 91.3),
        zoom: 3.75,
        size: size,
      );
      final bounds = projector.approximateVisibleBounds(camera, 0);
      // Right limb is center + 90° for this zoom; the window must not stop
      // short of it.
      expect(bounds.east, greaterThan(91.3 + 80));
      expect(bounds.west, lessThan(91.3 - 80));
    });
  });
}
