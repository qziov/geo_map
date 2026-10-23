/// Camera kinematics: pan, anchor-preserving zoom, constraints.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../math/geo_geometry.dart';
import '../math/geodesy.dart';
import '../math/projections.dart';
import '../projection/geo_projector.dart';
import '../tuning/geo_engine_tuning.dart';
import 'camera_state.dart';

class CameraMath {
  const CameraMath._();

  static LatLng _clampCenter(LatLng c) {
    final lat = c.latitude.clamp(
        -GeoEngineTuning.maxCameraLatitude, GeoEngineTuning.maxCameraLatitude);
    return LatLng(lat, wrapLongitude(c.longitude));
  }

  /// Move the camera so the map content shifts by ([dxPx], [dyPx]) pixels.
  static CameraState panByPixels(
    CameraState camera,
    GeoProjector projector,
    double dxPx,
    double dyPx,
  ) {
    if (projector.kind == 'mercator') {
      final world = camera.worldSize;
      final scale = world / 360.0;
      final dLng = -dxPx / scale;
      // Mercator y is non-linear in latitude: convert via world-t.
      final t = mercatorTAt(camera.center.latitude);
      final tNew = t - dyPx / world;
      final latNew = mercatorLatitudeAt(tNew.clamp(0.0, 1.0));
      return camera.copyWith(
        center: LatLng(
          latNew.clamp(-mercatorMaxLatitude, mercatorMaxLatitude),
          wrapLongitude(camera.center.longitude + dLng),
        ),
      );
    }

    // Globe: longitude moves faster near the poles (classic 1/cos(lat) compensation).
    final r = camera.radiusPx;
    final cosLat = math.max(math.cos(rad(camera.center.latitude)).abs(), 1e-6);
    final dLng = (-dxPx / r) / cosLat * rad2deg;
    final dLat = (dyPx / r) * rad2deg;
    return camera.copyWith(
      center: _clampCenter(LatLng(
        camera.center.latitude + dLat,
        camera.center.longitude + dLng,
      )),
    );
  }

  /// Zoom to [targetZoom] while keeping the geodetic point under [anchor]
  /// pinned to that screen position (MapLibre / flutter_map behaviour).
  ///
  /// Solved iteratively with [panByPixels]; converges in 2–3 passes because the
  /// residual is a pure screen-space translation.
  static CameraState zoomAround(
    CameraState camera,
    GeoProjector projector,
    double targetZoom,
    Vec2 anchor, {
    int iterations = 3,
  }) {
    final zoomed = camera.copyWith(
      zoom: targetZoom.clamp(camera.minZoom, camera.maxZoom),
    );
    if (zoomed.zoom == camera.zoom) return camera;

    final geo = projector.unproject(anchor, camera);
    if (geo == null) return zoomed; // anchor off-globe: plain centre zoom

    var result = zoomed;
    for (var i = 0; i < iterations; i++) {
      final projected = projector.project(geo, result);
      if (projected == null) break;
      final errX = anchor.x - projected.x;
      final errY = anchor.y - projected.y;
      if (errX.abs() < 1e-9 && errY.abs() < 1e-9) break;
      result = panByPixels(result, projector, errX, errY);
    }
    return result;
  }

  /// Clamp a zoom value into the camera range.
  static double clampZoom(CameraState camera, double zoom) =>
      zoom.clamp(camera.minZoom, camera.maxZoom);
}
