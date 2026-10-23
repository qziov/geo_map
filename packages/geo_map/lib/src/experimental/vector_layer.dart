/// Projection test overlays: graticule (经纬网) + Tissot indicatrix (变形指示圈).
///
/// Both are vector layers driven purely by the active [GeoProjector] — they are
/// the standard visual test for "the projection is actually being applied".
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' hide Path; // latlong2 has its own generic Path

import '../camera/geo_map_controller.dart';

int? _gridDiagTick;

/// 经纬网：赤道/本初子午线加粗，其余 15°（可配）间隔。
class GraticuleLayer extends StatelessWidget {
  const GraticuleLayer({
    required this.controller,
    this.spacingDeg = 15,
    this.color = const Color(0x66FFD54F),
    this.equatorColor = const Color(0xCCFFB300),
    this.strokeWidth = 1.0,
    this.labels = true,
    super.key,
  });

  final GeoMapController controller;
  final double spacingDeg;
  final Color color;
  final Color equatorColor;
  final double strokeWidth;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GraticulePainter(
        controller: controller,
        spacingDeg: spacingDeg,
        color: color,
        equatorColor: equatorColor,
        strokeWidth: strokeWidth,
        labels: labels,
      ),
      size: Size.infinite,
    );
  }
}

class _GraticulePainter extends CustomPainter {
  _GraticulePainter({
    required this.controller,
    required this.spacingDeg,
    required this.color,
    required this.equatorColor,
    required this.strokeWidth,
    required this.labels,
  }) : super(repaint: controller);

  final GeoMapController controller;
  final double spacingDeg;
  final Color color;
  final Color equatorColor;
  final double strokeWidth;
  final bool labels;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = controller.value;
    final projector = controller.projector;
    final bounds = projector.approximateVisibleBounds(camera);

    final normal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    final strong = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.6
      ..color = equatorColor;

    // Meridians (vertical): clamp to the visible latitude band.
    final lngStart = (bounds.west / spacingDeg).ceil() * spacingDeg;
    for (var lng = lngStart; lng <= bounds.east; lng += spacingDeg) {
      final isPrime = (lng % 360).abs() < 1e-9;
      final path = _meridianPath(
          projector, camera, lng, bounds.south, bounds.north);
      if (path != null) {
        canvas.drawPath(path, isPrime ? strong : normal);
        if (labels) _label(canvas, '$lng°', projector.project(LatLng(0, lng), camera));
      }
    }

    // Parallels: the globe CAN show the polar band (±85.05..±90) — clamping the
    // graticule to the mercator limit made parallels vanish near the poles.
    final latStart = (bounds.south / spacingDeg).ceil() * spacingDeg;
    final latLimit = 90.0;
    var parallels = 0;
    for (var lat = math.max(latStart, -latLimit);
        lat <= math.min(bounds.north, latLimit);
        lat += spacingDeg) {
      parallels++;
      final isEquator = lat.abs() < 1e-9;
      final path = _parallelPath(projector, camera, lat, bounds.west, bounds.east);
      if (path != null) {
        canvas.drawPath(path, isEquator ? strong : normal);
        if (labels) {
          final anchorLng = controller.value.center.longitude;
          _label(canvas, _latLabel(lat), projector.project(LatLng(lat, anchorLng), camera));
        }
      }
    }
    if (kDebugMode && parallels == 0) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_gridDiagTick == null || nowMs - _gridDiagTick! > 3000) {
        _gridDiagTick = nowMs;
        debugPrint('[geo_map:grid] 0 parallels — bounds=$bounds '
            'latStart=$latStart projector=${projector.kind}');
      }
    }
  }

  Path? _meridianPath(
      GeoProjector projector, CameraState camera, double lng, double south, double north) {
    final path = Path();
    var started = false;
    void add(LatLng p) {
      final s = projector.project(p, camera);
      if (s == null) {
        started = false;
        return;
      }
      if (!started) {
        path.moveTo(s.x, s.y);
        started = true;
      } else {
        path.lineTo(s.x, s.y);
      }
    }

    if (projector.densifyStepRad(camera) <= 0) {
      add(LatLng(south, lng));
      add(LatLng(north, lng));
    } else {
      final step = projector.densifyStepRad(camera);
      final line = densifyGreatCircle(
        [LatLng(south, lng), LatLng(north, lng)],
        stepRad: step,
      );
      for (final p in line) {
        add(p);
      }
    }
    return started ? path : null;
  }

  Path? _parallelPath(
      GeoProjector projector, CameraState camera, double lat, double west, double east) {
    final path = Path();
    var started = false;
    void add(LatLng p) {
      final s = projector.project(p, camera);
      if (s == null) {
        started = false;
        return;
      }
      if (!started) {
        path.moveTo(s.x, s.y);
        started = true;
      } else {
        path.lineTo(s.x, s.y);
      }
    }

    if (projector.densifyStepRad(camera) <= 0) {
      add(LatLng(lat, west));
      add(LatLng(lat, east));
    } else {
      // Parallel: subdivide in longitude, not along great circles (parallels
      // are NOT great circles except the equator).
      final stepDeg = projector.densifyStepRad(camera) * 180 / math.pi /
          math.max(0.2, math.cos(lat * math.pi / 180).abs());
      var lng = west;
      while (lng <= east) {
        add(LatLng(lat, lng));
        lng += stepDeg;
      }
    }
    return started ? path : null;
  }

  String _latLabel(double lat) =>
      '${lat.abs().round()}°${lat >= 0 ? 'N' : 'S'}';

  void _label(Canvas canvas, String text, Vec2? screen) {
    if (screen == null) return;
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(screen.x + 3, screen.y + 3));
  }

  @override
  bool shouldRepaint(covariant _GraticulePainter oldDelegate) =>
      oldDelegate.spacingDeg != spacingDeg ||
      oldDelegate.color != color ||
      oldDelegate.labels != labels;
}

/// Tissot indicatrix: circles of equal geodesic radius. On a correct projection
/// they stay near-circular at the centre and distort predictably toward the edges.
class TissotLayer extends StatelessWidget {
  const TissotLayer({
    required this.controller,
    this.radiusKm = 1000,
    this.spacingDeg = 30,
    this.color = const Color(0x88FF5252),
    this.strokeWidth = 1.4,
    super.key,
  });

  final GeoMapController controller;
  final double radiusKm;
  final double spacingDeg;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TissotPainter(
        controller: controller,
        radiusKm: radiusKm,
        spacingDeg: spacingDeg,
        color: color,
        strokeWidth: strokeWidth,
      ),
      size: Size.infinite,
    );
  }
}

class _TissotPainter extends CustomPainter {
  _TissotPainter({
    required this.controller,
    required this.radiusKm,
    required this.spacingDeg,
    required this.color,
    required this.strokeWidth,
  }) : super(repaint: controller);

  static const double earthRadiusKm = 6371.0088;

  final GeoMapController controller;
  final double radiusKm;
  final double spacingDeg;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = controller.value;
    final projector = controller.projector;
    final bounds = projector.approximateVisibleBounds(camera);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;

    const samples = 24;
    final delta = radiusKm / earthRadiusKm; // angular radius (rad)

    final latStart = (bounds.south / spacingDeg).ceil() * spacingDeg;
    final lngStart = (bounds.west / spacingDeg).ceil() * spacingDeg;

    for (var lat = latStart; lat <= bounds.north; lat += spacingDeg) {
      for (var lng = lngStart; lng <= bounds.east; lng += spacingDeg) {
        final path = Path();
        var started = false;
        for (var k = 0; k <= samples; k++) {
          final bearing = k / samples * 2 * math.pi;
          final p = destinationPoint(LatLng(lat, lng), bearing, delta);
          final s = projector.project(p, camera);
          if (s == null) {
            started = false;
            continue;
          }
          if (!started) {
            path.moveTo(s.x, s.y);
            started = true;
          } else {
            path.lineTo(s.x, s.y);
          }
        }
        if (started) canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TissotPainter oldDelegate) =>
      oldDelegate.radiusKm != radiusKm || oldDelegate.spacingDeg != spacingDeg;
}
