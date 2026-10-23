/// Gesture overlay for the globe/flat engine — verbatim port of the lab
/// host's interaction logic (tap / double-tap / fling / pan / anchor pinch /
/// wheel zoom), wired to [GeoMapController] instead of Riverpod providers.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/widgets.dart';

import 'package:latlong2/latlong.dart';

import '../camera/geo_map_controller.dart';

class GlobeGestureOverlay extends StatefulWidget {
  const GlobeGestureOverlay({
    required this.controller,
    this.onTap,
    this.minZoom,
    this.maxZoom,
    super.key,
  });

  final GeoMapController controller;
  final void Function(LatLng latLng)? onTap;

  /// Zoom clamps for wheel/double-tap; null = controller's own range.
  final double? minZoom;
  final double? maxZoom;

  @override
  State<GlobeGestureOverlay> createState() => _GlobeGestureOverlayState();
}

class _GlobeGestureOverlayState extends State<GlobeGestureOverlay> {
  static const _tapSlop = 12.0;
  static const _tapMaxMs = 400;
  static const _flingMinVelocity = 600.0;

  int? _tapPointer;
  Offset? _tapStart;
  DateTime? _tapStartAt;
  final List<(Offset, Duration)> _samples = [];
  Offset? _lastTapPos;
  DateTime? _lastTapAt;
  Offset? _lastFocal;
  double _lastScale = 1;
  Timer? _fling;

  double get _minZoom => widget.minZoom ?? widget.controller.minZoom;
  double get _maxZoom => widget.maxZoom ?? widget.controller.maxZoom;

  @override
  void dispose() {
    _fling?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent e) {
    _fling?.cancel();
    if (_tapPointer != null) {
      // A second finger means a pinch, not a tap/fling.
      _tapPointer = null;
      _tapStart = null;
      _samples.clear();
      return;
    }
    _tapPointer = e.pointer;
    _tapStart = e.localPosition;
    _tapStartAt = DateTime.now();
    _samples
      ..clear()
      ..add((e.localPosition, e.timeStamp));
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _tapPointer) return;
    _samples.add((e.localPosition, e.timeStamp));
    if (_samples.length > 8) _samples.removeAt(0);
  }

  void _onPointerUp(PointerUpEvent e) {
    final start = _tapStart;
    final startedAt = _tapStartAt;
    final isTap = e.pointer == _tapPointer &&
        start != null &&
        startedAt != null &&
        (e.localPosition - start).distance <= _tapSlop &&
        DateTime.now().difference(startedAt).inMilliseconds <= _tapMaxMs;

    _tapPointer = null;
    _tapStart = null;
    _tapStartAt = null;

    if (!isTap) {
      _startFling(_estimateVelocity());
      _samples.clear();
      return;
    }

    final now = DateTime.now();
    if (_lastTapPos != null &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!).inMilliseconds < 320 &&
        (e.localPosition - _lastTapPos!).distance <= _tapSlop) {
      _lastTapPos = null;
      _lastTapAt = null;
      _samples.clear();
      final nextZoom = (widget.controller.zoom + 1).clamp(_minZoom, _maxZoom);
      widget.controller.zoomAround(e.localPosition, nextZoom);
      return;
    }
    _lastTapAt = now;

    final point = widget.controller.delegate.unproject(e.localPosition);
    if (point != null) widget.onTap?.call(point);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer == _tapPointer) {
      _tapPointer = null;
      _tapStart = null;
      _tapStartAt = null;
    }
  }

  /// Pixels/second over the last samples of the drag.
  Offset _estimateVelocity() {
    if (_samples.length < 2) return Offset.zero;
    final last = _samples.last;
    final cutoff = last.$2 - const Duration(milliseconds: 120);
    final first = _samples.firstWhere(
      (s) => s.$2 >= cutoff,
      orElse: () => _samples.first,
    );
    final seconds = (last.$2 - first.$2).inMicroseconds / 1e6;
    if (seconds <= 0.008) return Offset.zero;
    return (last.$1 - first.$1) / seconds;
  }

  void _startFling(Offset velocity) {
    _fling?.cancel();
    var vx = velocity.dx;
    var vy = velocity.dy;
    if (math.sqrt(vx * vx + vy * vy) < _flingMinVelocity) return;
    const tickMs = 16;
    const decay = 0.94;
    _fling = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      widget.controller.panBy(Offset(vx * tickMs / 1000, vy * tickMs / 1000));
      vx *= decay;
      vy *= decay;
      if (math.sqrt(vx * vx + vy * vy) < 40) timer.cancel();
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final factor = math.pow(1.0015, -event.scrollDelta.dy).toDouble();
    if (!factor.isFinite || factor <= 0 || factor == 1.0) return;
    _fling?.cancel();
    final next =
        (widget.controller.zoom + math.log(factor) / math.ln2)
            .clamp(_minZoom, _maxZoom);
    widget.controller.zoomAround(event.localPosition, next);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _fling?.cancel();
          _lastScale = 1;
          _lastFocal = details.localFocalPoint;
        },
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: (details) => _startFling(details.velocity.pixelsPerSecond),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final controller = widget.controller;
    final focal = d.localFocalPoint;
    final delta = focal - (_lastFocal ?? focal);
    _lastFocal = focal;

    var center = controller.center;
    if (delta != Offset.zero) {
      // Content follows the finger (1/cos compensation inside the delegate).
      center = controller.delegate.panCenter(center, delta, controller.zoom);
    }

    var zoom = controller.zoom;
    // Only pinch changes the zoom level: a single-pointer drag reports
    // `scale == 1`, and finger-count jitter must not alter the level.
    if (d.pointerCount < 2) _lastScale = 1;
    final scaleRatio = d.scale / _lastScale;
    if (d.pointerCount >= 2 &&
        scaleRatio.isFinite &&
        scaleRatio > 0 &&
        scaleRatio != 1) {
      zoom = (controller.zoom + math.log(scaleRatio) / math.ln2)
          .clamp(_minZoom, _maxZoom);
      _lastScale = d.scale;
    }

    if (zoom != controller.zoom) {
      // Anchor the point under the focal point while zooming.
      final anchor = controller.delegate.unproject(focal);
      if (anchor != null) {
        center = controller.delegate.anchorCenter(center, anchor, controller.zoom, zoom);
      }
    }

    if (center != controller.center || zoom != controller.zoom) {
      controller.move(center, zoom);
    }
  }
}
