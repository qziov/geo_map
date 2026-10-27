/// Minimal protobuf wire reader (varint / length-delimited / fixed32 / fixed64).
///
/// Only the subset the Mapbox Vector Tile schema needs. Self-contained so
/// `geo_map_core` keeps zero third-party dependencies for the decode path
/// (mirrors how maplibre-native vendors `protozero` rather than pulling a
/// general protobuf runtime).
library;

import 'dart:convert';
import 'dart:typed_data';

class PbfReader {
  PbfReader(this._buf, [this.pos = 0]);

  final Uint8List _buf;
  int pos;

  bool get isAtEnd => pos >= _buf.length;

  /// Reads a base-128 varint (unsigned).
  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (pos >= _buf.length) {
        throw const FormatException('pbf: unexpected EOF while reading varint');
      }
      final byte = _buf[pos++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
      if (shift > 63) {
        throw const FormatException('pbf: varint longer than 64 bits');
      }
    }
    return result;
  }

  /// Reads a zigzag-encoded signed varint.
  int readSVarint() {
    final value = readVarint();
    return (value >>> 1) ^ -(value & 1);
  }

  /// Reads a field tag; callers split it with `tag >>> 3` / `tag & 0x7`.
  int readTag() => readVarint();

  /// Reads a length-delimited blob as a view (no copy).
  Uint8List readBytes() {
    final length = readVarint();
    if (pos + length > _buf.length) {
      throw const FormatException('pbf: length-delimited field past end');
    }
    final view = Uint8List.sublistView(_buf, pos, pos + length);
    pos += length;
    return view;
  }

  String readString() => utf8.decode(readBytes(), allowMalformed: true);

  double readFloat() {
    _require(4);
    final value =
        ByteData.sublistView(_buf, pos, pos + 4).getFloat32(0, Endian.little);
    pos += 4;
    return value;
  }

  double readDouble() {
    _require(8);
    final value =
        ByteData.sublistView(_buf, pos, pos + 8).getFloat64(0, Endian.little);
    pos += 8;
    return value;
  }

  /// Reads a length-delimited embedded message into its own reader.
  PbfReader readMessage() {
    final length = readVarint();
    if (pos + length > _buf.length) {
      throw const FormatException('pbf: embedded message past end');
    }
    final view = Uint8List.sublistView(_buf, pos, pos + length);
    pos += length;
    return PbfReader(view);
  }

  /// Skips a field of the given protobuf wire type.
  void skip(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 1:
        _advance(8);
        break;
      case 2:
        _advance(readVarint());
        break;
      case 5:
        _advance(4);
        break;
      default:
        throw FormatException('pbf: unsupported wire type $wireType');
    }
  }

  void _advance(int count) {
    _require(count);
    pos += count;
  }

  void _require(int count) {
    if (pos + count > _buf.length) {
      throw const FormatException('pbf: unexpected EOF');
    }
  }
}
