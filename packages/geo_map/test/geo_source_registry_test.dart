// Runtime GeoJSON source management: MapLibre `setData` / `updateData` /
// `getData` / `getSource` / feature-state equivalents, plus the regression
// that rendering data and query data used to be two independently updated
// copies.
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

GeoJsonFeature _dot(
  String? id, {
  double lat = 0,
  double lng = 0,
  Map<String, Object?> props = const <String, Object?>{},
}) =>
    GeoJsonFeature(
      id: id,
      properties: props,
      geometry: PointGeometry(LatLng(lat, lng)),
    );

GeoMapController _flatController() {
  final controller = GeoMapController(
    useGlobe: false,
    initialCenter: const LatLng(0, 0),
    initialZoom: 4,
    minZoom: 1,
    maxZoom: 18,
  );
  controller.setViewport(const Size(800, 600));
  return controller;
}

void main() {
  group('setData / getData / handles', () {
    test('setData creates a source; getSource / source expose a handle', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);

      expect(registry.getSource('point'), isNull);
      expect(registry.getData('point'), isEmpty);

      registry.setData('point', [_dot('a')]);
      expect(registry.containsSource('point'), isTrue);
      expect(registry.length, 1);
      expect(registry.getData('point').single.id, 'a');
      expect(registry.getSource('point'), isNotNull);
      expect(registry.source('point').getData().single.id, 'a');
    });

    test('a handle writes through to the registry', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a')]);

      registry.getSource('point')!.setData([_dot('b')]);
      expect(registry.getData('point').single.id, 'b');
    });

    test('setSource (legacy API) behaves like setData', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setSource('point', [_dot('a')]);
      expect(registry.getData('point').single.id, 'a');
    });

    test('setData with identical features does not bump revision', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      final features = [_dot('a')];
      registry.setData('point', features);
      final rev = registry.revision;
      final view = registry.sourcesView;

      registry.setData('point', features);
      expect(registry.revision, rev);
      expect(identical(registry.sourcesView, view), isTrue);
    });

    test('a real change bumps revision and rebuilds sourcesView', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a')]);
      final rev = registry.revision;
      final view = registry.sourcesView;

      registry.setData('point', [_dot('b')]);
      expect(registry.revision, rev + 1);
      expect(identical(registry.sourcesView, view), isFalse);
      expect(registry.sourcesView['point']!.single.id, 'b');
    });
  });

  group('updateData', () {
    test('applies a diff and returns true on a real change', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a'), _dot('b')]);
      final rev = registry.revision;

      final changed = registry.updateData(
        'point',
        GeoSourceDiff(
          remove: const ['b'],
          add: [_dot('c', props: const {'new': true})],
          update: const [
            GeoSourceUpdate(
                id: 'a', addOrUpdateProperties: {'hover': true}),
          ],
        ),
      );

      expect(changed, isTrue);
      expect(registry.revision, rev + 1);
      final ids = registry.getData('point').map((f) => f.id).toList();
      expect(ids, ['a', 'c']);
      expect(registry.getData('point').first.properties['hover'], isTrue);
      expect(registry.getData('point').last.properties['new'], isTrue);
    });

    test('returns false for an unknown source / empty diff / no-op diff', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a')]);
      final rev = registry.revision;

      expect(registry.updateData('missing', const GeoSourceDiff()), isFalse);
      expect(registry.updateData('point', const GeoSourceDiff()), isFalse);
      expect(
        registry.updateData(
          'point',
          const GeoSourceDiff(remove: ['unknown']),
        ),
        isFalse,
      );
      expect(registry.revision, rev);
    });

    test('refuses a non-updateable source (missing / duplicate ids)', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot(null), _dot('a')]);
      final before = registry.getData('point');

      expect(
        registry.updateData(
          'point',
          const GeoSourceDiff(remove: ['a']),
        ),
        isFalse,
      );
      expect(identical(registry.getData('point'), before), isTrue);
    });
  });

  group('feature state (MapLibre style.ts:1463-1541)', () {
    test('merges, reads and removes state by key / feature / source', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a')]);

      registry.setFeatureState(
          sourceId: 'point', featureId: 'a', state: {'hover': true});
      registry.setFeatureState(
          sourceId: 'point', featureId: 'a', state: {'selected': 1});
      expect(registry.getFeatureState(sourceId: 'point', featureId: 'a'),
          {'hover': true, 'selected': 1});

      registry.removeFeatureState(
          sourceId: 'point', featureId: 'a', key: 'hover');
      expect(registry.getFeatureState(sourceId: 'point', featureId: 'a'),
          {'selected': 1});

      registry.removeFeatureState(sourceId: 'point', featureId: 'a');
      expect(registry.getFeatureState(sourceId: 'point', featureId: 'a'),
          isEmpty);
    });

    test('state changes bump revision even though sourcesView is unchanged',
        () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a')]);
      final rev = registry.revision;
      final view = registry.sourcesView;

      registry.setFeatureState(
          sourceId: 'point', featureId: 'a', state: {'hover': true});
      expect(registry.revision, rev + 1);
      expect(identical(registry.sourcesView, view), isTrue,
          reason: 'the data did not change; only the revision signals a repaint');
    });

    test('setting the same state twice does not notify', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a')]);
      registry.setFeatureState(
          sourceId: 'point', featureId: 'a', state: {'hover': true});
      final rev = registry.revision;
      registry.setFeatureState(
          sourceId: 'point', featureId: 'a', state: {'hover': true});
      expect(registry.revision, rev);
    });

    test('boundary: unknown source, empty id, forbidden keys are no-ops', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a')]);
      final rev = registry.revision;

      registry.setFeatureState(
          sourceId: 'missing', featureId: 'a', state: {'hover': true});
      registry.setFeatureState(
          sourceId: 'point', featureId: '', state: {'hover': true});
      for (final key in const ['__proto__', 'constructor', 'prototype']) {
        registry.setFeatureState(
            sourceId: 'point', featureId: 'a', state: {key: true});
      }
      expect(registry.revision, rev);
      expect(registry.getFeatureState(sourceId: 'point', featureId: 'a'),
          isEmpty);
    });

    test('removeFeatureState with a key but no feature id is a no-op', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a')]);
      registry.setFeatureState(
          sourceId: 'point', featureId: 'a', state: {'hover': true});
      final rev = registry.revision;

      registry.removeFeatureState(sourceId: 'point', key: 'hover');
      expect(registry.revision, rev);
      expect(
          registry.getFeatureState(sourceId: 'point', featureId: 'a')['hover'],
          isTrue);
    });

    test('removeSource / clear discard state', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      registry.setData('point', [_dot('a')]);
      registry.setFeatureState(
          sourceId: 'point', featureId: 'a', state: {'hover': true});

      registry.removeSource('point');
      expect(registry.getFeatureState(sourceId: 'point', featureId: 'a'),
          isEmpty);
      // Re-registering the same id must not resurrect the old state.
      registry.setData('point', [_dot('a')]);
      expect(registry.getFeatureState(sourceId: 'point', featureId: 'a'),
          isEmpty);
    });
  });

  group('rendering / query use the same data', () {
    test('queryFeatures sees data written through setData / updateData', () {
      final controller = _flatController();
      addTearDown(controller.dispose);
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);

      registry.setData('point', [_dot('old', lat: 40)]);
      expect(
        registry
            .queryFeatures(const LatLng(0, 0), controller: controller)
            .isEmpty,
        isTrue,
      );

      registry.setData('point', [_dot('new', lat: 0)]);
      final hits =
          registry.queryFeatures(const LatLng(0, 0), controller: controller);
      expect(hits, hasLength(1));
      expect(hits.single.feature.id, 'new');

      registry.updateData(
          'point', GeoSourceDiff(removeAll: true, add: [_dot('diff', lat: 0)]));
      expect(
        registry
            .queryFeatures(const LatLng(0, 0), controller: controller)
            .single
            .feature
            .id,
        'diff',
      );
    });

    test('notifications count matches real mutations', () {
      final registry = GeoFeatureRegistry();
      addTearDown(registry.dispose);
      var notifications = 0;
      registry.addListener(() => notifications++);

      registry.setData('point', [_dot('a')]); // +1
      registry.setData('point', registry.getData('point')); // no-op
      registry.setFeatureState(
          sourceId: 'point', featureId: 'a', state: {'hover': true}); // +1
      expect(notifications, 2);
    });
  });

  group('GeoStyleController source lookup', () {
    test('getSource returns the definition, null for unknown ids', () {
      final controller = GeoStyleController(StyleSpec.parse(<String, Object?>{
        'version': 8,
        'sources': <String, Object?>{
          's': <String, Object?>{'type': 'geojson'},
        },
        'layers': <Object?>[],
      }));
      addTearDown(controller.dispose);

      expect(controller.getSource('s')!['type'], 'geojson');
      expect(controller.getSource('missing'), isNull);
    });

    test('addSource without a type is rejected (style.ts:1092)', () {
      final controller = GeoStyleController(StyleSpec.parse(<String, Object?>{
        'version': 8,
        'sources': <String, Object?>{},
        'layers': <Object?>[],
      }));
      addTearDown(controller.dispose);

      expect(
        () => controller.addSource('bad', <String, Object?>{}),
        throwsArgumentError,
      );
    });
  });
}
