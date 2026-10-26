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
    // Analytic window. A sampled one misses the extreme longitudes that high
    // latitudes sweep in near the limb (which is exactly where black tiles appear).
    final r = math.max(camera.radiusPx, 1.0);
    final halfDiag = camera.size.diagonal / 2;
    final alpha = math.asin(math.min(1.0, halfDiag / r)); // angular screen radius
    final lat0 = camera.clampedLatitude;

    var south = lat0 - alpha * rad2deg;
    var north = lat0 + alpha * rad2deg;
    // One tile of slack so a tile straddling the edge is not dropped.
    final slackDeg = rad2deg * math.max(8 / r, 0.0) + 0.02;
    // Clamp to the sphere, NOT the mercator limit: the visible band may lie
    // entirely inside the polar cap, and clamping here made the graticule and
    // selector agree on an empty band.
    south = (south - slackDeg).clamp(-90.0, 90.0);
    north = (north + slackDeg).clamp(-90.0, 90.0);
    // Max |Δlng| of a point within `alpha` of the centre, taken over the lat band.
    final phi0 = rad(lat0);
    var maxDLng = 0.0;
    for (var i = 0; i <= 16; i++) {
      final phi = rad(south + (north - south) * i / 16);
      final denom = math.cos(phi0) * math.cos(phi);
      if (denom.abs() < 1e-9) {
        maxDLng = 180;
        break;
      }
      final cosD = (math.cos(alpha) - math.sin(phi0) * math.sin(phi)) / denom;
      if (cosD <= -1.0) {
        maxDLng = 180;
        break;
      }
      final d = math.acos(cosD.clamp(-1.0, 1.0)) * rad2deg;
      if (d > maxDLng) maxDLng = d;
    }
    final padLng = math.min(180.0, maxDLng) + 1.0;

    return GeoBounds(
      south: south,
      north: north,
      west: camera.center.longitude - padLng,
      east: camera.center.longitude + padLng,
    );
  }

}
