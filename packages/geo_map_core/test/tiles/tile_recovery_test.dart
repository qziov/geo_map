import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('planAncestorRequests', () {
    // z4 tile (5,6) has parents (2,3) at z3, (1,1) at z2, (0,0) at z1 ... etc.
    const ideal = TileKey(4, 5, 6);

    test('asks for the immediate parent when nothing is available', () {
      final requests = planAncestorRequests(
        missing: const [ideal],
        isAvailable: (_) => false,
        sourceMinZoom: 0,
      );
      expect(requests, [const TileKey(3, 2, 3)]);
    });

    test('one escalation per call — the grandparent waits for the next pass', () {
      final first = planAncestorRequests(
        missing: const [ideal],
        isAvailable: (_) => false,
        sourceMinZoom: 0,
      );
      expect(first.single.z, 3);
    });

    test('stops when a loaded ancestor already covers the footprint', () {
      final requests = planAncestorRequests(
        missing: const [ideal],
        isAvailable: (key) => key.z == 3,
        sourceMinZoom: 0,
      );
      expect(requests, isEmpty);
    });

    test('a loaded grandparent still needs the parent fetched', () {
      // The parent itself is what has to exist to be stretched: we ask for it
      // even though a coarser tile is already there.
      final requests = planAncestorRequests(
        missing: const [ideal],
        isAvailable: (key) => key.z == 2,
        sourceMinZoom: 0,
      );
      expect(requests, [const TileKey(3, 2, 3)]);
    });

    test('an in-flight ancestor counts as available', () {
      final requests = planAncestorRequests(
        missing: const [ideal],
        isAvailable: (key) => key == const TileKey(3, 2, 3),
        sourceMinZoom: 0,
      );
      expect(requests, isEmpty);
    });

    test('never climbs below sourceMinZoom', () {
      final requests = planAncestorRequests(
        missing: const [TileKey(1, 0, 0)],
        isAvailable: (_) => false,
        sourceMinZoom: 1,
      );
      expect(requests, isEmpty);
    });

    test('siblings sharing a parent dedupe to one request', () {
      final requests = planAncestorRequests(
        missing: const [
          TileKey(4, 5, 6),
          TileKey(4, 5, 7),
          TileKey(4, 4, 6),
        ],
        isAvailable: (_) => false,
        sourceMinZoom: 0,
      );
      expect(requests, [const TileKey(3, 2, 3)]);
    });

    test('different parents are both requested', () {
      final requests = planAncestorRequests(
        missing: const [TileKey(4, 0, 0), TileKey(4, 9, 9)],
        isAvailable: (_) => false,
        sourceMinZoom: 0,
      );
      expect(requests, [const TileKey(3, 0, 0), const TileKey(3, 4, 4)]);
    });

    test('respects maxUnderzoom', () {
      expect(
        planAncestorRequests(
          missing: const [TileKey(12, 100, 100)],
          isAvailable: (_) => false,
          sourceMinZoom: 0,
          maxUnderzoom: 10,
        ),
        [const TileKey(11, 50, 50)],
      );
      expect(
        planAncestorRequests(
          missing: const [TileKey(4, 5, 6)],
          isAvailable: (_) => false,
          sourceMinZoom: 0,
          maxUnderzoom: 0,
        ),
        isEmpty,
      );
    });
  });

  group('tileRetryDelay', () {
    test('doubles per attempt', () {
      expect(tileRetryDelay(1, baseMs: 3000).inMilliseconds, 3000);
      expect(tileRetryDelay(2, baseMs: 3000).inMilliseconds, 6000);
      expect(tileRetryDelay(3, baseMs: 3000).inMilliseconds, 12000);
      expect(tileRetryDelay(4, baseMs: 3000).inMilliseconds, 24000);
    });

    test('is capped', () {
      expect(tileRetryDelay(30, baseMs: 3000).inMilliseconds, 60000);
      expect(tileRetryDelay(30, baseMs: 3000, capMs: 5000).inMilliseconds, 5000);
    });

    test('a 404 backs off from its longer base', () {
      expect(tileRetryDelay(1, baseMs: 30000).inMilliseconds, 30000);
      expect(tileRetryDelay(2, baseMs: 30000).inMilliseconds, 60000);
    });

    test('guards nonsense attempt counts', () {
      expect(tileRetryDelay(0, baseMs: 3000).inMilliseconds, 3000);
      expect(tileRetryDelay(-4, baseMs: 3000).inMilliseconds, 3000);
    });
  });
}
