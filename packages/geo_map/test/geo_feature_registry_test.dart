import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

/// A controller over a flat map, sized so the projection is meaningful.
GeoMapController _flatController({
  LatLng center = const LatLng(0, 0),
  double zoom = 4,
}) {
  final controller = GeoMapController(
    useGlobe: false,
    initialCenter: center,
    initialZoom: zoom,
    minZoom: 1,
    maxZoom: 18,
  );
  controller.setViewport(const Size(800, 600));
  return controller;
}

GeoJsonFeature _dot(String id, double lat, double lng) => GeoJsonFeature(
      id: id,
      geometry: PointGeometry(LatLng(lat, lng)),
    );

GeoJsonFeature _box(String id, {double south = -5, double north = 5,
    double west = -5, double east = 5}) =>
    GeoJsonFeature(
      id: id,
      geometry: PolygonGeometry(<List<LatLng>>[
        <LatLng>[
          LatLng(south, west),
          LatLng(south, east),
          LatLng(north, east),
          LatLng(north, west),
          LatLng(south, west),
        ],
      ]),
    );

void main() {
  group('GeoFeatureRegistry — point features', () {
    test('a feature under the tap is picked', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[_dot('a', 0, 0)]);

      final hits = registry.queryFeatures(
        const LatLng(0, 0),
        controller: controller,
      );
      expect(hits.length, equals(1));
      expect(hits.first.feature.id, equals('a'));
      expect(hits.first.sourceId, equals('dots'));
      expect(hits.first.distancePx, closeTo(0, 1e-6));
    });

    test('a feature beyond the pick radius is not picked', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[_dot('a', 0, 10)]);

      // 10° of longitude at zoom 4 is ~114 px — far outside the 24 px radius.
      final hits = registry.queryFeatures(
        const LatLng(0, 0),
        controller: controller,
      );
      expect(hits, isEmpty);
    });

    test('the pick radius is honoured', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[_dot('a', 0, 2.1)]);

      // 2.1° ≈ 23.9 px — inside the 24 px radius.
      expect(
        registry.queryFeatures(const LatLng(0, 0), controller: controller),
        hasLength(1),
      );
    });

    test('a source can override the pick radius', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource(
          'dots',
          <GeoJsonFeature>[_dot('a', 0, 5)],
          pointRadiusPx: 200,
        );

      expect(
        registry.queryFeatures(const LatLng(0, 0), controller: controller),
        hasLength(1),
      );
    });

    test('the nearest feature comes first', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[
          _dot('far', 0, 1.0),
          _dot('near', 0, 0.5),
        ]);

      final hits = registry.queryFeatures(
        const LatLng(0, 0),
        controller: controller,
      );
      expect(
        hits.map((h) => h.feature.id).toList(),
        equals(<String>['near', 'far']),
      );
    });
  });

  group('GeoFeatureRegistry — the globe', () {
    test('a feature on the far side of the globe is not picked', () {
      final controller = GeoMapController(
        useGlobe: true,
        initialCenter: const LatLng(0, 0),
        initialZoom: 3,
        minZoom: 1,
        maxZoom: 18,
      );
      controller.setViewport(const Size(800, 600));
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[_dot('back', 0, 180)]);

      // The globe's `project` returns the (-1e6, -1e6) sentinel for the far
      // side; `isVisible` would still say "visible" down to z > -0.03, so the
      // sentinel has to be detected explicitly.
      final hits = registry.queryFeatures(
        const LatLng(0, 0),
        controller: controller,
      );
      expect(hits, isEmpty);
    });

    test('a feature on the near side is picked', () {
      final controller = GeoMapController(
        useGlobe: true,
        initialCenter: const LatLng(0, 0),
        initialZoom: 3,
        minZoom: 1,
        maxZoom: 18,
      );
      controller.setViewport(const Size(800, 600));
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[_dot('front', 0, 1)]);

      final hits = registry.queryFeatures(
        const LatLng(0, 1),
        controller: controller,
      );
      expect(hits.length, equals(1));
    });
  });

  group('GeoFeatureRegistry — the flat antimeridian', () {
    test('a feature across the seam is still reachable', () {
      // The camera sits just west of the seam and the feature just east of
      // it. Plain `project` does not wrap the longitude, so it would place
      // the feature a whole world away (~4073 px) and the tap could never
      // reach it; `projectForVector` folds it onto the nearest world copy.
      final controller = _flatController(center: const LatLng(0, -179));
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[_dot('east', 0, 179)]);

      final hits = registry.queryFeatures(
        const LatLng(0, 179),
        controller: controller,
      );
      expect(hits.length, equals(1));
      expect(hits.first.feature.id, equals('east'));

      // The unwrapped projection really is ~22 px away, not a world away.
      expect(hits.first.distancePx!, lessThan(24));
    });
  });

  group('GeoFeatureRegistry — area features', () {
    test('a polygon containing the tap is picked', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('areas', <GeoJsonFeature>[_box('a')]);

      final hits = registry.queryFeatures(
        const LatLng(0, 0),
        controller: controller,
      );
      expect(hits.length, equals(1));
      expect(hits.first.feature.id, equals('a'));
      // Areas are picked geographically, so there is no pixel distance.
      expect(hits.first.distancePx, isNull);
    });

    test('a polygon not containing the tap is not picked', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('areas', <GeoJsonFeature>[_box('a')]);

      final hits = registry.queryFeatures(
        const LatLng(0, 30),
        controller: controller,
      );
      expect(hits, isEmpty);
    });

    test('overlapping polygons are both picked', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('areas', <GeoJsonFeature>[
          _box('a'),
          _box('b', west: -2, east: 8),
        ]);

      final hits = registry.queryFeatures(
        const LatLng(0, 0),
        controller: controller,
      );
      expect(
        hits.map((h) => h.feature.id).toList(),
        equals(<String>['a', 'b']),
      );
    });
  });

  group('GeoFeatureRegistry — filtering', () {
    test('an invisible source is not picked', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[_dot('a', 0, 0)],
            visible: false);

      expect(
        registry.queryFeatures(const LatLng(0, 0), controller: controller),
        isEmpty,
      );
    });

    test('sourceIds narrows the query', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('a', <GeoJsonFeature>[_dot('a', 0, 0)])
        ..setSource('b', <GeoJsonFeature>[_dot('b', 0, 0)]);

      final hits = registry.queryFeatures(
        const LatLng(0, 0),
        controller: controller,
        sourceIds: <String>{'b'},
      );
      expect(hits.length, equals(1));
      expect(hits.first.sourceId, equals('b'));
    });

    test('geometries narrows the query', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('mixed', <GeoJsonFeature>[_dot('a', 0, 0), _box('b')]);

      final hits = registry.queryFeatures(
        const LatLng(0, 0),
        controller: controller,
        geometries: <GeoGeometryKind>{GeoGeometryKind.polygon},
      );
      expect(
        hits.map((h) => h.feature.id).toList(),
        equals(<String>['b']),
      );
    });

    test('a removed source is no longer picked', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[_dot('a', 0, 0)]);
      expect(registry.containsSource('dots'), isTrue);
      expect(registry.sourceIds, equals(<String>['dots']));

      registry.removeSource('dots');
      expect(registry.containsSource('dots'), isFalse);
      expect(
        registry.queryFeatures(const LatLng(0, 0), controller: controller),
        isEmpty,
      );
    });

    test('limit truncates the result', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[
          _dot('a', 0, 0.1),
          _dot('b', 0, 0.2),
          _dot('c', 0, 0.3),
        ]);

      final hits = registry.queryFeatures(
        const LatLng(0, 0),
        controller: controller,
        limit: 2,
      );
      expect(hits.length, equals(2));
    });
  });

  group('GeoFeatureRegistry — the hit carries the feature back', () {
    test('the feature id and properties survive the round trip', () {
      final controller = _flatController();
      addTearDown(controller.dispose);

      final registry = GeoFeatureRegistry()
        ..setSource('dots', <GeoJsonFeature>[
          const GeoJsonFeature(
            id: 'ZBAA',
            geometry: PointGeometry(LatLng(40, 116)),
            properties: <String, Object?>{'code': 'ZBAA'},
          ),
        ]);

      final hits = registry.queryFeatures(
        const LatLng(40, 116),
        controller: controller,
      );
      expect(hits.length, equals(1));
      expect(hits.first.feature.id, equals('ZBAA'));
      expect(hits.first.feature.properties['code'], equals('ZBAA'));
    });
  });
}
