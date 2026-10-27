import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('SpriteIndex', () {
    test('parses rects and density', () {
      final index = SpriteIndex.parse({
        'cafe': {'x': 0, 'y': 0, 'width': 32, 'height': 24, 'pixelRatio': 2},
        'park': {'x': 32, 'y': 0, 'width': 20, 'height': 20},
      });
      expect(index.length, 2);

      final cafe = index['cafe']!;
      expect(cafe.x, 0);
      expect(cafe.width, 32);
      // Drawn size is sprite pixels over density, so a @2x icon draws at half.
      expect(cafe.displayWidth, 16);
      expect(cafe.displayHeight, 12);

      final park = index['park']!;
      expect(park.pixelRatio, 1, reason: 'missing pixelRatio defaults to 1');
      expect(park.displayWidth, 20);
    });

    test('missing icon is null, not a throw', () {
      final index = SpriteIndex.parse({
        'a': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
      });
      expect(index['nope'], isNull);
    });

    test('malformed entries are skipped, the rest survive', () {
      final index = SpriteIndex.parse({
        'good': {'x': 1, 'y': 2, 'width': 3, 'height': 4},
        'no-size': {'x': 1, 'y': 2},
        'not-a-map': 42,
      });
      expect(index.length, 1);
      expect(index['good'], isNotNull);
    });

    test('non-map json yields an empty index', () {
      expect(SpriteIndex.parse(null).length, 0);
      expect(SpriteIndex.parse([1, 2, 3]).length, 0);
    });

    test('sdf flag is carried', () {
      final index = SpriteIndex.parse({
        'marker': {'x': 0, 'y': 0, 'width': 8, 'height': 8, 'sdf': true},
      });
      expect(index['marker']!.sdf, isTrue);
    });

    test('a zero pixelRatio does not divide by zero', () {
      final index = SpriteIndex.parse({
        'bad': {'x': 0, 'y': 0, 'width': 8, 'height': 8, 'pixelRatio': 0},
      });
      expect(index['bad']!.displayWidth, 8);
    });
  });
}
