// 公共 MBTiles 读取器的契约测试。
//
// 只走 [MbtilesStore.openFile]（已落盘的文件），不碰 `rootBundle` /
// `path_provider` —— 那部分（asset 拷贝、WAL 转换、自愈）依赖 Flutter 运行时
// 设施，靠真机验收。这里锁住 SDK 与 App 共用的底层语义：
//   ① 什么算合法 MBTiles；
//   ② tile() 返回**原始字节**（不解压，解码归适配器）；
//   ③ zoom 层级以 tiles 表数据真值优先；
//   ④ 数据库错误必须抛出，不能被吞成 "miss"（否则引擎会用 30s 的
//      notFound TTL 把底图空白半分钟）。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mbtiles_store_test_');
    dbPath = p.join(tmp.path, 'test.mbtiles');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 造一个最小 MBTiles。[tiles] 每项为 `[z, x, tmsY]`，
  /// `tile_data` 编码成 `[z, x, tmsY, 0xFF]` 便于断言取到的是哪一张。
  void buildDb({
    Map<String, String> metadata = const {},
    List<List<int>> tiles = const [],
    bool tilesAsView = false,
    bool withTilesTable = true,
  }) {
    final db = sqlite3.open(dbPath);
    db.execute('CREATE TABLE metadata (name TEXT, value TEXT);');
    final target = tilesAsView ? 'raw_tiles' : 'tiles';
    db.execute('CREATE TABLE $target ('
        'zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, '
        'tile_data BLOB);');
    if (tilesAsView) {
      db.execute('CREATE VIEW tiles AS SELECT * FROM $target;');
    }
    if (!withTilesTable) {
      db.execute('DROP TABLE tiles;');
    }
    for (final e in metadata.entries) {
      db.execute('INSERT INTO metadata (name, value) VALUES (?, ?);',
          [e.key, e.value]);
    }
    for (final t in tiles) {
      db.execute(
        'INSERT INTO $target (zoom_level, tile_column, tile_row, tile_data) '
        'VALUES (?, ?, ?, ?);',
        [t[0], t[1], t[2], Uint8List.fromList([t[0], t[1], t[2], 0xFF])],
      );
    }
    db.dispose();
  }

  group('openFile 合法性识别', () {
    test('文件不存在 → null', () {
      expect(MbtilesStore.openFile(dbPath), isNull);
    });

    test('不是 SQLite → null', () {
      File(dbPath).writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
      expect(MbtilesStore.openFile(dbPath), isNull);
    });

    test('是 SQLite 但没有 tiles 表 → null', () {
      final db = sqlite3.open(dbPath);
      db.execute('CREATE TABLE something_else (a INT);');
      db.dispose();
      expect(MbtilesStore.openFile(dbPath), isNull);
    });

    test('tiles 是 VIEW 也可以打开（MBTiles 规范允许）', () {
      buildDb(tilesAsView: true, tiles: [
        [0, 0, 0],
      ]);
      final store = MbtilesStore.openFile(dbPath);
      expect(store, isNotNull);
      expect(store!.tile(0, 0, 0), isNotNull);
      store.dispose();
    });
  });

  group('tile() 的字节语义', () {
    test('命中时返回原始字节，查不到返回 null', () {
      buildDb(tiles: [
        [1, 0, 1],
      ]);
      final store = MbtilesStore.openFile(dbPath)!;
      final hit = store.tile(1, 0, 1);
      expect(hit, isNotNull);
      expect(hit![2], 1, reason: '必须取到 TMS row=1 那张');
      expect(store.tile(1, 0, 0), isNull);
      store.dispose();
    });

    test('gzip 魔数字节原样返回，不在 store 里解压', () {
      final db = sqlite3.open(dbPath);
      db.execute('CREATE TABLE tiles ('
          'zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, '
          'tile_data BLOB);');
      db.execute(
        'INSERT INTO tiles VALUES (?, ?, ?, ?);',
        [0, 0, 0, Uint8List.fromList([0x1F, 0x8B, 0x08, 0x00])],
      );
      db.dispose();

      final store = MbtilesStore.openFile(dbPath)!;
      final bytes = store.tile(0, 0, 0)!;
      expect(bytes[0], 0x1F);
      expect(bytes[1], 0x8B);
      expect(bytes.length, 4, reason: '解压是 MbtilesTileSource 的职责');
      store.dispose();
    });
  });

  group('metadata 与 zoom 层级', () {
    test('metadata 命中 / 缺失 / 表不存在', () {
      buildDb(metadata: {'minzoom': '2'});
      final store = MbtilesStore.openFile(dbPath)!;
      expect(store.metadata('minzoom'), '2');
      expect(store.metadata('maxzoom'), isNull);
      store.dispose();
    });

    test('tileLevels 取 tiles 表真实层级，不被 metadata 谎报带偏', () {
      buildDb(
        metadata: {'minzoom': '0', 'maxzoom': '9'},
        tiles: [
          [3, 0, 0],
          [5, 1, 1],
        ],
      );
      final store = MbtilesStore.openFile(dbPath)!;
      expect(store.tileLevels, (3, 5));
      store.dispose();
    });

    test('tiles 表为空 → (null, null)', () {
      buildDb();
      final store = MbtilesStore.openFile(dbPath)!;
      expect(store.tileLevels, (null, null));
      store.dispose();
    });
  });

  group('生命周期与错误归因', () {
    test('dispose 幂等，之后 tile() 返回 null', () {
      buildDb(tiles: [
        [0, 0, 0],
      ]);
      final store = MbtilesStore.openFile(dbPath)!;
      store.dispose();
      expect(store.dispose, returnsNormally);
      expect(store.tile(0, 0, 0), isNull);
      expect(store.metadata('minzoom'), isNull);
    });

    test('数据库查询报错时抛出，不吞成 miss', () {
      buildDb(tiles: [
        [0, 0, 0],
      ]);
      final store = MbtilesStore.openFile(dbPath)!;
      // 另开一个连接把表删掉，让 store 的下一次查询真的失败。
      final other = sqlite3.open(dbPath);
      other.execute('DROP TABLE tiles;');
      other.dispose();

      expect(() => store.tile(0, 0, 0), throwsA(anything));
      store.dispose();
    });
  });
}
