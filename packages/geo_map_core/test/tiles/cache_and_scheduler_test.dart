import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('cache policy', () {
    test('evicts least recently used when over budget', () {
      final p = TileCachePolicy<String>(budgetBytes: 300);
      p.put('a', 100);
      p.put('b', 100);
      p.put('c', 100);
      p.touch('a');
      p.put('d', 100);
      final evicted = p.trim();
      expect(evicted, ['b']);
      expect(p.contains('b'), isFalse);
      expect(p.contains('a') && p.contains('c') && p.contains('d'), isTrue);
    });

    test('never evicts tiles in the current render set', () {
      final p = TileCachePolicy<String>(budgetBytes: 150);
      p.put('a', 100);
      p.put('b', 100);
      p.beginFrame();
      p.addRenderTile('a');
      p.commitFrame();
      final evicted = p.trim();
      expect(evicted, ['b']);
      expect(p.contains('a'), isTrue);
    });

    test('previous render set is protected during a zoom switch', () {
      final p = TileCachePolicy<String>(budgetBytes: 120);
      p.put('z4a', 100);
      p.put('z4b', 100);
      p.beginFrame();
      p.addRenderTile('z4a');
      p.addRenderTile('z4b');
      p.commitFrame(); // they become "previous"

      // next frame draws nothing yet (new zoom level still loading)
      p.beginFrame();
      p.commitFrame();
      expect(p.previousRenderSet, containsAll(['z4a', 'z4b']));
      p.trim();
      expect(p.contains('z4a'), isTrue);
    });

    test('empty commit keeps the previous set (no underlay flicker)', () {
      final p = TileCachePolicy<int>(budgetBytes: 1000);
      p.put(1, 10);
      p.beginFrame();
      p.addRenderTile(1);
      p.commitFrame();
      expect(p.previousRenderSet, {1});
      p.beginFrame();
      p.commitFrame();
      expect(p.previousRenderSet, {1});
    });

    test('commit replaces the previous set when tiles were drawn', () {
      final p = TileCachePolicy<int>(budgetBytes: 1000);
      p.put(1, 10);
      p.put(2, 10);
      p.beginFrame();
      p.addRenderTile(1);
      p.commitFrame();
      p.beginFrame();
      p.addRenderTile(2);
      p.commitFrame();
      expect(p.previousRenderSet, {2});
    });

    test('byte accounting tracks inserts and removals', () {
      final p = TileCachePolicy<String>(budgetBytes: 1000);
      p.put('a', 300);
      p.put('b', 200);
      expect(p.bytes, 500);
      p.put('a', 100);
      expect(p.bytes, 300);
      p.remove('a');
      expect(p.bytes, 200);
    });

    test('never exceeds the budget after trimming', () {
      final p = TileCachePolicy<int>(budgetBytes: 250);
      for (var i = 0; i < 10; i++) {
        p.put(i, 100);
        p.trim();
      }
      expect(p.bytes, lessThanOrEqualTo(250));
    });

    test('touching refreshes recency', () {
      final p = TileCachePolicy<int>(budgetBytes: 200);
      p.put(1, 100);
      p.put(2, 100);
      p.touch(1);
      p.put(3, 100);
      expect(p.trim(), [2]);
    });
  });

  group('tile scheduler', () {
    test('blocks requests while a gesture is active', () {
      final s = TileScheduler(debounceMillis: 120);
      s.noteCameraChange(1000, interacting: true);
      expect(s.canRequest(1050), isFalse);
      expect(s.canRequest(1120), isTrue);
    });

    test('allows requests when idle for long enough', () {
      final s = TileScheduler(debounceMillis: 120);
      s.noteCameraChange(100, interacting: true);
      expect(s.canRequest(199), isFalse);
      expect(s.canRequest(220), isTrue);
    });

    test('generation tokens invalidate in-flight requests', () {
      final s = TileScheduler();
      final gen = s.generation;
      expect(s.isStale(gen), isFalse);
      final next = s.invalidate();
      expect(next, gen + 1);
      expect(s.isStale(gen), isTrue);
      expect(s.isStale(next), isFalse);
    });

    test('reset restores the initial state', () {
      final s = TileScheduler();
      s.noteCameraChange(500, interacting: true);
      s.invalidate();
      s.reset();
      expect(s.generation, 0);
      expect(s.canRequest(0), isTrue);
    });
  });
}
