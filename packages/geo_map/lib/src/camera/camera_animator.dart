/// Frame driver for the camera animation API (T5c).
///
/// `GeoMapController` has no animation primitive — only `move(center, zoom)`.
/// So we own one [Ticker], interpolate center/zoom each frame and forward the
/// result to `move`. A single ticker is reused: starting a new animation
/// cancels the previous one (MapLibre semantics), and the cancelled `Future`
/// still completes so callers never hang.
library;

import 'dart:async';

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:latlong2/latlong.dart';

import 'camera_animation.dart' show interpolateCenter;
import 'geo_map_controller.dart';

class CameraAnimator {
  CameraAnimator(this.camera);

  final GeoMapController camera;

  Ticker? _ticker;
  Completer<void>? _completer;

  bool get isAnimating => _ticker != null;

  /// Animate to [toCenter] / [toZoom] over [duration].
  ///
  /// [zoomOverride], when given, replaces the linear zoom lerp with a custom
  /// function of the eased progress (used by `flyTo`'s zoom-out arch).
  Future<void> run({
    required LatLng toCenter,
    required double toZoom,
    required Duration duration,
    Curve curve = Curves.easeInOut,
    double Function(double eased)? zoomOverride,
  }) {
    cancel();

    final fromCenter = camera.center;
    final fromZoom = camera.zoom;
    if (duration <= Duration.zero ||
        (fromCenter == toCenter && fromZoom == toZoom)) {
      camera.move(toCenter, toZoom);
      return Future<void>.value();
    }

    final completer = Completer<void>();
    _completer = completer;
    final sphere = camera.isGlobe;
    final micros = duration.inMicroseconds;

    late final Ticker ticker;
    ticker = Ticker((elapsed) {
      final raw = elapsed.inMicroseconds / micros;
      final t = raw.clamp(0.0, 1.0);
      final eased = curve.transform(t);
      final center =
          interpolateCenter(fromCenter, toCenter, eased, sphere: sphere);
      final zoom = zoomOverride != null
          ? zoomOverride(eased)
          : fromZoom + (toZoom - fromZoom) * eased;
      camera.move(center, zoom.clamp(camera.minZoom, camera.maxZoom));

      if (raw >= 1.0) {
        // Exact landing — no curve rounding, and move() applies zoom clamps.
        camera.move(toCenter, toZoom);
        _finish(ticker);
      }
    }, debugLabel: 'geo_map.cameraAnimation');
    _ticker = ticker;
    ticker.start();
    return completer.future;
  }

  /// Stop the current animation. The pending future completes normally.
  void cancel() {
    final ticker = _ticker;
    if (ticker != null) {
      _finish(ticker);
      return;
    }
    final pending = _completer;
    _completer = null;
    pending?.complete();
  }

  void _finish(Ticker ticker) {
    ticker.stop();
    // Dispose on the next frame: stop() is called from inside the ticker's own
    // onTick callback, and disposing in that same callback is not safe.
    if (identical(_ticker, ticker)) _ticker = null;
    final pending = _completer;
    _completer = null;
    if (!ticker.isActive) ticker.dispose();
    pending?.complete();
  }

  void dispose() => cancel();
}
