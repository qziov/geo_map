import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('tile request plan', () {
    final ideal = TileKey(10, 512, 340);

    TileRequestPlan plan({
      Set<TileKey> loaded = const {},
      Map<TileKey, TileFailureKind> failed = const {},
      int minZoom = 0,
      bool suspend = false,
    }) =>
        planTileRequest(
          ideal: ideal,
          sourceMinZoom: minZoom,
          isLoaded: loaded.contains,
          failureOf: (k) => failed[k],
          suspendAncestors: suspend,
        );

    test('the ideal tile is requested even when a parent is cached', () {
      // ★ The regression: zooming in leaves the previous level in the cache.
      // If the ideal tile were only requested when *nothing* is drawable, the
      // view would stay pinned to the coarse level forever.
      final result = plan(loaded: {TileKey(9, 256, 170)});
      expect(result.ideal, ideal);
      expect(result.ancestors, isEmpty);
    });

    test('a loaded ideal tile needs no request at all', () {
      final result = plan(loaded: {ideal});
      expect(result.isEmpty, isTrue);
    });

    test('the ancestor chain is walked only through failed levels', () {
      final result = plan(failed: {ideal: TileFailureKind.notFound});
      expect(result.ideal, ideal);
      // The parent has not failed, so nothing above it is fetched yet.
      expect(result.ancestors, [TileKey(9, 256, 170)]);
    });

    test('the chain escalates one level per round', () {
      final parent = TileKey(9, 256, 170);
      final result = plan(failed: {
        ideal: TileFailureKind.notFound,
        parent: TileFailureKind.notFound,
      });
      expect(result.ancestors, [parent, TileKey(8, 128, 85)]);
    });

    test('a cached ancestor stops the chain', () {
      final parent = TileKey(9, 256, 170);
      final result = plan(
        loaded: {parent},
        failed: {
          ideal: TileFailureKind.notFound,
          parent: TileFailureKind.notFound,
        },
      );
      expect(result.ancestors, isEmpty);
    });

    test('the chain never goes below the source min zoom', () {
      final result = plan(
        minZoom: 9,
        failed: {
          for (var z = 10; z >= 0; z--)
            TileKey(z, 512 >> (10 - z), 340 >> (10 - z)):
                TileFailureKind.notFound,
        },
      );
      expect(result.ancestors, [TileKey(9, 256, 170)]);
    });

    test('the chain depth is bounded by maxUnderzooming', () {
      final failed = <TileKey, TileFailureKind>{};
      for (var dz = 0; dz <= GeoEngineTuning.maxUnderzooming + 4; dz++) {
        failed[TileKey(ideal.z - dz, ideal.x >> dz, ideal.y >> dz)] =
            TileFailureKind.network;
      }
      final result = plan(failed: failed);
      expect(result.ancestors.length, GeoEngineTuning.maxUnderzooming);
      expect(result.ancestors.first, TileKey(9, 256, 170));
      expect(result.ancestors.last.z, ideal.z - GeoEngineTuning.maxUnderzooming);
    });

    test('the ancestor keys are the true parents of the ideal tile', () {
      final result = plan(failed: {
        ideal: TileFailureKind.notFound,
        TileKey(9, 256, 170): TileFailureKind.notFound,
        TileKey(8, 128, 85): TileFailureKind.notFound,
      });
      for (var i = 0; i < result.ancestors.length; i++) {
        final a = result.ancestors[i];
        expect(a.z, ideal.z - i - 1);
        expect(a.x, ideal.x >> (i + 1));
        expect(a.y, ideal.y >> (i + 1));
      }
    });

    group('parent-request suspension (while zooming)', () {
      test('suspending drops ancestor requests but keeps the ideal tile', () {
        final result = plan(
          suspend: true,
          failed: {ideal: TileFailureKind.notFound},
        );
        expect(result.ideal, ideal);
        expect(result.ancestors, isEmpty);
      });

      test('suspending still requests nothing when the ideal is cached', () {
        final result = plan(suspend: true, loaded: {ideal});
        expect(result.isEmpty, isTrue);
      });

      test('without suspension the ancestor chain is unaffected', () {
        final result = plan(failed: {ideal: TileFailureKind.notFound});
        expect(result.ancestors, [TileKey(9, 256, 170)]);
      });
    });
  });
}
