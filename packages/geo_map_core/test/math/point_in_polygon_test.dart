import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:test/test.dart';

/// A unit square spanning lat 0..10, lng 0..10.
final _square = <LatLng>[
  const LatLng(0, 0),
  const LatLng(0, 10),
  const LatLng(10, 10),
  const LatLng(10, 0),
  const LatLng(0, 0),
];

/// A hole inside [_square]: lat 2..4, lng 2..4.
final _hole = <LatLng>[
  const LatLng(2, 2),
  const LatLng(2, 4),
  const LatLng(4, 4),
  const LatLng(4, 2),
  const LatLng(2, 2),
];

void main() {
  group('pointInRing', () {
    test('a point inside the ring hits', () {
      expect(pointInRing(_square, const LatLng(5, 5)), isTrue);
    });

    test('a point outside the ring misses', () {
      expect(pointInRing(_square, const LatLng(15, 5)), isFalse);
      expect(pointInRing(_square, const LatLng(5, 15)), isFalse);
      expect(pointInRing(_square, const LatLng(-5, 5)), isFalse);
    });

    test('a point on the boundary hits', () {
      expect(pointInRing(_square, const LatLng(10, 5)), isTrue);
      expect(pointInRing(_square, const LatLng(5, 0)), isTrue);
    });

    test('includeBoundary: false excludes the boundary', () {
      expect(
        pointInRing(_square, const LatLng(10, 5), includeBoundary: false),
        isFalse,
      );
    });

    test('a degenerate ring never hits', () {
      expect(pointInRing(const <LatLng>[], const LatLng(0, 0)), isFalse);
      expect(
        pointInRing(const <LatLng>[LatLng(0, 0)], const LatLng(0, 0)),
        isFalse,
      );
      expect(
        pointInRing(
          const <LatLng>[LatLng(0, 0), LatLng(0, 10)],
          const LatLng(0, 5),
        ),
        isFalse,
      );
    });

    test('a collinear ring never hits', () {
      final collinear = <LatLng>[
        const LatLng(0, 0),
        const LatLng(0, 10),
        const LatLng(0, 20),
      ];
      expect(pointInRing(collinear, const LatLng(0, 5)), isFalse);
    });

    test('repeated adjacent vertices do not crash the test', () {
      final duplicated = <LatLng>[
        const LatLng(0, 0),
        const LatLng(0, 0),
        const LatLng(0, 10),
        const LatLng(10, 10),
        const LatLng(10, 0),
      ];
      expect(pointInRing(duplicated, const LatLng(5, 5)), isTrue);
    });
  });

  group('pointInRing — antimeridian', () {
    // A band straddling ±180°: raw longitudes 170 → -170.
    final band = <LatLng>[
      const LatLng(10, 170),
      const LatLng(10, -170),
      const LatLng(-10, -170),
      const LatLng(-10, 170),
      const LatLng(10, 170),
    ];

    test('both sides of the seam hit', () {
      expect(pointInRing(band, const LatLng(0, 180)), isTrue);
      expect(pointInRing(band, const LatLng(0, 179.9)), isTrue);
      expect(pointInRing(band, const LatLng(0, -179.9)), isTrue);
    });

    test('a point on the other side of the globe misses', () {
      expect(pointInRing(band, const LatLng(0, 0)), isFalse);
      expect(pointInRing(band, const LatLng(0, 90)), isFalse);
    });

    test('a band wider than 180° keeps its far end reachable', () {
      // Raw longitudes 0 → 160 → -160: unwrapped to 0 → 160 → 200, so the
      // window spans 200°. Anchoring the tap on the *first* vertex (the old
      // behaviour) folded lng 190 onto -170 and missed it entirely.
      final wide = <LatLng>[
        const LatLng(20, 0),
        const LatLng(20, 160),
        const LatLng(20, -160),
        const LatLng(-20, -160),
        const LatLng(-20, 160),
        const LatLng(-20, 0),
        const LatLng(20, 0),
      ];
      expect(pointInRing(wide, const LatLng(0, 190)), isTrue);
      expect(pointInRing(wide, const LatLng(0, -170)), isTrue);
      expect(pointInRing(wide, const LatLng(0, 100)), isTrue);
      // Outside the 0..200 window → miss, whichever copy we try.
      expect(pointInRing(wide, const LatLng(0, 250)), isFalse);
      expect(pointInRing(wide, const LatLng(0, -110)), isFalse);
    });
  });

  group('pointInRing — vertex on the query latitude', () {
    test('a tangent vertex is counted once, not twice', () {
      // The apex sits exactly on the query latitude. Counting it twice would
      // flip the even-odd result to "outside".
      final triangle = <LatLng>[
        const LatLng(0, 0),
        const LatLng(10, 10),
        const LatLng(20, 0),
      ];
      expect(pointInRing(triangle, const LatLng(10, 5)), isTrue);
    });
  });

  group('pointInPolygon', () {
    test('a point inside the outer ring hits', () {
      expect(pointInPolygon(<List<LatLng>>[_square], const LatLng(1, 1)),
          isTrue);
    });

    test('a point inside a hole misses', () {
      expect(
        pointInPolygon(<List<LatLng>>[_square, _hole], const LatLng(3, 3)),
        isFalse,
      );
    });

    test('a point on the outer boundary hits', () {
      expect(
        pointInPolygon(<List<LatLng>>[_square], const LatLng(0, 5)),
        isTrue,
      );
    });

    test('a point on a hole boundary misses — the hole wins', () {
      // The hole's first edge runs along lat 2 from lng 2 to 4.
      expect(
        pointInPolygon(
          <List<LatLng>>[_square, _hole],
          const LatLng(2, 3),
        ),
        isFalse,
      );
    });

    test('an empty or degenerate polygon misses', () {
      expect(pointInPolygon(const <List<LatLng>>[], const LatLng(0, 0)),
          isFalse);
      expect(
        pointInPolygon(
          const <List<LatLng>>[
            <LatLng>[LatLng(0, 0), LatLng(0, 1)],
          ],
          const LatLng(0, 0),
        ),
        isFalse,
      );
    });

    test('the hole winding does not matter', () {
      // Reversed hole: still a hole.
      final reversedHole = _hole.reversed.toList();
      expect(
        pointInPolygon(
          <List<LatLng>>[_square, reversedHole],
          const LatLng(3, 3),
        ),
        isFalse,
      );
    });
  });

  group('pointInMultiPolygon', () {
    final a = <LatLng>[
      const LatLng(0, 0),
      const LatLng(0, 10),
      const LatLng(10, 10),
      const LatLng(10, 0),
      const LatLng(0, 0),
    ];
    final b = <LatLng>[
      const LatLng(0, 5),
      const LatLng(0, 15),
      const LatLng(10, 15),
      const LatLng(10, 5),
      const LatLng(0, 5),
    ];

    test('the overlap of two sub-polygons hits', () {
      expect(
        pointInMultiPolygon(
          <List<List<LatLng>>>[
            <List<LatLng>>[a],
            <List<LatLng>>[b],
          ],
          const LatLng(5, 7),
        ),
        isTrue,
      );
    });

    test('a point outside every sub-polygon misses', () {
      expect(
        pointInMultiPolygon(
          <List<List<LatLng>>>[
            <List<LatLng>>[a],
            <List<LatLng>>[b],
          ],
          const LatLng(20, 7),
        ),
        isFalse,
      );
    });
  });

  group('ringSignedArea', () {
    test('the sign follows the winding', () {
      final ccw = <LatLng>[
        const LatLng(0, 0),
        const LatLng(0, 1),
        const LatLng(1, 1),
        const LatLng(1, 0),
      ];
      expect(ringSignedArea(ccw), greaterThan(0));
      expect(ringSignedArea(ccw.reversed.toList()), lessThan(0));
    });

    test('a ring crossing ±180° keeps the sign of its translation', () {
      // Near the seam.
      final nearSeam = <LatLng>[
        const LatLng(0, 170),
        const LatLng(0, -170),
        const LatLng(20, -175),
      ];
      // The same triangle, moved away from the seam.
      final awayFromSeam = <LatLng>[
        const LatLng(0, -5),
        const LatLng(0, 5),
        const LatLng(20, 0),
      ];
      expect(
        ringSignedArea(nearSeam).sign,
        equals(ringSignedArea(awayFromSeam).sign),
      );
    });

    test('a degenerate ring has no area', () {
      expect(ringSignedArea(const <LatLng>[]), 0);
      expect(
        ringSignedArea(const <LatLng>[LatLng(0, 0), LatLng(0, 1)]),
        0,
      );
    });
  });

  group('normalizeRingWinding', () {
    final outer = <LatLng>[
      const LatLng(0, 0),
      const LatLng(0, 10),
      const LatLng(10, 10),
      const LatLng(10, 0),
    ];

    test('a single ring is returned unchanged', () {
      expect(normalizeRingWinding(<List<LatLng>>[outer]), <List<LatLng>>[outer]);
    });

    test('a hole wound like the outer ring is reversed', () {
      final hole = <LatLng>[
        const LatLng(2, 2),
        const LatLng(2, 4),
        const LatLng(4, 4),
        const LatLng(4, 2),
      ];
      final out = normalizeRingWinding(<List<LatLng>>[outer, hole]);
      expect(out.length, equals(2));
      expect(ringSignedArea(out[1]).sign, isNot(equals(ringSignedArea(hole).sign)));
      // The outer ring keeps its orientation.
      expect(ringSignedArea(out[0]).sign, equals(ringSignedArea(outer).sign));
    });

    test('a hole already wound the other way is left alone', () {
      final hole = <LatLng>[
        const LatLng(2, 2),
        const LatLng(4, 2),
        const LatLng(4, 4),
        const LatLng(2, 4),
      ];
      final out = normalizeRingWinding(<List<LatLng>>[outer, hole]);
      expect(out[1], equals(hole));
    });
  });
}
