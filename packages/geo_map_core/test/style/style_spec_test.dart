import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  test('parse a minimal fill + line style', () {
    final spec = StyleSpec.parse({
      'version': 8,
      'sources': {
        'v': {'type': 'geojson', 'data': 'x.geojson'},
      },
      'layers': [
        {
          'id': 'bg',
          'type': 'fill',
          'source': 'v',
          'paint': {'fill-color': '#3366ff', 'fill-opacity': 0.5},
        },
        {
          'id': 'roads',
          'type': 'line',
          'source': 'v',
          'minzoom': 6,
          'paint': {
            'line-color': [
              'interpolate', ['linear'], ['zoom'], 6, '#888888', 12, '#111111',
            ],
            'line-width': [
              'interpolate', ['linear'], ['zoom'], 6, 1, 12, 8,
            ],
          },
        },
      ],
    });

    expect(spec.version, 8);
    expect(spec.sources['v']!['type'], 'geojson');
    expect(spec.layers.length, 2);

    final bg = spec.layers[0];
    expect(bg.type, 'fill');
    expect(bg.paint['fill-color']!.evaluate(const ExpressionContext(zoom: 5)),
        const StyleColor(0x33, 0x66, 0xff));
    expect(bg.paint['fill-opacity']!.evaluate(const ExpressionContext(zoom: 5)),
        0.5);

    final roads = spec.layers[1];
    expect(roads.isVisibleAt(5.9), isFalse);
    expect(roads.isVisibleAt(6), isTrue);

    final width =
        roads.paint['line-width']!.evaluate(const ExpressionContext(zoom: 9))
            as num;
    expect(width.toDouble(), closeTo(4.5, 1e-9)); // (9-6)/6 = .5 -> 1+7*.5

    final color = roads.paint['line-color']!
        .evaluate(const ExpressionContext(zoom: 9)) as StyleColor;
    expect(color.r, closeTo(0x4d, 8)); // between 0x88 and 0x11
  });

  test('a bad expression inside a property throws at parse time', () {
    expect(
      () => StyleSpec.parse({
        'version': 8,
        'layers': [
          {
            'id': 'x',
            'type': 'fill',
            'paint': {
              'fill-color': ['nope', 1],
            },
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('property value knows if it is data-driven', () {
    final constant = PropertyValue.fromJson(2);
    expect(constant.isExpression, isFalse);
    expect(constant.isFeatureConstant, isTrue);

    final dataDriven = PropertyValue.fromJson(['get', 'w'], isColor: false);
    expect(dataDriven.isExpression, isTrue);
    expect(dataDriven.isFeatureConstant, isFalse);
  });
}
