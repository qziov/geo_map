/// Scalar projection helpers (Web Mercator) shared by the projector, tile grid
/// and tests. Pure functions, no state.
library;

import 'dart:math' as math;

import 'geodesy.dart';

/// Latitude limit of Web Mercator (±85.05112878°).
const double mercatorMaxLatitude = 85.05112878;

/// `y = ln(tan(π/4 + φ/2))` for a latitude in radians.
double mercatorY(double latRad) => math.log(math.tan(math.pi / 4 + latRad / 2));

/// Inverse of [mercatorY].
double inverseMercatorY(double y) =>
    (2 * math.atan(math.exp(y)) - math.pi / 2) * rad2deg;

/// Latitude (degrees) at normalized world-Y `t` where `t=0` is the north edge.
double mercatorLatitudeAt(double t) =>
    degreesOf(math.atan(_sinh(math.pi * (1 - 2 * t))));

/// `sinh(x) = (e^x − e^-x)/2` — dart:math has no sinh.
double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

/// Normalized world-Y (`0` north → `1` south) of a latitude in degrees.
double mercatorTAt(double latDeg) {
  final lat = clampMercatorLat(latDeg);
  return (1 - mercatorY(rad(lat)) / math.pi) / 2;
}

double clampMercatorLat(double latDeg) =>
    latDeg.clamp(-mercatorMaxLatitude, mercatorMaxLatitude);

/// Wrap a longitude into `[-180, 180)`.
double wrapLongitude(double lng) {
  var v = lng;
  while (v < -180) {
    v += 360;
  }
  while (v >= 180) {
    v -= 360;
  }
  return v;
}
