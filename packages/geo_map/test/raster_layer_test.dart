/// Acceptance tests for `raster` as a style layer (T3).
///
/// T3 moves raster rendering into the shared [paintImageOverlay] function and the
/// two style renderers. These tests drive the actual rendering off-screen
/// (through [paintImageOverlay] + a `PictureRecorder`, the same mechanism the
/// existing symbol/vector tests use) so they inspect real pixels on both the 2D
/// Mercator fast path and the 3D orthographic sphere (Q2: 2D + 3D both
/// supported), plus the [GeoStyleController] image registry (A2) and the
/// style-renderer wiring (no throw on a `raster` layer).
library;

import 'dart:async';
import 'dart:math' show Point;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:geo_map/src/globe/image_overlay.dart'
    show ImageSource, paintImageOverlay;
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'test_helpers.dart';

const LatLng _center = LatLng(35.0, 104.0);

/// A solid orange image drawn through the engine's raster thread.
Future<ui.Image> _makeImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = ui.Color.fromRGBO(0xff, 0x80, 0x00, 1),
  );
  return recorder.endRecording().toImage(w, h);
}

MapCamera _camera({bool flat = true, LatLng center = _center, double zoom = 4.2}) =>
    MapCamera(
      crs: const Epsg3857(),
      center: center,
      zoom: zoom,
      rotation: 0,
      nonRotatedSize: const Point<double>(800, 600),
      // `null` delegate → globe/orthographic path; `FlatProjectionDelegate`
      // → 2D Mercator fast path.
      projectionDelegate: flat ? FlatProjectionDelegate() : null,
    );

Widget _host(Widget child, {bool flat = true}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MapInheritedModel(
        camera: _camera(flat: flat),
        child: child,
      ),
    );

/// A one-layer `raster` style keyed by `img`.
StyleSpec _rasterStyle({bool mercator = false, double opacity = 1.0}) =>
    StyleSpec.parse(<String, Object?>{
      'version': 8,
      'sources': <String, Object?>{
        'img': <String, Object?>{'type': 'image'},
      },
      'layers': <Object?>[
        <String, Object?>{
          'id': 'r',
          'type': 'raster',
          'source': 'img',
          'paint': <String, Object?>{
            'mercator-sampling': mercator,
            'raster-opacity': opacity,
          },
        },
      ],
    });

/// Bounds (south-west → north-east) around the camera centre.
final LatLngBounds _bounds =
    LatLngBounds(const LatLng(32, 100), const LatLng(38, 108));

/// Renders [paintImageOverlay] off-screen and returns the rasterized image.
Future<ui.Image> _renderRaster({
  required bool flat,
  bool mercator = false,
  required ui.Image img,
  double opacity = 1.0,
  int subdivisions = 24,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintImageOverlay(
    canvas,
    const ui.Size(800, 600),
    camera: _camera(flat: flat),
    image: img,
    bounds: _bounds,
    opacity: opacity,
    mercatorSampling: mercator,
    subdivisions: subdivisions,
  );
  return recorder.endRecording().toImage(800, 600);
}

void main() {
  testWidgets('raster renders on 2D (Mercator fast path)',
      (WidgetTester tester) async {
    final ui.Image image = (await tester.runAsync(() async {
      final img = await _makeImage(64, 64);
      return _renderRaster(flat: true, mercator: true, img: img);
    }))!;
    final opaque = await tester.runAsync(() => countOpaquePixels(image));
    expect(opaque, greaterThan(0),
        reason: '2D raster overlay must draw non-transparent pixels');
  });

  testWidgets('raster renders on 3D (orthographic sphere)',
      (WidgetTester tester) async {
    final ui.Image image = (await tester.runAsync(() async {
      final img = await _makeImage(64, 64);
      return _renderRaster(flat: false, mercator: false, img: img);
    }))!;
    final opaque = await tester.runAsync(() => countOpaquePixels(image));
    expect(opaque, greaterThan(0),
        reason: '3D raster overlay must draw non-transparent pixels '
            'on the visible hemisphere');
  });

  testWidgets('raster-opacity 0 draws nothing', (WidgetTester tester) async {
    final ui.Image image = (await tester.runAsync(() async {
      final img = await _makeImage(64, 64);
      return _renderRaster(
          flat: true, mercator: true, img: img, opacity: 0.0);
    }))!;
    final opaque = await tester.runAsync(() => countOpaquePixels(image));
    expect(opaque, 0, reason: 'zero opacity must suppress the overlay');
  });

  testWidgets('controller image registry: add/remove, no revision bump (A2)',
      (WidgetTester tester) async {
    final ui.Image img = (await tester.runAsync(() => _makeImage(8, 8)))!;
    final controller = GeoStyleController(_rasterStyle(mercator: true));
    final before = controller.revision;
    controller.addImageSource(
      'img',
      ImageSource(image: img, bounds: _bounds),
    );
    // A2: registering an image rebuilds renderers but must NOT bump the
    // document revision (the document itself did not change).
    expect(controller.revision, before,
        reason: 'image registry change must not bump revision');
    expect(controller.imageSources['img'], isNotNull);
    controller.removeImageSource('img');
    expect(controller.imageSources.containsKey('img'), isFalse);
  });

  testWidgets('StyleVectorLayer wires a raster layer without throwing',
      (WidgetTester tester) async {
    final ui.Image img = (await tester.runAsync(() => _makeImage(64, 64)))!;
    await tester.pumpWidget(
      _host(
        StyleVectorLayer(
          style: _rasterStyle(mercator: true),
          features: const <GeoJsonFeature>[],
          imageSources: <String, ImageSource>{
            'img': ImageSource(image: img, bounds: _bounds),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('MvtVectorLayer wires a raster layer without throwing',
      (WidgetTester tester) async {
    final ui.Image img = (await tester.runAsync(() => _makeImage(64, 64)))!;
    await tester.pumpWidget(
      _host(
        MvtVectorLayer(
          source: _memSource(),
          style: _rasterStyle(mercator: true),
          imageSources: <String, ImageSource>{
            'img': ImageSource(image: img, bounds: _bounds),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}

/// In-memory [GeoTileSource] stub (no network) so `MvtVectorLayer` builds.
class _MemSource implements GeoTileSource {
  @override
  int get minZoom => 0;
  @override
  int get maxZoom => 12;
  @override
  TileSchemeKind get scheme => TileSchemeKind.webMercator;
  @override
  TileRowOrder get rowOrder => TileRowOrder.xyzTopDown;
  @override
  int get maxConcurrentRequests => 6;
  @override
  String get attribution => 'mem';
  @override
  Future<TileFetchResult> fetch(int z, int x, int y) async =>
      TileFetchResult.ok(Uint8List(0));
  @override
  void dispose() {}
}

GeoTileSource _memSource() => _MemSource();
