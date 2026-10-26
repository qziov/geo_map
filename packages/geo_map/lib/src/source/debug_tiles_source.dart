/// Debug tile sources for locating placement/coverage bugs.
///
/// 两种模式：
/// - `maplibreNumber`：maplibre 官方 debug 瓦片（`number/{z}.png`，每级一张
///   256px 整级图，印层级数字）——按 (x,y) 裁出子块，验证 zoom 映射与摆放；
/// - `labeled`：本地生成的 z/x/y 标注瓦片（零网络）——每块自报坐标，
///   黑区 = 坐标缺口，行翻转/偏移一眼可见。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../diagnostics/geo_diagnostics.dart';
import '../globe/tile_source.dart' show GlobeRasterSource, TileFetchResult;
import 'package:geo_map_core/geo_map_core.dart'
    show GeoEngineTuning, TileFailureKind, TileRowOrder, TileSchemeKind;

enum DebugTilesMode { maplibreNumber, labeled }

class DebugTilesSource implements GlobeRasterSource {
  DebugTilesSource.maplibreNumber({this.maxZoom = 22})
      : mode = DebugTilesMode.maplibreNumber,
        minZoom = 0;

  DebugTilesSource.labeled({this.maxZoom = 8})
      : mode = DebugTilesMode.labeled,
        minZoom = 0;

  final DebugTilesMode mode;

  static const _base =
      'https://demotiles.maplibre.org/debug-tiles/number';

  final Map<int, ui.Image> _sheets = {};

  @override
  final int minZoom;

  @override
  final int maxZoom;

  @override
  TileSchemeKind get scheme => TileSchemeKind.webMercator;

  /// The debug sheets are stored north-up (row 0 = northern edge).
  @override
  TileRowOrder get rowOrder => TileRowOrder.xyzTopDown;

  @override
  int get maxConcurrentRequests => GeoEngineTuning.maxParallelRequests;

  @override
  String get attribution =>
      mode == DebugTilesMode.maplibreNumber
          ? '© MapLibre debug tiles'
          : 'generated debug tiles';

  @override
  Future<TileFetchResult> fetch(int z, int x, int y) async {
    if (mode == DebugTilesMode.labeled) {
      if (GeoDiagnostics.traceOn) {
        debugPrint('[geo_map:debug] gen z=$z x=$x y=$y');
      }
      final png = await _labeledPng(z, x, y);
      return png == null
          ? const TileFetchResult.failed(TileFailureKind.decode)
          : TileFetchResult.ok(png);
    }

    final sheet = await _numberSheet(z);
    if (sheet == null) {
      return const TileFetchResult.failed(TileFailureKind.network);
    }
    final cols = 1 << z;
    final sw = sheet.width / cols;
    final sh = sheet.height / cols;
    final png = await _cropPng(sheet, Rect.fromLTWH(x * sw, y * sh, sw, sh));
    return png == null
        ? const TileFetchResult.failed(TileFailureKind.decode)
        : TileFetchResult.ok(png);
  }

  Future<ui.Image?> _numberSheet(int z) async {
    final existing = _sheets[z];
    if (existing != null) return existing;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse('$_base/$z.png'));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final builder = BytesBuilder();
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final codec = await ui.instantiateImageCodec(builder.takeBytes());
      final frame = await codec.getNextFrame();
      codec.dispose();
      return _sheets[z] = frame.image;
    } catch (e) {
      debugPrint('[geo_map:debug] number sheet $z failed: $e');
      return null;
    }
  }

  /// 裁切整级图子块并重编码为 PNG。
  Future<Uint8List?> _cropPng(ui.Image sheet, Rect src) async {
    final size = src.size;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, src);
    canvas.drawImageRect(
      sheet,
      src,
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
        size.width.round(), size.height.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data?.buffer.asUint8List();
  }

  /// 本地生成 z/x/y 标注瓦片：四象限底色 + 网格边框 + 大字坐标。
  Future<Uint8List?> _labeledPng(int z, int x, int y) async {
    try {
      return await _labeledPngInner(z, x, y);
    } catch (e) {
      debugPrint('[geo_map:debug] labeled $z/$x/$y FAILED: $e');
      return null;
    }
  }

  Future<Uint8List?> _labeledPngInner(int z, int x, int y) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, const Rect.fromLTWH(0, 0, 256, 256));
    const quadColors = [
      Color(0xFF2E7D32), // 左上 绿
      Color(0xFF1565C0), // 右上 蓝
      Color(0xFFF9A825), // 左下 黄
      Color(0xFFC62828), // 右下 红
    ];
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 128, 128), Paint()..color = quadColors[0]);
    canvas.drawRect(
        const Rect.fromLTWH(128, 0, 128, 128), Paint()..color = quadColors[1]);
    canvas.drawRect(
        const Rect.fromLTWH(0, 128, 128, 128), Paint()..color = quadColors[2]);
    canvas.drawRect(
        const Rect.fromLTWH(128, 128, 128, 128),
        Paint()..color = quadColors[3]);
    canvas.drawRect(
        const Rect.fromLTWH(2, 2, 252, 252),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFFFFFFFF));

    ui.Paragraph para(String text, double size) {
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.center),
      )
        ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF), fontSize: size))
        ..addText(text);
      final para = builder.build()..layout(const ui.ParagraphConstraints(width: 256));
      return para;
    }

    canvas.drawParagraph(para('z$z', 44), const Offset(0, 58));
    canvas.drawParagraph(para('x$x', 34), const Offset(0, 118));
    canvas.drawParagraph(para('y$y', 34), const Offset(0, 162));
    final picture = recorder.endRecording();
    final image = await picture.toImage(256, 256);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  void dispose() {
    for (final sheet in _sheets.values) {
      sheet.dispose();
    }
    _sheets.clear();
  }
}
