/// Immutable, testable style state behind the runtime API (M1.4).
///
/// Mirrors the mutable operations of MapLibre's `map.style` (`addSource`,
/// `addLayer`, `moveLayer`, `setPaintProperty`, `setFilter`, …) while keeping
/// every mutation a *new* document. The Flutter `GeoStyleController` wraps this
/// with a `ChangeNotifier` + revision counter; keeping the state machine here
/// (pure Dart) makes the semantics unit-testable without `dart:ui`.
library;

import 'style_filter.dart';
import 'style_properties.dart';
import 'style_spec.dart';

class StyleDocument {
  StyleDocument({
    this.version = 8,
    Map<String, Map<String, Object?>> sources = const {},
    List<StyleLayer> layers = const [],
  })  : sources = Map.unmodifiable(sources),
        layers = List.unmodifiable(layers);

  factory StyleDocument.fromSpec(StyleSpec spec) => StyleDocument(
        version: spec.version,
        sources: spec.sources,
        layers: spec.layers,
      );

  final int version;
  final Map<String, Map<String, Object?>> sources;
  final List<StyleLayer> layers;

  StyleSpec toSpec() =>
      StyleSpec(version: version, sources: sources, layers: layers);

  StyleLayer? layer(String id) {
    for (final l in layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  // --- sources -----------------------------------------------------------------

  StyleDocument addSource(String id, Map<String, Object?> source) {
    if (sources.containsKey(id)) {
      throw ArgumentError('source already exists: $id');
    }
    return _copy(sources: {...sources, id: Map.unmodifiable(source)});
  }

  StyleDocument removeSource(String id) {
    if (!sources.containsKey(id)) return this;
    return _copy(sources: {...sources}..remove(id));
  }

  // --- layers (order = z-order) -------------------------------------------------

  StyleDocument addLayer(StyleLayer layer, {String? before}) {
    if (this.layer(layer.id) != null) {
      throw ArgumentError('layer already exists: ${layer.id}');
    }
    final next = [...layers];
    next.insert(_insertIndex(next, before), layer);
    return _copy(layers: next);
  }

  StyleDocument removeLayer(String id) {
    if (layer(id) == null) return this;
    return _copy(layers: [for (final l in layers) if (l.id != id) l]);
  }

  StyleDocument moveLayer(String id, {String? before}) {
    final moving = layer(id);
    if (moving == null) return this;
    final rest = [for (final l in layers) if (l.id != id) l];
    rest.insert(_insertIndex(rest, before), moving);
    return _copy(layers: rest);
  }

  // --- per-layer operations -----------------------------------------------------

  StyleDocument setPaintProperty(String id, String name, Object? value) =>
      _updateLayer(id, (l) {
        final def = layerPaintDefs[l.type]?[name];
        return l.copyWith(paint: {
          ...l.paint,
          name: PropertyValue.fromJson(
            value,
            isColor: def?.type == StylePropertyType.color,
          ),
        });
      });

  StyleDocument setLayoutProperty(String id, String name, Object? value) =>
      _updateLayer(id, (l) {
        final def = layerLayoutDefs[l.type]?[name];
        return l.copyWith(layout: {
          ...l.layout,
          name: PropertyValue.fromJson(
            value,
            isColor: def?.type == StylePropertyType.color,
          ),
        });
      });

  StyleDocument setFilter(String id, Object? filter) =>
      _updateLayer(id, (l) => l.copyWith(filter: compileFilter(filter)));

  StyleDocument setLayerZoomRange(String id, num min, num max) =>
      _updateLayer(id, (l) => l.copyWith(minZoom: min, maxZoom: max));

  StyleDocument setVisibility(String id, String visibility) =>
      setLayoutProperty(id, 'visibility', visibility);

  // --- internal -----------------------------------------------------------------

  int _insertIndex(List<StyleLayer> list, String? before) {
    if (before == null) return list.length;
    final index = list.indexWhere((l) => l.id == before);
    return index < 0 ? list.length : index;
  }

  StyleDocument _updateLayer(String id, StyleLayer Function(StyleLayer) update) {
    final index = layers.indexWhere((l) => l.id == id);
    if (index < 0) return this;
    final next = [...layers];
    next[index] = update(next[index]);
    return _copy(layers: next);
  }

  StyleDocument _copy({
    Map<String, Map<String, Object?>>? sources,
    List<StyleLayer>? layers,
  }) =>
      StyleDocument(
        version: version,
        sources: sources ?? this.sources,
        layers: layers ?? this.layers,
      );
}
