// Integration tests for the registry-backed StyleVectorLayer path.
//
// Proves that (a) `setData` rebuilds the painter, (b) a feature-state change
// repaints even though the data did not change, and (c) `["feature-state", ...]`
// actually reaches the paint expression, by rasterizing a real canvas.
library;

import 'dart:math' show Point;
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

const LatLng _center = LatLng(35.86, 104.19);

MapCamera _camera() => MapCamera(
      crs: const Epsg3857(),
      center: _center,
      zoom: 4.2,
      rotation: 0,
      nonRotatedSize: const Point<double>(800, 600),
      projectionDelegate: FlatProjectionDelegate(),
    );

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: MapInheritedModel(camera: _camera(), child: child),
    );

/// A rectangle comfortably covering the viewport centre at z4.2.
GeoJsonFeature _bigPolygon() => GeoJsonFeature(
      id: 'a',
      geometry: PolygonGeometry(<List<LatLng>>[
        <LatLng>[
          const LatLng(20, 90),
          const LatLng(20, 120),
          const LatLng(50, 120),
          const LatLng(50, 90),
          const LatLng(20, 90),
        ],
      ]),
    );

StyleSpec _stateStyle() => StyleSpec.parse(<String, Object?>{
      'version': 8,
      'sources': <String, Object?>{
        's': <String, Object?>{'type': 'geojson'},
      },
      'layers': <Object?>[
        <String, Object?>{
          'id': 'fill',
          'type': 'fill',
          'source': 's',
          'paint': <String, Object?>{
            'fill-color': '#ff0000',
            'fill-opacity': <Object?>[
              'case',
              ['feature-state', 'hover'],
              1.0,
              0.0,
            ],
          },
        },
      ],
    });

/// Centre pixel of the layer's RepaintBoundary, as RGBA bytes.
Future<List<int>> _centrePixel(WidgetTester tester) async {
  final rb = tester.element(find.byType(RepaintBoundary)).renderObject!
      as RenderRepaintBoundary;
  late ui.Image image;
  late ByteData data;
  await tester.runAsync(() async {
    image = await rb.toImage();
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  final x = image.width ~/ 2;
  final y = image.height ~/ 2;
  final i = (y * image.width + x) * 4;
  return <int>[
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
    data.getUint8(i + 3),
  ];
}

Object? _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byType(CustomPaint).first).painter;

void main() {
  testWidgets('setData rebuilds the painter; setFeatureState also repaints',
      (tester) async {
    final registry = GeoFeatureRegistry();
    addTearDown(registry.dispose);

    await tester.pumpWidget(_host(StyleVectorLayer(
      style: _stateStyle(),
      features: const <GeoJsonFeature>[],
      registry: registry,
    )));
    final first = _painter(tester);
    expect(first, isNotNull);

    registry.setData('s', [_bigPolygon()]);
    await tester.pump();
    final afterData = _painter(tester);
    expect(identical(first, afterData), isFalse,
        reason: 'setData must rebuild the painter');

    registry.setFeatureState(
        sourceId: 's', featureId: 'a', state: const {'hover': true});
    await tester.pump();
    final afterState = _painter(tester);
    expect(identical(afterData, afterState), isFalse,
        reason: 'feature state changes must repaint even with unchanged data');
  });

  testWidgets('feature-state reaches the paint expression (pixel proof)',
      (tester) async {
    final registry = GeoFeatureRegistry();
    addTearDown(registry.dispose);
    registry.setData('s', [_bigPolygon()]);

    await tester.pumpWidget(_host(StyleVectorLayer(
      style: _stateStyle(),
      features: const <GeoJsonFeature>[],
      registry: registry,
    )));
    await tester.pump();

    // No state yet: fill-opacity is 0 -> nothing drawn.
    final before = await _centrePixel(tester);
    expect(before[3], 0, reason: 'unset feature state must not draw');

    registry.setFeatureState(
        sourceId: 's', featureId: 'a', state: const {'hover': true});
    await tester.pump();

    final after = await _centrePixel(tester);
    expect(after[3], greaterThan(0), reason: 'hover must make the fill opaque');
    expect(after[0], greaterThan(200), reason: 'fill-color is #ff0000');
    expect(after[1], lessThan(30));
    expect(after[2], lessThan(30));
  });

  testWidgets('the legacy declarative path still paints without a registry',
      (tester) async {
    await tester.pumpWidget(_host(StyleVectorLayer(
      style: _stateStyle(),
      features: [_bigPolygon()],
    )));
    await tester.pump();

    // fill-opacity stays 0 with no state provider — this asserts the old
    // constructor path is wired and does not throw.
    final pixel = await _centrePixel(tester);
    expect(pixel[3], 0);
  });
}
