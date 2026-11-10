/// Pure math behind the MapLibre-shaped camera animation API (T5c).
///
/// Nothing here touches a [Ticker] or a controller, so every rule can be
/// pinned down by a plain unit test. `map_handle.dart` drives these functions
/// frame by frame and forwards the result to `GeoMapController.move`.
///
/// Deliberate limits of this batch (BASELINE §1.3): only center / zoom / bounds
/// are animated. `bearing` / `pitch` and the camera's own padding offset are
/// reserved parameter slots, not implemented — no 3D tilt is produced.
library;

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:geo_map_core/geo_map_core.dart'
    show GeoEngineTuning, mercatorLatitudeAt, mercatorTAt, wrapLongitude;
import 'package:latlong2/latlong.dart';

import '../vendor/flutter_map_camera/flutter_map_camera.dart' show LatLngBounds;

/// Shortest signed longitude delta in degrees, in `[-180, 180]`.
///
/// A plain `to - from` interpolation from 179° to -179° would travel 358°
/// through Greenwich; the shortest path is the 2° hop across the antimeridian.
double shortestLongitudeDelta(double from, double to) {
  var d = (to - from) % 360.0;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Interpolate a camera centre.
///
/// * Flat map: latitude lerps linearly, longitude follows the shortest wrap.
/// * Globe: great-circle (slerp) interpolation on the unit sphere, so a long
///   move does not visibly cut across the sphere (BASELINE §3.4 risk table).
LatLng interpolateCenter(
  LatLng from,
  LatLng to,
  double t, {
  required bool sphere,
}) {
  final clamped = t.clamp(0.0, 1.0);
  if (clamped <= 0) return from;
  if (clamped >= 1) return to;
  if (sphere) return _slerp(from, to, clamped);
  return LatLng(
    from.latitude + (to.latitude - from.latitude) * clamped,
    wrapLongitude(
      from.longitude +
          shortestLongitudeDelta(from.longitude, to.longitude) * clamped,
    ),
  );
}

/// Zoom at eased progress [t] during a `flyTo`: a linear zoom lerp minus an
/// arch that pulls the camera back in the middle of the flight.
///
/// This is a deliberately small simplification of MapLibre's van Wijk flight
/// path — enough to reproduce the "zoom out, travel, zoom in" shape while
/// keeping the endpoint exact (`sin(pi * 1) == 0`).
double flyZoomAt({
  required double startZoom,
  required double targetZoom,
  required double arc,
  required double t,
}) =>
    startZoom + (targetZoom - startZoom) * t - arc * math.sin(math.pi * t);

/// How many zoom levels [flyTo] should pull back, derived from the on-screen
/// travel distance at the starting zoom. Capped so a world-scale jump does not
/// collapse the map to z0.
double flyZoomArc({
  required LatLng from,
  required LatLng to,
  required double startZoom,
  required Size viewport,
}) {
  final world = GeoEngineTuning.tileSize * math.pow(2, startZoom).toDouble();
  final dx = shortestLongitudeDelta(from.longitude, to.longitude).abs() /
      360 *
      world;
  final dy =
      (mercatorTAt(to.latitude) - mercatorTAt(from.latitude)).abs() * world;
  final distance = math.sqrt(dx * dx + dy * dy);
  final reference =
      math.max(GeoEngineTuning.tileSizeD, math.max(viewport.width, viewport.height));
  return math.min(2.5, math.log(1 + distance / reference) / math.ln2);
}

/// Centre + zoom that fits [bounds] into [viewport] (minus [padding]).
///
/// Padding here is the *fitBounds viewport inset* (MapLibre's
/// `fitBounds(bounds, {padding})`), which is pure bounds math and therefore in
/// scope. It is NOT the camera's own padding/tilt offset — that stays reserved.
///
/// Web Mercator: `worldSize(z) = tileSize * 2^z`. The normalized span of the
/// bounds is `dx` (longitude) and `dy` (Mercator-Y), so the largest zoom that
/// still fits is `log2(availablePx / (span * tileSize))`, taking the tighter
/// of the two axes.
({LatLng center, double zoom}) cameraForBounds(
  LatLngBounds bounds, {
  required Size viewport,
  required double minZoom,
  required double maxZoom,
  EdgeInsets padding = EdgeInsets.zero,
  double? maxZoomCap,
}) {
  final availableW = math.max(1.0, viewport.width - padding.horizontal);
  final availableH = math.max(1.0, viewport.height - padding.vertical);

  final x0 = (bounds.west + 180) / 360;
  final x1 = (bounds.east + 180) / 360;
  final t0 = mercatorTAt(bounds.north); // north edge -> smaller world-Y
  final t1 = mercatorTAt(bounds.south);
  final dx = math.max((x1 - x0).abs(), 1e-9);
  final dy = math.max((t1 - t0).abs(), 1e-9);

  final zoomX =
      math.log(availableW / (dx * GeoEngineTuning.tileSize)) / math.ln2;
  final zoomY =
      math.log(availableH / (dy * GeoEngineTuning.tileSize)) / math.ln2;
  final cap = math.min(maxZoom, maxZoomCap ?? maxZoom);
  final zoom = math.min(zoomX, zoomY).clamp(minZoom, cap);

  // Use the Mercator-Y midpoint (not the arithmetic latitude mean), otherwise
  // high-latitude bounds land visibly off-centre.
  final center = LatLng(
    mercatorLatitudeAt((t0 + t1) / 2),
    wrapLongitude((bounds.west + bounds.east) / 2),
  );
  return (center: center, zoom: zoom);
}

// --- great-circle interpolation ---------------------------------------------

({double x, double y, double z}) _unit(LatLng p) {
  final lat = p.latitude * math.pi / 180;
  final lng = p.longitude * math.pi / 180;
  final c = math.cos(lat);
  return (x: c * math.cos(lng), y: c * math.sin(lng), z: math.sin(lat));
}

LatLng _slerp(LatLng a, LatLng b, double t) {
  final va = _unit(a);
  final vb = _unit(b);
  final dot = (va.x * vb.x + va.y * vb.y + va.z * vb.z).clamp(-1.0, 1.0);

  // Antipodal (or nearly identical) points make slerp ill-defined; fall back
  // to the shortest-wrap linear path so the animation never produces NaN.
  if (dot < -0.999999 || dot > 0.999999) {
    return interpolateCenter(a, b, t, sphere: false);
  }

  final omega = math.acos(dot);
  final sinOmega = math.sin(omega);
  final w1 = math.sin((1 - t) * omega) / sinOmega;
  final w2 = math.sin(t * omega) / sinOmega;
  final x = va.x * w1 + vb.x * w2;
  final y = va.y * w1 + vb.y * w2;
  final z = va.z * w1 + vb.z * w2;
  final length = math.sqrt(x * x + y * y + z * z);
  if (length < 1e-12) return interpolateCenter(a, b, t, sphere: false);
  final nz = z / length;
  return LatLng(
    math.asin(nz.clamp(-1.0, 1.0)) * 180 / math.pi,
    wrapLongitude(math.atan2(y, x) * 180 / math.pi),
  );
}
