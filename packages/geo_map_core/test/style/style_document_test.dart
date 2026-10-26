import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

StyleLayer _layer(String id, {String type = 'fill'}) =>
    StyleLayer.parse({'id': id, 'type': type, 'source': 's'});

void main() {
  StyleDocument base() => StyleDocument.fromSpec(StyleSpec.parse({
        'version': 8,
        'sources': {
          's': {'type': 'geojson'},
        },
        'layers': [
          {'id': 'a', 'type': 'fill', 'source': 's'},
          {'id': 'b', 'type': 'line', 'source': 's'},
        ],
      }));

  test('addLayer inserts before an id, or appends', () {
    final d = base().addLayer(_layer('c'), before: 'b');
    expect(d.layers.map((l) => l.id), ['a', 'c', 'b']);
    final appended = d.addLayer(_layer('d'));
    expect(appended.layers.map((l) => l.id), ['a', 'c', 'b', 'd']);
  });

  test('addLayer rejects duplicate ids', () {
    expect(() => base().addLayer(_layer('a')), throwsArgumentError);
  });

  test('moveLayer reorders', () {
    final d = base().moveLayer('b', before: 'a');
    expect(d.layers.map((l) => l.id), ['b', 'a']);
  });

  test('removeLayer, and the original document is unchanged', () {
    final original = base();
    final d = original.removeLayer('a');
    expect(d.layers.map((l) => l.id), ['b']);
    expect(original.layers.map((l) => l.id), ['a', 'b']);
  });

  test('setPaintProperty evaluates, including colors', () {
    final d = base().setPaintProperty('a', 'fill-color', '#ff0000');
    expect(
      d.layer('a')!.color('fill-color', const ExpressionContext(zoom: 5)),
      const StyleColor(255, 0, 0),
    );
  });

  test('setFilter compiles a predicate', () {
    final d = base().setFilter('a', ['==', 'use', 'park']);
    expect(d.layer('a')!.filter({'use': 'park'}), isTrue);
    expect(d.layer('a')!.filter({'use': 'road'}), isFalse);
  });

  test('setLayerZoomRange and setVisibility', () {
    final d = base().setLayerZoomRange('a', 5, 10).setVisibility('a', 'none');
    expect(d.layer('a')!.minZoom, 5);
    expect(d.layer('a')!.maxZoom, 10);
    expect(d.layer('a')!.isVisibleAt(6), isFalse);
  });

  test('addSource / removeSource', () {
    final d = base().addSource('t', {'type': 'raster'});
    expect(d.sources.containsKey('t'), isTrue);
    expect(() => d.addSource('t', <String, Object?>{}), throwsArgumentError);
    expect(d.removeSource('t').sources.containsKey('t'), isFalse);
  });

  test('toSpec preserves version/sources/layers', () {
    final spec = base().toSpec();
    expect(spec.version, 8);
    expect(spec.sources.containsKey('s'), isTrue);
    expect(spec.layers.length, 2);
  });
}
