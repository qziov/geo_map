/// MBTiles raster source.
///
/// Copies the bundled asset to the app documents dir, converts it from WAL to
/// rollback-journal mode (a read-only WAL copy without its `-wal` sidecar cannot
/// be opened), and self-heals corrupted cache copies (delete main + `-wal` +
/// `-shm`, then re-copy on the next call).
///
/// The cached copy is **content-verified against the asset on every open**
/// (size + chunked byte compare) — re-shipping an updated asset under the same
/// filename replaces the stale cache automatically. This is what keeps the
/// vector basemap's bundled MBTiles and the on-disk cache in sync when only
/// the asset changes (e.g. adding a `land` layer to the same `world_borders.mbtiles`).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geo_map_core/geo_map_core.dart'
    show
        GeoEngineTuning,
        TileFailureKind,
        TileGrid,
        TileRowOrder,
        TileSchemeKind;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../globe/tile_source.dart' show GlobeRasterSource, TileFetchResult;

class MbtilesTileSource implements GlobeRasterSource {
  MbtilesTileSource._(this.id, this._db, this.minZoom, this.maxZoom);

  final Database _db;

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
  /// The cached copy in the documents dir is **content-verified against the
  /// asset on every open**: file size first (cheap reject), then a chunked
  /// byte compare. A re-shipped asset under the same filename therefore
  /// replaces a stale cache automatically — no manual cache clearing, no id
  /// versioning. Cost: one full asset read per open (fast for typical
  /// basemaps; the journal-mode header bytes are excluded from the compare,
  /// see [_matchesAsset]).
  static Future<MbtilesTileSource> open({
    required String id,
    required String assetPath,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'geo_map'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final target = File(p.join(dir.path, p.basename(assetPath)));

    debugPrint('[geo_map:mbtiles] open: $assetPath');
    final asset = await rootBundle.load(assetPath);
    final bytes =
        Uint8List.sublistView(asset, asset.offsetInBytes, asset.lengthInBytes);

    if (!_matchesAsset(target, bytes)) {
      debugPrint('[geo_map:mbtiles] cache missing/stale — re-copying');
      _deleteTrio(target);
      await target.writeAsBytes(bytes, flush: true);
      if (target.lengthSync() != bytes.length) {
        await target.delete();
        throw StateError('MBTiles copy incomplete: $assetPath');
      }
      _toRollbackJournal(target.path);
      debugPrint('[geo_map:mbtiles] copied ${target.lengthSync()} bytes');
    } else {
      debugPrint('[geo_map:mbtiles] cache matches asset '
          '(${target.lengthSync()} bytes)');
    }

    if (!_hasTilesTable(target.path)) {
      // Corrupt cache copy (historical interrupted copy / stale sidecars):
      // delete the trio and re-copy once.
      debugPrint('[geo_map:mbtiles] cache copy corrupt — self-healing');
      _deleteTrio(target);
      await target.writeAsBytes(bytes, flush: true);
      _toRollbackJournal(target.path);
      if (!_hasTilesTable(target.path)) {
        throw StateError('MBTiles re-copy still has no tiles table: $assetPath');
      }
    }

    final db = sqlite3.open(target.path, mode: OpenMode.readOnly);
    final meta = _readZoomRange(db);
    if (meta.$1 == null || meta.$2 == null) {
      debugPrint('[geo_map:mbtiles] WARNING: metadata zoom range missing '
          '(${meta.$1}, ${meta.$2}) — using 0..${GeoTileDefaults.maxZoom}');
    }
    debugPrint('[geo_map:mbtiles] ready z${meta.$1 ?? 0}-${meta.$2 ?? GeoTileDefaults.maxZoom}');
    return MbtilesTileSource._(
        id, db, meta.$1 ?? 0, meta.$2 ?? GeoTileDefaults.maxZoom);
  }

  /// Whether the cached copy is byte-identical to the asset.
  ///
  /// Journal-mode header bytes (SQLite header offsets 18/19) are excluded:
  /// [_toRollbackJournal] legitimately rewrites them on the cached copy, and
  /// comparing them would turn every open into a pointless re-copy. Size is
  /// checked first (cheap reject); bytes are then compared in 1 MiB chunks
  /// with early exit on the first difference.
  static bool _matchesAsset(File target, Uint8List asset) {
    if (!target.existsSync()) return false;
    if (target.lengthSync() != asset.length) return false;
    final raf = target.openSync(mode: FileMode.read);
    try {
      const chunkSize = 1 << 20;
      final buf = Uint8List(chunkSize);
      for (var offset = 0; offset < asset.length; offset += chunkSize) {
        var want = chunkSize;
        if (offset + want > asset.length) want = asset.length - offset;
        final got = raf.readIntoSync(buf, 0, want);
        if (got != want) return false;
        for (var i = 0; i < want; i++) {
          final pos = offset + i;
          if (pos == 18 || pos == 19) continue; // journal-mode bytes
          if (buf[i] != asset[pos]) return false;
        }
      }
      return true;
    } finally {
      raf.closeSync();
    }
  }

  static void _toRollbackJournal(String path) {
    Database? db;
    try {
      db = sqlite3.open(path);
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      db.execute('PRAGMA journal_mode = DELETE');
    } catch (_) {
      // Best effort — a non-WAL file simply keeps working.
    } finally {
      db?.dispose();
    }
  }

  static void _deleteTrio(File db) {
    for (final suffix in const ['', '-wal', '-shm']) {
      try {
        final f = File('${db.path}$suffix');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  static bool _hasTilesTable(String path) {
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      // mbtiles spec allows `tiles` to be a VIEW, not just a TABLE.
      final rows = db.select(
        "SELECT name FROM sqlite_master "
        "WHERE name='tiles' AND type IN ('table','view')",
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      db?.dispose();
    }
  }

  static (int?, int?) _readZoomRange(Database db) {
    // ★ 数据真值优先：metadata 常谎报（本库声称 z1 起，实际 z1 层 0 块），
    //   clamp 到谎报层级会让 under-zoom 全 miss → 黑瓦。取 tiles 表实际层级。
    int? minZ;
    int? maxZ;
    try {
      final rows = db.select(
        'SELECT DISTINCT zoom_level FROM tiles ORDER BY zoom_level ASC');
      final levels = [
        for (final row in rows)
          if (row['zoom_level'] is int) row['zoom_level'] as int,
      ];
      if (levels.isNotEmpty) {
        minZ = levels.first;
        maxZ = levels.last;
        debugPrint('[geo_map:mbtiles] real tile levels: z$minZ..z$maxZ '
            '(${levels.length} levels)');
      }
    } catch (e) {
      debugPrint('[geo_map:mbtiles] real zoom scan failed: $e');
    }
    // metadata 作为回退/对照
    try {
      final rows = db.select(
          "SELECT name, value FROM metadata WHERE name IN ('minzoom','maxzoom')");
      for (final row in rows) {
        final v = int.tryParse(row['value'] as String? ?? '');
        if (v == null) continue;
        if (row['name'] == 'minzoom') {
          minZ ??= v;
        } else if (row['name'] == 'maxzoom') {
          maxZ ??= v;
        }
      }
    } catch (_) {}
    return (minZ, maxZ);
  }

  @override
  Future<TileFetchResult> fetch(int z, int x, int y) async {
    if (z < minZoom || z > maxZoom) {
      return const TileFetchResult.failed(TileFailureKind.notFound);
    }
    // 行序统一由 core TileGrid.rowForFetch 处理（MBTiles = TMS 自下而上）。
    final wireRow = TileGrid.of(TileSchemeKind.webMercator, z,
            order: TileRowOrder.tmsBottomUp)
        .rowForFetch(y);
    try {
      final rows = _db.select(
        'SELECT tile_data FROM tiles '
        'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
        [z, x, wireRow],
      );
      if (rows.isEmpty) {
        return const TileFetchResult.failed(TileFailureKind.notFound);
      }
      final data = rows.first['tile_data'];
      if (data is! Uint8List || data.isEmpty) {
        return const TileFetchResult.failed(TileFailureKind.empty);
      }
      // tippecanoe 默认 gzip 压缩 MVT 再写入 MBTiles（HTTP 路径由 HttpClient
      // 自动解压，直读 sqlite 拿到的是原始 gzip 字节，不解压则全部解码失败）。
      // 按魔数 1F 8B 判定透传解压；栅格 png/jpg 无此魔数，原样返回。
      return TileFetchResult.ok(_maybeGunzip(data));
    } catch (e) {
      debugPrint('[geo_map:mbtiles] fetch error $z/$x/$y: $e');
      return const TileFetchResult.failed(TileFailureKind.network);
    }
  }

  /// 瓦片若是 gzip（魔数 `1F 8B`）则解压，否则原样返回。
  ///
  /// 覆盖两类场景：tippecanoe 默认 gzip 的 MVT（不解压则 MVT 解码必然失败），
  /// 以及个别工具 gzip 的栅格包。解压错误按原字节返回，交由上层解码报错——
  /// 坏瓦片的归因路径不变。
  static Uint8List _maybeGunzip(Uint8List data) {
    if (data.length >= 2 && data[0] == 0x1F && data[1] == 0x8B) {
      try {
        return Uint8List.fromList(GZipCodec().decode(data));
      } catch (_) {
        // 非法 gzip：原样交回，让 MVT/图像解码器给出一致错误路径。
        return data;
      }
    }
    return data;
  }

  @override
  void dispose() => _db.dispose();
}

abstract class GeoTileDefaults {
  static const int maxZoom = 18;
}
