import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

const _scheme = TileSchemeKind.webMercator;

VectorDrawTiles _resolve(List<TileKey> visible, Set<TileKey> loaded) =>
    resolveVectorDrawTiles(
      visible: visible,
      isLoaded: loaded.contains,
      sourceMinZoom: 0,
      sourceMaxZoom: 14,
      scheme: _scheme,
    );

void main() {
  group('resolveVectorDrawTiles', () {
    test('an exact tile is ready and needs no placeholder', () {
      const ideal = TileKey(4, 5, 6);
      final draw = _resolve([ideal], {ideal});

      expect(draw.ready, [ideal]);
      expect(draw.placeholders, isEmpty);
      expect(draw.missing, isEmpty);
      expect(draw.drawOrder, [ideal]);
    });

    test('a missing tile falls back to a loaded ancestor', () {
      const ideal = TileKey(2, 1, 1);
      const parent = TileKey(1, 0, 0);
      final draw = _resolve([ideal], {parent});

      expect(draw.placeholders, [parent]);
      expect(draw.ready, isEmpty);
      // The ancestor is drawable, so the ideal is not blank.
      expect(draw.missing, isEmpty);
      // Placeholder is drawn before anything else.
      expect(draw.drawOrder, [parent]);
    });

    test('the nearest loaded ancestor wins, not the root', () {
      const ideal = TileKey(5, 17, 11);
      const grandparent = TileKey(3, 4, 2);
      const root = TileKey(0, 0, 0);
      final draw = _resolve([ideal], {root, grandparent});

      expect(draw.placeholders, [grandparent]);
    });

    test('a complete child generation is ready', () {
      const ideal = TileKey(2, 0, 0);
      final children = TileGrid.of(_scheme, 3).childrenOf(ideal).toSet();
      final draw = _resolve([ideal], children);

      expect(draw.ready, hasLength(4));
      expect(draw.ready.toSet(), children);
      expect(draw.placeholders, isEmpty);
      expect(draw.missing, isEmpty);
    });

    test('three of four children is not enough — falls back to an ancestor', () {
      const ideal = TileKey(2, 0, 0);
      const parent = TileKey(1, 0, 0);
      final children = TileGrid.of(_scheme, 3).childrenOf(ideal).toList();
      final loaded = {parent, ...children.take(3)};
      final draw = _resolve([ideal], loaded);

      expect(draw.placeholders, [parent]);
      expect(draw.ready, isEmpty);
    });

    test('one ancestor shared by four ideals is drawn once', () {
      const ideals = [
        TileKey(3, 0, 0),
        TileKey(3, 1, 0),
        TileKey(3, 0, 1),
        TileKey(3, 1, 1),
      ];
      const parent = TileKey(2, 0, 0);
      final draw = _resolve(ideals, {parent});

      expect(draw.placeholders, [parent]);
      expect(draw.missing, isEmpty);
      expect(draw.drawOrder, [parent]);
    });

    test('nothing loaded yields no draw work', () {
      const ideal = TileKey(6, 20, 20);
      final draw = _resolve([ideal], {});

      expect(draw.placeholders, isEmpty);
      expect(draw.ready, isEmpty);
      expect(draw.missing, [ideal]);
      expect(draw.drawOrder, isEmpty);
    });
  });
}
