import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

/// Build a decision from a set of "loaded" keys.
TileFallbackDecision _decide(TileKey ideal, Set<TileKey> loaded) =>
    planTileResolution(
      ideal: ideal,
      sourceMinZoom: 0,
      sourceMaxZoom: 22,
      scheme: TileSchemeKind.webMercator,
      isLoaded: loaded.contains,
    );

void main() {
  const scheme = TileSchemeKind.webMercator;
  const ideal = TileKey(3, 2, 2);
  final children = TileGrid.of(scheme, 4).childrenOf(ideal);

  group('exact', () {
    test('the ideal tile itself wins over everything', () {
      final loaded = {
        ideal,
        ...children,
        const TileKey(2, 1, 1),
      };
      final d = _decide(ideal, loaded);
      expect(d.kind, TileFallbackKind.exact);
    });
  });

  group('descendants', () {
    test('a complete generation of children is used', () {
      final d = _decide(ideal, {...children});
      expect(d.kind, TileFallbackKind.descendants);
      expect(d.children.toSet(), children.toSet());
    });

    test('three of four children is not a complete generation', () {
      final d = _decide(ideal, {...children.take(3), const TileKey(2, 1, 1)});
      expect(d.kind, TileFallbackKind.ancestor,
          reason: 'missing quarter must fall through to the ancestor');
      expect(d.children, isEmpty);
    });

    test('children beyond sourceMaxZoom are ignored', () {
      const ideal22 = TileKey(22, 1, 1);
      // These would-be children exist in the set, but they are past maxZoom,
      // so resolution must not use them (and there is no ancestor either).
      final child23 = TileGrid.of(scheme, 23).childrenOf(ideal22).toSet();
      final d = planTileResolution(
        ideal: ideal22,
        sourceMinZoom: 0,
        sourceMaxZoom: 22,
        scheme: scheme,
        isLoaded: child23.contains,
      );
      expect(d.kind, TileFallbackKind.none);
    });
  });

  group('ancestor', () {
    test('nearest loaded ancestor is chosen with the right dz', () {
      // Loaded two levels up, none at one level up.
      final d = _decide(ideal, {const TileKey(1, 0, 0)});
      expect(d.kind, TileFallbackKind.ancestor);
      expect(d.dz, 2);
      expect(d.ancestor, const TileKey(1, 0, 0));
    });

    test('the closest loaded ancestor wins over a farther one', () {
      final d = _decide(ideal, {
        const TileKey(2, 1, 1), // dz = 1 (parent)
        const TileKey(1, 0, 0), // dz = 2 (grandparent)
      });
      expect(d.dz, 1);
      expect(d.ancestor, const TileKey(2, 1, 1));
    });
  });

  group('none', () {
    test('nothing loaded means nothing to draw', () {
      final d = _decide(ideal, {});
      expect(d.kind, TileFallbackKind.none);
    });

    test('ancestor search stops at sourceMinZoom', () {
      final d = planTileResolution(
        ideal: const TileKey(1, 0, 0),
        sourceMinZoom: 1,
        sourceMaxZoom: 22,
        scheme: scheme,
        isLoaded: (_) => false,
      );
      expect(d.kind, TileFallbackKind.none);
    });
  });
}
