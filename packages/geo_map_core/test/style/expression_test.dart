import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

ExpressionContext ctx({double zoom = 5, Map<String, Object?> props = const {}}) =>
    ExpressionContext(zoom: zoom, properties: props);

void main() {
  group('literals & accessors', () {
    test('literal scalar', () {
      expect(parseExpression(3).evaluate(ctx()), 3);
      expect(parseExpression('a').evaluate(ctx()), 'a');
    });

    test('get reads feature properties', () {
      final e = parseExpression(['get', 'class']);
      expect(e.evaluate(ctx(props: {'class': 'road'})), 'road');
      expect(e.isFeatureConstant, isFalse);
      expect(e.isZoomConstant, isTrue);
    });

    test('has', () {
      final e = parseExpression(['has', 'x']);
      expect(e.evaluate(ctx(props: {'x': 1})), isTrue);
      expect(e.evaluate(ctx()), isFalse);
    });

    test('zoom', () {
      final e = parseExpression(['zoom']);
      expect(e.evaluate(ctx(zoom: 7.5)), 7.5);
      expect(e.isZoomConstant, isFalse);
      expect(e.isFeatureConstant, isTrue);
    });
  });

  group('comparison & logic', () {
    test('== / != with properties', () {
      final e = parseExpression(['==', ['get', 'kind'], 'park']);
      expect(e.evaluate(ctx(props: {'kind': 'park'})), isTrue);
      expect(e.evaluate(ctx(props: {'kind': 'water'})), isFalse);
      expect(parseExpression(['!=', 1, 2]).evaluate(ctx()), isTrue);
    });

    test('numeric comparisons', () {
      expect(parseExpression(['>', ['get', 'v'], 10]).evaluate(ctx(props: {'v': 12})),
          isTrue);
      expect(parseExpression(['<=', 2, 2]).evaluate(ctx()), isTrue);
    });

    test('all / any / !', () {
      final c = ctx(props: {'a': true, 'b': false});
      expect(parseExpression(['all', ['get', 'a'], ['get', 'b']]).evaluate(c),
          isFalse);
      expect(parseExpression(['any', ['get', 'a'], ['get', 'b']]).evaluate(c),
          isTrue);
      expect(parseExpression(['!', ['get', 'b']]).evaluate(c), isTrue);
    });
  });

  group('interpolate & step', () {
    test('linear interpolate on zoom, clamped at both ends', () {
      final e = parseExpression(
          ['interpolate', ['linear'], ['zoom'], 0, 0, 10, 100]);
      expect((e.evaluate(ctx(zoom: 0)) as num).toDouble(), 0);
      expect((e.evaluate(ctx(zoom: 5)) as num).toDouble(), 50);
      expect((e.evaluate(ctx(zoom: 10)) as num).toDouble(), 100);
      expect((e.evaluate(ctx(zoom: -5)) as num).toDouble(), 0);
      expect((e.evaluate(ctx(zoom: 99)) as num).toDouble(), 100);
      expect(e.isZoomConstant, isFalse);
    });

    test('interpolate color in RGB', () {
      final e = parseExpression(
          ['interpolate', ['linear'], ['zoom'], 0, '#000000', 10, '#ffffff']);
      expect(e.evaluate(ctx(zoom: 5)), const StyleColor(128, 128, 128));
    });

    test('exponential interpolate differs from linear', () {
      final lin = parseExpression(
          ['interpolate', ['linear'], ['zoom'], 0, 0, 10, 100]);
      final exp = parseExpression(
          ['interpolate', ['exponential', 2], ['zoom'], 0, 0, 10, 100]);
      final l = (lin.evaluate(ctx(zoom: 5)) as num).toDouble();
      final x = (exp.evaluate(ctx(zoom: 5)) as num).toDouble();
      expect(l, 50);
      expect(x, lessThan(50));
    });

    test('step', () {
      final e = parseExpression(['step', ['zoom'], 'a', 5, 'b', 10, 'c']);
      expect(e.evaluate(ctx(zoom: 4)), 'a');
      expect(e.evaluate(ctx(zoom: 5)), 'b');
      expect(e.evaluate(ctx(zoom: 9.9)), 'b');
      expect(e.evaluate(ctx(zoom: 10)), 'c');
    });
  });

  group('case / coalesce / coercion', () {
    test('case picks the first truthy branch', () {
      final e = parseExpression([
        'case',
        ['==', ['get', 'type'], 'a'], 1,
        ['==', ['get', 'type'], 'b'], 2,
        0,
      ]);
      expect(e.evaluate(ctx(props: {'type': 'b'})), 2);
      expect(e.evaluate(ctx(props: {'type': 'z'})), 0);
    });

    test('coalesce falls back through nulls', () {
      final e = parseExpression(
          ['coalesce', ['get', 'missing'], ['get', 'present'], 'fallback']);
      expect(e.evaluate(ctx(props: {'present': 'x'})), 'x');
      expect(e.evaluate(ctx()), 'fallback');
    });

    test('to-number / to-color', () {
      expect(parseExpression(['to-number', '42']).evaluate(ctx()), 42.0);
      expect(parseExpression(['to-color', '#ff0000']).evaluate(ctx()),
          const StyleColor(255, 0, 0));
    });
  });

  group('errors & constant analysis', () {
    test('unsupported operator throws loudly', () {
      expect(() => parseExpression(['within', <String, Object?>{}]),
          throwsFormatException);
    });

    test('interpolate stops must strictly increase', () {
      expect(
        () => parseExpression(
            ['interpolate', ['linear'], ['zoom'], 10, 0, 5, 1]),
        throwsFormatException,
      );
    });

    test('feature/zoom constant analysis', () {
      final zoomOnly = parseExpression(
          ['interpolate', ['linear'], ['zoom'], 0, 1, 10, 2]);
      expect(zoomOnly.isFeatureConstant, isTrue);
      expect(zoomOnly.isZoomConstant, isFalse);

      final feature = parseExpression(['get', 'x']);
      expect(feature.isFeatureConstant, isFalse);
      expect(feature.isZoomConstant, isTrue);

      final both = parseExpression(['==', ['get', 'x'], ['zoom']]);
      expect(both.isFeatureConstant, isFalse);
      expect(both.isZoomConstant, isFalse);
    });
  });

  group('let / var / match / in / to-boolean', () {
    test('let binds, and a later binding sees an earlier one', () {
      final e = parseExpression([
        'let', 'a', ['get', 'x'], 'b', ['var', 'a'], ['var', 'b'],
      ]);
      expect(e.evaluate(ctx(props: {'x': 7})), 7);
    });

    test('a var without a let binding is null', () {
      expect(parseExpression(['var', 'nope']).evaluate(ctx()), isNull);
    });

    test('match picks scalar and array labels', () {
      final e = parseExpression([
        'match', ['get', 'kind'],
        'a', 'A',
        ['b', 'c'], 'BC',
        'other',
      ]);
      expect(e.evaluate(ctx(props: {'kind': 'a'})), 'A');
      expect(e.evaluate(ctx(props: {'kind': 'c'})), 'BC');
      expect(e.evaluate(ctx(props: {'kind': 'z'})), 'other');
    });

    test('in checks arrays and substrings', () {
      final arr = parseExpression(['in', ['get', 'k'], ['literal', ['a', 'b']]]);
      expect(arr.evaluate(ctx(props: {'k': 'a'})), isTrue);
      expect(arr.evaluate(ctx(props: {'k': 'z'})), isFalse);
      final sub = parseExpression(['in', 'ell', ['literal', 'hello']]);
      expect(sub.evaluate(ctx()), isTrue);
    });

    test('to-boolean coerces numbers and strings', () {
      expect(parseExpression(['to-boolean', 1]).evaluate(ctx()), isTrue);
      expect(parseExpression(['to-boolean', 0]).evaluate(ctx()), isFalse);
      expect(parseExpression(['to-boolean', 'true']).evaluate(ctx()), isTrue);
    });
  });

  group('zoom placement validation', () {
    test('zoom as a step/interpolate input is allowed', () {
      expect(
        () => validateZoomUsage(parseExpression(
            ['interpolate', ['linear'], ['zoom'], 0, 1, 10, 2])),
        returnsNormally,
      );
      expect(
        () => validateZoomUsage(parseExpression(['step', ['zoom'], 0, 10, 1])),
        returnsNormally,
      );
    });

    test('zoom nested in another operator is rejected', () {
      expect(
        () => validateZoomUsage(parseExpression(['==', ['zoom'], 5])),
        throwsFormatException,
      );
    });

    test('a bare zoom is not a valid property value', () {
      expect(() => PropertyValue.fromJson(['zoom']), throwsFormatException);
    });
  });

  group('arithmetic', () {
    Object? eval(Object json, {double zoom = 0, Map<String, Object?>? props}) =>
        parseExpression(json).evaluate(
          ExpressionContext(zoom: zoom, properties: props ?? const {}),
        );

    test('adds and multiplies', () {
      expect(eval(['+', 1, 2, 3]), 6.0);
      expect(eval(['*', 2, 3]), 6.0);
      expect(eval(['-', 5, 2]), 3.0);
      expect(eval(['/', 6, 4]), 1.5);
      expect(eval(['%', 7, 4]), 3.0);
    });

    test('works with zoom and properties', () {
      expect(eval(['+', ['zoom'], 1], zoom: 3.5), 4.5);
      expect(eval(['*', ['get', 'n'], 2], props: {'n': 3}), 6.0);
    });

    test('unary minus negates, unary plus is a no-op', () {
      expect(eval(['-', 4]), -4.0);
      expect(eval(['+', 4]), 4.0);
    });

    test('+ concatenates strings', () {
      expect(eval(['+', 'a', 'b']), 'ab');
    });

    test('a non-numeric operand yields null', () {
      expect(eval(['+', 'a', 1]), isNull);
      expect(eval(['*', 2, null]), isNull);
    });

    test('division and modulo by zero yield null, not infinity', () {
      expect(eval(['/', 1, 0]), isNull);
      expect(eval(['%', 1, 0]), isNull);
    });

    test('constness follows the operands', () {
      final withZoom = parseExpression(['+', ['zoom'], 1]);
      expect(withZoom.isConstant, isFalse);
      expect(withZoom.isFeatureConstant, isTrue);

      final withProp = parseExpression(['+', ['get', 'n'], 1]);
      expect(withProp.isFeatureConstant, isFalse);
      expect(parseExpression(['+', 1, 2]).isConstant, isTrue);
    });
  });
}
