/// Camera controller: owns the [CameraState] and notifies listeners.
///
/// Design constraint (plan §7.1): camera changes notify *painters* only —
/// layers subscribe with `CustomPainter(repaint: controller)` so a pan never
/// rebuilds widgets.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'package:geo_map_core/geo_map_core.dart';

class GeoMapController extends ChangeNotifier {
  GeoMapController({
    required GeoProjector projector,
    required CameraState initial,
  })  : _projector = projector,
        _value = initial;

  GeoProjector _projector;
  CameraState _value;

  GeoProjector get projector => _projector;
  CameraState get value => _value;

  /// Swap the projection (2D ↔ 3D) keeping centre/zoom continuous.
  void setProjector(GeoProjector projector) {
    if (identical(projector, _projector)) return;
    _projector = projector;
    notifyListeners();
  }

  void move(CameraState next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  /// Request a repaint without changing the camera (e.g. a tile arrived).
  void repaint() => notifyListeners();

  /// Move so the content shifts by ([dx], [dy]) pixels.
  void panBy(double dx, double dy) =>
      move(CameraMath.panByPixels(_value, _projector, dx, dy));

  /// Multiply the zoom by [factor] (2 = one zoom level), anchored at [anchor].
  void zoomBy(double factor, Vec2 anchor) {
    final next =
        (value.zoom + math.log(factor) / math.ln2).clamp(value.minZoom, value.maxZoom);
    move(CameraMath.zoomAround(value, _projector, next, anchor));
  }

  /// Set the zoom directly, anchored at [anchor].
  void zoomAround(double targetZoom, Vec2 anchor) {
    final next = targetZoom.clamp(value.minZoom, value.maxZoom);
    move(CameraMath.zoomAround(value, _projector, next, anchor));
  }

  /// Called by the host when the viewport size changes.
  void setViewport(ViewportSize size) {
    if (value.size == size) return;
    move(value.copyWith(size: size));
  }

  /// Centre the camera on [target] (no animation in P1).
  void recenter(LatLng target) {
    if (value.center == target) return;
    move(value.copyWith(center: target));
  }
}
