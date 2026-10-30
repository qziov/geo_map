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
      ]), z: 0, x: 0, y: 0);
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
      ]), z: 0, x: 0, y: 0);
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
      ]), z: 0, x: 0, y: 0);
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
      ]), z: 0, x: 0, y: 0);
      expect(bucket.map((s) => s.tilePriority), [1, 2]);
    });

    test('carries properties for text-field evaluation', () {
      final bucket = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(1, 1)],
        ], properties: {'name': '乌鲁木齐', 'rank': 2}),
      ]), z: 0, x: 0, y: 0);
      expect(bucket.single.properties, {'name': '乌鲁木齐', 'rank': 2});
    });

    test('a zero extent gives nothing instead of dividing by zero', () {
      final bucket = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(1, 1)],
        ]),
      ], extent: 0), z: 0, x: 0, y: 0);
      expect(bucket, isEmpty);
    });
  });

  group('buildMvtLineSymbolBucket', () {
    test('samples one anchor per segment midpoint, rotated to the segment', () {
      final bucket = buildMvtLineSymbolBucket(_layer([
        _feature(MvtGeomType.lineString, [
          [const Vec2(0, 0), const Vec2(100, 100)],
        ]),
      ]), z: 0, x: 0, y: 0);
      expect(bucket, hasLength(1));
      // Midpoint of the single segment, normalized by the extent.
      expect(bucket.single.anchor.x, closeTo(0.5, 1e-12));
      expect(bucket.single.anchor.y, closeTo(0.5, 1e-12));
      // Tile space is y-down like the screen, so atan2 already yields a
      // screen-ready rotation (pi/4 for a 45-degree line).
      expect(bucket.single.angle, closeTo(0.7853981633974483, 1e-9));
      expect(bucket.single.placement, MvtSymbolPlacement.line);
    });

    test('a three-point line yields one symbol per segment', () {
      final bucket = buildMvtLineSymbolBucket(_layer([
        _feature(MvtGeomType.lineString, [
          [const Vec2(0, 0), const Vec2(50, 0), const Vec2(50, 50)],
        ]),
      ]), z: 0, x: 0, y: 0);
      expect(bucket, hasLength(2));
      expect(bucket.map((s) => s.placement).toSet(), {MvtSymbolPlacement.line});
    });

    test('points and polygons are skipped', () {
      final bucket = buildMvtLineSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(5, 5)],
        ]),
        _feature(MvtGeomType.polygon, [
          [const Vec2(0, 0), const Vec2(10, 0), const Vec2(10, 10)],
        ]),
      ]), z: 0, x: 0, y: 0);
      expect(bucket, isEmpty);
    });
  });

  group('cross-tile keys', () {
    test('a degenerate (0,0,0) tile has no world identity', () {
      final bucket = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(25, 75)],
        ]),
      ]), z: 0, x: 0, y: 0);
      expect(bucket.single.crossTileKey, isNull);
    });

    test('the same world point from two adjacent tiles shares one key', () {
      // Tile (1,0,0) ends where tile (1,1,0) begins, so a point on the shared
      // edge must collapse to one key and be drawn only once.
      final left = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(100, 50)],
        ]),
      ]), z: 1, x: 0, y: 0);
      final right = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(0, 50)],
        ]),
      ]), z: 1, x: 1, y: 0);
      expect(left.single.crossTileKey, isNotNull);
      expect(left.single.crossTileKey, right.single.crossTileKey);
    });

    test('different places get different keys', () {
      final a = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(10, 10)],
        ]),
      ]), z: 1, x: 0, y: 0);
      final b = buildMvtSymbolBucket(_layer([
        _feature(MvtGeomType.point, [
          [const Vec2(90, 90)],
        ]),
      ]), z: 1, x: 0, y: 0);
      expect(a.single.crossTileKey, isNot(b.single.crossTileKey));
    });
  });

  group('symbol style properties', () {
    StyleLayer symbol(Map<String, Object?> json) => StyleSpec.parse({
          'version': 8,
          'layers': [
            {'id': 's', 'type': 'symbol', 'source': 'v', ...json},
          ],
        }).layers.first;

    test('is a supported layer type now that the painter exists', () {
      final layer = symbol({
        'layout': {'text-field': ['get', 'name']},
      });
      expect(layer.type, 'symbol');
      expect(layer.isSupported, isTrue);
    });

    test('text layout defaults follow v8.json', () {
      final layer = symbol({});
      const ctx = ExpressionContext(zoom: 5);
      expect(layer.number('text-size', ctx), 16);
      expect(layer.valueOf('text-allow-overlap', ctx), isFalse);
      expect(layer.valueOf('text-ignore-placement', ctx), isFalse);
      expect(layer.string('symbol-placement', ctx), 'point');
    });

    test('M3 symbol properties follow v8.json defaults', () {
      final layer = symbol({});
      const ctx = ExpressionContext(zoom: 5);
      // Anchors: the box sits centred on the anchor until the style moves it.
      expect(layer.string('text-anchor', ctx), 'center');
      expect(layer.string('icon-anchor', ctx), 'center');
      // Rotation is in degrees and starts upright.
      expect(layer.number('text-rotate', ctx), 0);
      expect(layer.number('icon-rotate', ctx), 0);
      // Offsets arrive as `[x, y]` pairs.
      expect(layer.valueOf('text-offset', ctx), isA<List>());
      expect(layer.valueOf('icon-offset', ctx), isA<List>());
      // `icon-color` tints SDF sprites and defaults to opaque black.
      final tint = layer.color('icon-color', ctx);
      expect(tint, isNotNull);
      expect(tint!.r, 0);
      expect(tint.g, 0);
      expect(tint.b, 0);
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
