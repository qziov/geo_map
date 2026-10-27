import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geo_map_core/geo_map_core.dart';
import '../vendor/flutter_map_camera/flutter_map_camera.dart';
import 'package:latlong2/latlong.dart';

/// A polyline on the sphere, drawn in screen space.
class GlobePolyline {
  const GlobePolyline({
    required this.points,
    required this.color,
    this.strokeWidth = 1.2,
    this.closed = false,
  });

  final List<LatLng> points;
  final Color color;
  final double strokeWidth;
  final bool closed;
}

/// A filled polygon on the sphere (fill + border), used in globe mode instead
/// of flutter_map's `PolygonLayer`, whose painter cannot clip to the horizon.
class GlobePolygonShape {
  const GlobePolygonShape({
    required this.points,
    required this.fill,
    required this.stroke,
    this.strokeWidth = 2,
    this.label,
    this.labelStyle = const TextStyle(color: Colors.white, fontSize: 12),
  });

  final List<LatLng> points;
  final Color fill;
  final Color stroke;
  final double strokeWidth;

  /// Optional text drawn at the ring's centroid (3D counterpart of
  /// `Polygon.label`, which only the native painter handles).
  final String? label;
  final TextStyle labelStyle;
}

/// A text label anchored at a geographic point.
class GlobeLabel {
  const GlobeLabel({
    required this.point,
    required this.text,
    this.style = const TextStyle(color: Colors.white, fontSize: 11),
    this.offset = const Offset(0, -16),
    this.background = const Color(0xCC0F2440),
  });

  final LatLng point;
  final String text;
  final TextStyle style;
  final Offset offset;
  final Color background;
}

/// Vector debug layer for the globe.
///
/// Deliberately **not** flutter_map's `PolylineLayer`/`PolygonLayer`: those
/// re-project with `crs.transform` after `camera.project`, which is wrong once
/// a projection delegate is in play. Here every vertex goes through
/// `camera.project` (the delegate) and great-circle densification, so the layer
/// also serves as the reference for what those layers will need later.
class GlobeVectorLayer extends StatelessWidget {
  const GlobeVectorLayer({
    super.key,
    required this.lines,
    this.polygons = const [],
    this.dots = const [],
    this.labels = const [],
    this.dotRadius = 1.6,
    this.dotColor = const Color(0x803DDC97),
    this.opacity = 1,
  });

  final List<GlobePolyline> lines;
  final List<GlobePolygonShape> polygons;

  /// Points (e.g. graticule intersections) drawn in the same projection as the
  /// lines — avoids the mismatch you get from mixing in a separate layer.
  final List<LatLng> dots;
  final List<GlobeLabel> labels;
  final double dotRadius;
  final Color dotColor;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(camera.size.x, camera.size.y),
        painter: _VectorPainter(
          camera: camera,
          lines: lines,
          polygons: polygons,
          dots: dots,
          labels: labels,
          dotRadius: dotRadius,
          dotColor: dotColor,
          opacity: opacity,
        ),
      ),
    );
  }
}

class _VectorPainter extends CustomPainter {
  _VectorPainter({
    required this.camera,
    required this.lines,
    required this.polygons,
    required this.dots,
    required this.labels,
    required this.dotRadius,
    required this.dotColor,
    required this.opacity,
  });

  final MapCamera camera;
  final List<GlobePolyline> lines;
  final List<GlobePolygonShape> polygons;
  final List<LatLng> dots;
  final List<GlobeLabel> labels;
  final double dotRadius;
  final Color dotColor;
  final double opacity;

  static const double _eps = 0.01;

  @override
  bool shouldRepaint(covariant _VectorPainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.lines != lines ||
      oldDelegate.polygons != polygons ||
      oldDelegate.dots != dots ||
      oldDelegate.labels != labels ||
      oldDelegate.dotRadius != dotRadius ||
      oldDelegate.dotColor != dotColor ||
      oldDelegate.opacity != opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // ★ 投影多态：flat 走 delegate 仿射（antimeridian 最近副本），globe 走正交。
    final flat = camera.projectionDelegate is FlatProjectionDelegate;
    final lat0 = camera.center.latitude * math.pi / 180;
    final lng0 = camera.center.longitude * math.pi / 180;
    final radius = flat
        ? double.infinity
        : 256 * math.pow(2, camera.zoom) / (2 * math.pi);
    if (!flat && radius <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final worldSize = camera.crs.scale(camera.zoom);

    Offset screenOf(LatLng p) {
      if (flat) {
        final pt = camera.projectClamped(p);
        return Offset(pt.x, pt.y);
      }
      final v = _view(
        p.longitude * math.pi / 180,
        p.latitude * math.pi / 180,
        lat0,
        lng0,
      );
      return Offset(center.dx + v.$1 * radius, center.dy - v.$2 * radius);
    }

    bool hidden(LatLng p) {
      if (flat) return false;
      return _view(
              p.longitude * math.pi / 180,
              p.latitude * math.pi / 180,
              lat0,
              lng0)
          .$3 <= _eps;
    }

    /// flat 的 antimeridian 处理：逐点相对前一点取最近 world copy。
    List<Offset> unwrap(List<Offset> raw) {
      if (raw.isEmpty) return raw;
      final out = <Offset>[raw.first];
      final half = worldSize / 2;
      for (var i = 1; i < raw.length; i++) {
        final prev = out.last;
        var dx = raw[i].dx - prev.dx;
        while (dx > half) {
          dx -= worldSize;
        }
        while (dx < -half) {
          dx += worldSize;
        }
        out.add(Offset(prev.dx + dx, raw[i].dy));
      }
      return out;
    }

    canvas.save();
    if (!flat) {
      canvas.clipPath(
        ui.Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Repeat the flat world the same way the raster layer does
    // (`AffineGeometry.worldCopies = 1`), so the graticule/Tissot do not stop
    // at the first world copy while the tiles keep repeating. A globe has no
    // seam and needs exactly one copy.
    final copies = flat ? 1 : 0;
    for (var copy = -copies; copy <= copies; copy++) {
      canvas.save();
      if (flat) canvas.translate(copy * worldSize, 0);

      for (final shape in polygons) {
      if (flat) {
        final pts = unwrap(
            [for (final p in shape.points) screenOf(p)]);
        if (pts.length < 3) continue;
        final fillPath = ui.Path()..addPolygon(pts, true);
        final strokePath = ui.Path()
          ..addPolygon(pts, true)
          ..close();
        canvas.drawPath(
          fillPath,
          Paint()
            ..style = PaintingStyle.fill
            ..isAntiAlias = true
            ..color = shape.fill.withValues(alpha: shape.fill.a * opacity),
        );
        canvas.drawPath(
          strokePath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = shape.strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true
            ..color = shape.stroke.withValues(alpha: shape.stroke.a * opacity),
        );
        final anchor = _centroid(shape.points);
        if (anchor == null) continue;
        final painter = _labelPainter(shapeLabelText(shape), shape.labelStyle);
        painter.paint(
          canvas,
          Offset(
            _flatAnchorX(pts, painter.width),
            _flatAnchorY(pts, painter.height),
          ),
        );
        continue;
      }
      final paths = _polygonPaths(shape.points, lat0, lng0, radius, center);
      if (paths == null) continue;
      final (fillPath, strokePath) = paths;

      canvas.drawPath(
        fillPath,
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = shape.fill.withValues(alpha: shape.fill.a * opacity),
      );
      canvas.drawPath(
        strokePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = shape.strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..color = shape.stroke.withValues(alpha: shape.stroke.a * opacity),
      );

      final label = shape.label;
      if (label == null) continue;
      final anchor = _centroid(shape.points);
      if (anchor == null) continue;
      final v = _view(
        anchor.longitude * math.pi / 180,
        anchor.latitude * math.pi / 180,
        lat0,
        lng0,
      );
      if (v.$3 <= _eps) continue;
      final painter = _labelPainter(label, shape.labelStyle);
      painter.paint(
        canvas,
        Offset(
          center.dx + v.$1 * radius - painter.width / 2,
          center.dy - v.$2 * radius - painter.height / 2,
        ),
      );
    }

    if (dots.isNotEmpty) {
      final painter = Paint()
        ..isAntiAlias = true
        ..color = dotColor.withValues(alpha: dotColor.a * opacity);
      for (final p in dots) {
        if (hidden(p)) continue;
        canvas.drawCircle(screenOf(p), dotRadius, painter);
      }
    }

      canvas.restore(); // world-copy transform
    }
    canvas.restore(); // disc clip

    // Labels are drawn OUTSIDE the disc clip on purpose: clipping them at the
    // limb cuts the text in half. They are still hidden when their anchor is
    // behind the horizon (the z check below).
    for (final label in labels) {
      if (hidden(label.point)) continue;
      final painter = _labelPainter(label.text, label.style);
      final anchor = screenOf(label.point);
      final topLeft =
          anchor + label.offset - Offset(painter.width / 2, painter.height / 2);
      final rect = Rect.fromLTWH(
        topLeft.dx - 4,
        topLeft.dy - 2,
        painter.width + 8,
        painter.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = label.background.withValues(alpha: opacity),
      );
      painter.paint(canvas, topLeft);
    }

    for (var copy = -copies; copy <= copies; copy++) {
      canvas.save();
      if (flat) canvas.translate(copy * worldSize, 0);

      for (final line in lines) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..color = line.color.withValues(alpha: line.color.a * opacity);

      final path = ui.Path();
      var started = false;

      final raw = [
        for (final p in _cachedDensify(line.points, closed: line.closed))
          screenOf(p)
      ];
      final pts = flat ? unwrap(raw) : raw;

      for (var i = 0; i < pts.length; i++) {
        final p = _cachedDensify(line.points, closed: line.closed)[i];
        if (!flat && hidden(p)) {
          // Behind the horizon: break the subpath so we never draw across the
          // disc (the same rule the tile layer uses).
          started = false;
          continue;
        }
        final pt = pts[i];
        if (!started) {
          path.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }

      if (line.closed && started) path.close();
      canvas.drawPath(path, paint);
    }
      canvas.restore();
    }
  }

  String shapeLabelText(GlobePolygonShape shape) => shape.label ?? '';

  double _flatAnchorX(List<Offset> pts, double labelWidth) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
    }
    return (minX + maxX) / 2 - labelWidth / 2;
  }

  double _flatAnchorY(List<Offset> pts, double labelHeight) {
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final p in pts) {
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return (minY + maxY) / 2 - labelHeight / 2;
  }

  /// Builds a fill path for a ring, clipped against the horizon.
  ///
  /// Clamping hidden vertices onto the silhouette is fine for a stroke, but for
  /// a *fill* it wraps the whole disc (a ring that is entirely behind becomes a
  /// closed curve along the limb). So the ring is clipped at z = 0 and the open
  /// ends are joined with an arc along the limb.
  /// Spherical centroid: normalise the sum of unit vectors. Averaging lat/lng
  /// breaks for rings near a pole or straddling the antimeridian.
  LatLng? _centroid(List<LatLng> points) {
    if (points.isEmpty) return null;
    var x = 0.0;
    var y = 0.0;
    var z = 0.0;
    for (final p in points) {
      final lng = p.longitude * math.pi / 180;
      final lat = p.latitude * math.pi / 180;
      final c = math.cos(lat);
      x += c * math.sin(lng);
      y += math.sin(lat);
      z += c * math.cos(lng);
    }
    final len = math.sqrt(x * x + y * y + z * z);
    if (len < 1e-6) return null;
    return LatLng(
      math.asin((y / len).clamp(-1.0, 1.0)) * 180 / math.pi,
      math.atan2(x, z) * 180 / math.pi,
    );
  }

  (ui.Path, ui.Path)? _polygonPaths(
    List<LatLng> points,
    double lat0,
    double lng0,
    double radius,
    Offset center,
  ) {
    final ring = _cachedDensify(points, closed: true);
    if (ring.length < 3) return null;

    final view = <(double, double, double)>[
      for (final p in ring)
        _view(
          p.longitude * math.pi / 180,
          p.latitude * math.pi / 180,
          lat0,
          lng0,
        ),
    ];

    Offset toScreen((double, double, double) v) =>
        Offset(center.dx + v.$1 * radius, center.dy - v.$2 * radius);

    // Rotate so the walk starts on a hidden vertex (if any): runs then never
    // straddle the array boundary.
    final firstHidden = view.indexWhere((v) => v.$3 <= _eps);
    if (firstHidden > 0) {
      final rotated = [
        ...view.sublist(firstHidden),
        ...view.sublist(0, firstHidden),
      ];
      view
        ..clear()
        ..addAll(rotated);
    }

    if (view.every((v) => v.$3 > _eps)) {
      final ring = [for (final v in view) toScreen(v)];
      return (
        ui.Path()..addPolygon(ring, true),
        ui.Path()..addPolygon(ring, true),
      );
    }

    // z = 0 crossing between two view points, projected onto the limb.
    (double, double, double) crossing(
      (double, double, double) a,
      (double, double, double) b,
    ) {
      final t = a.$3 / (a.$3 - b.$3);
      var x = a.$1 + (b.$1 - a.$1) * t;
      var y = a.$2 + (b.$2 - a.$2) * t;
      final len = math.sqrt(x * x + y * y);
      if (len < 1e-9) return (1, 0, 0);
      return (x / len, y / len, 0);
    }

    final runs = <List<Offset>>[];
    List<Offset>? current;

    for (var i = 0; i < view.length; i++) {
      final a = view[i];
      final b = view[(i + 1) % view.length];
      final aIn = a.$3 > _eps;
      final bIn = b.$3 > _eps;

      if (aIn && bIn) {
        (current ??= <Offset>[]).add(toScreen(a));
      } else if (aIn && !bIn) {
        (current ??= <Offset>[]).add(toScreen(a));
        current.add(toScreen(crossing(a, b)));
        runs.add(current);
        current = null;
      } else if (!aIn && bIn) {
        current = [toScreen(crossing(a, b)), toScreen(b)];
      }
    }
    if (current != null && current.isNotEmpty) runs.add(current);
    if (runs.isEmpty) return null;

    final fillPath = ui.Path();
    final strokePath = ui.Path();

    for (var r = 0; r < runs.length; r++) {
      final run = runs[r];

      // Stroke follows only the real edges (no limb arc).
      strokePath.moveTo(run.first.dx, run.first.dy);
      for (var i = 1; i < run.length; i++) {
        strokePath.lineTo(run[i].dx, run[i].dy);
      }

      fillPath.moveTo(run.first.dx, run.first.dy);
      for (var i = 1; i < run.length; i++) {
        fillPath.lineTo(run[i].dx, run[i].dy);
      }
      // Close the fill along the silhouette so it never cuts across the disc.
      final next = runs[(r + 1) % runs.length];
      _arcAlongLimb(fillPath, run.last, next.first, center, radius);
    }
    fillPath.close();
    return (fillPath, strokePath);
  }

  /// Appends the shorter arc on the silhouette from [from] to [to].
  void _arcAlongLimb(
    ui.Path path,
    Offset from,
    Offset to,
    Offset center,
    double radius,
  ) {
    var a0 = math.atan2(from.dy - center.dy, from.dx - center.dx);
    var a1 = math.atan2(to.dy - center.dy, to.dx - center.dx);
    var delta = a1 - a0;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }

    const steps = 24;
    for (var i = 1; i <= steps; i++) {
      final a = a0 + delta * i / steps;
      path.lineTo(
        center.dx + math.cos(a) * radius,
        center.dy + math.sin(a) * radius,
      );
    }
  }

  /// Densification is expensive (slerp per 1°) and the source lists are
  /// stable, so results are memoised **on the list object itself**.
  ///
  /// An `identityHashCode` key looked cheaper but is unsound: the hash can be
  /// reused after a list is collected, and since every meridian has the same
  /// length the stale entry passes the length check — a line then renders with
  /// another line's densified points and visibly kinks. An `Expando` is keyed
  /// by object identity and is released with the object.
  static final _densifyCache = Expando<_Densified>();

  static List<LatLng> _cachedDensify(
    List<LatLng> source, {
    bool closed = false,
  }) {
    final hit = _densifyCache[source];
    if (hit != null && hit.length == source.length && hit.closed == closed) {
      return hit.points;
    }
    final points = _densifyStatic(source, closed: closed);
    _densifyCache[source] = _Densified(source.length, closed, points);
    return points;
  }

  static List<LatLng> _densifyStatic(
    List<LatLng> points, {
    bool closed = false,
  }) => subdivideSpherePolyline(points, closed: closed);

  static double _angle(LatLng a, LatLng b) {
    final va = _unit(a);
    final vb = _unit(b);
    final dot = (va.$1 * vb.$1 + va.$2 * vb.$2 + va.$3 * vb.$3).clamp(
      -1.0,
      1.0,
    );
    return math.acos(dot);
  }

  static (double, double, double) _unit(LatLng p) {
    final lng = p.longitude * math.pi / 180;
    final lat = p.latitude * math.pi / 180;
    final c = math.cos(lat);
    return (c * math.sin(lng), math.sin(lat), c * math.cos(lng));
  }

  static LatLng _slerp(LatLng a, LatLng b, double t) {
    final va = _unit(a);
    final vb = _unit(b);
    final omega = _angle(a, b);
    if (omega < 1e-9) return a;

    final sinOmega = math.sin(omega);
    final ka = math.sin((1 - t) * omega) / sinOmega;
    final kb = math.sin(t * omega) / sinOmega;

    final x = va.$1 * ka + vb.$1 * kb;
    final y = va.$2 * ka + vb.$2 * kb;
    final z = va.$3 * ka + vb.$3 * kb;

    return LatLng(
      math.asin(y.clamp(-1.0, 1.0)) * 180 / math.pi,
      math.atan2(x, z) * 180 / math.pi,
    );
  }

  (double, double, double) _view(
    double lng,
    double lat,
    double lat0,
    double lng0,
  ) {
    final dLng = lng - lng0;
    final cosLat = math.cos(lat);
    return (
      cosLat * math.sin(dLng),
      math.cos(lat0) * math.sin(lat) - math.sin(lat0) * cosLat * math.cos(dLng),
      math.sin(lat0) * math.sin(lat) + math.cos(lat0) * cosLat * math.cos(dLng),
    );
  }
}

/// Labels are laid out once per (text, style) pair instead of every frame.
final Map<String, TextPainter> _textCache = {};

TextPainter _labelPainter(String text, TextStyle style) {
  // NOTE: real interpolation — escaping the `$` here would make every label
  // share one cache entry and all of them render the first string.
  final key =
      '$text|${style.fontSize}|${style.fontWeight}|'
      '${style.color?.toARGB32()}';
  if (_textCache.length > 256) _textCache.clear();
  return _textCache.putIfAbsent(
    key,
    () => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(),
  );
}

class _Densified {
  const _Densified(this.length, this.closed, this.points);

  final int length;
  final bool closed;
  final List<LatLng> points;
}

/// Densifies a path along great circles.
///
/// flutter_map's polygon/polyline painters connect projected points with
/// straight screen lines, so data fed to them must already be densified for the
/// edges to follow the sphere.
List<LatLng> densifyPath(List<LatLng> points, {double stepDeg = 2}) {
  if (points.length < 2) return points;
  final out = <LatLng>[];
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final angle = _VectorPainter._angle(a, b);
    final steps = (angle / (stepDeg * math.pi / 180)).ceil().clamp(1, 360);
    for (var s = 0; s < steps; s++) {
      out.add(_VectorPainter._slerp(a, b, s / steps));
    }
  }
  out.add(points.last);
  return out;
}

/// Meridians every [lngStep]° and parallels every [latStep]°.
///
/// Parallels are sampled densely so they visibly curve — that curvature is the
/// first thing to check when the projection is off.
List<GlobePolyline> buildGraticule({
  double latStep = 15,
  double lngStep = 15,
  double maxLat = 80,
  Color color = const Color(0x553DDC97),
}) {
  final lines = <GlobePolyline>[];

  for (var lng = -180.0; lng < 180; lng += lngStep) {
    final pts = <LatLng>[];
    for (var lat = -maxLat; lat <= maxLat; lat += 2) {
      pts.add(LatLng(lat, lng));
    }
    lines.add(GlobePolyline(points: pts, color: color, strokeWidth: 0.8));
  }

  for (var lat = -75.0; lat <= 75; lat += latStep) {
    final pts = <LatLng>[];
    for (var lng = -180.0; lng <= 180.0; lng += 2) {
      pts.add(LatLng(lat, lng));
    }
    lines.add(GlobePolyline(points: pts, color: color, strokeWidth: 0.8));
  }

  return lines;
}

/// Tissot indicatrices: small equal-radius circles on the sphere.
///
/// On a correct orthographic projection they stay circular at the disc centre
/// and squash into ellipses towards the limb — an instant visual check for
/// distortion and for wrong great-circle interpolation.
List<GlobePolyline> buildTissot({
  double latStep = 30,
  double lngStep = 30,
  double radiusDeg = 9,
  int segments = 48,
  Color color = const Color(0x88FFC107),
}) {
  final lines = <GlobePolyline>[];

  for (var lat = -60.0; lat <= 60; lat += latStep) {
    for (var lng = -180.0; lng < 180; lng += lngStep) {
      final pts = <LatLng>[];
      for (var i = 0; i < segments; i++) {
        final bearing = 2 * math.pi * i / segments;
        pts.add(_destination(LatLng(lat, lng), radiusDeg, bearing));
      }
      lines.add(
        GlobePolyline(points: pts, color: color, strokeWidth: 1, closed: true),
      );
    }
  }

  return lines;
}

/// Great-circle segment between two points (for checking long distances).
GlobePolyline buildGreatCircle(
  LatLng from,
  LatLng to, {
  Color color = const Color(0xCCFF1744),
  double strokeWidth = 2,
}) => GlobePolyline(points: [from, to], color: color, strokeWidth: strokeWidth);

/// Point at [distanceDeg] from [origin] along [bearingRad].
LatLng _destination(LatLng origin, double distanceDeg, double bearingRad) {
  final lat1 = origin.latitude * math.pi / 180;
  final lng1 = origin.longitude * math.pi / 180;
  final d = distanceDeg * math.pi / 180;

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(d) +
        math.cos(lat1) * math.sin(d) * math.cos(bearingRad),
  );
  final lng2 =
      lng1 +
      math.atan2(
        math.sin(bearingRad) * math.sin(d) * math.cos(lat1),
        math.cos(d) - math.sin(lat1) * math.sin(lat2),
      );

  return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
}
