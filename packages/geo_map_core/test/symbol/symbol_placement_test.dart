import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

/// A candidate whose box is `w x h` centred on ([cx], [cy]).
SymbolCandidate _at(
  int id,
  double cx,
  double cy, {
  double w = 40,
  double h = 16,
  double sortKey = 0,
  int order = 0,
  bool allowOverlap = false,
  bool ignorePlacement = false,
  int group = 0,
}) =>
    SymbolCandidate(
      key: id,
      box: (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2),
      anchorX: cx,
      anchorY: cy,
      sortKey: sortKey,
      order: order,
      allowOverlap: allowOverlap,
      ignorePlacement: ignorePlacement,
      collisionGroup: group,
    );

const double _w = 400;
const double _h = 400;

void main() {
  group('GridIndex', () {
    test('reports hits and misses', () {
      final grid = GridIndex<String>(width: 200, height: 200);
      grid.insert('a', 10, 10, 50, 30);
      expect(grid.intersects(20, 15, 60, 25), isTrue);
      expect(grid.intersects(60, 60, 80, 80), isFalse);
    });

    test('a box spanning many cells is only returned once', () {
      final grid = GridIndex<String>(width: 200, height: 200);
      grid.insert('a', 0, 0, 190, 190);
      expect(grid.hits(10, 10, 180, 180), ['a']);
    });

    test('accept filters candidates', () {
      final grid = GridIndex<String>(width: 200, height: 200);
      grid.insert('a', 10, 10, 50, 50);
      grid.insert('b', 12, 12, 48, 48);
      expect(grid.hits(0, 0, 100, 100), hasLength(2));
      expect(
        grid.hits(0, 0, 100, 100, accept: (k) => k == 'a'),
        ['a'],
      );
    });

    test('keeps insertion order', () {
      final grid = GridIndex<int>(width: 200, height: 200);
      grid.insert(0, 0, 0, 60, 60);
      grid.insert(1, 20, 20, 80, 80);
      expect(grid.hits(30, 30, 40, 40), [0, 1]);
    });

    test('negative coordinates still land in a cell', () {
      final grid = GridIndex<String>(width: 200, height: 200);
      grid.insert('a', -30, -30, -10, -10);
      expect(grid.hits(-40, -40, 0, 0), ['a']);
    });
  });

  group('SymbolPlacer', () {
    test('the first of two overlapping labels wins', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final decisions = placer.place([
        _at(1, 100, 100),
        _at(2, 110, 105),
      ]);
      expect(decisions[0].isPlaced, isTrue);
      expect(decisions[1].result, SymbolPlacementResult.collision);
    });

    test('labels that do not touch both survive', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final decisions = placer.place([
        _at(1, 100, 100),
        _at(2, 200, 100),
      ]);
      expect(decisions.every((d) => d.isPlaced), isTrue);
    });

    test('sortKey decides who gets the space, not list order', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final decisions = placer.place([
        _at(1, 100, 100, sortKey: 10),
        _at(2, 108, 100, sortKey: 1),
      ]);
      // Candidate 2 is placed first even though it comes second in the list.
      expect(decisions[0].isPlaced, isFalse);
      expect(decisions[1].isPlaced, isTrue);
    });

    test('equal sortKey falls back to the feature order', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final decisions = placer.place([
        _at(1, 100, 100, order: 5),
        _at(2, 104, 100, order: 2),
      ]);
      expect(decisions[0].isPlaced, isFalse);
      expect(decisions[1].isPlaced, isTrue);
    });

    test('allow-overlap ignores both grids', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final decisions = placer.place([
        _at(1, 100, 100),
        _at(2, 100, 100, allowOverlap: true),
        _at(3, 100, 100, allowOverlap: true),
      ]);
      expect(decisions.every((d) => d.isPlaced), isTrue);
    });

    test('allow-overlap still reserves space for later normal labels', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final decisions = placer.place([
        _at(1, 100, 100, allowOverlap: true),
        _at(2, 100, 100),
      ]);
      expect(decisions[0].isPlaced, isTrue);
      // `overlapAllowed('never', 'always')` is false, so the always-placed label
      // does block this one.
      expect(decisions[1].result, SymbolPlacementResult.collision);
    });

    test('ignore-placement does not reserve space', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final decisions = placer.place([
        _at(1, 100, 100, ignorePlacement: true),
        _at(2, 100, 100),
      ]);
      expect(decisions[0].isPlaced, isTrue);
      expect(decisions[1].isPlaced, isTrue,
          reason: 'the first label went into the ignored grid');
    });

    test('ignore-placement is still blocked by an existing label', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final decisions = placer.place([
        _at(1, 100, 100),
        _at(2, 100, 100, ignorePlacement: true),
      ]);
      expect(decisions[0].isPlaced, isTrue);
      // MapLibre queries both grids, so an ignored symbol cannot cover a placed
      // one either (`collision_index.ts:388`).
      expect(decisions[1].result, SymbolPlacementResult.collision);
    });

    test('a shared collision group may overlap itself', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final decisions = placer.place([
        _at(1, 100, 100, group: 7),
        _at(2, 100, 100, group: 7),
      ]);
      expect(decisions.every((d) => d.isPlaced), isTrue);
    });

    test('labels outside the padded viewport are refused', () {
      final placer = SymbolPlacer(width: _w, height: _h, viewportPadding: 10);
      final decisions = placer.place([
        _at(1, -200, 100),
        _at(2, 100, -300),
      ]);
      expect(decisions[0].result, SymbolPlacementResult.offscreen);
      expect(decisions[1].result, SymbolPlacementResult.offscreen);
    });

    test('a label inside the padding still counts', () {
      final placer = SymbolPlacer(width: _w, height: _h, viewportPadding: 100);
      final decisions = placer.place([_at(1, -20, 100)]);
      expect(decisions.single.isPlaced, isTrue);
    });

    test('an empty frame is fine', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      expect(placer.place(const []), isEmpty);
      expect(placer.placedCount, 0);
    });

    test('decisions come back in input order', () {
      final placer = SymbolPlacer(width: _w, height: _h);
      final input = [
        _at(9, 300, 300, sortKey: 9),
        _at(1, 50, 50, sortKey: 1),
        _at(5, 200, 50, sortKey: 5),
      ];
      final decisions = placer.place(input);
      expect(decisions.map((d) => d.candidate.key), [9, 1, 5]);
    });
  });
}
