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
}
