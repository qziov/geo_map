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
}
