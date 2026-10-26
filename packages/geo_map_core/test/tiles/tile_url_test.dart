import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('TileUrlBuilder address', () {
    test('z/x/y', () {
      final b = TileUrlBuilder(templates: 'https://t/{z}/{x}/{y}.png');
      expect(b.urlFor(3, 5, 2), 'https://t/3/5/2.png');
    });

    test('WMTS spellings', () {
      final b = TileUrlBuilder(
          templates: 'https://t/{TileMatrix}/{TileCol}/{TileRow}.jpg');
      expect(b.urlFor(4, 1, 7), 'https://t/4/1/7.jpg');
    });

    test('tms flips the row', () {
      final b = TileUrlBuilder(
        templates: 'https://t/{z}/{x}/{y}.png',
        rowOrder: TileRowOrder.tmsBottomUp,
      );
      expect(b.urlFor(1, 0, 0), 'https://t/1/0/1.png');
      expect(b.urlFor(1, 0, 1), 'https://t/1/0/0.png');
    });
  });

  group('TileUrlBuilder placeholders', () {
    test('prefix cycles through subdomains', () {
      final b = TileUrlBuilder(
        templates: 'https://{prefix}.t/{z}/{x}/{y}.png',
        subdomains: const ['a', 'b', 'c'],
      );
      expect(b.urlFor(0, 0, 0), 'https://a.t/0/0/0.png');
      expect(b.urlFor(0, 1, 0), 'https://b.t/0/1/0.png');
      expect(b.urlFor(0, 2, 0), 'https://c.t/0/2/0.png');
      expect(b.urlFor(0, 1, 2), 'https://a.t/0/1/2.png');
    });

    test('ratio renders @Nx only above 1', () {
      final b2 = TileUrlBuilder(
          templates: 'https://t/{z}/{x}/{y}{ratio}.png', tileRatio: 2);
      expect(b2.urlFor(0, 0, 0), 'https://t/0/0/0@2x.png');
      final b1 = TileUrlBuilder(templates: 'https://t/{z}/{x}/{y}{ratio}.png');
      expect(b1.urlFor(0, 0, 0), 'https://t/0/0/0.png');
    });

    test('multi-template rotation', () {
      final b = TileUrlBuilder(
          templates: ['https://a/{z}/{x}/{y}', 'https://b/{z}/{x}/{y}']);
      expect(b.urlFor(0, 0, 0), 'https://a/0/0/0');
      expect(b.urlFor(0, 1, 0), 'https://b/0/1/0');
    });

    test('quadkey', () {
      final b = TileUrlBuilder(templates: '{quadkey}');
      expect(b.urlFor(1, 0, 0), '0');
      expect(b.urlFor(1, 1, 0), '1');
      expect(b.urlFor(1, 0, 1), '2');
      expect(b.urlFor(1, 1, 1), '3');
      expect(b.urlFor(2, 3, 3), '33');
      expect(b.urlFor(3, 3, 5), '213');
    });
  });

  group('TileUrlBuilder bbox', () {
    test('bbox is west,south,east,north (y up)', () {
      final b = TileUrlBuilder(templates: '{bbox}');
      final parts = b.urlFor(1, 0, 0).split(',').map(double.parse).toList();
      expect(parts.length, 4);
      expect(parts[0], closeTo(-180, 1e-4)); // west
      expect(parts[1], closeTo(0, 1e-4)); // south
      expect(parts[2], closeTo(0, 1e-4)); // east
      expect(parts[3], closeTo(85.0511, 0.01)); // north
      expect(parts[1], lessThan(parts[3]), reason: 'y-axis must point up');
    });

    test('bbox-epsg-3857 is metres with y up', () {
      final b = TileUrlBuilder(templates: '{bbox-epsg-3857}');
      final parts = b.urlFor(1, 0, 0).split(',').map(double.parse).toList();
      expect(parts[0], closeTo(-20037508.34, 1)); // minx
      expect(parts[1], closeTo(0, 1)); // miny (south)
      expect(parts[2], closeTo(0, 1)); // maxx
      expect(parts[3], closeTo(20037508.34, 1)); // maxy (north)
      expect(parts[1], lessThan(parts[3]), reason: 'y-axis must point up');
    });
  });
}
