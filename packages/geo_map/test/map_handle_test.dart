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

GeoJsonFeature _dot(String id) => GeoJsonFeature(
      id: id,
      properties: const <String, Object?>{'level': 1},
      geometry: PointGeometry(const LatLng(0, 0)),
    );

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

  group('feature data facade', () {
    test('setData creates the source and reaches getData / getSource', () {
      handle.setData('poi', [_dot('a')]);
      expect(handle.getData('poi'), hasLength(1));
      expect(handle.getSource('poi'), isA<GeoSourceHandle>());
      expect(handle.source('poi').getData(), hasLength(1));
    });

    test('getSource is null for an unknown id, source() creates it', () {
      expect(handle.getSource('missing'), isNull);
      handle.source('made').setData([_dot('a')]);
      expect(handle.getData('made'), hasLength(1));
    });

    test('updateData applies a diff and reports a no-op', () {
      handle.setData('poi', [_dot('a'), _dot('b')]);
      final changed = handle.updateData(
        'poi',
        GeoSourceDiff(remove: const ['a'], add: [_dot('c')]),
      );
      expect(changed, isTrue);
      expect([for (final f in handle.getData('poi')) f.id], ['b', 'c']);
      expect(handle.updateData('poi', const GeoSourceDiff()), isFalse);
      expect(handle.updateData('unknown', const GeoSourceDiff()), isFalse);
    });

    test('feature state forwards to the registry', () {
      handle.setData('poi', [_dot('a')]);
      handle.setFeatureState(
        sourceId: 'poi',
        featureId: 'a',
        state: const <String, Object?>{'selected': true},
      );
      expect(
        handle.getFeatureState(sourceId: 'poi', featureId: 'a')['selected'],
        isTrue,
      );
      handle.removeFeatureState(sourceId: 'poi', featureId: 'a');
      expect(
        handle.getFeatureState(sourceId: 'poi', featureId: 'a'),
        isEmpty,
      );
    });

    test('feature sources and style sources are independent namespaces', () {
      handle.addSource('poi', const <String, Object?>{'type': 'geojson'});
      handle.setData('poi', [_dot('a')]);
      expect(style.document.sources.containsKey('poi'), isTrue);
      expect(handle.getData('poi'), hasLength(1));

      handle.removeFeatureSource('poi'); // drops feature data only
      expect(handle.getData('poi'), isEmpty);
      expect(style.document.sources.containsKey('poi'), isTrue);

      handle.removeSource('poi'); // drops the style definition only
      expect(style.document.sources.containsKey('poi'), isFalse);
    });

    test('queryRenderedFeatures sees data written through the facade', () {
      handle.setData('poi', [_dot('a')]);
      expect(
        handle.queryRenderedFeatures(
          const LatLng(0, 0),
          sourceIds: const {'poi'},
        ),
        isNotEmpty,
      );
    });
  });
}
