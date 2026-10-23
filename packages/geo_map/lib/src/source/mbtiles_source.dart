/// MBTiles raster source.
///
/// Copies the bundled asset to the app documents dir, converts it from WAL to
/// rollback-journal mode (a read-only WAL copy without its `-wal` sidecar cannot
/// be opened), and self-heals corrupted cache copies (delete main + `-wal` +
/// `-shm`, then re-copy on the next call).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:geo_map_core/geo_map_core.dart' show TileSchemeKind;

import 'tile_source.dart';

class MbtilesTileSource implements GeoTileSource {
  MbtilesTileSource._(this.id, this._db, this.minZoom, this.maxZoom);

  final Database _db;

  @override
  final String id;

  @override
  final int minZoom;

  @override
  final int maxZoom;

  @override
  TileSchemeKind get scheme => TileSchemeKind.webMercator;

  /// Open (and lazily copy) an MBTiles asset.
  static Future<MbtilesTileSource> open({
    required String id,
    required String assetPath,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'geo_map'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final target = File(p.join(dir.path, p.basename(assetPath)));

    if (!target.existsSync()) {
      final bytes = await rootBundle.load(assetPath);
      await target.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      if (target.lengthSync() != bytes.lengthInBytes) {
        await target.delete();
        throw StateError('MBTiles copy incomplete: $assetPath');
      }
      _toRollbackJournal(target.path);
    }

    if (!_hasTilesTable(target.path)) {
      // Corrupt cache copy (historical interrupted copy / stale sidecars):
      // delete the trio and re-copy once.
      _deleteTrio(target);
      final bytes = await rootBundle.load(assetPath);
      await target.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      _toRollbackJournal(target.path);
    }

    final db = sqlite3.open(target.path, mode: OpenMode.readOnly);
    final meta = _readZoomRange(db);
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
      final rows = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='tiles'",
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
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() => _db.dispose();
}

abstract class GeoTileDefaults {
  static const int maxZoom = 18;
}
