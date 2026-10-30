/// The feature-query planner (pure Dart, no `dart:ui`).
///
/// This is the *decision* half of MapLibre's `queryRenderedFeatures`: given a
/// set of registered features and a tapped coordinate, decide which ones the
/// tap hit and in which order.
///
/// It lives in the core because that is where decisions belong (see
/// `docs/ARCHITECTURE.md`): the engine depends on `dart:ui` and cannot be
/// unit-tested here, so anything decided there escapes `dart test`.
///
/// Two strategies are dispatched **per feature, by geometry type**:
///
/// * **Point** → screen space: the feature is projected and compared to the
///   tap in pixels, within [pointRadiusPx]. This matches what the user sees:
///   a 12 px dot is grabbable within a 24 px radius.
/// * **Area** → geographic space: `pointInPolygon`, so the result does not
///   depend on zoom, pan, world copies or globe occlusion.
///
/// **Line features are not picked** in this version. They are skipped
/// silently by the planner but documented here, so a caller is never misled
/// into thinking a line was tested.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../math/geo_geometry.dart' show Vec2;
import '../math/point_in_polygon.dart';
import '../style/geojson.dart';
import '../tuning/geo_engine_tuning.dart';

/// The geometry kinds a query can consider.
enum GeoGeometryKind { point, line, polygon }

/// The kind of [geometry], for use as a filter.
GeoGeometryKind geometryKindOf(GeoJsonGeometry geometry) => switch (geometry) {
      PointGeometry() => GeoGeometryKind.point,
      LineStringGeometry() || MultiLineStringGeometry() => GeoGeometryKind.line,
      PolygonGeometry() || MultiPolygonGeometry() => GeoGeometryKind.polygon,
    };

/// A feature registered for querying.
///
/// It wraps the host's own [GeoJsonFeature], so a hit carries the feature's
/// id **and** its properties back to the caller — the registry does not have
/// to keep a second lookup table, and two sources may reuse the same id
/// without colliding.
class QueryFeature {
  const QueryFeature({
    required this.feature,
    this.sourceId = '',
    this.visible = true,
    this.pointRadiusPx,
  });

  final GeoJsonFeature feature;

  /// Groups features by origin. Sources are reported in registration order.
  final String sourceId;

  /// A hidden feature is skipped entirely (a turned-off layer).
  final bool visible;

  /// Overrides the query's default pick radius for this feature.
  final double? pointRadiusPx;

  /// The feature's id, or the empty string when it has none.
  String get id => feature.id ?? '';
}

/// A feature that answered the query.
class QueryHit {
  const QueryHit({required this.feature, this.distancePx});

  final QueryFeature feature;

  /// Screen distance in pixels for point features; `null` for areas.
  final double? distancePx;
}

/// Which registered features does [tap] hit?
///
/// [tapScreen] is the tap's own screen position; `null` disables point
/// picking (area picking still works).
///
/// [project] must return `null` for points that cannot be picked — the far
/// side of the globe, for instance. The planner skips those, so a back-side
/// point never falsely hits a point near the limb. This is the one contract
/// the core relies on the caller for, because the core cannot see the
/// projection delegate.
///
/// **Order** (the host may rely on it):
///
/// 1. grouped by [QueryFeature.sourceId], sources in registration order;
/// 2. within a source, point features first — by ascending screen distance,
///    ties broken so that the **later-registered** feature comes first
///    ("topmost wins", matching the draw order);
/// 3. within a source, area features last, in registration order.
List<QueryHit> planFeatureQuery({
  required List<QueryFeature> features,
  required LatLng tap,
  required Vec2? tapScreen,
  required Vec2? Function(LatLng point) project,
  double pointRadiusPx = GeoEngineTuning.featurePickRadiusPx,
  Set<GeoGeometryKind>? geometries,
  Set<String>? sourceIds,
  int? limit,
}) {
  // --- 1. filter ------------------------------------------------------------
  final candidates = <QueryFeature>[];
  for (final feature in features) {
    if (!feature.visible) continue;
    if (sourceIds != null && !sourceIds.contains(feature.sourceId)) continue;
    if (geometries != null &&
        !geometries.contains(geometryKindOf(feature.feature.geometry))) {
      continue;
    }
    candidates.add(feature);
  }
  if (candidates.isEmpty) return const <QueryHit>[];

  // --- 2. dispatch by geometry kind -----------------------------------------
  final points = <_PointHit>[];
  final areas = <QueryFeature>[];
  for (var i = 0; i < candidates.length; i++) {
    final feature = candidates[i];
    final geometry = feature.feature.geometry;
    if (geometry is PointGeometry) {
      if (tapScreen == null) continue;
      final screen = project(geometry.point);
      if (screen == null) continue;
      final dx = screen.x - tapScreen.x;
      final dy = screen.y - tapScreen.y;
      final radius = feature.pointRadiusPx ?? pointRadiusPx;
      if (radius <= 0) continue;
      final distanceSq = dx * dx + dy * dy;
      if (distanceSq <= radius * radius) {
        points.add(_PointHit(feature, math.sqrt(distanceSq), i));
      }
    } else if (geometry is PolygonGeometry) {
      if (pointInPolygon(geometry.rings, tap)) areas.add(feature);
    } else if (geometry is MultiPolygonGeometry) {
      if (pointInMultiPolygon(geometry.polygons, tap)) areas.add(feature);
    }
    // Line features are not picked (see the library doc comment).
  }
  if (points.isEmpty && areas.isEmpty) return const <QueryHit>[];

  // --- 3. group by source, sources in registration order --------------------
  final sourceOrder = <String>[];
  final seen = <String>{};
  for (final feature in candidates) {
    if (seen.add(feature.sourceId)) sourceOrder.add(feature.sourceId);
  }

  final pointsBySource = <String, List<_PointHit>>{};
  final areasBySource = <String, List<QueryFeature>>{};
  for (final hit in points) {
    (pointsBySource[hit.feature.sourceId] ??= <_PointHit>[]).add(hit);
  }
  for (final feature in areas) {
    (areasBySource[feature.sourceId] ??= <QueryFeature>[]).add(feature);
  }

  final out = <QueryHit>[];
  for (final sourceId in sourceOrder) {
    final sourcePoints = pointsBySource[sourceId];
    if (sourcePoints != null && sourcePoints.isNotEmpty) {
      sourcePoints.sort((a, b) {
        final byDistance = a.distance.compareTo(b.distance);
        // Equal distance → the later registration wins (it is drawn on top).
        return byDistance != 0 ? byDistance : b.index.compareTo(a.index);
      });
      for (final hit in sourcePoints) {
        out.add(QueryHit(feature: hit.feature, distancePx: hit.distance));
      }
    }
    final sourceAreas = areasBySource[sourceId];
    if (sourceAreas != null) {
      for (final feature in sourceAreas) {
        out.add(QueryHit(feature: feature));
      }
    }
  }

  if (limit != null && limit >= 0 && out.length > limit) {
    return out.sublist(0, limit);
  }
  return out;
}

/// A point hit with its screen distance and registration index.
class _PointHit {
  _PointHit(this.feature, this.distance, this.index);

  final QueryFeature feature;
  final double distance;
  final int index;
}
