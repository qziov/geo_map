/// Web stub for [MbtilesStore].
///
/// Keeps the type in the public API so code that mentions it still compiles on
/// web, and fails loudly at the call site instead of at build time. Mirrors
/// `mbtiles_source_stub.dart`: the real reader needs `dart:io` + `sqlite3`,
/// neither of which exists in a browser.
library;

import 'dart:typed_data';

class MbtilesStore {
  static const String _message =
      'MBTiles 需要 dart:io 与 sqlite3，浏览器里不可用。';

  static Future<MbtilesStore?> fromAsset({
    required String assetPath,
    required String cacheDirName,
  }) async =>
      throw UnsupportedError(_message);

  static MbtilesStore? openFile(String path) => throw UnsupportedError(_message);

  Uint8List? tile(int z, int x, int yTms) => throw UnsupportedError(_message);

  String? metadata(String name) => throw UnsupportedError(_message);

  (int?, int?) get tileLevels => throw UnsupportedError(_message);

  void dispose() {}
}
