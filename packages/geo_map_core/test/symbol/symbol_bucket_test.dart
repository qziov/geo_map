import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

MvtFeature _feature(
  MvtGeomType type,
  List<List<Vec2>> geometry, {
  Map<String, Object?> properties = const {},
}) =>
    MvtFeature(type: type, properties: properties, geometry: geometry);

MvtLayer _layer(List<MvtFeature> features, {int extent = 100}) => MvtLayer(
      name: 'places',
      extent: extent,
      version: 2,
      features: features,
    );

void main() {
  group('buildMvtSymbolBucket', () {
    test('turns a point into a normalized anchor', () {
      final bucket = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(25, 75)],
        ], properties: {'name': 'A'}),
      ]));
      expect(bucket, hasLength(1));
      expect(bucket.single.anchor.x, closeTo(0.25, 1e-12));
      expect(bucket.single.anchor.y, closeTo(0.75, 1e-12));
      expect(bucket.single.properties['name'], 'A');
    });

    test('a multi-point geometry yields one symbol per point', () {
      // MapLibre lays out a MultiPoint as one instance per point, not one per
      // feature.
      final bucket = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(10, 10)],
          [const Vec2(20, 20)],
          [const Vec2(30, 30)],
        ]),
      ]));
      expect(bucket, hasLength(3));
      expect(bucket.map((s) => s.tilePriority).toSet(), {0});
    });

    test('lines and polygons are skipped', () {
      final bucket = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.lineString, [
          [const Vec2(0, 0), const Vec2(10, 10)],
        ]),
        _feature(MvtGeomType.polygon, [
          [const Vec2(0, 0), const Vec2(10, 0), const Vec2(10, 10)],
        ]),
      ]));
      expect(bucket, isEmpty);
    });

    test('tilePriority follows the feature index, skipped ones included', () {
      // A stable order matters: two labels that cannot both fit must not swap
      // places between frames.
      final bucket = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.lineString, [
          [const Vec2(0, 0), const Vec2(1, 1)],
        ]),
        _feature(MvtGeomType.point, [
          [const Vec2(5, 5)],
        ]),
        _feature(MvtGeomType.point, [
          [const Vec2(6, 6)],
        ]),
      ]));
      expect(bucket.map((s) => s.tilePriority), [1, 2]);
    });

    test('carries properties for text-field evaluation', () {
      final bucket = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(1, 1)],
        ], properties: {'name': '乌鲁木齐', 'rank': 2}),
      ]));
      expect(bucket.single.properties, {'name': '乌鲁木齐', 'rank': 2});
    });

    test('a zero extent gives nothing instead of dividing by zero', () {
      final bucket = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(1, 1)],
        ]),
      ], extent: 0));
      expect(bucket, isEmpty);
    });
  });

  group('symbol style properties', () {
    StyleLayer symbol(Map<String, Object?> json) => StyleSpec.parse({
          'version': 8,
          'layers': [
            {'id': 's', 'type': 'symbol', 'source': 'v', ...json},
          ],
        }).layers.first;

    test('parses as a layer but is not drawn yet', () {
      final layer = symbol({
        'layout': {'text-field': ['get', 'name']},
      });
      expect(layer.type, 'symbol');
      // The painters only handle fill/line, so advertising symbol support would
      // silently drop the layer instead of skipping it on purpose.
      expect(layer.isSupported, isFalse);
    });

    test('text layout defaults follow v8.json', () {
      final layer = symbol({});
      const ctx = ExpressionContext(zoom: 5);
      expect(layer.number('text-size', ctx), 16);
      expect(layer.valueOf('text-allow-overlap', ctx), isFalse);
      expect(layer.valueOf('text-ignore-placement', ctx), isFalse);
      expect(layer.string('symbol-placement', ctx), 'point');
    });

    test('text-field is data driven', () {
      final layer = symbol({
        'layout': {
          'text-field': ['get', 'name'],
        },
      });
      final ctx = ExpressionContext(
        zoom: 5,
        properties: const {'name': 'Benxi'},
      );
      expect(layer.valueOf('text-field', ctx), 'Benxi');
    });

    test('text colours live in paint', () {
      final layer = symbol({
        'paint': {'text-color': '#ff8800', 'text-halo-width': 2},
      });
      const ctx = ExpressionContext(zoom: 5);
      final color = layer.color('text-color', ctx)!;
      expect(color.r, 0xff);
      expect(color.g, 0x88);
      expect(layer.number('text-halo-width', ctx), 2);
    });
  });
}
