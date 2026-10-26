import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses a FeatureCollection with a polygon and a line', () {
    final features = parseGeoJsonFeatures({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'id': 1,
          'properties': {'use': 'park'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [100, 30], [101, 30], [101, 31], [100, 31], [100, 30],
              ],
            ],
          },
        },
        {
          'type': 'Feature',
          'properties': {'name': 'road'},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [100, 30], [101, 31],
            ],
          },
        },
      ],
    });

    expect(features.length, 2);
    expect(features[0].id, '1');
    expect(features[0].properties['use'], 'park');
    expect(features[0].geometry, isA<PolygonGeometry>());
    final poly = features[0].geometry as PolygonGeometry;
    expect(poly.rings.length, 1);
    expect(poly.rings[0].first.longitude, 100);
    expect(poly.rings[0].first.latitude, 30);
    expect(features[1].geometry, isA<LineStringGeometry>());
  });

  test('accepts a single Feature and skips unsupported geometry', () {
    final single = parseGeoJsonFeatures({
      'type': 'Feature',
      'properties': {'k': 1},
      'geometry': {
        'type': 'Point',
        'coordinates': [100, 30],
      },
    });
    expect(single.length, 1);
    expect(single[0].geometry, isA<PointGeometry>());

    final skipped = parseGeoJsonFeatures({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {'type': 'GeometryCollection', 'geometries': <Object?>[]},
        },
      ],
    });
    expect(skipped, isEmpty);
  });
}
