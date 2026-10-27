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

  test('defaults are applied per layer type', () {
    final spec = StyleSpec.parse({
      'version': 8,
      'layers': [
        {'id': 'f', 'type': 'fill', 'source': 's'},
        {'id': 'l', 'type': 'line', 'source': 's'},
      ],
    });

    final fill = spec.layers[0];
    expect(fill.color('fill-color', const ExpressionContext(zoom: 5)),
        const StyleColor(0, 0, 0));
    expect(fill.number('fill-opacity', const ExpressionContext(zoom: 5)), 1);
    expect(fill.boolean('fill-antialias', const ExpressionContext(zoom: 5)),
        isTrue);

    final line = spec.layers[1];
    expect(line.number('line-width', const ExpressionContext(zoom: 5)), 1);
    expect(line.string('line-join', const ExpressionContext(zoom: 5)), 'miter');
    expect(line.string('line-cap', const ExpressionContext(zoom: 5)), 'butt');
  });

  test('typed getter reads an expression', () {
    final spec = StyleSpec.parse({
      'version': 8,
      'layers': [
        {
          'id': 'l',
          'type': 'line',
          'source': 's',
          'paint': {
            'line-width': [
              'interpolate', ['linear'], ['zoom'], 0, 1, 10, 11,
            ],
          },
        },
      ],
    });
    expect(spec.layers[0].number('line-width', const ExpressionContext(zoom: 5)),
        closeTo(6, 1e-9));
  });

  test('filter is compiled and evaluable', () {
    final spec = StyleSpec.parse({
      'version': 8,
      'layers': [
        {
          'id': 'f',
          'type': 'fill',
          'source': 's',
          'filter': ['==', 'use', 'park'],
        },
      ],
    });
    final f = spec.layers[0];
    expect(f.filter({'use': 'park'}), isTrue);
    expect(f.filter({'use': 'road'}), isFalse);
  });

  test('visibility none hides a layer', () {
    final spec = StyleSpec.parse({
      'version': 8,
      'layers': [
        {
          'id': 'f',
          'type': 'fill',
          'source': 's',
          'layout': {'visibility': 'none'},
        },
      ],
    });
    expect(spec.layers[0].isVisibleAt(10), isFalse);
  });

  test('unknown layer type parses but is not supported', () {
    final spec = StyleSpec.parse({
      'version': 8,
      'layers': [
        {'id': 's', 'type': 'heatmap', 'source': 's'},
      ],
    });
    expect(spec.layers[0].isSupported, isFalse);
  });

  group('fill outline', () {
    StyleLayer fill(Map<String, Object?> paint) => StyleSpec.parse({
          'version': 8,
          'layers': [
            {'id': 'f', 'type': 'fill', 'source': 's', 'paint': paint},
          ],
        }).layers.first;

    test('is unset by default, so callers fall back to fill-color', () {
      // MapLibre leaves `fill-outline-color` undefined and copies `fill-color`
      // in at layer-construction time (`fill_style_layer.ts:30-32`). Keeping the
      // "null" here is what lets the painter apply that rule; a default of
      // "transparent" would silently mean "no outline".
      final layer = fill({'fill-color': '#3366ff'});
      expect(layer.color('fill-outline-color', const ExpressionContext(zoom: 5)),
          isNull);
      expect(
        layer.color('fill-color', const ExpressionContext(zoom: 5))!.b,
        0xff,
      );
    });

    test('parses a colour', () {
      final layer = fill({
        'fill-color': '#3366ff',
        'fill-outline-color': '#102030',
      });
      final c = layer.color('fill-outline-color', const ExpressionContext(zoom: 5));
      expect(c, isNotNull);
      expect(c!.r, 0x10);
      expect(c.g, 0x20);
      expect(c.b, 0x30);
    });

    test('can be data driven', () {
      final layer = fill({
        'fill-color': '#3366ff',
        'fill-outline-color': ['get', 'edge'],
      });
      final red = layer.color(
        'fill-outline-color',
        const ExpressionContext(zoom: 5, properties: {'edge': '#ff0000'}),
      );
      expect(red!.r, 0xff);
      expect(red.g, 0x00);
    });

    test('fill-antialias defaults to true and can be turned off', () {
      const ctx = ExpressionContext(zoom: 5);
      expect(fill({}).valueOf('fill-antialias', ctx), isTrue);
      expect(fill({'fill-antialias': false}).valueOf('fill-antialias', ctx),
          isFalse);
    });
  });
}
