/// Orthographic globe projector — the 3D view.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../camera/camera_state.dart';
import '../math/geo_geometry.dart';
import '../math/geodesy.dart';
import '../tuning/geo_engine_tuning.dart';
import 'geo_projector.dart';

class OrthographicProjector extends GeoProjector {
  const OrthographicProjector();

  @override
  String get kind => 'orthographic';

  @override
  bool get hasDepth => true;

  static Vec3 _view(LatLng geo, CameraState camera) {
    final p = Vec3.of(geo);
    final basis = cameraBasis(
        LatLng(camera.clampedLatitude, camera.center.longitude));
    return Vec3(p.dot(basis.east), p.dot(basis.north), p.dot(basis.forward));
  }

  @override
  Vec2? project(LatLng geo, CameraState camera) {
    final v = _view(geo, camera);
    if (v.z <= GeoEngineTuning.epsDepth) return null;
    final r = camera.radiusPx;
    return Vec2(
      camera.size.width / 2 + v.x * r,
      camera.size.height / 2 - v.y * r,
    );
  }

  @override
  Vec2? projectUnit(Vec3 unit, CameraState camera) {
    final basis = cameraBasis(
        LatLng(camera.clampedLatitude, camera.center.longitude));
    final z = unit.dot(basis.forward);
    if (z <= GeoEngineTuning.epsDepth) return null;
    final r = camera.radiusPx;
    return Vec2(
      camera.size.width / 2 + unit.dot(basis.east) * r,
      camera.size.height / 2 - unit.dot(basis.north) * r,
    );
  }

  @override
  LatLng? unproject(Vec2 screen, CameraState camera) {
    final r = camera.radiusPx;
    if (r <= 0) return null;
    final vx = (screen.x - camera.size.width / 2) / r;
    final vy = -(screen.y - camera.size.height / 2) / r;
    final r2 = vx * vx + vy * vy;
    if (r2 > 1.0) return null; // outside the disc
    final vz = math.sqrt(math.max(0.0, 1.0 - r2));
    final basis = cameraBasis(
        LatLng(camera.clampedLatitude, camera.center.longitude));
    final p = basis.east * vx + basis.north * vy + basis.forward * vz;
    return p.toLatLng();
  }

  @override
  double depthOf(LatLng geo, CameraState camera) => _view(geo, camera).z;

  @override
  CircleClip? clipCircle(CameraState camera) =>
      CircleClip(camera.size.center, camera.radiusPx);

  @override
  double densifyStepRad(CameraState camera) => densifyStepForPixelError(
      camera.radiusPx, GeoEngineTuning.densifyPixelError);

  @override
  GeoBounds approximateVisibleBounds(CameraState camera) {
    // Exact visible footprint from the viewport, not an analytic angular
    // radius. The old formula used `asin(halfDiag / r)` — the viewport's angle
    // as seen from the *globe centre* — which, for an orthographic globe, is
    // only correct when the disc is larger than the viewport; once the disc is
    // smaller it clamps to 90° and the window collapses to the whole front
    // hemisphere regardless of zoom. MapLibre (`getBounds`) instead unprojects
    // the viewport corners and takes the lat/lng extremes, snapping off-disc
    // samples to the horizon ring.
    final w = camera.size.width;
    final h = camera.size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = math.max(camera.radiusPx, 1.0);
    final center = camera.center;

    // Four corners + four edge midpoints.
    const samples = <(double, double)>[
      (0.0, 0.0),
      (0.5, 0.0),
      (1.0, 0.0),
      (1.0, 0.5),
      (1.0, 1.0),
      (0.5, 1.0),
      (0.0, 1.0),
      (0.0, 0.5),
    ];

    LatLng? unprojectClamped(double fx, double fy) {
      final p = Vec2(fx * w, fy * h);
      var geo = unproject(p, camera);
      if (geo == null) {
        // Off the disc: snap to the nearest point on the limb (horizon ring),
        // i.e. along the ray from the disc centre, at radius r.
        final dx = p.x - cx;
        final dy = p.y - cy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1e-6) return null;
        final t = r / len;
        geo = unproject(Vec2(cx + dx * t, cy + dy * t), camera);
      }
      return geo;
    }

    var mostWest = 0.0, mostEast = 0.0, mostNorth = 0.0, mostSouth = 0.0;
    var anyOnGlobe = false;
    for (final s in samples) {
      final geo = unprojectClamped(s.$1, s.$2);
      if (geo == null) continue;
      anyOnGlobe = true;
      final dLng = _angularDiff(geo.longitude, center.longitude);
      final dLat = geo.latitude - center.latitude;
      if (dLng < mostWest) mostWest = dLng;
      if (dLng > mostEast) mostEast = dLng;
      if (dLat > mostNorth) mostNorth = dLat;
      if (dLat < mostSouth) mostSouth = dLat;
    }

    // A pole on screen means the meridians converge there and the visible
    // longitude span opens to the full ±180 — the same case MapLibre's
    // `getBounds` patches after sampling the corners.
    final poleMargin = math.min(w, h) * 0.05;
    void checkPole(double lat, double setNorthFromCenter, double setSouthFromCenter) {
      final p = project(LatLng(lat, center.longitude), camera);
      if (p == null) return;
      if (p.x < -poleMargin ||
          p.x > w + poleMargin ||
          p.y < -poleMargin ||
          p.y > h + poleMargin) {
        return;
      }
      if (setNorthFromCenter > mostNorth) mostNorth = setNorthFromCenter;
      if (setSouthFromCenter < mostSouth) mostSouth = setSouthFromCenter;
      mostWest = -180;
      mostEast = 180;
    }
    checkPole(90, 90 - center.latitude, 0);
    checkPole(-90, 0, -90 - center.latitude);

    if (!anyOnGlobe) {
      // Disc entirely off-screen: nothing visible — return a degenerate point.
      return GeoBounds(
        south: center.latitude,
        west: center.longitude,
        north: center.latitude,
        east: center.longitude,
      );
    }

    return GeoBounds(
      south: center.latitude + mostSouth,
      north: center.latitude + mostNorth,
      west: center.longitude + mostWest,
      east: center.longitude + mostEast,
    );
  }

  /// Shortest signed angular difference `a - b` in (-180, 180].
  static double _angularDiff(double a, double b) {
    var d = (a - b) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

}
