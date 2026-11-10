import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

/// The facade is a thin MapLibre-shaped wrapper; this test pins down that
/// every operation reaches the underlying controller (no hidden second style
/// document, no swallowed calls).
StyleSpec _empty() => StyleSpec.parse(const <String, Object?>{
      'version': 8,
      'sources': <String, Object?>{},
      'layers': <Object?>[],
    });

void main() {
  late GeoMapController camera;
  late GeoStyleController style;
  late MapHandle handle;

  setUp(() {
    camera = GeoMapController(useGlobe: false);
    style = GeoStyleController(_empty());
    handle = MapHandle(
      camera: camera,
      style: style,
      features: GeoFeatureRegistry(),
    );
  });

  tearDown(() {
    camera.dispose();
    style.dispose();
  });

  test('one style document is shared by the facade', () {
    expect(identical(handle.style, style), isTrue);

    handle.addSource('s', <String, Object?>{'type': 'vector'});
    expect(style.document.sources.containsKey('s'), isTrue);
    expect(style.revision, 1);

    handle.removeSource('s');
    expect(style.document.sources.containsKey('s'), isFalse);
  });

  test('addLayer(before:) reaches the style document in order', () {
    handle.style.addLayer(
      StyleLayer.parse(const <String, Object?>{
        'id': 'top',
        'type': 'background',
      }),
    );
    handle.style.addLayer(
      StyleLayer.parse(const <String, Object?>{
        'id': 'bottom',
        'type': 'background',
      }),
      before: 'top',
    );
    expect(
      [for (final l in style.document.layers) l.id],
      ['bottom', 'top'],
    );
  });

  test('jumpTo / setCenter / setZoom forward to the camera', () {
    handle.setZoom(6);
    expect(camera.zoom, 6);

    final target = const LatLng(35.86, 104.19);
    handle.setCenter(target);
    expect(camera.center, target);
    expect(camera.zoom, 6, reason: 'center-only jump keeps the zoom');

    handle.jumpTo(center: const LatLng(10, 20), zoom: 4);
    expect(camera.center, const LatLng(10, 20));
    expect(camera.zoom, 4);
  });

  test('queryRenderedFeatures is safe on an empty registry', () {
    expect(
      handle.queryRenderedFeatures(const LatLng(0, 0)),
      isEmpty,
    );
  });
}
