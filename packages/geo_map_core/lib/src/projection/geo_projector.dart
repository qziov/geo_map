/// Stateless projection contract. One implementation per view mode:
/// `MercatorProjector` (2D) and `OrthographicProjector` (3D globe).
///
/// Layers never branch on the mode — they only consume this interface.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../camera/camera_state.dart';
import '../math/geo_geometry.dart';
import '../math/geodesy.dart';

abstract class GeoProjector {
  const GeoProjector();

  /// Stable identifier used in cache keys ('mercator' | 'orthographic').
  String get kind;

  /// Whether the projection has a depth component (back-face culling).
  bool get hasDepth;

  /// Screen position of [geo], or `null` when the point is not drawable
  /// (behind the horizon / outside the world).
  Vec2? project(LatLng geo, CameraState camera);

  /// Same as [project] but takes a unit-sphere vector (mesh vertices avoid
  /// repeated lat/lng → xyz conversions).
  Vec2? projectUnit(Vec3 unit, CameraState camera);

  /// Inverse of [project]. Returns `null` when the screen point misses the globe.
  LatLng? unproject(Vec2 screen, CameraState camera);

  /// `cos` of the angular distance to the camera centre; `1` at the centre,
  /// `0` on the horizon, negative on the far side.
  double depthOf(LatLng geo, CameraState camera);

  /// Circular clip region (globe) or `null` for a rectangular clip (flat map).
  CircleClip? clipCircle(CameraState camera);

  /// Angular step for great-circle densification; `0` when the projection is
  /// affine (Mercator) and densification is unnecessary.
  double densifyStepRad(CameraState camera);

  /// Extra tile rows/columns the tile selector should pad the window by beyond
  /// [approximateVisibleBounds].
  ///
  /// The globe's bounds are sampled at the inflated rectangle's corners and
  /// edge midpoints, which can under-cover the projection's curvature; one
  /// extra row guarantees the window stays a superset of the per-tile test.
  /// An affine projection (Mercator) needs none.
  int get windowPadTiles => 0;

  /// Generous geographic window currently visible — the starting window used by
  /// the tile selector before per-tile verification.
  ///
  /// [marginPx] inflates the viewport rectangle by that many screen pixels
  /// before sampling, so the returned bounds already cover the margin the
  /// per-tile verification uses. On a globe a fixed pixel margin spans more
  /// than one tile row near the poles, so a plain bounds + row-count pad can
  /// drop a tile that only reaches into the margin.
  GeoBounds approximateVisibleBounds(CameraState camera, [double? marginPx]);
}

class CircleClip {
  const CircleClip(this.center, this.radius);

  final Vec2 center;
  final double radius;
}

/// Depth used for back-face tests on unit-sphere geometry.
double depthFromUnitVector(Vec3 view, Vec3 centerUnit) => view.dot(centerUnit);

/// East/north/forward basis at the camera centre.
({Vec3 east, Vec3 north, Vec3 forward}) cameraBasis(LatLng center) {
  final lat = rad(center.latitude);
  final lng = rad(center.longitude);
  final forward = Vec3.of(center);
  final east = Vec3(-math.sin(lng), math.cos(lng), 0);
  final north = Vec3(-math.sin(lat) * math.cos(lng), -math.sin(lat) * math.sin(lng),
      math.cos(lat));
  return (east: east, north: north, forward: forward);
}
