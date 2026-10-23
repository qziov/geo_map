/// Spherical math: unit vectors, slerp, great-circle densification, centroids.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';


const double deg2rad = math.pi / 180.0;
const double rad2deg = 180.0 / math.pi;

double rad(double degrees) => degrees * deg2rad;
double degreesOf(double radians) => radians * rad2deg;

class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static Vec3 of(LatLng p) {
    final lat = rad(p.latitude);
    final lng = rad(p.longitude);
    final c = math.cos(lat);
    return Vec3(c * math.cos(lng), c * math.sin(lng), math.sin(lat));
  }

  LatLng toLatLng() {
    final len = math.sqrt(x * x + y * y + z * z);
    if (len == 0) return const LatLng(0, 0);
    final lat = math.asin((z / len).clamp(-1.0, 1.0));
    final lng = math.atan2(y, x);
    return LatLng(degreesOf(lat), degreesOf(lng));
  }

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 normalized() {
    final l = length;
    if (l == 0) return const Vec3(0, 0, 1);
    return Vec3(x / l, y / l, z / l);
  }

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
}

/// Great-circle interpolation between two unit vectors, [t] in `[0,1]`.
Vec3 slerp(Vec3 a, Vec3 b, double t) {
  final dot = a.dot(b).clamp(-1.0, 1.0);
  final theta = math.acos(dot);
  if (theta.abs() < 1e-12) return a;
  final sinTheta = math.sin(theta);
  final w1 = math.sin((1 - t) * theta) / sinTheta;
  final w2 = math.sin(t * theta) / sinTheta;
  return (a * w1 + b * w2).normalized();
}

/// Central angle between two geodetic points (radians).
double angleBetween(LatLng a, LatLng b) {
  final va = Vec3.of(a);
  final vb = Vec3.of(b);
  return math.acos(va.dot(vb).clamp(-1.0, 1.0));
}

/// Great-circle distance in metres on a sphere of [radiusM].
double haversine(LatLng a, LatLng b, {double radiusM = 6371008.8}) =>
    angleBetween(a, b) * radiusM;

/// Densify a polyline along great circles.
///
/// [stepRad] is the maximum angular step; [maxPoints] guards pathological input.
List<LatLng> densifyGreatCircle(
  List<LatLng> points, {
  required double stepRad,
  bool closed = false,
  int maxPoints = 20000,
}) {
  if (points.length < 2) return List<LatLng>.of(points);
  final step = stepRad <= 0 ? 1.0 : stepRad;
  final out = <LatLng>[points.first];
  final segments = closed ? points.length : points.length - 1;
  for (var i = 0; i < segments; i++) {
    final a = Vec3.of(points[i % points.length]);
    final b = Vec3.of(points[(i + 1) % points.length]);
    final theta = math.acos(a.dot(b).clamp(-1.0, 1.0));
    final n = math.max(1, (theta / step).ceil());
    for (var k = 1; k <= n; k++) {
      if (out.length >= maxPoints) return out;
      final p = slerp(a, b, k / n).toLatLng();
      out.add(p);
    }
  }
  return out;
}

/// Angular step whose chord error stays below [pixelError] on a sphere of [radiusPx].
///
/// chord error ≈ R·(1 − cos(step/2)) ⇒ step ≈ 2·acos(1 − err/R).
double densifyStepForPixelError(double radiusPx, double pixelError) {
  if (radiusPx <= 0) return math.pi;
  final ratio = (pixelError / radiusPx).clamp(0.0, 1.0);
  final step = 2 * math.acos(1 - ratio);
  return step.clamp(1e-6, math.pi);
}

/// Area-weighted Cartesian centroid, then re-projected to the sphere.
LatLng sphericalCentroid(List<LatLng> ring) {
  if (ring.isEmpty) return const LatLng(0, 0);
  var sx = 0.0, sy = 0.0, sz = 0.0;
  for (final p in ring) {
    final v = Vec3.of(p);
    sx += v.x;
    sy += v.y;
    sz += v.z;
  }
  return Vec3(sx, sy, sz).normalized().toLatLng();
}
