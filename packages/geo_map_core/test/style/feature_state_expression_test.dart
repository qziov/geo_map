// `["feature-state", key]` support, mirroring MapLibre's evaluation context.
// Also guards the regression where `let` built a fresh ExpressionContext and
// dropped the state (and, after this change, any other context field).
import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('feature-state expression', () {
    test('reads the runtime state map', () {
      final expr = parseExpression(['feature-state', 'hover']);
      expect(
        expr.evaluate(const ExpressionContext(
          zoom: 3,
          featureState: {'hover': true},
        )),
        isTrue,
      );
      expect(
        expr.evaluate(const ExpressionContext(zoom: 3)),
        isNull,
      );
    });

    test('is feature-dependent, so paint properties are not constant-folded',
        () {
      final expr = parseExpression(['feature-state', 'hover']);
      expect(expr.isFeatureConstant, isFalse);
      expect(expr.isZoomConstant, isTrue);
      expect(expr.isConstant, isFalse);
    });

    test('works inside let / var (context propagation regression)', () {
      final expr = parseExpression([
        'let',
        'h',
        ['feature-state', 'hover'],
        ['var', 'h'],
      ]);
      expect(
        expr.evaluate(const ExpressionContext(
          zoom: 3,
          featureState: {'hover': 'yes'},
        )),
        'yes',
      );
    });

    test('works inside coalesce / case', () {
      final expr = parseExpression([
        'coalesce',
        ['feature-state', 'selected'],
        false,
      ]);
      expect(expr.evaluate(const ExpressionContext(zoom: 3)), isFalse);
      expect(
        expr.evaluate(const ExpressionContext(
          zoom: 3,
          featureState: {'selected': true},
        )),
        isTrue,
      );
    });

    test('state is separate from feature properties', () {
      final expr = parseExpression(['feature-state', 'hover']);
      expect(
        expr.evaluate(const ExpressionContext(
          zoom: 3,
          properties: {'hover': 'from-geojson'},
        )),
        isNull,
      );
      final get = parseExpression(['get', 'hover']);
      expect(
        get.evaluate(const ExpressionContext(
          zoom: 3,
          properties: {'hover': 'from-geojson'},
          featureState: {'hover': 'from-state'},
        )),
        'from-geojson',
      );
    });
  });

  test('filters get no feature state (MapLibre forbids it there)', () {
    final predicate = compileFilter([
      '==',
      ['feature-state', 'hover'],
      true,
    ]);
    // No exception, and the expression resolves to null -> false.
    expect(predicate(const {'x': 1}, 3), isFalse);
  });

  test('existing expressions still work with the default empty state', () {
    final expr = parseExpression([
      '+',
      ['get', 'rank'],
      ['zoom'],
    ]);
    expect(
      expr.evaluate(const ExpressionContext(zoom: 4, properties: {'rank': 2})),
      6,
    );
  });
}
