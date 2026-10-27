/// Web stub for [MbtilesTileSource].
///
/// MBTiles needs `dart:io` (copying the asset to a writable file) **and**
/// sqlite3 (a native library). Neither exists in a browser, so the real
/// implementation cannot be compiled for web — it would drag `dart:io` into the
/// export graph and break the whole package.
///
/// This stub keeps the type in the public API so code that mentions it still
/// compiles, and fails loudly at the call site instead of at build time. The
/// `example` app lists MBTiles under "native only" for exactly this reason.
library;

import 'package:geo_map_core/geo_map_core.dart'
    show GeoEngineTuning, GeoTileSource, TileRowOrder, TileSchemeKind;

/// Always throws: MBTiles is native-only.
class MbtilesTileSource implements GeoTileSource {
  MbtilesTileSource._(this.id, this.minZoom, this.maxZoom);

  final String id;

  @override
  final int minZoom;

  @override
  final int maxZoom;

  @override
  TileSchemeKind get scheme => TileSchemeKind.webMercator;

  @override
  TileRowOrder get rowOrder => TileRowOrder.tmsBottomUp;

  @override
  int get maxConcurrentRequests => GeoEngineTuning.sqliteParallelRequests;

  @override
  String get attribution => 'MBTiles: $id';

  static const String _message =
      'MBTiles 需要 dart:io 与 sqlite3，浏览器里不可用。'
      '请用 native 入口运行：flutter run -t lib/native/mbtiles_demo.dart';

  /// Always throws [UnsupportedError].
  static Future<MbtilesTileSource> open({
    required String id,
    required String assetPath,
  }) async =>
      throw UnsupportedError(_message);

  @override
  Future<Never> fetch(int z, int x, int y) async => throw UnsupportedError(_message);

  @override
  void dispose() {}
}
