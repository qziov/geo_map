/// A deliberately quiet base map, generated on the fly — no network, no assets.
///
/// The package's `DebugTilesSource.labeled` is excellent for finding placement
/// bugs (it prints `z/x/y` all over the tile), but as a *backdrop* for vector
/// layers it is far too loud: solid primary colours fight with the data.
///
/// This source keeps only what a demo backdrop needs: a dark fill, a hairline
/// tile border (so you can see where tiles meet) and a small `z/x/y` label in
/// the corner. Tiles are encoded to PNG once and cached.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:geo_map/geo_map.dart';

class GridTileSource implements GeoTileSource {
  GridTileSource({
    this.maxZoom = 8,
    this.minZoom = 0,
    this.size = 256,
    this.fill = const Color(0xFF0E1116),
    this.line = const Color(0xFF1E2733),
    this.label = const Color(0xFF2C3A4B),
  });

  @override
  final int minZoom;

  @override
  final int maxZoom;

  final int size;
  final Color fill;
  final Color line;
  final Color label;

  final Map<String, Uint8List> _cache = {};

  @override
  TileSchemeKind get scheme => TileSchemeKind.webMercator;

  @override
  TileRowOrder get rowOrder => TileRowOrder.xyzTopDown;

  @override
  int get maxConcurrentRequests => GeoEngineTuning.maxParallelRequests;

  @override
  String get attribution => 'generated';

  @override
  Future<TileFetchResult> fetch(int z, int x, int y) async {
    final key = '$z/$x/$y';
    final cached = _cache[key];
    if (cached != null) return TileFetchResult.ok(cached);
    final png = await _paint(z, x, y);
    if (png == null) {
      return const TileFetchResult.failed(TileFailureKind.decode);
    }
    return TileFetchResult.ok(_cache[key] = png);
  }

  Future<Uint8List?> _paint(int z, int x, int y) async {
    final side = size.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, side, side));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, side, side),
      Paint()..color = fill,
    );
    // Hairline on the north and west edges only: two tiles sharing an edge then
    // draw it once instead of twice, so the seam stays 1 px instead of 2.
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0, 0), Offset(side, 0), stroke);
    canvas.drawLine(const Offset(0, 0), Offset(0, side), stroke);

    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: 10,
      textAlign: TextAlign.left,
    ))
      ..pushStyle(ui.TextStyle(color: label))
      ..addText('$z/$x/$y');
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: side));
    canvas.drawParagraph(paragraph, const Offset(6, 6));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  void dispose() => _cache.clear();
}
