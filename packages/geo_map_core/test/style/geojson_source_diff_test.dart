// Contract tests for `geojson_source_diff.dart`, ported from the semantics of
// maplibre-gl-js/src/source/geojson_source_diff.ts (`toUpdateable`,
// `applySourceDiff`). Focus: operation order, id validity, and no-op handling.
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

GeoJsonFeature feature(
  String? id, {
  Map<String, Object?> props = const <String, Object?>{},
  double lat = 0,
  double lng = 0,
}) =>
    GeoJsonFeature(
      id: id,
      properties: props,
      geometry: PointGeometry(LatLng(lat, lng)),
    );

void main() {
  group('indexFeaturesById (toUpdateable)', () {
    test('unique ids can be updated', () {
      final indexed = indexFeaturesById([feature('a'), feature('b')]);
      expect(indexed, isNotNull);
      expect(indexed!.keys.toList(), ['a', 'b']);
    });

    test('a null id makes the whole source non-updateable', () {
      expect(indexFeaturesById([feature('a'), feature(null)]), isNull);
    });

    test('duplicate ids make the whole source non-updateable', () {
      expect(indexFeaturesById([feature('a'), feature('a')]), isNull);
    });

    test('an empty string is a valid id (0 / empty must not be treated falsy)',
        () {
      final indexed = indexFeaturesById([feature('')]);
      expect(indexed, isNotNull);
      expect(indexed!.containsKey(''), isTrue);
    });

    test('an empty source is updateable', () {
      expect(indexFeaturesById(const <GeoJsonFeature>[]), isNotNull);
    });
  });

  group('applySourceDiff ordering', () {
    test('operations run remove -> add -> update', () {
      final base = [
        feature('a', props: const {'k': 1}),
        feature('b'),
      ];
      final result = applySourceDiff(
        base,
        GeoSourceDiff(
          remove: const ['a'],
          add: [feature('a', props: const {'k': 2})],
          update: const [
            GeoSourceUpdate(id: 'a', addOrUpdateProperties: {'k': 3}),
          ],
        ),
      );

      expect(result.changed, isTrue);
      // 'a' was removed then re-added, so it moves to the end.
      expect(result.features.map((f) => f.id).toList(), ['b', 'a']);
      // The update applies to the feature that survived the remove/add phase.
      expect(result.features.last.properties['k'], 3);
    });

    test('removeAll clears first, then add repopulates', () {
      final result = applySourceDiff(
        [feature('a'), feature('b')],
        GeoSourceDiff(removeAll: true, add: [feature('c')]),
      );
      expect(result.features.map((f) => f.id).toList(), ['c']);
      expect(result.affectedCount, 3); // 2 removed + 1 added
    });

    test('add with the same id replaces the feature', () {
      final replacement = feature('a', props: const {'new': true});
      final result = applySourceDiff(
        [feature('a')],
        GeoSourceDiff(add: [replacement]),
      );
      expect(result.features.single, same(replacement));
    });

    test('add without an id is skipped', () {
      final result = applySourceDiff(
        const <GeoJsonFeature>[],
        GeoSourceDiff(add: [feature(null)]),
      );
      expect(result.changed, isFalse);
    });
  });

  group('applySourceDiff boundary handling', () {
    test('removing / updating an unknown id is a silent no-op', () {
      final base = [feature('a')];
      final result = applySourceDiff(
        base,
        const GeoSourceDiff(
          remove: ['missing'],
          update: [
            GeoSourceUpdate(id: 'missing', addOrUpdateProperties: {'x': 1}),
          ],
        ),
      );
      expect(result.changed, isFalse);
      expect(identical(result.features, base), isTrue);
    });

    test('an empty update is a no-op', () {
      final base = [feature('a')];
      final result = applySourceDiff(
        base,
        const GeoSourceDiff(update: [GeoSourceUpdate(id: 'a')]),
      );
      expect(result.changed, isFalse);
      expect(result.affectedCount, 0);
    });

    test('property edits run removeAll -> remove -> addOrUpdate', () {
      final base = [
        feature('a', props: const {'x': 1, 'y': 2}),
      ];
      final result = applySourceDiff(
        base,
        const GeoSourceDiff(
          update: [
            GeoSourceUpdate(
              id: 'a',
              removeAllProperties: false,
              removeProperties: ['x'],
              addOrUpdateProperties: {'y': 9, 'z': 3},
            ),
          ],
        ),
      );
      expect(result.features.single.properties, {'y': 9, 'z': 3});
    });

    test('removeAllProperties drops every existing property', () {
      final result = applySourceDiff(
        [feature('a', props: const {'x': 1, 'y': 2})],
        const GeoSourceDiff(
          update: [
            GeoSourceUpdate(
              id: 'a',
              removeAllProperties: true,
              addOrUpdateProperties: {'z': 3},
            ),
          ],
        ),
      );
      expect(result.features.single.properties, {'z': 3});
    });

    test('newGeometry replaces the geometry but keeps the id and properties',
        () {
      final geometry = PointGeometry(const LatLng(10, 20));
      final result = applySourceDiff(
        [feature('a', props: const {'p': 1})],
        GeoSourceDiff(
          update: [GeoSourceUpdate(id: 'a', newGeometry: geometry)],
        ),
      );
      expect(identical(result.features.single.geometry, geometry), isTrue);
      expect(result.features.single.id, 'a');
      expect(result.features.single.properties['p'], 1);
    });

    test('a non-updateable source rejects the diff without throwing', () {
      final base = [feature(null), feature('a')];
      final result = applySourceDiff(
        base,
        const GeoSourceDiff(remove: ['a']),
      );
      expect(result.changed, isFalse);
      expect(result.affectedCount, 0);
      expect(identical(result.features, base), isTrue);
    });

    test('the returned list is unmodifiable', () {
      final result = applySourceDiff(
        const <GeoJsonFeature>[],
        GeoSourceDiff(add: [feature('a')]),
      );
      expect(
        () => result.features.add(feature('b')),
        throwsUnsupportedError,
      );
    });
  });

  test('GeoSourceDiff.isEmpty', () {
    expect(const GeoSourceDiff().isEmpty, isTrue);
    expect(const GeoSourceDiff(removeAll: true).isEmpty, isFalse);
    expect(const GeoSourceDiff(remove: ['a']).isEmpty, isFalse);
  });
}
