/// Subdivision of lat/lng geometry for sphere projection.
///
/// Same idea as `mvt_subdivide.dart`, applied to data that arrives as
/// coordinates rather than as a tile: split **linearly in Mercator space**,
/// never along a great circle.
///
/// Why not great circles: a great circle between two points that share a
/// latitude bows towards the pole, and a 180° span passes straight over it. A
/// parallel drawn that way is wrong, which is exactly the kink that showed up on
/// the tropics when the MVT layer still used `densifyGreatCircle`.
///
/// Why Mercator and not lat/lng: MapLibre converts GeoJSON to Mercator first
/// (`geojson_source.ts:672` hands `subdivisionGranularity` to the worker) and
/// then subdivides in tile space, so a straight edge stays a *rhumb line* — the
/// same line a Mercator map draws. Both axes are therefore interpolated linearly
/// in Mercator space, which coincidentally keeps a parallel exactly on its
/// parallel and a meridian exactly on its meridian.
library;

import 'package:latlong2/latlong.dart';

import '../mvt/mvt_subdivide.dart';
import 'geo_geometry.dart';
import 'projections.dart';

/// Densest useful grid: 0.7° per cell, i.e. MapLibre's line preset of 512 cells
/// across the world (`subdivision_granularity_settings.ts:36-39`).
const int sphereSubdivisionGranularity = 512;

/// Splits [points] on a Mercator grid so a sphere projection follows the surface.
///
/// Returns [points] unchanged when nothing needed splitting (same instance), so
/// already-dense borders cost one comparison per segment.
///
/// Longitudes are unwrapped against the previous point before splitting, so a
/// segment that crosses the antimeridian stays one short hop instead of
/// stretching a whole world — otherwise the interpolated samples would fan out
/// across the sphere.
List<LatLng> subdivideSpherePolyline(
  List<LatLng> points, {
  int granularity = sphereSubdivisionGranularity,
  bool closed = false,
}) {
  if (points.length < 2 || granularity < 2) return points;

  final world = <Vec2>[];
  double? previousX;
  for (final p in points) {
    var x = (p.longitude + 180.0) / 360.0;
    final previous = previousX;
    if (previous != null) {
      while (x - previous > 0.5) {
        x -= 1;
      }
      while (previous - x > 0.5) {
        x += 1;
      }
    }
    previousX = x;
    world.add(Vec2(x, mercatorTAt(p.latitude)));
  }

  final split =
      subdivideTilePolyline(world, granularity: granularity, closed: closed);
  // Subdivision only ever inserts points, so an unchanged length means the
  // caller's list is already dense enough.
  if (split.length == world.length) return points;

  return [
    for (final w in split)
      LatLng(
        _latOf(w.y),
        wrapLongitude(w.x * 360.0 - 180.0),
      ),
  ];
}

/// `mercatorLatitudeAt` clamped to the ±90° a `LatLng` can hold.
double _latOf(double t) {
  final lat = mercatorLatitudeAt(t.clamp(0.0, 1.0));
  return lat < -90.0 ? -90.0 : (lat > 90.0 ? 90.0 : lat);
}
