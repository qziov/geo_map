import 'dart:typed_data';

import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

/// Hand-built tile: one layer `roads`, extent 4096, version 2, no features.
Uint8List _oneLayerTile() {
  final layer = <int>[
    0x0A, 0x05, 0x72, 0x6F, 0x61, 0x64, 0x73, // name "roads"
    0x28, 0x80, 0x20, // extent 4096
    0x78, 0x02, // version 2
  ];
  return Uint8List.fromList([
    0x1A, layer.length, // tile field 3, length-delimited
    ...layer,
  ]);
}

void main() {
  group('decodeMvtTileAsync', () {
    test('round-trips a decoded tile across the isolate boundary', () async {
      final tile = await decodeMvtTileAsync(_oneLayerTile());

      expect(tile.layers, hasLength(1));
      final layer = tile.layers.single;
      expect(layer.name, 'roads');
      expect(layer.extent, 4096);
      expect(layer.version, 2);
      expect(layer.features, isEmpty);
    });

    test('an empty payload decodes to an empty tile', () async {
      final tile = await decodeMvtTileAsync(Uint8List(0));
      expect(tile.layers, isEmpty);
    });
  });
}
