import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:test/test.dart';

/// A deliberately simple projection: 10 px per degree, so distances in the
/// tests are easy to reason about. Longitude grows to the right, latitude
/// grows upwards (screen y is flipped).
Vec2 _project(LatLng point) => Vec2(point.longitude * 10, -point.latitude * 10);

QueryFeature _point(String id, double lat, double lng, {String source = ''}) =>
    QueryFeature(
      id: id,
      geometry: PointGeometry(LatLng(lat, lng)),
      sourceId: source,
    );

final _square = PolygonGeometry(<List<LatLng>>[
  <LatLng>[
    const LatLng(0, 0),
    const LatLng(0, 10),
    const LatLng(10, 10),
    const LatLng(10, 0),
    const LatLng(0, 0),
  ],
]);

void main() {
  group('planFeatureQuery — point features', () {
    test('a feature under the tap hits', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[_point('a', 0, 0)],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
      );
      expect(hits.length, equals(1));
      expect(hits.first.feature.id, equals('a'));
      expect(hits.first.distancePx, equals(0));
    });

    test('a feature beyond the radius misses', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[_point('a', 0, 3)],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
      );
      expect(hits, isEmpty);
    });

    test('the radius is inclusive', () {
      // 2.4° → 24 px, exactly the default radius.
      final hits = planFeatureQuery(
        features: <QueryFeature>[_point('a', 0, 2.4)],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
      );
      expect(hits.length, equals(1));
      expect(hits.first.distancePx, closeTo(24, 1e-9));
    });

    test('a feature that cannot be projected is skipped', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[_point('a', 0, 0)],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: (LatLng _) => null,
      );
      expect(hits, isEmpty);
    });

    test('a null tap screen disables point picking', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[_point('a', 0, 0)],
        tap: const LatLng(0, 0),
        tapScreen: null,
        project: _project,
      );
      expect(hits, isEmpty);
    });

    test('a per-feature radius overrides the query default', () {
      final far = QueryFeature(
        id: 'a',
        geometry: PointGeometry(const LatLng(0, 3)),
        pointRadiusPx: 40,
      );
      final hits = planFeatureQuery(
        features: <QueryFeature>[far],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
      );
      expect(hits.length, equals(1));
    });
  });

  group('planFeatureQuery — ordering', () {
    test('points come back nearest first', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[
          _point('far', 0, 0.5),
          _point('near', 0, 0.1),
          _point('mid', 0, 0.3),
        ],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
      );
      expect(
        hits.map((h) => h.feature.id).toList(),
        equals(<String>['near', 'mid', 'far']),
      );
    });

    test('an equidistant tie goes to the later registration', () {
      // Both are 10 px away; the later one is drawn on top.
      final hits = planFeatureQuery(
        features: <QueryFeature>[
          _point('left', 0, -1),
          _point('right', 0, 1),
        ],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
      );
      expect(
        hits.map((h) => h.feature.id).toList(),
        equals(<String>['right', 'left']),
      );
    });

    test('sources are grouped in registration order', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[
          _point('a1', 0, 0.1, source: 'a'),
          _point('b1', 0, 0.2, source: 'b'),
          _point('a2', 0, 0.3, source: 'a'),
        ],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
      );
      expect(
        hits.map((h) => h.feature.id).toList(),
        equals(<String>['a1', 'a2', 'b1']),
      );
    });

    test('areas come after the points of the same source', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[
          QueryFeature(
            id: 'area',
            geometry: _square,
            sourceId: 's',
          ),
          _point('dot', 5, 5.1, source: 's'),
        ],
        tap: const LatLng(5, 5),
        tapScreen: _project(const LatLng(5, 5)),
        project: _project,
      );
      expect(
        hits.map((h) => h.feature.id).toList(),
        equals(<String>['dot', 'area']),
      );
    });

    test('limit truncates after sorting', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[
          _point('far', 0, 0.5),
          _point('near', 0, 0.1),
          _point('mid', 0, 0.3),
        ],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
        limit: 2,
      );
      expect(
        hits.map((h) => h.feature.id).toList(),
        equals(<String>['near', 'mid']),
      );
    });
  });

  group('planFeatureQuery — filtering', () {
    test('an invisible feature is skipped', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[
          const QueryFeature(
            id: 'a',
            geometry: PointGeometry(LatLng(0, 0)),
            visible: false,
          ),
        ],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
      );
      expect(hits, isEmpty);
    });

    test('sourceIds restricts the query to those sources', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[
          _point('a', 0, 0.1, source: 'a'),
          _point('b', 0, 0.1, source: 'b'),
        ],
        tap: const LatLng(0, 0),
        tapScreen: const Vec2(0, 0),
        project: _project,
        sourceIds: <String>{'b'},
      );
      expect(hits.length, equals(1));
      expect(hits.first.feature.id, equals('b'));
    });

    test('geometries restricts the query to those kinds', () {
      // Both the dot and the area contain the tap, so only the kind filter
      // decides what comes back.
      final features = <QueryFeature>[
        _point('dot', 5, 5),
        QueryFeature(id: 'area', geometry: _square),
      ];
      final tap = const LatLng(5, 5);
      final screen = _project(tap);

      final onlyPolygons = planFeatureQuery(
        features: features,
        tap: tap,
        tapScreen: screen,
        project: _project,
        geometries: <GeoGeometryKind>{GeoGeometryKind.polygon},
      );
      expect(
        onlyPolygons.map((h) => h.feature.id).toList(),
        equals(<String>['area']),
      );

      final onlyPoints = planFeatureQuery(
        features: features,
        tap: tap,
        tapScreen: screen,
        project: _project,
        geometries: <GeoGeometryKind>{GeoGeometryKind.point},
      );
      expect(
        onlyPoints.map((h) => h.feature.id).toList(),
        equals(<String>['dot']),
      );
    });
  });

  group('planFeatureQuery — area features', () {
    test('a polygon containing the tap hits', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[QueryFeature(id: 'area', geometry: _square)],
        tap: const LatLng(5, 5),
        tapScreen: _project(const LatLng(5, 5)),
        project: _project,
      );
      expect(hits.length, equals(1));
      expect(hits.first.distancePx, isNull);
    });

    test('a polygon not containing the tap misses', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[QueryFeature(id: 'area', geometry: _square)],
        tap: const LatLng(20, 5),
        tapScreen: _project(const LatLng(20, 5)),
        project: _project,
      );
      expect(hits, isEmpty);
    });

    test('overlapping polygons both hit', () {
      final other = PolygonGeometry(<List<LatLng>>[
        <LatLng>[
          const LatLng(0, 5),
          const LatLng(0, 15),
          const LatLng(10, 15),
          const LatLng(10, 5),
          const LatLng(0, 5),
        ],
      ]);
      final hits = planFeatureQuery(
        features: <QueryFeature>[
          QueryFeature(id: 'a', geometry: _square),
          QueryFeature(id: 'b', geometry: other),
        ],
        tap: const LatLng(5, 7),
        tapScreen: _project(const LatLng(5, 7)),
        project: _project,
      );
      expect(
        hits.map((h) => h.feature.id).toList(),
        equals(<String>['a', 'b']),
      );
    });

    test('areas are picked even without a tap screen', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[QueryFeature(id: 'area', geometry: _square)],
        tap: const LatLng(5, 5),
        tapScreen: null,
        project: _project,
      );
      expect(hits.length, equals(1));
    });
  });

  group('planFeatureQuery — lines are not picked', () {
    test('a line feature never hits', () {
      final hits = planFeatureQuery(
        features: <QueryFeature>[
          QueryFeature(
            id: 'line',
            geometry: const LineStringGeometry(<LatLng>[
              LatLng(0, 0),
              LatLng(0, 10),
            ]),
          ),
        ],
        tap: const LatLng(0, 5),
        tapScreen: _project(const LatLng(0, 5)),
        project: _project,
      );
      expect(hits, isEmpty);
    });
  });

  group('geometryKindOf', () {
    test('maps every geometry to its kind', () {
      expect(
        geometryKindOf(const PointGeometry(LatLng(0, 0))),
        equals(GeoGeometryKind.point),
      );
      expect(
        geometryKindOf(const LineStringGeometry(<LatLng>[LatLng(0, 0)])),
        equals(GeoGeometryKind.line),
      );
      expect(
        geometryKindOf(const MultiLineStringGeometry(<List<LatLng>>[])),
        equals(GeoGeometryKind.line),
      );
      expect(
        geometryKindOf(_square),
        equals(GeoGeometryKind.polygon),
      );
      expect(
        geometryKindOf(const MultiPolygonGeometry(<List<List<LatLng>>>[])),
        equals(GeoGeometryKind.polygon),
      );
    });
  });
}
