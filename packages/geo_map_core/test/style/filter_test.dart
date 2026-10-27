import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  test('null filter matches everything', () {
    expect(compileFilter(null)({'x': 1}), isTrue);
  });

  test('== / != compare a property to a literal', () {
    final eq = compileFilter(['==', 'use', 'park']);
    expect(eq({'use': 'park'}), isTrue);
    expect(eq({'use': 'road'}), isFalse);
    expect(compileFilter(['!=', 'use', 'park'])({'use': 'road'}), isTrue);
  });

  test('numeric equality normalizes int/double', () {
    expect(compileFilter(['==', 'n', 1])({'n': 1.0}), isTrue);
  });

  test('numeric comparisons', () {
    final f = compileFilter(['>=', 'pop', 100]);
    expect(f({'pop': 150}), isTrue);
    expect(f({'pop': 99}), isFalse);
    expect(f({'pop': 'x'}), isFalse); // non-numeric -> false
  });

  test('in / !in (variadic and array form)', () {
    final variadic = compileFilter(['in', 'use', 'park', 'garden']);
    expect(variadic({'use': 'park'}), isTrue);
    expect(variadic({'use': 'road'}), isFalse);
    final arrayForm = compileFilter(['in', 'use', ['park', 'garden']]);
    expect(arrayForm({'use': 'garden'}), isTrue);
    expect(compileFilter(['!in', 'use', 'park'])({'use': 'road'}), isTrue);
  });

  test('has / !has', () {
    expect(compileFilter(['has', 'name'])({'name': 'x'}), isTrue);
    expect(compileFilter(['has', 'name'])({}), isFalse);
    expect(compileFilter(['!has', 'name'])({}), isTrue);
  });

  test('all / any / none', () {
    final all = compileFilter([
      'all', ['==', 'a', 1], ['==', 'b', 2],
    ]);
    expect(all({'a': 1, 'b': 2}), isTrue);
    expect(all({'a': 1, 'b': 3}), isFalse);
    final any = compileFilter([
      'any', ['==', 'a', 1], ['==', 'b', 2],
    ]);
    expect(any({'a': 0, 'b': 2}), isTrue);
    final none = compileFilter(['none', ['==', 'a', 1]]);
    expect(none({'a': 2}), isTrue);
    expect(none({'a': 1}), isFalse);
  });

  test('expression-style operand', () {
    final f = compileFilter(['==', ['get', 'use'], 'park']);
    expect(f({'use': 'park'}), isTrue);
    expect(f({'use': 'road'}), isFalse);
  });

  test('unsupported operator throws', () {
    expect(() => compileFilter(['within', <String, Object?>{}]),
        throwsFormatException);
  });

  group('zoom in filters', () {
    // MapLibre evaluates a filter with `new EvaluationParameters(zoom)`
    // (`data/feature_index.ts:235`), so `["zoom"]` is legal inside one. Passing
    // a constant zoom (the old behaviour) made every such filter behave as if
    // the map were at z0.
    final filter = compileFilter(
      ['<=', ['get', 'rank'], ['+', ['zoom'], 1]],
    );

    test('accepts a feature the current zoom can afford', () {
      expect(filter({'rank': 2}, 3.6), isTrue);
      expect(filter({'rank': 5}, 3.6), isFalse);
    });

    test('the same feature flips as the zoom grows', () {
      expect(filter({'rank': 5}, 3.6), isFalse);
      expect(filter({'rank': 5}, 6.0), isTrue);
    });

    test('omitting the zoom means zoom 0', () {
      expect(filter({'rank': 1}), isTrue);
      expect(filter({'rank': 2}), isFalse);
    });
  });
}
