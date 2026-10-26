import 'package:geo_map_core/src/math/fade.dart';
import 'package:test/test.dart';

void main() {
  group('selfFadeOpacity', () {
    const dur = 300;
    test('null loadedAt is always 1', () {
      expect(selfFadeOpacity(null, 0, dur), 1.0);
      expect(selfFadeOpacity(null, 9999, dur), 1.0);
    });
    test('rises linearly 0 -> 1 then clamps', () {
      expect(selfFadeOpacity(1000, 1000, dur), 0.0);
      expect(selfFadeOpacity(1000, 1150, dur), 0.5);
      expect(selfFadeOpacity(1000, 1300, dur), 1.0);
      expect(selfFadeOpacity(1000, 900, dur), 0.0);
      expect(selfFadeOpacity(1000, 2000, dur), 1.0);
    });
  });

  group('crossFadeProgress', () {
    const dur = 300;
    test('0 -> 1 over duration then clamps', () {
      expect(crossFadeProgress(0, 0, dur), 0.0);
      expect(crossFadeProgress(0, 150, dur), 0.5);
      expect(crossFadeProgress(0, 300, dur), 1.0);
      expect(crossFadeProgress(0, -50, dur), 0.0);
      expect(crossFadeProgress(0, 999, dur), 1.0);
    });
    test('zero duration snaps to done', () {
      expect(crossFadeProgress(0, 0, 0), 1.0);
    });
  });

  group('isWithinFade', () {
    test('true inside window, false after or without start', () {
      expect(isWithinFade(0, 100, 300), isTrue);
      expect(isWithinFade(0, 299, 300), isTrue);
      expect(isWithinFade(0, 300, 300), isFalse);
      expect(isWithinFade(null, 100, 300), isFalse);
    });
  });
}
