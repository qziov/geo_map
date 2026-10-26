/// Web Mercator (EPSG:3857) projector — the 2D flat map.
library;

import 'package:latlong2/latlong.dart';

import '../camera/camera_state.dart';
import '../math/geo_geometry.dart';
import '../math/geodesy.dart';
import '../math/projections.dart';
import '../tuning/geo_engine_tuning.dart';
import 'geo_projector.dart';

class MercatorProjector extends GeoProjector {
  const MercatorProjector();

  @override
  String get kind => 'mercator';

  @override
  bool get hasDepth => false;

  @override
  Vec2? project(LatLng geo, CameraState camera) {
    final world = camera.worldSize;
    final lat = clampMercatorLat(geo.latitude);
    // The longitude is taken **relative to the camera**, wrapped into
    // [-180, 180). That makes the projection periodic: a point at -180° with
    // the camera at 179° lands 1° east of the camera instead of jumping a
    // whole world to the left — which is what the antimeridian needs, and what
    // the renderer draws (the tile is repeated at every world copy).
    final dx = wrapLongitude(geo.longitude - camera.center.longitude);
    final x = dx / 360 * world;
    final y = mercatorTAt(lat) * world;
    final yc = mercatorTAt(camera.center.latitude) * world;
    return Vec2(
      x + camera.size.width / 2,
      y - yc + camera.size.height / 2,
    );
  }

  @override
  Vec2? projectUnit(Vec3 unit, CameraState camera) => project(unit.toLatLng(), camera);

  @override
  LatLng? unproject(Vec2 screen, CameraState camera) {
    final world = camera.worldSize;
    final dx = (screen.x - camera.size.width / 2) / world * 360;
    final yc = mercatorTAt(camera.center.latitude) * world;
    final y = screen.y - camera.size.height / 2 + yc;
    final lng = camera.center.longitude + dx;
    final t = (y / world).clamp(0.0, 1.0);
    return LatLng(mercatorLatitudeAt(t), wrapLongitude(lng));
  }

  @override
  double depthOf(LatLng geo, CameraState camera) => 1.0;

  @override
  CircleClip? clipCircle(CameraState camera) => null;

  @override
  double densifyStepRad(CameraState camera) => 0;

  @override
  GeoBounds approximateVisibleBounds(CameraState camera, [double? marginPx]) {
    final world = camera.worldSize;
    final halfW = camera.size.width / 2;
    final halfH = camera.size.height / 2;
    final yc = mercatorTAt(camera.center.latitude) * world;
    final m = marginPx ?? 0;
    final w = camera.size.width;
    final h = camera.size.height;
    final samples = [
      Vec2(-m, -m),
      Vec2(w + m, -m),
      Vec2(-m, h + m),
      Vec2(w + m, h + m),
      camera.size.center,
    ];

    // The longitude is measured **relative to the camera** and is never
    // wrapped here: the window must stay continuous across the antimeridian,
    // otherwise the two tiles that straddle ±180° land in different worlds and
    // one of them is dropped (a black stripe at the screen edge).
    var minDx = double.infinity, maxDx = -double.infinity;
    var south = double.infinity, north = -double.infinity;
    for (final s in samples) {
      final dx = (s.x - halfW) / world * 360;
      if (dx < minDx) minDx = dx;
      if (dx > maxDx) maxDx = dx;
      final y = s.y - halfH + yc;
      final lat = mercatorLatitudeAt((y / world).clamp(0.0, 1.0));
      if (lat < south) south = lat;
      if (lat > north) north = lat;
    }

    // Pad by exactly two tiles: enough to avoid edge flicker, small enough that
    // the candidate window stays O(visible tiles) even at z18.
    final padLng = 360 / world * GeoEngineTuning.tileSize * 2;
    final padT = GeoEngineTuning.tileSize * 2 / world;
    return GeoBounds(
      south: mercatorLatitudeAt(
          (mercatorTAt(south) + padT).clamp(0.0, 1.0)),
      north: mercatorLatitudeAt(
          (mercatorTAt(north) - padT).clamp(0.0, 1.0)),
      west: camera.center.longitude + minDx - padLng,
      east: camera.center.longitude + maxDx + padLng,
    );
  }
}
