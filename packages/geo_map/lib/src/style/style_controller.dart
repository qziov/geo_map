/// Runtime style API (M1.4): a `ChangeNotifier` over an immutable
/// [StyleDocument].
///
/// Method names mirror MapLibre's `map.style` (`addSource`, `addLayer`,
/// `moveLayer`, `setPaintProperty`, `setFilter`, …). Every mutation produces a
/// new document and bumps [revision], so the renderer can diff by layer id +
/// revision instead of rebuilding everything.
library;

import 'package:flutter/foundation.dart';
import 'package:geo_map_core/geo_map_core.dart';

class GeoStyleController extends ChangeNotifier {
  GeoStyleController(StyleSpec spec) : _document = StyleDocument.fromSpec(spec);

  GeoStyleController.document(StyleDocument document)
      : _document = document;

  StyleDocument _document;
  int _revision = 0;

  StyleDocument get document => _document;

  /// Monotonic revision; changes only when the document actually changed.
  int get revision => _revision;

  void _set(StyleDocument next) {
    if (identical(next, _document)) return;
    _document = next;
    _revision++;
    notifyListeners();
  }

  // --- sources -----------------------------------------------------------------

  void addSource(String id, Map<String, Object?> source) =>
      _set(_document.addSource(id, source));

  void removeSource(String id) => _set(_document.removeSource(id));

  // --- layers (order = z-order) -------------------------------------------------

  void addLayer(StyleLayer layer, {String? before}) =>
      _set(_document.addLayer(layer, before: before));

  void removeLayer(String id) => _set(_document.removeLayer(id));

  void moveLayer(String id, {String? before}) =>
      _set(_document.moveLayer(id, before: before));

  // --- per-layer operations -----------------------------------------------------

  void setPaintProperty(String id, String name, Object? value) =>
      _set(_document.setPaintProperty(id, name, value));

  void setLayoutProperty(String id, String name, Object? value) =>
      _set(_document.setLayoutProperty(id, name, value));

  void setFilter(String id, Object? filter) =>
      _set(_document.setFilter(id, filter));

  void setLayerZoomRange(String id, num min, num max) =>
      _set(_document.setLayerZoomRange(id, min, max));

  void setVisibility(String id, String visibility) =>
      _set(_document.setVisibility(id, visibility));
}
