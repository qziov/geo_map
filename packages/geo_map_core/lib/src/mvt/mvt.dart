/// Mapbox Vector Tile (MVT) decoding.
///
/// Wire format: protobuf `Tile { repeated Layer layers = 3 }` where each layer
/// carries `keys`/`values` pools and features whose geometry is a stream of
/// command integers (`id = cmd & 0x7`, `count = cmd >> 3`, params zigzag).
///
/// Coordinate policy: geometry is returned in the **layer's own extent**
/// (usually 4096) with integer values promoted to double. Callers normalize
/// with the layer extent; we deliberately do not rescale at decode time so the
/// original extent stays visible and testable. maplibre-native scales to its
/// internal 8192 in `vector_mvt_tile_data.cpp:49`; that division is cheap and
/// belongs to the renderer, not the parser.
library;

import 'dart:typed_data';

import '../math/geo_geometry.dart';
import 'pbf_reader.dart';

enum MvtGeomType { unknown, point, lineString, polygon }

class MvtFeature {
  const MvtFeature({
    this.id,
    required this.type,
    required this.properties,
    required this.geometry,
  });

  /// Feature id from the tile, when the producer supplied one.
  final int? id;
  final MvtGeomType type;
  final Map<String, Object?> properties;

  /// Rings in the tile's extent space. Points are single-element rings;
  /// lines are open rings; polygons are closed rings (last == first).
  final List<List<Vec2>> geometry;
}

class MvtLayer {
  const MvtLayer({
    required this.name,
    required this.extent,
    required this.version,
    required this.features,
  });

  final String name;

  /// Tile-local coordinate ceiling (MVT default 4096).
  final int extent;
  final int version;
  final List<MvtFeature> features;
}

class MvtTile {
  const MvtTile(this.layers);

  final List<MvtLayer> layers;

  MvtLayer? layer(String name) {
    for (final layer in layers) {
      if (layer.name == name) return layer;
    }
    return null;
  }
}

/// Decodes a complete MVT payload.
MvtTile decodeMvtTile(Uint8List bytes) {
  final reader = PbfReader(bytes);
  final layers = <MvtLayer>[];
  while (!reader.isAtEnd) {
    final tag = reader.readTag();
    final field = tag >>> 3;
    final wire = tag & 0x7;
    if (field == 3 && wire == 2) {
      layers.add(_decodeLayer(reader.readMessage()));
    } else {
      reader.skip(wire);
    }
  }
  return MvtTile(layers);
}

MvtLayer _decodeLayer(PbfReader reader) {
  var name = '';
  var extent = 4096;
  var version = 1;
  final keys = <String>[];
  final values = <Object?>[];
  // Features index into keys/values, so decode them only after the whole layer
  // has been scanned (protobuf does not order fields).
  final featureBlobs = <Uint8List>[];

  while (!reader.isAtEnd) {
    final tag = reader.readTag();
    final field = tag >>> 3;
    final wire = tag & 0x7;
    switch (field) {
      case 1:
        name = reader.readString();
        break;
      case 2:
        featureBlobs.add(reader.readBytes());
        break;
      case 3:
        keys.add(reader.readString());
        break;
      case 4:
        values.add(_decodeValue(reader.readMessage()));
        break;
      case 5:
        extent = reader.readVarint();
        break;
      case 15:
        version = reader.readVarint();
        break;
      default:
        reader.skip(wire);
    }
  }

  final features = <MvtFeature>[
    for (final blob in featureBlobs) _decodeFeature(blob, keys, values),
  ];
  return MvtLayer(
    name: name,
    extent: extent,
    version: version,
    features: features,
  );
}

MvtFeature _decodeFeature(
  Uint8List bytes,
  List<String> keys,
  List<Object?> values,
) {
  final reader = PbfReader(bytes);
  int? id;
  var type = MvtGeomType.unknown;
  var tags = const <int>[];
  var geometry = const <int>[];

  while (!reader.isAtEnd) {
    final tag = reader.readTag();
    final field = tag >>> 3;
    final wire = tag & 0x7;
    switch (field) {
      case 1:
        id = reader.readVarint();
        break;
      case 2:
        tags = _readPackedVarints(reader, wire);
        break;
      case 3:
        final raw = reader.readVarint();
        type = raw >= 0 && raw < MvtGeomType.values.length
            ? MvtGeomType.values[raw]
            : MvtGeomType.unknown;
        break;
      case 4:
        geometry = _readPackedVarints(reader, wire);
        break;
      default:
        reader.skip(wire);
    }
  }

  final properties = <String, Object?>{};
  for (var i = 0; i + 1 < tags.length; i += 2) {
    final keyIndex = tags[i];
    final valueIndex = tags[i + 1];
    if (keyIndex >= 0 && keyIndex < keys.length) {
      properties[keys[keyIndex]] =
          valueIndex >= 0 && valueIndex < values.length
              ? values[valueIndex]
              : null;
    }
  }

  return MvtFeature(
    id: id,
    type: type,
    properties: properties,
    geometry: decodeMvtGeometry(geometry),
  );
}

Object? _decodeValue(PbfReader reader) {
  while (!reader.isAtEnd) {
    final tag = reader.readTag();
    final field = tag >>> 3;
    switch (field) {
      case 1:
        return reader.readString();
      case 2:
        return reader.readFloat();
      case 3:
        return reader.readDouble();
      case 4:
        return reader.readVarint();
      case 5:
        return reader.readVarint();
      case 6:
        return reader.readSVarint();
      case 7:
        return reader.readVarint() != 0;
      default:
        reader.skip(tag & 0x7);
    }
  }
  return null;
}

/// MVT encodes `tags` and `geometry` packed (wire type 2), but the proto
/// definition allows a non-packed repeated field (wire type 0) too.
List<int> _readPackedVarints(PbfReader reader, int wire) {
  if (wire == 0) return [reader.readVarint()];
  final sub = reader.readMessage();
  final out = <int>[];
  while (!sub.isAtEnd) {
    out.add(sub.readVarint());
  }
  return out;
}

/// Decodes the MVT geometry command stream into rings.
///
/// Command ids: 1 = MoveTo (starts a ring), 2 = LineTo, 7 = ClosePath.
/// MoveTo/LineTo payloads are zigzag delta pairs; coordinates accumulate.
List<List<Vec2>> decodeMvtGeometry(List<int> commands) {
  final rings = <List<Vec2>>[];
  var current = <Vec2>[];
  var x = 0;
  var y = 0;
  var i = 0;

  void addPoint(int dx, int dy) {
    x += dx;
    y += dy;
    current.add(Vec2(x.toDouble(), y.toDouble()));
  }

  int param() {
    if (i >= commands.length) {
      throw const FormatException('MVT: geometry command truncated');
    }
    return commands[i++];
  }

  while (i < commands.length) {
    final command = commands[i++];
    final id = command & 0x7;
    final count = command >> 3;
    switch (id) {
      case 1: // MoveTo starts a new ring
        if (current.isNotEmpty) {
          rings.add(current);
          current = <Vec2>[];
        }
        for (var k = 0; k < count; k++) {
          addPoint(_zigzag(param()), _zigzag(param()));
        }
        break;
      case 2: // LineTo extends the current ring
        if (current.isEmpty) {
          throw const FormatException('MVT: LineTo before MoveTo');
        }
        for (var k = 0; k < count; k++) {
          addPoint(_zigzag(param()), _zigzag(param()));
        }
        break;
      case 7: // ClosePath
        if (current.isNotEmpty) {
          final first = current.first;
          final last = current.last;
          if (first.x != last.x || first.y != last.y) {
            current.add(first);
          }
          rings.add(current);
          current = <Vec2>[];
        }
        break;
      default:
        throw FormatException('MVT: unknown geometry command $id');
    }
  }

  if (current.isNotEmpty) rings.add(current);
  return rings;
}

int _zigzag(int value) => (value >>> 1) ^ -(value & 1);

/// Signed area using the same shoelace variant as maplibre-native
/// (`geometry_tile_data.cpp:26-36`). Only the sign matters: it tells outer
/// rings from holes when grouping a polygon's rings.
double mvtRingSignedArea(List<Vec2> ring) {
  var sum = 0.0;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    sum += (ring[j].x - ring[i].x) * (ring[i].y + ring[j].y);
  }
  return sum;
}

/// Groups a flat ring list into polygons (outer ring first, then holes).
///
/// Direct port of maplibre-native `classifyRings`
/// (`geometry_tile_data.cpp:79-115`): consecutive rings of the same
/// orientation belong to one polygon; a sign flip starts the next one.
List<List<List<Vec2>>> classifyMvtPolygonRings(List<List<Vec2>> rings) {
  if (rings.length <= 1) return [rings];

  final polygons = <List<List<Vec2>>>[];
  var polygon = <List<Vec2>>[];
  var orientation = 0;

  for (final ring in rings) {
    final area = mvtRingSignedArea(ring);
    if (area == 0) continue;
    final sign = area < 0 ? -1 : 1;
    if (orientation == 0) orientation = sign;
    if (orientation == sign && polygon.isNotEmpty) {
      polygons.add(polygon);
      polygon = <List<Vec2>>[];
    }
    polygon.add(ring);
  }

  if (polygon.isNotEmpty) polygons.add(polygon);
  return polygons;
}
