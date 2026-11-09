/// Integration tests for [StyleVectorLayer] — the M1 style-driven renderer.
///
/// These drive the full pipeline through the real widget tree: a [StyleSpec] is
/// parsed, each layer's paint properties are evaluated per feature (constants and
/// expressions), geometry is projected with the same core [GeoProjector] the tile
/// layer uses, and the result is drawn onto a real `Canvas` and rasterized. The
/// picture is then inspected for non-transparent pixels, proving the layer
/// emitted draw calls rather than silently drawing nothing.
library;

import 'dart:math' show Point;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'test_helpers.dart';

const LatLng _center = LatLng(35.86, 104.19);

MapCamera _camera({
  MapProjectionDelegate? delegate,
  LatLng center = _center,
  double zoom = 4.2,
}) =>
    MapCamera(
      crs: const Epsg3857(),
      center: center,
      zoom: zoom,
      rotation: 0,
      nonRotatedSize: const Point<double>(800, 600),
      // Default to flat (2D) so the 2D group actually exercises the Mercator
      // path. Previously `null` made `flat == false`, i.e. it ran the globe
      // projector.
      projectionDelegate: delegate ?? FlatProjectionDelegate(),
    );

StyleSpec _style({String? labelText}) => StyleSpec.parse(<String, Object?>{
      'version': 8,
      'sources': <String, Object?>{'s': <String, Object?>{'type': 'geojson'}},
      'layers': <Object?>[
        <String, Object?>{
          'id': 'fill',
          'type': 'fill',
          'source': 's',
          'paint': <String, Object?>{'fill-color': '#e63946', 'fill-opacity': 0.6},
        },
        <String, Object?>{
          'id': 'line',
          'type': 'line',
          'source': 's',
          'paint': <String, Object?>{'line-color': '#1d3557', 'line-width': 2},
        },
        <String, Object?>{
          'id': 'label',
          'type': 'symbol',
          'source': 's',
          'layout': <String, Object?>{
            'text-field': labelText ?? 'Hi',
          },
          'paint': <String, Object?>{
            'text-color': '#000000',
            'text-size': 16,
          },
        },
      ],
    });

List<GeoJsonFeature> _features() => <GeoJsonFeature>[
      GeoJsonFeature(
        properties: const <String, Object?>{'name': 'Square'},
        geometry: PolygonGeometry(<List<LatLng>>[
          <LatLng>[
            const LatLng(30, 100),
            const LatLng(30, 110),
            const LatLng(40, 110),
            const LatLng(40, 100),
            const LatLng(30, 100),
          ],
        ]),
      ),
      GeoJsonFeature(
        properties: const <String, Object?>{'name': 'Road'},
        geometry: LineStringGeometry(<LatLng>[
          const LatLng(31, 101),
          const LatLng(39, 109),
        ]),
      ),
      GeoJsonFeature(
        properties: const <String, Object?>{'name': 'City'},
        geometry: const PointGeometry(LatLng(35, 105)),
      ),
    ];

Widget _host(
  Widget child, {
  MapProjectionDelegate? delegate,
  LatLng center = _center,
  double zoom = 4.2,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: MapInheritedModel(
        camera: _camera(delegate: delegate, center: center, zoom: zoom),
        child: child,
      ),
    );

Future<int> _opaquePixelsOf(WidgetTester tester) async {
  final rb = tester.element(find.byType(RepaintBoundary)).renderObject!
      as RenderRepaintBoundary;
  var opaque = 0;
  // Rasterization needs the engine's raster thread; under the test's
  // fake-async zone the future never completes, so step out with `runAsync`.
  await tester.runAsync(() async {
    final image = await rb.toImage();
    opaque = await countOpaquePixels(image);
  });
  return opaque;
}

Future<ui.Image> _renderImage(WidgetTester tester) async {
  final rb = tester.element(find.byType(RepaintBoundary)).renderObject!
      as RenderRepaintBoundary;
  late ui.Image image;
  await tester.runAsync(() async {
    image = await rb.toImage();
  });
  return image;
}

/// Whether any pixel whose x is in `[x0, x1)` is non-transparent.
Future<bool> _hasOpaqueInColumns(
  WidgetTester tester,
  ui.Image image,
  int x0,
  int x1,
) async {
  var found = false;
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return;
    final w = image.width;
    for (var y = 0; y < image.height && !found; y++) {
      final row = y * w;
      for (var x = x0; x < x1 && x < w; x++) {
        if (data.getUint8((row + x) * 4 + 3) > 0) {
          found = true;
          break;
        }
      }
    }
  });
  return found;
}

/// A single `line` layer over an otherwise empty (transparent) canvas, so a
/// horizontal stroke can be inspected row by row.
StyleSpec _lineStyle({Object? dasharray, double width = 2}) =>
    StyleSpec.parse(<String, Object?>{
      'version': 8,
      'sources': <String, Object?>{'s': <String, Object?>{'type': 'geojson'}},
      'layers': <Object?>[
        <String, Object?>{
          'id': 'line',
          'type': 'line',
          'source': 's',
          'paint': <String, Object?>{
            'line-color': '#000000',
            'line-width': width,
            if (dasharray != null) 'line-dasharray': dasharray,
          },
        },
      ],
    });

/// A constant-latitude line: ~650 px wide at zoom 4.2, entirely inside one
/// world copy so the multi-copy phase behaviour cannot skew the segment count.
List<GeoJsonFeature> _horizontalLine({
  Map<String, Object?> props = const <String, Object?>{},
}) =>
    <GeoJsonFeature>[
      GeoJsonFeature(
        properties: props,
        geometry: LineStringGeometry(<LatLng>[
          const LatLng(35, 80),
          const LatLng(35, 130),
        ]),
      ),
    ];

Future<ui.Image> _paintLine(
  WidgetTester tester, {
  Object? dasharray,
  double width = 2,
  Map<String, Object?> props = const <String, Object?>{},
  MapProjectionDelegate? delegate,
}) async {
  await tester.pumpWidget(
    _host(
      StyleVectorLayer(
        style: _lineStyle(dasharray: dasharray, width: width),
        features: _horizontalLine(props: props),
      ),
      delegate: delegate,
    ),
  );
  await tester.pumpAndSettle();
  return _renderImage(tester);
}

Future<int> _opaqueOfImage(WidgetTester tester, ui.Image image) async {
  var opaque = 0;
  await tester.runAsync(() async {
    opaque = await countOpaquePixels(image);
  });
  return opaque;
}

/// Counts `transparent -> painted` transitions on the densest row: a solid
/// stroke has 1 run, a dashed stroke has many.
Future<int> _rowRuns(WidgetTester tester, ui.Image image) async {
  var mask = const <bool>[];
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return;
    final w = image.width;
    var bestRow = -1;
    var bestCount = -1;
    for (var y = 0; y < image.height; y++) {
      var count = 0;
      final row = y * w;
      for (var x = 0; x < w; x++) {
        if (data.getUint8((row + x) * 4 + 3) > 0) count++;
      }
      if (count > bestCount) {
        bestCount = count;
        bestRow = y;
      }
    }
    if (bestRow < 0) return;
    final row = bestRow * w;
    mask = <bool>[
      for (var x = 0; x < w; x++) data.getUint8((row + x) * 4 + 3) > 0,
    ];
  });
  var runs = 0;
  var previous = false;
  for (final on in mask) {
    if (on && !previous) runs++;
    previous = on;
  }
  return runs;
}

void main() {
  group('StyleVectorLayer (2D)', () {
    testWidgets('parses style, projects and paints without throwing',
        (tester) async {
      await tester.pumpWidget(
        _host(StyleVectorLayer(style: _style(), features: _features())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('emits draw calls for fill/line/symbol', (tester) async {
      await tester.pumpWidget(
        _host(StyleVectorLayer(style: _style(), features: _features())),
      );
      await tester.pumpAndSettle();
      // A filled polygon + stroked line + a placed label must leave marks.
      expect(await _opaquePixelsOf(tester), greaterThan(0));
    });
  });

  group('StyleVectorLayer (3D globe)', () {
    testWidgets('paints under the orthographic projector without throwing',
        (tester) async {
      await tester.pumpWidget(
        _host(
          StyleVectorLayer(style: _style(), features: _features()),
          delegate: GlobeProjectionDelegate(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The geometry sits at the camera centre, on the visible hemisphere.
      expect(await _opaquePixelsOf(tester), greaterThan(0));
    });
  });

  group('StyleVectorLayer.ofSources', () {
    testWidgets('a layer only draws its own source', (tester) async {
      final style = StyleSpec.parse(<String, Object?>{
        'version': 8,
        'sources': <String, Object?>{
          's': <String, Object?>{'type': 'geojson'},
          't': <String, Object?>{'type': 'geojson'},
        },
        'layers': <Object?>[
          <String, Object?>{
            'id': 'only-t',
            'type': 'fill',
            'source': 't',
            'paint': <String, Object?>{'fill-color': '#2a9d8f'},
          },
        ],
      });
      final features = <String, List<GeoJsonFeature>>{
        // 's' would be stroked by a layer that ignores `source` — the bug this
        // variant fixes — so give it a polygon and confirm it is not drawn.
        's': _features(),
        't': <GeoJsonFeature>[
          GeoJsonFeature(
            properties: const <String, Object?>{},
            geometry: PolygonGeometry(<List<LatLng>>[
              <LatLng>[
                const LatLng(30, 100),
                const LatLng(30, 110),
                const LatLng(40, 110),
                const LatLng(40, 100),
                const LatLng(30, 100),
              ],
            ]),
          ),
        ],
      };
      await tester.pumpWidget(
        _host(StyleVectorLayer.ofSources(style: style, sources: features)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await _opaquePixelsOf(tester), greaterThan(0));
    });
  });

  group('StyleVectorLayer (2D antimeridian)', () {
    StyleSpec fillStyle() => StyleSpec.parse(<String, Object?>{
          'version': 8,
          'sources': <String, Object?>{
            's': <String, Object?>{'type': 'geojson'},
          },
          'layers': <Object?>[
            <String, Object?>{
              'id': 'fill',
              'type': 'fill',
              'source': 's',
              'paint': <String, Object?>{'fill-color': '#e63946'},
            },
          ],
        });

    testWidgets('a ring crossing the seam does not fill the screen centre',
        (tester) async {
      // At zoom 1.6 the world (256·2^1.6 ≈ 776 px) fits the 800 px viewport, so
      // lon 180 sits at the right edge and repeats on the left. A ring whose
      // vertices are at +170 and −170 straddles that seam — the exact case that
      // used to draw a screen-wide band.
      final ring = <LatLng>[
        const LatLng(10, 170),
        const LatLng(10, -170),
        const LatLng(-10, -170),
        const LatLng(-10, 170),
        const LatLng(10, 170),
      ];
      await tester.pumpWidget(_host(
        StyleVectorLayer(
          style: fillStyle(),
          features: <GeoJsonFeature>[
            GeoJsonFeature(geometry: PolygonGeometry(<List<LatLng>>[ring])),
          ],
        ),
        center: const LatLng(0, 0),
        zoom: 1.6,
      ));
      await tester.pumpAndSettle();

      final image = await _renderImage(tester);
      // No band: the middle columns must be untouched.
      expect(await _hasOpaqueInColumns(tester, image, 380, 420), isFalse);
      // World copies: the shape appears on both edges.
      expect(await _hasOpaqueInColumns(tester, image, 0, 20), isTrue);
      expect(await _hasOpaqueInColumns(tester, image, 780, 800), isTrue);
    });

    testWidgets('a normal polygon still paints', (tester) async {
      final ring = <LatLng>[
        const LatLng(30, 100),
        const LatLng(30, 110),
        const LatLng(40, 110),
        const LatLng(40, 100),
        const LatLng(30, 100),
      ];
      await tester.pumpWidget(_host(
        StyleVectorLayer(
          style: fillStyle(),
          features: <GeoJsonFeature>[
            GeoJsonFeature(geometry: PolygonGeometry(<List<LatLng>>[ring])),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await _opaquePixelsOf(tester), greaterThan(0));
    });
  });

  group('background layer', () {
    testWidgets('background-only style paints fullscreen', (tester) async {
      final style = StyleSpec.parse(<String, Object?>{
        'version': 8,
        'layers': <Object?>[
          <String, Object?>{
            'id': 'bg',
            'type': 'background',
            'paint': <String, Object?>{'background-color': '#D7E3EC'},
          },
        ],
      });
      await tester.pumpWidget(
        _host(StyleVectorLayer(style: style, features: const [])),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await _opaquePixelsOf(tester), 800 * 600);
    });
  });

  group('StyleVectorLayer line-dasharray', () {
    testWidgets('a constant [3, 3] really splits the stroke', (tester) async {
      final solid = await _paintLine(tester);
      final solidPixels = await _opaqueOfImage(tester, solid);
      final solidRuns = await _rowRuns(tester, solid);

      final dashed = await _paintLine(tester, dasharray: <Object?>[3, 3]);
      final dashPixels = await _opaqueOfImage(tester, dashed);
      final dashRuns = await _rowRuns(tester, dashed);

      expect(tester.takeException(), isNull);
      expect(solidRuns, 1);
      expect(dashRuns, greaterThan(1));
      expect(dashPixels, greaterThan(0));
      expect(dashPixels, lessThan((solidPixels * 0.85).round()));
    });

    testWidgets('data-driven dasharray through a get expression',
        (tester) async {
      final dashStyle = _lineStyle(dasharray: <Object?>['get', 'dasharray']);

      await tester.pumpWidget(_host(StyleVectorLayer(
        style: dashStyle,
        features: _horizontalLine(props: const <String, Object?>{
          'dasharray': <Object?>[4, 4],
        }),
      )));
      await tester.pumpAndSettle();
      final dashed = await _renderImage(tester);
      expect(await _rowRuns(tester, dashed), greaterThan(1));

      // Missing property -> valueOf returns null -> solid stroke.
      await tester.pumpWidget(_host(StyleVectorLayer(
        style: dashStyle,
        features: _horizontalLine(),
      )));
      await tester.pumpAndSettle();
      final solid = await _renderImage(tester);
      expect(await _rowRuns(tester, solid), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('invalid patterns fall back to a solid stroke', (tester) async {
      for (final pattern in <Object?>[
        <Object?>[0, 0], // zero sum
        <Object?>[3], // too short
        <Object?>[3, -1], // negative
        <Object?>[3, 'x'], // non-numeric
      ]) {
        final image = await _paintLine(tester, dasharray: pattern);
        expect(await _rowRuns(tester, image), 1, reason: 'pattern $pattern');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('pattern units are line-width multiples', (tester) async {
      final narrow = await _paintLine(
        tester,
        dasharray: <Object?>[3, 3],
        width: 1,
      );
      final wide = await _paintLine(
        tester,
        dasharray: <Object?>[3, 3],
        width: 3,
      );
      final narrowRuns = await _rowRuns(tester, narrow);
      final wideRuns = await _rowRuns(tester, wide);
      expect(narrowRuns, greaterThan(1));
      expect(wideRuns, greaterThan(1));
      // A screen-pixel implementation would produce the same count.
      expect(wideRuns, lessThan(narrowRuns));
    });

    testWidgets('dashes also render on the 3D globe', (tester) async {
      final solid = await _paintLine(
        tester,
        delegate: GlobeProjectionDelegate(),
      );
      final solidPixels = await _opaqueOfImage(tester, solid);
      final dashed = await _paintLine(
        tester,
        dasharray: <Object?>[3, 3],
        delegate: GlobeProjectionDelegate(),
      );
      final dashPixels = await _opaqueOfImage(tester, dashed);

      expect(tester.takeException(), isNull);
      expect(solidPixels, greaterThan(0));
      expect(dashPixels, greaterThan(0));
      expect(dashPixels, lessThan((solidPixels * 0.95).round()));
    });
  });
}
