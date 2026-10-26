import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('failure classification', () {
    test('network failures retry faster than not-found failures', () {
      final p = TileCachePolicy<String>();
      expect(p.ttlFor(TileFailureKind.network),
          lessThan(p.ttlFor(TileFailureKind.notFound)));
      expect(p.ttlFor(TileFailureKind.decode),
          lessThan(p.ttlFor(TileFailureKind.notFound)));
    });

    test('not-found does not block a tile (MapLibre falls back instead)', () {
      final p = TileCachePolicy<String>();
      p.markFailure('z/1/2', TileFailureKind.notFound, nowMs: 1000);
      // Advisory only — the parent/child fallback must still be allowed.
      expect(p.isFailed('z/1/2', nowMs: 1001), isFalse);
      expect(p.failureKind('z/1/2'), TileFailureKind.notFound);
      // ...but the retry of the same URL is delayed.
      expect(p.retryAfter('z/1/2')!, greaterThan(1000));
    });

    test('network failures do block an immediate retry', () {
      final p = TileCachePolicy<String>();
      p.markFailure('z/1/2', TileFailureKind.network, nowMs: 1000);
      expect(p.isFailed('z/1/2', nowMs: 1001), isTrue);
      expect(p.isFailed('z/1/2', nowMs: 1000 + 3001), isFalse);
    });

    test('repeated failures back off exponentially', () {
      final p = TileCachePolicy<String>();
      p.markFailure('k', TileFailureKind.network, nowMs: 0);
      final first = p.retryAfter('k')!;
      p.markFailure('k', TileFailureKind.network, nowMs: 0);
      final second = p.retryAfter('k')!;
      expect(second, greaterThan(first));
      expect(second - first, lessThanOrEqualTo(GeoEngineTuning.failureBackoffMaxMs));
    });

    test('a success clears the failure record', () {
      final p = TileCachePolicy<String>();
      p.markFailure('k', TileFailureKind.network, nowMs: 0);
      p.clearFailure('k');
      expect(p.isFailed('k', nowMs: 1), isFalse);
      expect(p.failureKind('k'), isNull);
    });
  });

  group('bounded tracking', () {
    test('tracked keys stay bounded', () {
      final p = TileCachePolicy<String>(maxTrackedKeys: 32);
      for (var i = 0; i < 500; i++) {
        p.markFailure('k$i', TileFailureKind.network, nowMs: 0);
      }
      expect(p.trackedKeys, lessThanOrEqualTo(64));
    });
  });

  group('concurrency gate', () {
    test('slots are limited and released', () {
      final p = TileCachePolicy<String>(maxConcurrentRequests: 16);
      for (var i = 0; i < 16; i++) {
        expect(p.tryAcquireSlot(), isTrue);
      }
      expect(p.tryAcquireSlot(), isFalse);
      expect(p.inFlight, 16);
      p.releaseSlot();
      expect(p.inFlight, 15);
      expect(p.tryAcquireSlot(), isTrue);
    });

    test('release never goes negative', () {
      final p = TileCachePolicy<String>();
      p.releaseSlot();
      expect(p.inFlight, 0);
    });
  });

  group('tuning constants', () {
    test('retained-tile limits match MapLibre', () {
      expect(GeoEngineTuning.maxUnderzooming, 10);
      expect(GeoEngineTuning.maxOverzooming, 3);
      expect(GeoEngineTuning.maxParallelRequests, 16);
      expect(GeoEngineTuning.tileCacheZoomLevels, 5);
    });
  });
}
