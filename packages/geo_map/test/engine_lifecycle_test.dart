/// Host-level lifecycle tests for the shared tile engine.
///
/// These cannot live in `geo_map_core`: the regression they cover is a
/// *widget ownership* bug, not a geometry one. The engine is created by the
/// host and **borrowed** by the layer; a layer that disposed it while being
/// unmounted killed every in-flight decode (`_decode` drops the frame once
/// `_disposed`) and the next build asserted `A TileEngine was used after being
/// disposed` — which reached the user as "the globe basemap never loads".
library;

import 'dart:math' show Point;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';

/// A source that never produces a tile — these tests are about lifecycle, and
/// a real decode would only add engine-level asynchrony.
class _NullSource implements GlobeRasterSource {
  @override
  int get minZoom => 1;

  @override
  int get maxZoom => 8;

  @override
  TileSchemeKind get scheme => TileSchemeKind.webMercator;

  @override
  TileRowOrder get rowOrder => TileRowOrder.xyzTopDown;

  @override
  int get maxConcurrentRequests => GeoEngineTuning.maxParallelRequests;

  @override
  String get attribution => 'null';

  @override
  Future<TileFetchResult> fetch(int z, int x, int y) async =>
      const TileFetchResult.failed(TileFailureKind.notFound);

  @override
  void dispose() {}
}

MapCamera _camera() => MapCamera(
      crs: const Epsg3857(),
      center: const LatLng(30, 105),
      zoom: 4.2,
      rotation: 0,
      nonRotatedSize: const Point<double>(800, 600),
    );

Widget _app({
  required GeoMapController controller,
  required GlobeRasterSource source,
  required bool useGlobe,
}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Directionality(
        textDirection: TextDirection.ltr,
        child: GeoMap(
          controller: controller,
          source: source,
          options: GeoMapOptions(useGlobe: useGlobe),
        ),
      ),
    );

Widget _hosted(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: MapInheritedModel(camera: _camera(), child: child),
    );

void main() {
  testWidgets('the shared engine survives rebuilds and the 2D/3D switch',
      (tester) async {
    final source = _NullSource();
    final controller = GeoMapController(
      useGlobe: true,
      initialCenter: const LatLng(30, 105),
      initialZoom: 4.2,
      minZoom: 1,
      maxZoom: 8,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(controller: controller, source: source, useGlobe: true),
    );
    // ★ The first rebuild after the initial frame is where the engine used to
    // be disposed: `setViewport` fires from a post-frame callback, notifies the
    // controller and rebuilds the layer.
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'the globe layer must not dispose the shared engine');

    // 3D → 2D.
    await tester.pumpWidget(
      _app(controller: controller, source: source, useGlobe: false),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 2D → 3D.
    await tester.pumpWidget(
      _app(controller: controller, source: source, useGlobe: true),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a layer never disposes an engine it was given', (tester) async {
    final source = _NullSource();
    final engine = TileEngine(source: source);
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      _hosted(
        TileLayer(
          source: source,
          engine: engine,
          mode: TileLayerMode.globe,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Unmount the layer — the engine belongs to the caller and must survive.
    await tester.pumpWidget(const SizedBox());
    expect(
      () => engine.addListener(() {}),
      returnsNormally,
      reason: 'borrowed engines must outlive the layer that drew them',
    );
  });

  testWidgets('a layer that owns its engine disposes it on unmount',
      (tester) async {
    final source = _NullSource();

    await tester.pumpWidget(
      _hosted(TileLayer(source: source, mode: TileLayerMode.mercator)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // No handle on the owned engine — the contract is just "no leak and no
    // exception while rebuilding with a different source".
    await tester.pumpWidget(
      _hosted(TileLayer(source: _NullSource(), mode: TileLayerMode.globe)),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
