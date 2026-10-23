import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

/// Replaces flutter_map's built-in (affine, Web-Mercator) camera → screen
/// conversion with an arbitrary one, e.g. an orthographic globe.
///
/// This is a **fork-only** extension used to validate the idea in
/// `globe_lab`. When [MapCamera.projectionDelegate] is null, flutter_map
/// behaves exactly as upstream.
abstract class MapProjectionDelegate {
  /// Called by [MapCamera] right before any projection, with the current view
  /// state. Implementations should cache these values; the method must be
  /// cheap and side-effect free apart from that cache.
  void updateCamera(LatLng center, double zoom, Size size);

  /// Screen position of [point].
  ///
  /// Return a position far outside the viewport for points that are not
  /// visible (e.g. on the far side of a globe): flutter_map's layers cull
  /// against `camera.pixelBounds`, so this is the cheapest visibility filter.
  Offset project(LatLng point);

  /// Like [project], but hidden points are clamped onto the silhouette
  /// instead of being pushed far off-screen. Use this for geometry (polygons,
  /// polylines): a path that runs behind the globe must hug the limb, not jump.
  Offset projectForVector(LatLng point);

  /// Whether [point] is on the visible surface (front hemisphere).
  bool isVisible(LatLng point);

  /// Inverse of [project]; `null` when the position is outside the surface.
  LatLng? unproject(Offset localPoint);

  /// New camera centre after dragging by [pixelDelta].
  LatLng panBy(Offset pixelDelta);

  /// Content-follows-finger pan with projection-specific compensation
  /// (globe: 1/cos(lat); flat: affine). [delta] is the finger movement.
  LatLng panCenter(LatLng from, Offset delta, double zoom);

  /// Unit view vector of [point] (x right, y up, z towards camera).
  /// Consumed by the default [anchorCenter]; flat implementations return a
  /// constant since the base formula does not apply.
  (double, double, double) viewDirection(LatLng point);

  /// Keep the map point under [anchor] fixed while zooming
  /// `fromZoom → toZoom`.
  ///
  /// Globe: radius correction via [viewDirection]/[panCenter] (lab-verified).
  /// Flat: normalized-world slippy formula `n(c1) = n(a) − (n(a) − n(c0))/s`.
  LatLng anchorCenter(
      LatLng center, LatLng anchor, double fromZoom, double toZoom);
}
