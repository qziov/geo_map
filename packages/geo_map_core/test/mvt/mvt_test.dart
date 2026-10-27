import 'dart:convert';
import 'dart:typed_data';

import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

/// MVT command integer: `(count << 3) | id`.
int _cmd(int id, int count) => (count << 3) | id;

/// Zigzag-encode a signed integer for the command payload.
int _zz(int value) => (value << 1) ^ (value >> 31);

/// Tiny protobuf writer so tests can build MVT bytes without a fixture file.
class _Wire {
  final BytesBuilder _b = BytesBuilder();

  void _varint(int value) {
    var x = value;
    while (x >= 0x80) {
      _b.addByte((x & 0x7f) | 0x80);
      x >>= 7;
    }
    _b.addByte(x & 0x7f);
  }

  void _tag(int field, int wire) => _varint((field << 3) | wire);

  void rawVarint(int field, int value) {
    _tag(field, 0);
    _varint(value);
  }

  void bytes(int field, List<int> data) {
    _tag(field, 2);
    _varint(data.length);
    _b.add(data);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, _Wire child) => bytes(field, child.toBytes());

  void packed(int field, List<int> values) {
    final child = _Wire();
    for (final v in values) {
      child._varint(v);
    }
    bytes(field, child.toBytes());
  }

  Uint8List toBytes() => _b.toBytes();
}

_Wire _stringValue(String s) => _Wire()..string(1, s);
_Wire _intValue(int v) => _Wire()..rawVarint(4, v);

_Wire _feature({
  int? id,
  List<int> tags = const [],
  required int type,
  required List<int> geometry,
}) {
  final w = _Wire();
  if (id != null) w.rawVarint(1, id);
  if (tags.isNotEmpty) w.packed(2, tags);
  w.rawVarint(3, type);
  w.packed(4, geometry);
  return w;
}

_Wire _layer({
  required String name,
  int extent = 4096,
  int version = 2,
  List<String> keys = const [],
  List<_Wire> values = const [],
  required List<_Wire> features,
}) {
  final w = _Wire();
  w.string(1, name);
  for (final f in features) {
    w.message(2, f);
  }
  for (final k in keys) {
    w.string(3, k);
  }
  for (final v in values) {
    w.message(4, v);
  }
  w.rawVarint(5, extent);
  w.rawVarint(15, version);
  return w;
}

Uint8List _tile(List<_Wire> layers) {
  final w = _Wire();
  for (final l in layers) {
    w.message(3, l);
  }
  return w.toBytes();
}

void main() {
  group('decodeMvtGeometry', () {
    test('MoveTo + LineTo with negative deltas accumulates coordinates', () {
      // MoveTo(1) dx=2,dy=3 ; LineTo(2) dx=1,dy=0 ; dx=0,dy=-1
      final rings = decodeMvtGeometry([
        _cmd(1, 1), _zz(2), _zz(3), //
        _cmd(2, 2), _zz(1), _zz(0), _zz(0), _zz(-1), //
      ]);

      expect(rings, hasLength(1));
      expect(rings.single, hasLength(3));
      expect(rings.single[0].x, 2);
      expect(rings.single[0].y, 3);
      expect(rings.single[1].x, 3);
      expect(rings.single[1].y, 3);
      expect(rings.single[2].x, 3);
      expect(rings.single[2].y, 2);
    });

    test('MoveTo starts a new ring (multi-linestring)', () {
      // Coordinates carry over across rings: (0,0)->(5,0), then delta (-5,5)
      // puts the second ring at absolute (0,5)->(5,5).
      final rings = decodeMvtGeometry([
        _cmd(1, 1), _zz(0), _zz(0), _cmd(2, 1), _zz(5), _zz(0), //
        _cmd(1, 1), _zz(-5), _zz(5), _cmd(2, 1), _zz(5), _zz(0), //
      ]);

      expect(rings, hasLength(2));
      expect(rings[0], hasLength(2));
      expect(rings[1], hasLength(2));
      expect(rings[1].first.x, 0);
      expect(rings[1].first.y, 5);
    });

    test('MoveTo with count > 1 keeps points in one ring (multipoint)', () {
      final rings = decodeMvtGeometry([
        _cmd(1, 3), _zz(1), _zz(2), _zz(2), _zz(2), _zz(2), _zz(2), //
      ]);

      expect(rings, hasLength(1));
      expect(rings.single, hasLength(3));
      expect(rings.single[0].x, 1);
      expect(rings.single[1].x, 3);
      expect(rings.single[2].x, 5);
      expect(rings.single[2].y, 6);
    });

    test('ClosePath appends the first point and ends the ring', () {
      final rings = decodeMvtGeometry([
        _cmd(1, 1), _zz(0), _zz(0), //
        _cmd(2, 3), _zz(10), _zz(0), _zz(0), _zz(10), _zz(-10), _zz(0), //
        _cmd(7, 1), //
      ]);

      expect(rings, hasLength(1));
      final ring = rings.single;
      expect(ring, hasLength(5));
      expect(ring.last.x, ring.first.x);
      expect(ring.last.y, ring.first.y);
    });

    test('truncated command throws', () {
      expect(
          () => decodeMvtGeometry([_cmd(1, 1), _zz(1)]), throwsFormatException);
    });

    test('LineTo before MoveTo throws', () {
      expect(() => decodeMvtGeometry([_cmd(2, 1), _zz(1), _zz(1)]),
          throwsFormatException);
    });

    test('unknown command throws', () {
      expect(() => decodeMvtGeometry([_cmd(3, 1)]), throwsFormatException);
    });
  });

  group('classifyMvtPolygonRings', () {
    List<Vec2> rect(double x, double y, double w, double h) => [
          Vec2(x, y),
          Vec2(x + w, y),
          Vec2(x + w, y + h),
          Vec2(x, y + h),
          Vec2(x, y),
        ];

    test('outer + opposite-wound hole groups into one polygon', () {
      final outer = rect(0, 0, 10, 10);
      final hole = [
        const Vec2(2, 2),
        const Vec2(2, 4),
        const Vec2(4, 4),
        const Vec2(4, 2),
        const Vec2(2, 2),
      ];

      expect(mvtRingSignedArea(outer).isNegative,
          isNot(mvtRingSignedArea(hole).isNegative));

      final polygons = classifyMvtPolygonRings([outer, hole]);
      expect(polygons, hasLength(1));
      expect(polygons.single, hasLength(2));
      expect(polygons.single.first, same(outer));
    });

    test('two same-wound outers become two polygons', () {
      final polygons = classifyMvtPolygonRings([
        rect(0, 0, 10, 10),
        rect(20, 20, 10, 10),
      ]);
      expect(polygons, hasLength(2));
      expect(polygons[0], hasLength(1));
      expect(polygons[1], hasLength(1));
    });

    test('single ring passes through untouched', () {
      final ring = rect(0, 0, 4, 4);
      final polygons = classifyMvtPolygonRings([ring]);
      expect(polygons, hasLength(1));
      expect(polygons.single.single, same(ring));
    });
  });

  group('decodeMvtTile', () {
    test('decodes layer metadata, properties and line geometry', () {
      final layer = _layer(
        name: 'roads',
        extent: 4096,
        version: 2,
        keys: ['kind', 'rank'],
        values: [_stringValue('route'), _intValue(3)],
        features: [
          _feature(
            id: 7,
            tags: [0, 0, 1, 1],
            type: 2, // lineString
            geometry: [
              _cmd(1, 1), _zz(0), _zz(0), //
              _cmd(2, 1), _zz(4096), _zz(0), //
            ],
          ),
        ],
      );

      final tile = decodeMvtTile(_tile([layer]));
      expect(tile.layers, hasLength(1));

      final decoded = tile.layer('roads')!;
      expect(decoded.name, 'roads');
      expect(decoded.extent, 4096);
      expect(decoded.version, 2);
      expect(decoded.features, hasLength(1));

      final feature = decoded.features.single;
      expect(feature.id, 7);
      expect(feature.type, MvtGeomType.lineString);
      expect(feature.properties['kind'], 'route');
      expect(feature.properties['rank'], 3);
      expect(feature.geometry, hasLength(1));
      expect(feature.geometry.single, hasLength(2));
      expect(feature.geometry.single[1].x, 4096);
    });

    test('decodes a polygon with a hole into two rings', () {
      final geom = <int>[
        // outer: (0,0) (10,0) (10,10) (0,10) close
        _cmd(1, 1), _zz(0), _zz(0), //
        _cmd(2, 3), _zz(10), _zz(0), _zz(0), _zz(10), _zz(-10), _zz(0), //
        _cmd(7, 1), //
        // hole: (2,2) (2,4) (4,4) (4,2) close (reverse wound)
        _cmd(1, 1), _zz(2), _zz(2), //
        _cmd(2, 3), _zz(0), _zz(2), _zz(2), _zz(0), _zz(0), _zz(-2), //
        _cmd(7, 1), //
      ];

      final tile = decodeMvtTile(_tile([
        _layer(
          name: 'land',
          features: [_feature(type: 3, geometry: geom)],
        ),
      ]));

      final feature = tile.layer('land')!.features.single;
      expect(feature.type, MvtGeomType.polygon);
      expect(feature.geometry, hasLength(2));
      expect(feature.geometry[0].first.x, 0);
      expect(feature.geometry[1].first.x, 2);

      final polygons = classifyMvtPolygonRings(feature.geometry);
      expect(polygons, hasLength(1));
      expect(polygons.single, hasLength(2));
    });

    test('a tile with no layers decodes to an empty tile', () {
      final tile = decodeMvtTile(Uint8List(0));
      expect(tile.layers, isEmpty);
    });
  });
}
