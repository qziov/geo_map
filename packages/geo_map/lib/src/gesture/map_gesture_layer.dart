/// Gesture layer: pan / pinch (anchor-preserving) / double-tap / fling / tap.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/widgets.dart';

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';

import '../camera/geo_map_controller.dart';

/// Transparent full-size layer. Place it **above** non-interactive children;
/// interactive children (markers) must handle their own hits before this layer
/// (order the stack accordingly).
class MapGestureLayer extends StatefulWidget {
  const MapGestureLayer({
    required this.controller,
    this.onTap,
    this.child,
    super.key,
  });

  final GeoMapController controller;
  final void Function(LatLng latLng)? onTap;
  final Widget? child;

  @override
  State<MapGestureLayer> createState() => _MapGestureLayerState();
}

class _MapGestureLayerState extends State<MapGestureLayer> {
  static const _tapSlop = GeoEngineTuning.tapSlopPx;
  static const _tapMaxMs = GeoEngineTuning.tapMaxMillis;
  static const _doubleTapMaxMs = GeoEngineTuning.doubleTapMaxMillis;
  static const _flingMinVelocity = GeoEngineTuning.flingMinVelocityPxPerSec;

  Offset? _downPos;
  DateTime? _downTime;
  Offset? _lastTapPos;
  DateTime? _lastTapTime;
  Offset? _lastFocal;
  double _lastScale = 1.0;
  Timer? _flingTimer;

  @override
  void dispose() {
    _flingTimer?.cancel();
    super.dispose();
  }

  Vec2 _vec(Offset o) => Vec2(o.dx, o.dy);

  void _onPointerDown(PointerDownEvent event) {
    _downPos = event.localPosition;
    _downTime = DateTime.now();
  }

  /// Mouse wheel zoom, anchored at the cursor (Windows/desktop testing).
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // One notch (dy=120) ≈ one zoom level; smooth for trackpads.
    final factor = math.pow(1.0015, -event.scrollDelta.dy).toDouble();
    if (!factor.isFinite || factor <= 0 || factor == 1.0) return;
    _flingTimer?.cancel();
    widget.controller.zoomBy(factor, _vec(event.localPosition));
  }

  void _handleTap(Offset position) {
    final now = DateTime.now();
    final controller = widget.controller;

    if (_lastTapPos != null && _lastTapTime != null) {
      final sinceLast = now.difference(_lastTapTime!);
      final moved = (position - _lastTapPos!).distance;
      if (sinceLast.inMilliseconds <= _doubleTapMaxMs && moved <= _tapSlop) {
        _lastTapPos = null;
        _lastTapTime = null;
        controller.zoomBy(2, _vec(position));
        return;
      }
    }
    _lastTapPos = position;
    _lastTapTime = now;

    final geo = controller.projector.unproject(_vec(position), controller.value);
    widget.onTap?.call(geo ?? controller.value.center);
  }

  void _startFling(Offset velocity) {
    _flingTimer?.cancel();
    var vx = velocity.dx;
    var vy = velocity.dy;
    final speed = math.sqrt(vx * vx + vy * vy);
    if (speed < _flingMinVelocity) return;
    const tickMs = 16;
    const decay = 0.94;
    _flingTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      final dt = tickMs / 1000;
      widget.controller.panBy(vx * dt, vy * dt);
      vx *= decay;
      vy *= decay;
      if (math.sqrt(vx * vx + vy * vy) < 40) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerSignal: _onPointerSignal,
      onPointerUp: (event) {
        final down = _downPos;
        final downTime = _downTime;
        if (down == null || downTime == null) return;
        final moved = (event.localPosition - down).distance;
        final dt = DateTime.now().difference(downTime);
        if (moved <= _tapSlop && dt.inMilliseconds <= _tapMaxMs) {
          _handleTap(event.localPosition);
        }
        _downPos = null;
        _downTime = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _flingTimer?.cancel();
          _lastFocal = details.localFocalPoint;
          _lastScale = 1.0;
        },
        onScaleUpdate: (details) {
          final controller = widget.controller;
          final focal = details.localFocalPoint;
          final last = _lastFocal ?? focal;
          final dx = focal.dx - last.dx;
          final dy = focal.dy - last.dy;
          _lastFocal = focal;

          if (details.scale != 0 && details.scale != _lastScale) {
            final factor = details.scale / _lastScale;
            if (factor.isFinite && factor > 0) {
              controller.zoomBy(factor, _vec(focal));
              _lastScale = details.scale;
            }
          } else if (dx != 0 || dy != 0) {
            controller.panBy(dx, dy);
          }
        },
        onScaleEnd: (details) {
          _startFling(details.velocity.pixelsPerSecond);
        },
        child: widget.child ?? const SizedBox.expand(),
      ),
    );
  }
}
