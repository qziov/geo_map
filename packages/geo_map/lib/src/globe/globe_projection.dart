import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import '../vendor/flutter_map_camera/flutter_map_camera.dart';
import 'package:latlong2/latlong.dart';

/// Orthographic globe projection plugged into flutter_map through the
/// (fork-only) `MapProjectionDelegate` hook.
///
/// Screen space replaces world space:
/// * `project()` returns **screen pixels** (or far-away coordinates for points
///   on the far side, so flutter_map's own culling removes them),
/// * `pixelOrigin` is forced to zero by the forked `MapCamera`,
/// * `pixelBounds` is the viewport.
class GlobeProjectionDelegate implements MapProjectionDelegate {
  GlobeProjectionDelegate({this.tileSize = 256});

  final double tileSize;

  /// The camera may look straight at a pole. 85.0511° is a **tile data** limit
  /// (Web Mercator), not a projection limit — clamping the camera there makes
  /// the globe feel truncated, so only stop just short of the degenerate pole.
  static const double maxCameraLatitude = 89.999;
  static const double _hidden = -1e6;

  LatLng _center = const LatLng(35.8617, 104.1954);
  double _zoom = 3;
  Size _size = Size.zero;

  LatLng get center => _center;
  double get zoom => _zoom;

  /// Disc radius in logical pixels — a function of zoom only.
  ///
  /// Multiplying by `1/cos(lat)` (mercator's trick) would make the globe grow
  /// as you drag towards the poles; on a sphere the apparent size is fixed.
  double get radius => tileSize * math.pow(2, _zoom) / (2 * math.pi);

  double get _cosLatClamped =>
      math.max(math.cos(_center.latitude * math.pi / 180).abs(), 0.05);

  Offset get _screenCenter => Offset(_size.width / 2, _size.height / 2);

  @override
  void updateCamera(LatLng center, double zoom, Size size) {
    _center = center;
    _zoom = zoom;
    // `MapCamera` starts with an "impossible" size (negative) until layout
    // happens; keeping it would shift everything by half the placeholder size.
    if (size.width > 0 && size.height > 0) {
      _size = size;
    }
  }

  @override
  Offset project(LatLng point) {
    final view = _toView(point);
    if (view.$3 <= 0) return const Offset(_hidden, _hidden);

    final r = radius;
    final c = _screenCenter;
    return Offset(c.dx + view.$1 * r, c.dy - view.$2 * r);
  }

  /// Geometry-safe variant: hidden points are clamped onto the silhouette
  /// instead of being thrown far off-screen (used by polygon/polyline layers).
  @override
  Offset projectForVector(LatLng point) {
    final view = _toView(point);
    final r = radius;
    final c = _screenCenter;
    if (view.$3 > 0.02) {
      return Offset(c.dx + view.$1 * r, c.dy - view.$2 * r);
    }
    var x = view.$1;
    var y = view.$2;
    final len = math.sqrt(x * x + y * y);
    if (len < 1e-6) return c;
    x /= len;
    y /= len;
    return Offset(c.dx + x * r, c.dy - y * r);
  }

  @override
  // Slightly past the horizon on purpose: the layer is clipped to the disc, so
  // drawing a bit beyond the limb avoids a visible gap, without leaking.
  bool isVisible(LatLng point) => _toView(point).$3 > -0.03;

  @override
  LatLng? unproject(Offset local) {
    final r = radius;
    if (r <= 0) return null;
    final c = _screenCenter;
    final x = (local.dx - c.dx) / r;
    final y = -(local.dy - c.dy) / r;
    final r2 = x * x + y * y;
    if (r2 > 1) return null;

    final z = math.sqrt(math.max(0.0, 1 - r2));
    final lat0 = _center.latitude * math.pi / 180;
    final sinLat0 = math.sin(lat0);
    final cosLat0 = math.cos(lat0);

    final y1 = y * cosLat0 + z * sinLat0;
    final z1 = -y * sinLat0 + z * cosLat0;

    final lat = math.asin(y1.clamp(-1.0, 1.0)) * 180 / math.pi;
    final lng = _center.longitude + math.atan2(x, z1) * 180 / math.pi;
    return LatLng(lat, _wrapLng(lng));
  }

  @override
  LatLng panBy(Offset pixelDelta) => panCenter(_center, pixelDelta, _zoom);

  /// Drag: content follows the finger, longitude compensated by 1/cos(lat).
  LatLng panCenter(LatLng from, Offset delta, double zoom) {
    final r = tileSize * math.pow(2, zoom) / (2 * math.pi);
    // Horizontal drag sensitivity still grows towards the poles: the same pixel
    // span covers fewer degrees of longitude there.
    final dLng = -delta.dx / (r * _cosLatClamped) * 180 / math.pi;
    final dLat = delta.dy / r * 180 / math.pi;
    return LatLng(
      (from.latitude + dLat).clamp(-maxCameraLatitude, maxCameraLatitude),
      _wrapLng(from.longitude + dLng),
    );
  }

  /// Unit vector of [point] in view space (x right, y up, z towards camera).
  /// Used by the page for things like pinch-to-zoom anchored at the fingers.
  (double, double, double) viewDirection(LatLng point) => _toView(point);

  /// World → view space (unit sphere, camera centred).
  (double, double, double) _toView(LatLng point) {
    final lng0 = _center.longitude * math.pi / 180;
    final lat0 = _center.latitude * math.pi / 180;
    final lng = point.longitude * math.pi / 180;
    final lat = point.latitude * math.pi / 180;

    final dLng = lng - lng0;
    final cosLat = math.cos(lat);
    final x = cosLat * math.sin(dLng);
    final y =
        math.cos(lat0) * math.sin(lat) -
        math.sin(lat0) * cosLat * math.cos(dLng);
    final z =
        math.sin(lat0) * math.sin(lat) +
        math.cos(lat0) * cosLat * math.cos(dLng);
    return (x, y, z);
  }

  static double _wrapLng(double lng) {
    var value = lng;
    while (value > 180) {
      value -= 360;
    }
    while (value < -180) {
      value += 360;
    }
    return value;
  }
}
