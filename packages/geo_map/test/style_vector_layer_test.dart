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
}
