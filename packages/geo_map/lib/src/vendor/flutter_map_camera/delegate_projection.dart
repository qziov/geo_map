import 'dart:math' show Point;

import 'crs.dart';
import 'camera.dart';
import 'package:latlong2/latlong.dart';

/// A [Projection] that answers in **screen space** via
/// [MapCamera.projectClamped].
///
/// `PolygonLayer` / `PolylineLayer` pre-project their points through a
/// `Projection` and then let `getOffsetsXY` convert to pixels. In delegate mode
/// the delegate already produced pixels, so this adapter lets those layers keep
/// their existing code path (with `origin == Offset.zero` and a bypass inside
/// `getOffsetsXY`).
class DelegateProjection extends Projection {
  const DelegateProjection(this.camera, {this.hideInvisible = false})
      : super(null);

  final MapCamera camera;

  /// When true, hidden points become `NaN`. Polylines use this so the painter
  /// breaks the path instead of letting a segment cut across the disc
  /// ("showing through the back hemisphere"). Polygons keep clamped points
  /// because a `Path` cannot contain NaN.
  final bool hideInvisible;

  @override
  (double, double) projectXY(LatLng latlng) {
    if (hideInvisible && !camera.isPointVisible(latlng)) {
      return (double.nan, double.nan);
    }
    final p = camera.projectClamped(latlng);
    return (p.x, p.y);
  }

  /// Whether at least one of [points] faces the camera.
  bool anyVisible(Iterable<LatLng> points) {
    for (final p in points) {
      if (camera.isPointVisible(p)) return true;
    }
    return false;
  }

  @override
  LatLng unprojectXY(double x, double y) =>
      camera.unproject(Point<double>(x, y));
}
