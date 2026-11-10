// National-border pixel comparison for the T5d / T5b walkthrough.
//
// Goal: prove that the boundary lines (countries / provinces / nine-dash) are
// *actually painted above* the image group, in both the 2D Mercator and the 3D
// orthographic path — i.e. that the T5 z-order fix and the T5d predicate
// convergence did not change border rendering.
//
// Method (no golden files, so it stays machine-independent):
//   1. Render ONLY the line layers -> a mask of border pixels.
//   2. Render the correct order  [fill, raster, line] -> `correct`.
//   3. Render the broken order  [fill, line, raster] -> `wrong` (the T5b bug).
//   4. On every masked border pixel, `correct` must be the line colour and
//      `wrong` must NOT be. If the renderer ever reorders layers, the test
//      fails on real pixels rather than on a document list.
library;

import 'dart:math' show Point;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;

const LatLng _center = LatLng(35.0, 104.0);
const int _w = 400;
const int _h = 300;

// Opaque blue borders; the raster is opaque orange, so any covering is obvious.
const int _lineArgb = 0xff0000ff;

final LatLngBounds _imageBounds =
    LatLngBounds(const LatLng(10, 80), const LatLng(60, 130));

MapCamera _camera(bool flat) => MapCamera(
      crs: const Epsg3857(),
      center: _center,
      zoom: 4.2,
      rotation: 0,
      nonRotatedSize: const Point<double>(400.0, 300.0),
      projectionDelegate: flat ? FlatProjectionDelegate() : GlobeProjectionDelegate(),
    );

Widget _host(Widget child, bool flat) => Directionality(
      textDirection: TextDirection.ltr,
      child: MapInheritedModel(
        camera: _camera(flat),
        child: child,
      ),
    );

Future<ui.Image> _solidImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 64, 64),
    ui.Paint()..color = const ui.Color(0xffff8000),
  );
  return recorder.endRecording().toImage(64, 64);
}

List<GeoJsonFeature> _features() => <GeoJsonFeature>[
      // A land polygon and three boundary lines through the image's footprint.
      GeoJsonFeature(
        properties: const <String, Object?>{'kind': 'land'},
        geometry: PolygonGeometry(<List<LatLng>>[
          <LatLng>[
            const LatLng(20, 90),
            const LatLng(20, 120),
            const LatLng(50, 120),
            const LatLng(50, 90),
            const LatLng(20, 90),
          ],
        ]),
      ),
      GeoJsonFeature(
        properties: const <String, Object?>{'kind': 'border'},
        geometry: LineStringGeometry(<LatLng>[
          const LatLng(22, 92),
          const LatLng(35, 104),
          const LatLng(48, 118),
        ]),
      ),
    ];

/// Builds the same layers as the app's basemap specs, in a chosen order.
StyleSpec _style({required bool correctOrder}) {
  final fill = <String, Object?>{
    'id': 'land-fill',
    'type': 'fill',
    'source': 's',
    'paint': <String, Object?>{
      'fill-color': '#00aa00',
      'fill-opacity': 1.0,
    },
  };
  final raster = <String, Object?>{
    'id': 'radar',
    'type': 'raster',
    'source': 'img',
    'paint': <String, Object?>{
      'raster-opacity': 1.0,
      'mercator-sampling': false,
    },
  };
  final line = (String id, String color, num width) =>
      <String, Object?>{
        'id': id,
        'type': 'line',
        'source': 's',
        'paint': <String, Object?>{
          'line-color': color,
          'line-width': width,
        },
      };
  final lines = <Object?>[
    line('countries-line', '#0000ff', 8),
    line('provinces-line', '#0000ff', 8),
    line('nine-dash-line', '#0000ff', 8),
  ];
  return StyleSpec.parse(<String, Object?>{
    'version': 8,
    'sources': <String, Object?>{
      's': <String, Object?>{'type': 'geojson'},
      'img': <String, Object?>{'type': 'image'},
    },
    'layers': <Object?>[
      fill,
      if (correctOrder) raster,
      ...lines,
      if (!correctOrder) raster,
    ],
  });
}

Future<ui.Image> _render(
  WidgetTester tester, {
  required StyleSpec spec,
  required bool flat,
  ui.Image? image,
}) async {
  await tester.pumpWidget(
    _host(
      StyleVectorLayer(
        style: spec,
        features: spec.layers.any((l) => l.type == 'fill' ||
                l.type == 'line')
            ? _features()
            : const <GeoJsonFeature>[],
        imageSources: image == null
            ? null
            : <String, ImageSource>{
                'img': ImageSource(image: image, bounds: _imageBounds),
              },
      ),
      flat,
    ),
  );
  await tester.pumpAndSettle();
  final rb = tester.element(find.byType(RepaintBoundary)).renderObject!
      as RenderRepaintBoundary;
  late ui.Image out;
  await tester.runAsync(() async {
    out = await rb.toImage();
  });
  return out;
}

Future<Uint8List> _rgba(WidgetTester tester, ui.Image image) async {
  late ByteData data;
  await tester.runAsync(() async {
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

int _argb(Uint8List px, int i) => (px[i + 3] << 24) |
    (px[i] << 16) |
    (px[i + 1] << 8) |
    px[i + 2];

void main() {
  for (final flat in <bool>[true, false]) {
    final mode = flat ? '2D Mercator' : '3D orthographic';

    testWidgets('$mode: borders stay above the image group (pixel diff)',
        (tester) async {
      final img = (await tester.runAsync(_solidImage))!;

      // 1) Mask: only the line layers.
      final maskSpec = StyleSpec.parse(<String, Object?>{
        'version': 8,
        'sources': <String, Object?>{'s': <String, Object?>{'type': 'geojson'}},
        'layers': (_style(correctOrder: true)
                .layers
                .where((l) => l.type == 'line')
                .map((l) => <String, Object?>{
                      'id': l.id,
                      'type': 'line',
                      'source': 's',
                      'paint': <String, Object?>{
                        'line-color': '#0000ff',
                        'line-width': 8,
                      },
                    })
                .toList()),
      });
      final mask = await _rgba(tester,
          await _render(tester, spec: maskSpec, flat: flat));

      final correct = await _rgba(tester, await _render(
        tester,
        spec: _style(correctOrder: true),
        flat: flat,
        image: img,
      ));
      final wrong = await _rgba(tester, await _render(
        tester,
        spec: _style(correctOrder: false),
        flat: flat,
        image: img,
      ));

      // Border pixels must exist, otherwise the comparison is vacuous.
      var borderPixels = 0;
      var coveredWhenWrong = 0;
      for (var i = 0; i < mask.lengthInBytes; i += 4) {
        // Only fully opaque, exactly blue stroke-core pixels. Antialiased
        // edge pixels are blends of line + background and must be excluded,
        // otherwise the comparison would be about AA rather than z-order.
        if (mask[i + 3] != 255 || _argb(mask, i) != _lineArgb) continue;
        borderPixels++;
        // Correct z-order: the opaque blue stroke wins.
        expect(_argb(correct, i), _lineArgb,
            reason: '$mode: border pixel was covered by the image group');
        if (_argb(wrong, i) != _lineArgb) coveredWhenWrong++;
      }
      expect(borderPixels, greaterThan(0),
          reason: '$mode: no border pixels rendered');
      expect(coveredWhenWrong, greaterThan(0),
          reason: '$mode: control (broken order) did not change any pixel — '
              'the test can no longer detect a z-order regression');
    });
  }
}
