/// Camera controller for the vendored (fork) `MapCamera` + globe delegate.
///
/// Owns centre/zoom state, keeps the vendored `MapCamera` value object and the
/// `GlobeProjectionDelegate` in sync, and exposes the gesture verbs used by the
/// lab host (pan / anchor zoom / recenter). The math is the lab-verified one —
/// see `globe_projection.dart`.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../globe/globe_projection.dart';
import '../vendor/flutter_map_camera/flutter_map_camera.dart';

class GeoMapController extends ChangeNotifier {
  GeoMapController({
    GlobeProjectionDelegate? projectionDelegate,
    LatLng initialCenter = const LatLng(30, 105),
    double initialZoom = 4.2,
    this.minZoom = 1,
    this.maxZoom = 8,
  }) : delegate = projectionDelegate ?? GlobeProjectionDelegate() {
    _center = initialCenter;
    _zoom = initialZoom.clamp(minZoom, maxZoom);
    delegate.updateCamera(_center, _zoom, Size.zero);
    _camera = MapCamera.initialCamera(MapOptions(
      crs: const Epsg3857(),
      projectionDelegate: delegate,
      minZoom: minZoom,
      maxZoom: maxZoom,
      initialCenter: _center,
      initialZoom: _zoom,
    ));
  }

  final GlobeProjectionDelegate delegate;
  final double minZoom;
  final double maxZoom;

  late MapCamera _camera;
  late LatLng _center;
  late double _zoom;

  MapCamera get camera => _camera;
  LatLng get center => _center;
  double get zoom => _zoom;
  Size get viewport => Size(_camera.size.x, _camera.size.y);

  /// Move the camera; syncs the projection delegate and notifies listeners.
  void move(LatLng center, double zoom) {
    final z = zoom.clamp(minZoom, maxZoom);
    if (center == _center && z == _zoom) return;
    _center = center;
    _zoom = z;
    _sync();
  }

  /// Content follows the finger: delegate handles the 1/cos(lat) compensation.
  void panBy(Offset pixelDelta) =>
      move(delegate.panBy(pixelDelta), _zoom);

  /// Pinch: multiply zoom by [factor], keeping [anchor] (screen px) fixed.
  void zoomBy(double factor, Offset anchor) {
    final next = (_zoom + math.log(factor) / math.ln2).clamp(minZoom, maxZoom);
    zoomAround(anchor, next);
  }

  /// Lab-verified anchor zoom (`_zoomAround` + `_anchorCenter`): first-order
  /// correction for the radius change, then `panCenter` with the view direction.
  void zoomAround(Offset focal, double newZoom) {
    final toZoom = newZoom.clamp(minZoom, maxZoom);
    if (toZoom == _zoom) return;
    final anchor = delegate.unproject(focal);
    var center = _center;
    if (anchor != null) {
      center = _anchorCenter(center, anchor, _zoom, toZoom);
    }
    move(center, toZoom);
  }

  void recenter(LatLng target) => move(target, _zoom);

  /// Viewport size changed (layout pass).
  void setViewport(Size size) {
    if (_camera.size.x == size.width && _camera.size.y == size.height) return;
    _camera =
        _camera.withNonRotatedSize(math.Point(size.width, size.height));
    delegate.updateCamera(_center, _zoom, size);
    notifyListeners();
  }

  void _sync() {
    delegate.updateCamera(_center, _zoom, viewport);
    _camera = _camera.withPosition(center: _center, zoom: _zoom);
    notifyListeners();
  }

  /// Public wrapper — used by the gesture overlay for anchor zoom.
  LatLng anchorCenter(LatLng center, LatLng anchor, double fromZoom, double toZoom) =>
      _anchorCenter(center, anchor, fromZoom, toZoom);

  /// First-order correction for the radius change during a zoom — verbatim
  /// port of lab `main.dart::_anchorCenter`.
  LatLng _anchorCenter(
    LatLng center,
    LatLng anchor,
    double fromZoom,
    double toZoom,
  ) {
    if (fromZoom == toZoom) return center;
    final rOld = GeoEngineGlobe.tileSize * math.pow(2, fromZoom) / (2 * math.pi);
    final rNew = GeoEngineGlobe.tileSize * math.pow(2, toZoom) / (2 * math.pi);
    final v = delegate.viewDirection(anchor);
    final shift = Offset((rOld - rNew) * v.$1, -(rOld - rNew) * v.$2);
    return delegate.panCenter(center, shift, toZoom);
  }
}

/// Shared constants for the globe delegate / controller pair.
abstract class GeoEngineGlobe {
  static const double tileSize = 256;
}
