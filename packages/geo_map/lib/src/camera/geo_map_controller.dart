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
import '../vendor/flutter_map_camera/flutter_map_camera.dart'
    show
        Epsg3857,
        FlatProjectionDelegate,
        MapCamera,
        MapOptions,
        MapProjectionDelegate;

class GeoMapController extends ChangeNotifier {
  GeoMapController({
    bool useGlobe = true,
    GlobeProjectionDelegate? projectionDelegate,
    LatLng initialCenter = const LatLng(30, 105),
    double initialZoom = 4.2,
    this.minZoom = 1,
    this.maxZoom = 8,
  }) : delegate = projectionDelegate ??
            (useGlobe
                ? GlobeProjectionDelegate()
                : FlatProjectionDelegate()) {
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

  MapProjectionDelegate delegate;
  bool _isGlobe = true;
  final double minZoom;
  final double maxZoom;

  bool get isGlobe => _isGlobe;

  /// 2D/3D 切换：替换投影 delegate 并重建 vendored camera（center/zoom 连续）。
  void setMode(bool globe) {
    if (_isGlobe == globe) return;
    _isGlobe = globe;
    delegate = globe
        ? GlobeProjectionDelegate()
        : FlatProjectionDelegate();
    delegate.updateCamera(_center, _zoom, viewport);
    _camera = _camera.withOptions(MapOptions(
      crs: const Epsg3857(),
      projectionDelegate: delegate,
      minZoom: minZoom,
      maxZoom: maxZoom,
    ));
    notifyListeners();
  }

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
      center = delegate.anchorCenter(center, anchor, _zoom, toZoom);
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

}

