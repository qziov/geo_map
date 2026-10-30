/// The feature registry — MapLibre's `queryRenderedFeatures`, as a host-owned
/// object.
///
/// A host registers the features it draws (the very same `GeoJsonFeature`
/// instances its style layer renders), then asks the registry what a tap
/// hit. The registry is a **snapshot**, not an observable: the host rebuilds
/// or replaces it when its data changes, so the registry can never disagree
/// with what is on screen.
///
/// It is deliberately *not* attached to `GeoMap` or `GeoMapController`: the
/// controller is about the camera, the registry is about the host's data, and
/// their lifetimes differ. This mirrors `GeoMapPopupController`, which the
/// host also owns.
library;

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';

import '../camera/geo_map_controller.dart';
import 'geo_pick_projection.dart';

/// A feature that answered a query.
class GeoQueryHit {
  const GeoQueryHit({
    required this.feature,
    required this.sourceId,
    this.distancePx,
  });

  /// The registered feature, with its id and properties intact — the host
  /// maps it back to its own object (usually by [GeoJsonFeature.id]).
  final GeoJsonFeature feature;

  /// The source the feature was registered under.
  final String sourceId;

  /// Screen distance in pixels for point features; `null` for areas.
  final double? distancePx;
}

/// The registry of queryable features.
class GeoFeatureRegistry {
  final Map<String, _RegisteredSource> _sources = <String, _RegisteredSource>{};

  /// Register (or replace) the features of one source.
  ///
  /// [visible] hides the whole source without removing it — a layer that is
  /// switched off must not be pickable. [pointRadiusPx] overrides the query's
  /// default pick radius for this source, and [layerId] records which layer
  /// it came from.
  void setSource(
    String sourceId,
    List<GeoJsonFeature> features, {
    bool visible = true,
    String? layerId,
    double? pointRadiusPx,
  }) {
    _sources[sourceId] = _RegisteredSource(
      sourceId: sourceId,
      features: List<GeoJsonFeature>.unmodifiable(features),
      visible: visible,
      layerId: layerId,
      pointRadiusPx: pointRadiusPx,
    );
  }

  /// Drop a source. Its features are no longer pickable.
  void removeSource(String sourceId) => _sources.remove(sourceId);

  /// Drop every source.
  void clear() => _sources.clear();

  bool containsSource(String sourceId) => _sources.containsKey(sourceId);

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
}

/// One registered source and the settings that apply to it.
class _RegisteredSource {
  _RegisteredSource({
    required this.sourceId,
    required this.features,
    required this.visible,
    this.layerId,
    this.pointRadiusPx,
  });

  final String sourceId;
  final List<GeoJsonFeature> features;
  final bool visible;
  final String? layerId;
  final double? pointRadiusPx;
}
