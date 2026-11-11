/// The feature registry — geo_map's counterpart to MapLibre's
/// `GeoJSONSource` + `queryRenderedFeatures`, as a host-owned object.
///
/// A host registers the features it draws, then asks the registry what a tap
/// hit. Since v0.2.2 the registry is also the **single source of truth for the
/// data**: [setData] / [updateData] change both what the renderer draws and
/// what [queryFeatures] sees, so the two can no longer disagree. It is a
/// [ChangeNotifier], so a [StyleVectorLayer] given `registry:` rebuilds when
/// data or feature state changes — the declarative `sources:` constructor
/// parameter remains supported and behaves exactly as before.
///
/// It is deliberately *not* attached to `GeoMap` or `GeoMapController`: the
/// controller is about the camera, the registry is about the host's data, and
/// their lifetimes differ. This mirrors `GeoMapPopupController`, which the
/// host also owns. If a layer listens to this registry, the host must
/// [dispose] it when the layer goes away.
library;

import 'package:flutter/foundation.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';

import '../camera/geo_map_controller.dart';
import '../widget/geo_popup_binding.dart';
import 'geo_pick_projection.dart';
import 'geo_query_hit.dart';

export 'geo_query_hit.dart';

/// The registry of queryable features and their source data.
class GeoFeatureRegistry extends ChangeNotifier {
  final Map<String, _RegisteredSource> _sources =
      <String, _RegisteredSource>{};

  /// `sourceId -> featureId -> state`. Kept separate from the feature
  /// objects: state is host-owned, is not part of the GeoJSON payload, and
  /// changes without replacing the feature (MapLibre `style.ts:1463`).
  final Map<String, Map<String, Map<String, Object?>>> _featureStates =
      <String, Map<String, Map<String, Object?>>>{};

  /// Cached, identity-stable view consumed by `StyleVectorLayer`. Rebuilt only
  /// on a real change, otherwise every frame's rebuild would produce a fresh
  /// Map and defeat `shouldRepaint`'s identity short-circuit.
  Map<String, List<GeoJsonFeature>> _sourcesView =
      const <String, List<GeoJsonFeature>>{};

  int _revision = 0;

  /// Monotonic; increments only when data, visibility or feature state
  /// actually changed. Renderers compare it instead of deep-scanning.
  int get revision => _revision;

  /// All sources keyed by id, as an unmodifiable, identity-stable Map.
  ///
  /// This is what a registry-backed `StyleVectorLayer` draws. Prefer
  /// `registry:` over passing this Map yourself so state changes repaint too.
  Map<String, List<GeoJsonFeature>> get sourcesView => _sourcesView;

  // ---------------------------------------------------------------------------
  // Existing API — signatures and semantics preserved.
  // ---------------------------------------------------------------------------

  /// Register (or replace) the features of one source.
  ///
  /// [visible] hides the whole source without removing it — a layer that is
  /// switched off must not be pickable. [pointRadiusPx] overrides the query's
  /// default pick radius for this source, and [layerId] records which layer
  /// it came from.
  ///
  /// [popup] optionally binds a popup card to this source (the SDK equivalent of
  /// MapLibre `map.on('click', layerId, handler)`); see [GeoPopupBinding]. A
  /// source without a popup is still pickable — it just won't open a card via
  /// [GeoPopupController] (the host may drive a SnackBar or selection instead).
  void setSource(
    String sourceId,
    List<GeoJsonFeature> features, {
    bool visible = true,
    String? layerId,
    double? pointRadiusPx,
    GeoPopupBinding? popup,
  }) =>
      _replace(
        sourceId,
        features,
        visible: visible,
        layerId: layerId,
        pointRadiusPx: pointRadiusPx,
        popup: popup,
      );

  /// Drop a source. Its features are no longer pickable and its feature state
  /// is discarded (MapLibre `style.ts:1130` deletes `_updatedSources[id]`).
  /// A missing id is a silent no-op, matching the pre-existing behaviour.
  void removeSource(String sourceId) {
    if (_sources.remove(sourceId) == null) return;
    _featureStates.remove(sourceId);
    _bump();
  }

  /// Drop every source and all feature state.
  void clear() {
    if (_sources.isEmpty && _featureStates.isEmpty) return;
    _sources.clear();
    _featureStates.clear();
    _bump();
  }

  bool containsSource(String sourceId) => _sources.containsKey(sourceId);

  /// The popup binding registered for [sourceId], or `null` if that source has
  /// no popup card (e.g. it only drives a SnackBar or a selection state).
  GeoPopupBinding? popupOf(String sourceId) => _sources[sourceId]?.popup;

  /// The registered source ids, in registration order.
  Iterable<String> get sourceIds => _sources.keys;

  int get length => _sources.length;

  /// The features under [tap].
  ///
  /// Point features are matched in **screen space** (within [pointRadiusPx]);
  /// area features in **geographic space** (point-in-polygon). The two are
  /// dispatched per feature by its geometry type — see
  /// `planFeatureQuery` in `geo_map_core` for the full contract.
  ///
  /// [sourceIds] and [geometries] narrow the query; [limit] truncates the
  /// result after sorting.
  List<GeoQueryHit> queryFeatures(
    LatLng tap, {
    required GeoMapController controller,
    double? pointRadiusPx,
    Set<String>? sourceIds,
    Set<GeoGeometryKind>? geometries,
    int? limit,
  }) {
    final delegate = controller.delegate;
    final tapScreen = projectForPick(delegate, tap);

    final features = <QueryFeature>[];
    for (final source in _sources.values) {
      if (!source.visible) continue;
      for (final feature in source.features) {
        features.add(
          QueryFeature(
            feature: feature,
            sourceId: source.sourceId,
            visible: source.visible,
            pointRadiusPx: source.pointRadiusPx,
          ),
        );
      }
    }

    final hits = planFeatureQuery(
      features: features,
      tap: tap,
      tapScreen: tapScreen,
      project: (point) => projectForPick(delegate, point),
      pointRadiusPx: pointRadiusPx ?? GeoEngineTuning.featurePickRadiusPx,
      geometries: geometries,
      sourceIds: sourceIds,
      limit: limit,
    );

    return <GeoQueryHit>[
      for (final hit in hits)
        GeoQueryHit(
          feature: hit.feature.feature,
          sourceId: hit.feature.sourceId,
          distancePx: hit.distancePx,
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // MapLibre GeoJSONSource equivalents (new, purely additive).
  // ---------------------------------------------------------------------------

  /// Replace one source's data — geo_map's `source.setData(data)`.
  ///
  /// Unlike MapLibre this is synchronous and also **creates** the source when
  /// the id is unknown (there is no separate `addSource` for data here;
  /// `GeoStyleController.addSource` registers a *style source definition*).
  /// With no worker in between, the last call wins by construction, which is
  /// the same guarantee MapLibre gets from `UpdateQueue.replace` +
  /// `_onWorkerUpdateResult`'s `replaced` check.
  void setData(
    String sourceId,
    List<GeoJsonFeature> features, {
    bool visible = true,
    String? layerId,
    double? pointRadiusPx,
    GeoPopupBinding? popup,
  }) =>
      setSource(
        sourceId,
        features,
        visible: visible,
        layerId: layerId,
        pointRadiusPx: pointRadiusPx,
        popup: popup,
      );

  /// Read a source's current data (MapLibre `getData`).
  ///
  /// Synchronous because geo_map has no URL-backed source to await. Returns an
  /// empty, immutable list for an unknown id — MapLibre's `getSource` returns
  /// `undefined`, but an empty list is safer in Dart and keeps callers free of
  /// null checks.
  List<GeoJsonFeature> getData(String sourceId) =>
      _sources[sourceId]?.features ?? const <GeoJsonFeature>[];

  /// Get a handle by id, or `null` when the source does not exist.
  ///
  /// Mirrors `map.getSource(id) -> Source | undefined`. Use [source] instead
  /// when you want a get-or-create handle.
  GeoSourceHandle? getSource(String sourceId) =>
      containsSource(sourceId) ? GeoSourceHandle._(this, sourceId) : null;

  /// Get-or-create handle, so a host can write
  /// `registry.source('point').setData(points)` without a separate
  /// registration step. The source is created on the first `setData`.
  GeoSourceHandle source(String sourceId) => GeoSourceHandle._(this, sourceId);

  /// Apply an incremental [GeoSourceDiff] (MapLibre `updateData`).
  ///
  /// Returns `false` without notifying when the source is unknown, the diff is
  /// empty, the data is not updateable (a feature has no id, or ids are
  /// duplicated — `toUpdateable` in `geojson_source_diff.ts`), or nothing
  /// actually changed. Hosts can fall back to [setData] on `false`.
  bool updateData(String sourceId, GeoSourceDiff diff) {
    final current = _sources[sourceId];
    if (current == null || diff.isEmpty) return false;
    final result = applySourceDiff(current.features, diff);
    if (!result.changed) return false;
    _replace(
      sourceId,
      result.features,
      visible: current.visible,
      layerId: current.layerId,
      pointRadiusPx: current.pointRadiusPx,
      popup: current.popup,
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // Feature state (MapLibre `style.ts:1463-1541`).
  // ---------------------------------------------------------------------------

  /// Prototype-pollution keys rejected by MapLibre `style.ts:1486-1490`.
  static const Set<String> _forbiddenStateKeys = <String>{
    '__proto__',
    'constructor',
    'prototype',
  };

  /// Merge [state] into one feature's runtime state.
  ///
  /// Mirrors MapLibre's boundary handling: an unknown source, a missing
  /// feature id, or a forbidden state key is a **silent no-op** (MapLibre
  /// fires an error event and returns rather than throwing). Unlike MapLibre
  /// there is no `sourceLayer` concept here — geo_map's GeoJSON sources are
  /// single-layer, so that check does not apply.
  void setFeatureState({
    required String sourceId,
    required String featureId,
    required Map<String, Object?> state,
  }) {
    if (!containsSource(sourceId) || featureId.isEmpty) return;
    if (state.keys.any(_forbiddenStateKeys.contains)) return;

    final perSource = _featureStates.putIfAbsent(
        sourceId, () => <String, Map<String, Object?>>{});
    final current = perSource[featureId] ?? const <String, Object?>{};
    final next = <String, Object?>{...current, ...state};
    if (_mapEquals(current, next)) return;

    perSource[featureId] = Map<String, Object?>.unmodifiable(next);
    _bump(rebuildView: false);
  }

  /// Read one feature's state. Empty when unset or the source is unknown.
  Map<String, Object?> getFeatureState({
    required String sourceId,
    required String featureId,
  }) =>
      _featureStates[sourceId]?[featureId] ?? const <String, Object?>{};

  /// Remove state.
  ///
  /// * no [featureId] → clear the whole source's state;
  /// * with [key] → remove just that key (a feature id is mandatory, matching
  ///   MapLibre `style.ts:1513-1516`);
  /// * otherwise → drop the feature's state entirely.
  void removeFeatureState({
    required String sourceId,
    String? featureId,
    String? key,
  }) {
    final perSource = _featureStates[sourceId];
    if (perSource == null) return;
    if (key != null && (featureId == null || featureId.isEmpty)) return;

    if (featureId == null) {
      if (perSource.isEmpty) return;
      perSource.clear();
    } else if (key != null) {
      final current = perSource[featureId];
      if (current == null || !current.containsKey(key)) return;
      final next = <String, Object?>{...current}..remove(key);
      if (next.isEmpty) {
        perSource.remove(featureId);
      } else {
        perSource[featureId] = Map<String, Object?>.unmodifiable(next);
      }
    } else {
      if (perSource.remove(featureId) == null) return;
    }

    if (perSource.isEmpty) _featureStates.remove(sourceId);
    _bump(rebuildView: false);
  }

  // ---------------------------------------------------------------------------
  // Internals.
  // ---------------------------------------------------------------------------

  void _replace(
    String sourceId,
    List<GeoJsonFeature> features, {
    required bool visible,
    required String? layerId,
    required double? pointRadiusPx,
    required GeoPopupBinding? popup,
  }) {
    final next = List<GeoJsonFeature>.unmodifiable(features);
    final old = _sources[sourceId];
    if (old != null &&
        old.visible == visible &&
        old.layerId == layerId &&
        old.pointRadiusPx == pointRadiusPx &&
        identical(old.popup, popup) &&
        _sameFeatures(old.features, next)) {
      return; // idempotent: same data must not repaint
    }
    _sources[sourceId] = _RegisteredSource(
      sourceId: sourceId,
      features: next,
      visible: visible,
      layerId: layerId,
      pointRadiusPx: pointRadiusPx,
      popup: popup,
    );
    _bump();
  }

  /// Rebuild [sourcesView] only when the **data** changed. A feature-state
  /// change still needs a repaint (hence the revision + notification) but must
  /// keep the data view identity-stable, otherwise renderers would treat it as
  /// a source replacement.
  void _bump({bool rebuildView = true}) {
    _revision++;
    if (rebuildView) {
      _sourcesView = Map<String, List<GeoJsonFeature>>.unmodifiable(
        <String, List<GeoJsonFeature>>{
          for (final entry in _sources.entries) entry.key: entry.value.features,
        },
      );
    }
    notifyListeners();
  }

  static bool _sameFeatures(
      List<GeoJsonFeature> a, List<GeoJsonFeature> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}

/// A per-source view over a [GeoFeatureRegistry].
///
/// Lets hosts write `registry.getSource('point')?.setData(points)` in the same
/// shape as `map.getSource('point').setData(...)` without exposing the whole
/// registry's surface.
class GeoSourceHandle {
  GeoSourceHandle._(this._registry, this.sourceId);

  final GeoFeatureRegistry _registry;
  final String sourceId;

  List<GeoJsonFeature> getData() => _registry.getData(sourceId);

  void setData(List<GeoJsonFeature> features) =>
      _registry.setData(sourceId, features);

  bool updateData(GeoSourceDiff diff) =>
      _registry.updateData(sourceId, diff);

  Map<String, Object?> getFeatureState(String featureId) =>
      _registry.getFeatureState(sourceId: sourceId, featureId: featureId);

  void setFeatureState(String featureId, Map<String, Object?> state) =>
      _registry.setFeatureState(
          sourceId: sourceId, featureId: featureId, state: state);

  void removeFeatureState({String? featureId, String? key}) =>
      _registry.removeFeatureState(
          sourceId: sourceId, featureId: featureId, key: key);

  bool get isEmpty => getData().isEmpty;
}

/// One registered source and the settings that apply to it.
class _RegisteredSource {
  _RegisteredSource({
    required this.sourceId,
    required this.features,
    required this.visible,
    this.layerId,
    this.pointRadiusPx,
    this.popup,
  });

  final String sourceId;
  final List<GeoJsonFeature> features;
  final bool visible;
  final String? layerId;
  final double? pointRadiusPx;
  final GeoPopupBinding? popup;
}
