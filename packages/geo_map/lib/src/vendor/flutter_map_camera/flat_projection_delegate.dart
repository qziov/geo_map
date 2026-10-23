/// Flat (Web Mercator, affine) projection implementing the same
/// `MapProjectionDelegate` interface as the globe — this is what makes the
/// 2D/3D switch possible: the widget tree, gesture overlay and controller are
/// projection-agnostic and only talk to this interface.
///
/// Math mirrors the fork `MapCamera`'s delegate==null branch:
/// `crs.latLngToPoint/pointToLatLng` (crs.dart L247/L287), i.e. the standard
/// Leaflet affine with worldSize = 256·2^zoom.
library;

import 'dart:math' as math;
import 'dart:math' show Point;
import 'dart:ui' show Offset, Size;

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import 'crs.dart';
import 'extensions.dart';
import 'projection_delegate.dart';

class FlatProjectionDelegate implements MapProjectionDelegate {
  FlatProjectionDelegate({this.crs = const Epsg3857()});

  final Crs crs;

  static const double maxMercatorLatitude = 85.05112878;

  LatLng _center = const LatLng(30, 105);
  double _zoom = 4.2;
  Size _size = Size.zero;

  LatLng get center => _center;
  double get zoom => _zoom;
  double get worldSize => crs.scale(_zoom);
  Offset get _screenCenter => Offset(_size.width / 2, _size.height / 2);

  @override
  void updateCamera(LatLng center, double zoom, Size size) {
    _center = center;
    _zoom = zoom;
    if (size.width > 0 && size.height > 0) {
      _size = size;
    }
  }

  Point<double> _worldOf(LatLng p, double zoom) =>
      crs.latLngToPoint(p, zoom);

  @override
  Offset project(LatLng point) {
    final w = _worldOf(point, _zoom);
    final c = _worldOf(_center, _zoom);
    return Offset(
      w.x - c.x + _screenCenter.dx,
      w.y - c.y + _screenCenter.dy,
    );
  }

  @override
  Offset projectForVector(LatLng point) {
    // Same as project, but the longitude is unwrapped to the world copy
    // closest to the camera so polylines crossing the antimeridian stay put.
    final w = _worldOf(point, _zoom);
    final c = _worldOf(_center, _zoom);
    var dx = w.x - c.x;
    final half = worldSize / 2;
    if (dx > half) dx -= worldSize;
    if (dx < -half) dx += worldSize;
    return Offset(dx + _screenCenter.dx, w.y - c.y + _screenCenter.dy);
  }

  @override
  bool isVisible(LatLng point) => true; // 平面无背面；裁剪交给 canvas

  @override
  LatLng? unproject(Offset local) {
    final world = _worldOf(_center, _zoom) +
        Point<double>(local.dx - _screenCenter.dx, local.dy - _screenCenter.dy);
    final ll = crs.pointToLatLng(world, _zoom);
    // 跨日界线：pointToLatLng 只 clamp 不 wrap，补 wrap 保证点击落点正确
    return LatLng(ll.latitude, _wrapLng(ll.longitude));
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

  @override
  LatLng panBy(Offset pixelDelta) => panCenter(_center, pixelDelta, _zoom);

  @override
  LatLng panCenter(LatLng from, Offset delta, double zoom) {
    // 内容跟手指（与 globe 的 dLng=-dx/dLat=+dy 同约定）：手指右移，
    // 世界坐标中心左移。
    final world = _worldOf(from, zoom) -
        Point<double>(delta.dx, delta.dy);
    final ll = crs.pointToLatLng(world, zoom);
    return _clamp(ll);
  }

  @override
  (double, double, double) viewDirection(LatLng point) => (0, 1, 1);

  /// Flat anchor zoom: `n(c1) = n(a) − (n(a) − n(c0)) / s` in normalized world
  /// space (the standard slippy-map formula). The globe base implementation is
  /// radius-based and wrong here, hence the override.
  @override
  LatLng anchorCenter(
      LatLng center, LatLng anchor, double fromZoom, double toZoom) {
    if (fromZoom == toZoom) return center;
    final s = math.pow(2, toZoom - fromZoom).toDouble();
    final scaleFrom = crs.scale(fromZoom);
    final nA = _worldOf(anchor, fromZoom) / scaleFrom;
    final nC0 = _worldOf(center, fromZoom) / scaleFrom;
    final nC1 = nA - (nA - nC0) / s;
    final world = nC1 * crs.scale(toZoom);
    return _clamp(crs.pointToLatLng(world, toZoom));
  }

  LatLng _clamp(LatLng p) => LatLng(
        p.latitude.clamp(-maxMercatorLatitude, maxMercatorLatitude),
        p.longitude,
      );
}
