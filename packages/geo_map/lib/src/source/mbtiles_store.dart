/// Content-agnostic MBTiles reader shared by the SDK and the app.
///
/// ## What belongs here
///
/// Only "turn an asset into a queryable read-only database" and "read the raw
/// bytes of one tile". Everything that interprets those bytes stays in the
/// caller: [MbtilesTileSource] decompresses gzipped MVT, the app's raster
/// adapter feeds PNG/JPEG straight to the image codec.
///
/// This is why the store takes a **TMS** row, not an XYZ row. MBTiles stores
/// rows bottom-up; callers own the flip (the SDK uses core `TileGrid`, the app
/// uses its pure-Dart `tmsRowFor`). Both compute `(1 << z) - 1 - y`.
///
/// ## Why it lives in `geo_map`, not `geo_map_core`
///
/// `geo_map_core` is pure Dart (no Flutter, only `latlong2`). This reader needs
/// `dart:io`, `sqlite3`, `path_provider` and `rootBundle`.
///
/// ## Two entry points
///
/// * [fromAsset] — full pipeline: copy the bundled asset to a writable dir,
///   verify/repair the cached copy, convert WAL to rollback journal, open.
/// * [openFile] — open an already-on-disk database. Kept public so the app's
///   `MbtilesHandle.openFile` and its pure-file unit tests stay intact.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// A read-only handle to one MBTiles database.
class MbtilesStore {
  MbtilesStore._(this._db);

  final Database _db;
  bool _disposed = false;

  /// Open an already-on-disk MBTiles file.
  ///
  /// Returns `null` when the file is missing, is not SQLite, or has no `tiles`
  /// table/view. A missing tile is a normal condition, but an invalid database
  /// is not — callers use this `null` to decide whether to self-heal.
  static MbtilesStore? openFile(String path) {
    if (!File(path).existsSync()) return null;
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      // MBTiles spec allows `tiles` to be a VIEW, not just a TABLE.
      final rows = db.select(
        "SELECT name FROM sqlite_master "
        "WHERE name='tiles' AND type IN ('table','view')",
      );
      if (rows.isEmpty) {
        db.dispose();
        return null;
      }
      final store = MbtilesStore._(db);
      db = null; // ownership transferred to the store
      return store;
    } catch (e) {
      debugPrint('[geo_map:mbtiles] open failed: $path -> $e');
      db?.dispose();
      return null;
    }
  }

  /// Copy a bundled MBTiles asset into `<documents>/[cacheDirName]/` and open it.
  ///
  /// Returns `null` only when the **asset itself is missing** — the app treats
  /// that as "package not shipped yet, skip silently", while the SDK turns it
  /// into a [StateError]. Any other failure throws.
  ///
  /// The cached copy is **content-verified against the asset on every open**
  /// (size first, then a chunked byte compare). Re-shipping an updated asset
  /// under the same filename therefore replaces a stale cache automatically —
  /// no manual cache clearing, no id versioning. The two SQLite header bytes
  /// at offsets 18/19 are excluded because [toRollbackJournal] legitimately
  /// rewrites them (WAL -> DELETE).
  static Future<MbtilesStore?> fromAsset({
    required String assetPath,
    required String cacheDirName,
  }) async {
    final ByteData loaded;
    try {
      loaded = await rootBundle.load(assetPath);
    } catch (_) {
      debugPrint('[geo_map:mbtiles] asset missing: $assetPath');
      return null;
    }
    final bytes = Uint8List.sublistView(
        loaded, loaded.offsetInBytes, loaded.lengthInBytes);

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, cacheDirName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final target = File(p.join(dir.path, p.basename(assetPath)));

    debugPrint('[geo_map:mbtiles] open: $assetPath -> $cacheDirName/');
    if (!_matchesAsset(target, bytes)) {
      debugPrint('[geo_map:mbtiles] cache missing/stale — re-copying');
      _deleteTrio(target);
      await _writeCopy(target, bytes, assetPath);
      _toRollbackJournal(target.path);
      debugPrint('[geo_map:mbtiles] copied ${target.lengthSync()} bytes');
    } else {
      debugPrint('[geo_map:mbtiles] cache matches asset '
          '(${target.lengthSync()} bytes)');
    }

    var store = openFile(target.path);
    if (store == null) {
      // Corrupt cache copy (interrupted copy / orphaned -wal or -shm):
      // delete the trio and re-copy once. Self-heal instead of staying broken.
      debugPrint('[geo_map:mbtiles] cache copy corrupt — self-healing');
      _deleteTrio(target);
      await _writeCopy(target, bytes, assetPath);
      _toRollbackJournal(target.path);
      store = openFile(target.path);
      if (store == null) {
        throw StateError('MBTiles re-copy still has no tiles table: $assetPath');
      }
    }
    return store;
  }

  static Future<void> _writeCopy(
      File target, Uint8List bytes, String assetPath) async {
    await target.writeAsBytes(bytes, flush: true);
    if (target.lengthSync() != bytes.length) {
      await target.delete();
      throw StateError('MBTiles copy incomplete: $assetPath');
    }
  }

  /// Whether the cached copy is byte-identical to the asset.
  /// Header offsets 18/19 (journal mode) are excluded, see [fromAsset].
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

  /// MBTiles assets are often in WAL mode. We copy only the main file (no
  /// `-wal` sidecar); a read-only connection then cannot build `-shm`/`-wal`
  /// and refuses to open. Converting to DELETE once removes that trap.
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

  /// Delete the main file plus `-wal` and `-shm`. Deleting only the main file
  /// leaves orphan sidecars that will corrupt the next copy too.
  static void _deleteTrio(File db) {
    for (final suffix in const ['', '-wal', '-shm']) {
      try {
        final f = File('${db.path}$suffix');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  /// Raw bytes for one tile. [yTms] must already be flipped to the TMS axis.
  ///
  /// Returns `null` for "no such tile" (ocean, uncached region) — a normal,
  /// frequent outcome. Does **not** decompress: gzip handling belongs to the
  /// vector adapter, raster adapters want the bytes untouched.
  ///
  /// A **database error is thrown, not swallowed**. Callers need to tell
  /// "there is no tile" (cache the miss) from "the query broke" (let the engine
  /// retry with the short network TTL). Both existing adapters already wrap
  /// this call in their own try/catch for exactly that reason.
  Uint8List? tile(int z, int x, int yTms) {
    if (_disposed) return null;
    final rows = _db.select(
      'SELECT tile_data FROM tiles '
      'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
      [z, x, yTms],
    );
    if (rows.isEmpty) return null;
    final data = rows.first['tile_data'];
    return data is Uint8List ? data : null;
  }

  /// A `metadata` value, or `null` when the table/row is missing.
  String? metadata(String name) {
    if (_disposed) return null;
    try {
      final rows = _db.select(
          'SELECT value FROM metadata WHERE name = ?', [name]);
      if (rows.isEmpty) return null;
      final value = rows.first['value'];
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Actual zoom levels present in `tiles`, as `(min, max)`.
  ///
  /// `metadata.minzoom/maxzoom` often lies (a package may claim z1 while the
  /// z1 level has zero tiles). Prefer this data truth; the SDK uses it, the
  /// app intersects it with its declared package range instead.
  (int?, int?) get tileLevels {
    if (_disposed) return (null, null);
    try {
      final rows = _db.select(
          'SELECT DISTINCT zoom_level FROM tiles ORDER BY zoom_level ASC');
      final levels = [
        for (final row in rows)
          if (row['zoom_level'] is int) row['zoom_level'] as int,
      ];
      if (levels.isEmpty) return (null, null);
      debugPrint('[geo_map:mbtiles] real tile levels: '
          'z${levels.first}..${levels.last} (${levels.length} levels)');
      return (levels.first, levels.last);
    } catch (e) {
      debugPrint('[geo_map:mbtiles] real zoom scan failed: $e');
      return (null, null);
    }
  }

  /// Idempotent: a registry that is disposed twice must not double-close.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _db.dispose();
  }
}
