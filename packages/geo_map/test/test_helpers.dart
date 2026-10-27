import 'dart:ui' as ui;

import 'package:geo_map/src/style/symbol_painter.dart';

/// Counts non-transparent pixels in a rasterized image.
///
/// Lets a test prove the painter actually emitted draw calls, not just decided
/// placements — a `Picture` that only ran collision math and drew nothing would
/// produce a fully transparent image.
Future<int> countOpaquePixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return 0;
  var opaque = 0;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i + 3) > 0) opaque++;
  }
  return opaque;
}

/// Rasterizes [symbols] through [SymbolPainter] onto an off-screen 800×600
/// surface and returns the image, so a test can inspect the actual pixels.
Future<ui.Image> renderSymbols(
  SymbolPainter painter,
  List<SymbolSpec> symbols, {
  int width = 800,
  int height = 600,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  painter.paint(canvas, symbols);
  return recorder.endRecording().toImage(width, height);
}
