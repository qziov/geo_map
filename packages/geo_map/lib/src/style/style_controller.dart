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

import '../globe/image_overlay.dart' show ImageSource;

class GeoStyleController extends ChangeNotifier {
  GeoStyleController(StyleSpec spec) : _document = StyleDocument.fromSpec(spec);

  GeoStyleController.document(StyleDocument document)
      : _document = document;

  StyleDocument _document;
  int _revision = 0;

  StyleDocument get document => _document;

  /// Monotonic revision; changes only when the document actually changed.
  int get revision => _revision;

  StyleSpec? _specCache;
  int _specCacheRevision = -1;

  /// The current spec, cached by [revision].
  ///
  /// The renderers compare `StyleSpec` by identity in `shouldRepaint`. Calling
  /// `document.toSpec()` on every build produced a fresh object and forced a
  /// repaint even when nothing changed. The cache is invalidated only when a
  /// mutation bumps [revision], so an unchanged style keeps one identity and a
  /// changed style produces exactly one new one.
  StyleSpec get spec {
    if (_specCache == null || _specCacheRevision != _revision) {
      _specCache = _document.toSpec();
      _specCacheRevision = _revision;
    }
    return _specCache!;
  }

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

  // --- runtime images (A2: style documents stay JSON-like / pure Dart) ------

  Map<String, ImageSource> _imageSources = const <String, ImageSource>{};

  /// The images behind `raster` layers, keyed by the source id in the style
  /// document. Registering or removing one rebuilds the renderers but does
  /// **not** bump [revision], because the document itself did not change.
  Map<String, ImageSource> get imageSources => _imageSources;

  void addImageSource(String id, ImageSource source) {
    _imageSources = Map<String, ImageSource>.unmodifiable(
      <String, ImageSource>{..._imageSources, id: source},
    );
    notifyListeners();
  }

  void removeImageSource(String id) {
    if (!_imageSources.containsKey(id)) return;
    _imageSources = Map<String, ImageSource>.unmodifiable(
      <String, ImageSource>{..._imageSources}..remove(id),
    );
    notifyListeners();
  }

  /// Update (or register) the image behind an existing raster layer.
  ///
  /// Used when a time-animated layer swaps its frame: the layer id stays the
  /// same, only the decoded [ui.Image] changes. Like [addImageSource], this
  /// rebuilds the renderers but does **not** bump [revision], because the
  /// document itself did not change.
  void updateImageSource(String id, ImageSource source) {
    _imageSources = Map<String, ImageSource>.unmodifiable(
      <String, ImageSource>{..._imageSources, id: source},
    );
    notifyListeners();
  }

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
