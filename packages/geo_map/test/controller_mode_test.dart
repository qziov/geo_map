// Regression tests for two camera defects that only showed up when a host
// integrated the engine (they were invisible in the example, which starts in 3D
// and never changes its zoom constraints).
//
// Runs under `flutter test` (the controller needs the vendored camera, so this
// cannot live in `geo_map_core` with the pure-Dart suite).

import 'package:flutter/painting.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoMapController', () {
    test('useGlobe: false is honoured by isGlobe', () {
      final controller = GeoMapController(useGlobe: false);
      addTearDown(controller.dispose);

      expect(controller.isGlobe, isFalse);
      expect(controller.delegate, isA<FlatProjectionDelegate>());
    });

    test('a flat controller can switch to the globe', () {
      // The defect: `_isGlobe` started `true` regardless of the constructor, so
      // `setMode(true)` returned early and the globe `TileLayer` drew with a
      // flat delegate — the map rendered at the wrong scale.
      final controller = GeoMapController(useGlobe: false);
      addTearDown(controller.dispose);

      controller.setMode(true);

      expect(controller.isGlobe, isTrue);
      expect(controller.delegate, isA<GlobeProjectionDelegate>());
    });

    test('applyConstraints actually applies', () {
      final controller = GeoMapController(
        useGlobe: false,
        initialZoom: 10,
        minZoom: 1,
        maxZoom: 18,
      );
      addTearDown(controller.dispose);
      expect(controller.zoom, 10);

      controller.applyConstraints(minZoom: 4, maxZoom: 6);

      // The defect: the method assigned its parameters to themselves, so the
      // fields kept 1/18 and the zoom was never clamped.
      expect(controller.minZoom, 4);
      expect(controller.maxZoom, 6);
      expect(controller.zoom, 6, reason: 'move() clamps into the new range');
    });

    test('setViewport notifies only on a real change', () {
      final controller = GeoMapController(useGlobe: false);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setViewport(const Size(400, 800));
      controller.setViewport(const Size(400, 800));
      controller.setViewport(const Size(400, 700));

      expect(notifications, 2);
      expect(controller.viewport, const Size(400, 700));
    });

    test('center and zoom survive a mode switch', () {
      final controller = GeoMapController(
        useGlobe: false,
        initialCenter: const LatLng(35.86, 104.19),
        initialZoom: 4,
      );
      addTearDown(controller.dispose);
      controller.setViewport(const Size(400, 800));

      controller.setMode(true);

      expect(controller.center.latitude, closeTo(35.86, 1e-9));
      expect(controller.center.longitude, closeTo(104.19, 1e-9));
      expect(controller.zoom, 4);
    });
  });
}
