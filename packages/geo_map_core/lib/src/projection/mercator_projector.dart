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
    final x = (wrapLongitude(geo.longitude) + 180) / 360 * world;
    final y = mercatorTAt(lat) * world;
    final xc = (camera.center.longitude + 180) / 360 * world;
    final yc = mercatorTAt(camera.center.latitude) * world;
    return Vec2(
      x - xc + camera.size.width / 2,
      y - yc + camera.size.height / 2,
    );
  }

  @override
  Vec2? projectUnit(Vec3 unit, CameraState camera) => project(unit.toLatLng(), camera);

  @override
  LatLng? unproject(Vec2 screen, CameraState camera) {
    final world = camera.worldSize;
    final xc = (camera.center.longitude + 180) / 360 * world;
    final yc = mercatorTAt(camera.center.latitude) * world;
    final x = screen.x - camera.size.width / 2 + xc;
    final y = screen.y - camera.size.height / 2 + yc;
    final lng = x / world * 360 - 180;
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
  GeoBounds approximateVisibleBounds(CameraState camera) {
    final c = camera.size.center;
    final corners = [
      unproject(Vec2(0, 0), camera),
      unproject(Vec2(camera.size.width, 0), camera),
      unproject(Vec2(0, camera.size.height), camera),
      unproject(Vec2(camera.size.width, camera.size.height), camera),
      unproject(c, camera),
    ].whereType<LatLng>().toList();

    var south = double.infinity, north = -double.infinity;
    var west = double.infinity, east = -double.infinity;
    for (final p in corners) {
      south = south < p.latitude ? south : p.latitude;
      north = north > p.latitude ? north : p.latitude;
      west = west < p.longitude ? west : p.longitude;
      east = east > p.longitude ? east : p.longitude;
    }
    // Pad by exactly two tiles: enough to avoid edge flicker, small enough that
    // the candidate window stays O(visible tiles) even at z18.
    final world = camera.worldSize;
    final padLng = 360 / world * GeoEngineTuning.tileSize * 2;
    final padT = GeoEngineTuning.tileSize * 2 / world;
    return GeoBounds(
      south: mercatorLatitudeAt(
          (mercatorTAt(south) + padT).clamp(0.0, 1.0)),
      north: mercatorLatitudeAt(
          (mercatorTAt(north) - padT).clamp(0.0, 1.0)),
      west: west - padLng,
      east: east + padLng,
    );
  }
}
