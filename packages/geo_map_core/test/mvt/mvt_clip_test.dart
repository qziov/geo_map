import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

void main() {
  group('clipMvtPolylineToExtent', () {
    test('a line crossing the tile is cut to the box', () {
      final runs = clipMvtPolylineToExtent(
        [const Vec2(-100, 2048), const Vec2(4196, 2048)],
        4096,
      );

      expect(runs, hasLength(1));
      expect(runs.single.first.x, 0);
      expect(runs.single.last.x, 4096);
    });

    test('a line entirely outside is dropped', () {
      expect(
        clipMvtPolylineToExtent(
          [const Vec2(-200, -200), const Vec2(-100, -150)],
          4096,
        ),
        isEmpty,
      );
    });

    test('leaving and re-entering yields two runs', () {
      final runs = clipMvtPolylineToExtent(
        [
          const Vec2(100, 100),
          const Vec2(200, 100),
          const Vec2(5000, 100),
          const Vec2(6000, 100),
          const Vec2(100, 200),
        ],
        4096,
      );

      expect(runs, hasLength(2));
      expect(runs.first.first.x, 100);
      expect(runs.first.last.x, 4096);
      expect(runs.last.last.x, 100);
    });

    test('a buffered polygon edge is clipped away', () {
      // A ring that runs 64 units outside the tile, as MVT buffers do: every
      // edge is outside [0, extent], so nothing is stroked inside the tile.
      final ring = [
        const Vec2(-64, -64),
        const Vec2(4160, -64),
        const Vec2(4160, 4160),
        const Vec2(-64, 4160),
        const Vec2(-64, -64),
      ];
      expect(clipMvtPolylineToExtent(ring, 4096), isEmpty);
    });

    test('a polygon clipped at the tile edge drops the border runs', () {
      // Without a buffer the ring lies exactly on the tile border; stroking it
      // would draw the tile grid.
      final ring = [
        const Vec2(0, 0),
        const Vec2(4096, 0),
        const Vec2(4096, 4096),
        const Vec2(0, 4096),
        const Vec2(0, 0),
      ];
      expect(
        clipMvtPolylineToExtent(ring, 4096, dropTileEdges: true),
        isEmpty,
      );
      expect(clipMvtPolylineToExtent(ring, 4096), isNotEmpty);
    });

    test('degenerate input is ignored', () {
      expect(clipMvtPolylineToExtent(const [], 4096), isEmpty);
      expect(clipMvtPolylineToExtent([const Vec2(1, 1)], 4096), isEmpty);
      expect(
        clipMvtPolylineToExtent(
          [const Vec2(1, 1), const Vec2(2, 2)],
          0,
        ),
        isEmpty,
      );
    });
  });
}
