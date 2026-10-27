import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('dashPolyline', () {
    test('cuts a straight line into equal dashes', () {
      final line = [const Vec2(0, 0), const Vec2(100, 0)];
      final dashes = dashPolyline(line, [10, 10]);

      expect(dashes, hasLength(5));
      expect(dashes.first.first.x, 0);
      expect(dashes.first.last.x, 10);
      expect(dashes.last.first.x, 80);
      expect(dashes.last.last.x, 90);
    });

    test('the last dash is clipped at the line end', () {
      final dashes = dashPolyline(
        [const Vec2(0, 0), const Vec2(12, 0)],
        [5, 5],
      );

      expect(dashes, hasLength(2));
      expect(dashes[1].first.x, 10);
      expect(dashes[1].last.x, 12);
    });

    test('an odd pattern joins the last and first dashes', () {
      // [10,5,5]: dash 0-10, gap 10-15, dash 15-20, dash 20-30, gap 30-35,
      // dash 35-40. The two middle dashes touch at x=20.
      final dashes = dashPolyline(
        [const Vec2(0, 0), const Vec2(40, 0)],
        [10, 5, 5],
      );

      expect(dashes, hasLength(4));
      expect(dashes[1].last.x, 20);
      expect(dashes[2].first.x, 20);
    });

    test('a zero-length dash element leaves only gaps', () {
      final dashes = dashPolyline(
        [const Vec2(0, 0), const Vec2(20, 0)],
        [0, 10],
      );
      expect(dashes, isEmpty);
    });

    test('degenerate patterns draw the line solid', () {
      final line = [const Vec2(0, 0), const Vec2(10, 0)];
      expect(dashPolyline(line, const []), [line]);
      expect(dashPolyline(line, const [5, -1]), [line]);
      expect(dashPolyline(line, const [0, 0]), [line]);
      expect(dashPolyline(line, const [5, 5]), isNot([line]));
    });

    test('duplicate points do not break the walk', () {
      final dashes = dashPolyline(
        [
          const Vec2(0, 0),
          const Vec2(0, 0),
          const Vec2(30, 0),
        ],
        [10, 10],
      );
      expect(dashes, hasLength(2));
      expect(dashes.first.last.x, 10);
      expect(dashes.last.last.x, 30);
    });
  });

  group('dashPolyline phase', () {
    test('starts mid-dash with the remaining part of the current dash', () {
      final dashes = dashPolyline(
        [const Vec2(0, 0), const Vec2(100, 0)],
        [10, 10],
        phase: 4,
      );
      // The first dash has 6px left, then the usual 10/10 rhythm.
      expect(dashes, hasLength(6));
      expect(dashes.first.first.x, 0);
      expect(dashes.first.last.x, 6);
      expect(dashes[1].first.x, 16);
      expect(dashes[1].last.x, 26);
    });

    test('a phase inside a gap starts with a gap', () {
      final dashes = dashPolyline(
        [const Vec2(0, 0), const Vec2(100, 0)],
        [10, 10],
        phase: 15,
      );
      // 5px of gap left: the first dash starts at x=5.
      expect(dashes.first.first.x, 5);
      expect(dashes.first.last.x, 15);
    });

    test('a whole period is the same as no phase', () {
      final line = [const Vec2(0, 0), const Vec2(60, 0)];
      final plain = dashPolyline(line, const [10, 10]);
      final shifted = dashPolyline(line, const [10, 10], phase: 20);
      expect(shifted.length, plain.length);
      for (var i = 0; i < plain.length; i++) {
        expect(shifted[i].first.x, closeTo(plain[i].first.x, 1e-9));
        expect(shifted[i].last.x, closeTo(plain[i].last.x, 1e-9));
      }
    });

    test('a negative phase reduces into the pattern', () {
      final line = [const Vec2(0, 0), const Vec2(20, 0)];
      final negative = dashPolyline(line, const [10, 10], phase: -5);
      final positive = dashPolyline(line, const [10, 10], phase: 15);
      expect(negative.first.first.x, closeTo(positive.first.first.x, 1e-9));
    });
  });
}
