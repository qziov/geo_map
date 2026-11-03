import 'package:geo_map_core/geo_map_core.dart';

/// A feature that answered a query.
///
/// Returned by [GeoFeatureRegistry.queryFeatures]; the host maps [feature.id]
/// back to its own domain object (usually by [GeoJsonFeature.id]).
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
