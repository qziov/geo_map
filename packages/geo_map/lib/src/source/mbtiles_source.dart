/// MBTiles raster source.
///
/// Copies the bundled asset to the app documents dir, converts it from WAL to
/// rollback-journal mode (a read-only WAL copy without its `-wal` sidecar cannot
/// be opened), and self-heals corrupted cache copies (delete main + `-wal` +
/// `-shm`, then re-copy on the next call).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../globe/tile_source.dart' show GlobeRasterSource, TileScheme;

class MbtilesTileSource implements GlobeRasterSource {
  MbtilesTileSource._(this.id, this._db, this.minZoom, this.maxZoom);

  final Database _db;

  final String id;

  @override
  final int minZoom;

  @override
  final int maxZoom;

  @override
  TileScheme get scheme => TileScheme.webMercator;

  @override
  String get attribution => 'MBTiles: $id';

  /// Open (and lazily copy) an MBTiles asset.
  static Future<MbtilesTileSource> open({
    required String id,
    required String assetPath,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'geo_map'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final target = File(p.join(dir.path, p.basename(assetPath)));

    debugPrint('[geo_map:mbtiles] open: $assetPath');
    if (!target.existsSync()) {
      final bytes = await rootBundle.load(assetPath);
      await target.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      if (target.lengthSync() != bytes.lengthInBytes) {
        await target.delete();
        throw StateError('MBTiles copy incomplete: $assetPath');
      }
      _toRollbackJournal(target.path);
      debugPrint('[geo_map:mbtiles] copied ${target.lengthSync()} bytes');
    }

    if (!_hasTilesTable(target.path)) {
      // Corrupt cache copy (historical interrupted copy / stale sidecars):
      // delete the trio and re-copy once.
      debugPrint('[geo_map:mbtiles] cache copy corrupt — self-healing');
      _deleteTrio(target);
      final bytes = await rootBundle.load(assetPath);
      await target.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
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
    try {
      final rows = db
          .select("SELECT name, value FROM metadata WHERE name IN ('minzoom','maxzoom')");
      int? minZ, maxZ;
      for (final row in rows) {
        final v = int.tryParse(row['value'] as String? ?? '');
        if (row['name'] == 'minzoom') minZ = v;
        if (row['name'] == 'maxzoom') maxZ = v;
      }
      return (minZ, maxZ);
    } catch (_) {
      return (null, null);
    }
  }

  @override
  Future<Uint8List?> fetch(int z, int x, int y) async {
    if (z < minZoom || z > maxZoom) return null;
    final tms = (1 << z) - 1 - y; // XYZ → TMS
    try {
      final rows = _db.select(
        'SELECT tile_data FROM tiles '
        'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
        [z, x, tms],
      );
      if (rows.isEmpty) return null;
      final data = rows.first['tile_data'];
      return data is Uint8List ? data : null;
    } catch (e) {
      debugPrint('[geo_map:mbtiles] fetch error $z/$x/$y: $e');
      return null;
    }
  }

  void dispose() => _db.dispose();
}

abstract class GeoTileDefaults {
  static const int maxZoom = 18;
}
