/// MBTiles tile source (thin adapter over the shared [MbtilesStore]).
///
/// All the file plumbing — asset copy, content verification, WAL -> rollback
/// journal conversion, sidecar cleanup, read-only sqlite handle — lives in
/// `mbtiles_store.dart` so the SDK and the app share exactly one
/// implementation. This file keeps only what is specific to the vector path:
///
/// * zoom range resolved from the **actual tile levels** (data truth first,
///   `metadata` as fallback), which avoids a lying `minzoom` causing a whole
///   band of under-zoom misses;
/// * XYZ -> TMS row flip via core `TileGrid.rowForFetch`;
/// * gzip transparent decompression (tippecanoe gzips MVT before writing it
///   into MBTiles; an HTTP source would be decompressed by `HttpClient`, but
///   a direct sqlite read gets the raw gzip bytes);
/// * mapping missing/empty tiles to the engine's failure kinds.
///
/// `open(id, assetPath)` keeps its original signature for API compatibility.
library;

import 'dart:io' show GZipCodec;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geo_map_core/geo_map_core.dart'
    show
        GeoEngineTuning,
        TileFailureKind,
        TileGrid,
        TileRowOrder,
        TileSchemeKind;

import '../globe/tile_source.dart' show GlobeRasterSource, TileFetchResult;
import 'mbtiles_store.dart';

class MbtilesTileSource implements GlobeRasterSource {
  MbtilesTileSource._(this.id, this._store, this.minZoom, this.maxZoom);

  final MbtilesStore _store;

  final String id;

  @override
  final int minZoom;

  @override
  final int maxZoom;

  @override
  TileSchemeKind get scheme => TileSchemeKind.webMercator;

  /// MBTiles stores rows bottom-up (TMS convention).
  @override
  TileRowOrder get rowOrder => TileRowOrder.tmsBottomUp;

  /// One sqlite file handle — parallel reads do not help.
  @override
  int get maxConcurrentRequests => GeoEngineTuning.sqliteParallelRequests;

  @override
  String get attribution => 'MBTiles: $id';

  /// Open (and lazily copy) an MBTiles asset.
  ///
  /// Signature is unchanged. Throws [StateError] when the asset is missing or
  /// the cached copy cannot be repaired — the caller (`FutureProvider` in the
  /// app) surfaces this as a visible basemap error instead of a silent blank.
  static Future<MbtilesTileSource> open({
    required String id,
    required String assetPath,
  }) async {
    final store = await MbtilesStore.fromAsset(
      assetPath: assetPath,
      cacheDirName: 'geo_map',
    );
    if (store == null) {
      throw StateError('MBTiles asset not found: $assetPath');
    }

    // Data truth first: `metadata` commonly claims a minzoom whose level has
    // zero tiles. Clamping to it makes every under-zoom request miss.
    final (minTile, maxTile) = store.tileLevels;
    var minZ = minTile;
    var maxZ = maxTile;
    minZ ??= int.tryParse(store.metadata('minzoom') ?? '');
    maxZ ??= int.tryParse(store.metadata('maxzoom') ?? '');
    final effectiveMin = minZ ?? 0;
    final effectiveMax = maxZ ?? GeoTileDefaults.maxZoom;
    if (minZ == null || maxZ == null) {
      debugPrint('[geo_map:mbtiles] WARNING: zoom range incomplete '
          '($minZ, $maxZ) — using 0..${GeoTileDefaults.maxZoom}');
    }
    debugPrint('[geo_map:mbtiles] ready z$effectiveMin-$effectiveMax');
    return MbtilesTileSource._(id, store, effectiveMin, effectiveMax);
  }

  @override
  Future<TileFetchResult> fetch(int z, int x, int y) async {
    if (z < minZoom || z > maxZoom) {
      return const TileFetchResult.failed(TileFailureKind.notFound);
    }
    // Row order is handled by core TileGrid (MBTiles = TMS, bottom-up).
    final wireRow = TileGrid.of(TileSchemeKind.webMercator, z,
            order: TileRowOrder.tmsBottomUp)
        .rowForFetch(y);
    try {
      final bytes = _store.tile(z, x, wireRow);
      if (bytes == null) {
        return const TileFetchResult.failed(TileFailureKind.notFound);
      }
      if (bytes.isEmpty) {
        return const TileFetchResult.failed(TileFailureKind.empty);
      }
      return TileFetchResult.ok(_maybeGunzip(bytes));
    } catch (e) {
      // A real db error must use the short `network` TTL, not `notFound`
      // (30s), otherwise a transient failure blanks the basemap for a minute.
      debugPrint('[geo_map:mbtiles] fetch error $z/$x/$y: $e');
      return const TileFetchResult.failed(TileFailureKind.network);
    }
  }

  /// Decompress when the payload is gzip (magic `1F 8B`), else pass through.
  ///
  /// Covers tippecanoe's gzipped MVT (without this every MVT decode fails) and
  /// the occasional gzipped raster package. Raster PNG/JPEG never matches the
  /// magic. A corrupt gzip is returned as-is so the downstream decoder reports
  /// the error through the same attribution path as before.
  static Uint8List _maybeGunzip(Uint8List data) {
    if (data.length >= 2 && data[0] == 0x1F && data[1] == 0x8B) {
      try {
        return Uint8List.fromList(GZipCodec().decode(data));
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  @override
  void dispose() => _store.dispose();
}

abstract class GeoTileDefaults {
  static const int maxZoom = 18;
}
