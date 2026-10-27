/// A style-driven fill/line layer for the M1 subset.
///
/// Reads a [StyleSpec] + parsed GeoJSON features, evaluates each layer's
/// paint properties (constants or expressions) per feature, projects with the
/// **same** core [GeoProjector] the tile layer uses (so 2D and 3D share the
/// math), and draws with Canvas. It is intentionally a `children` overlay for
/// M1; M1.3/M1.4 move it to a first-class ordered layer stack.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../vendor/flutter_map_camera/flutter_map_camera.dart';
import 'style_controller.dart';

class StyleVectorLayer extends StatelessWidget {
  const StyleVectorLayer({
    super.key,
    this.style,
    this.controller,
    required this.features,
    this.opacity = 1.0,
  }) : assert(style != null || controller != null,
            'provide either style or controller');

  /// A static style. Ignored when [controller] is provided.
  final StyleSpec? style;

  /// A runtime style controller (M1.4); the layer rebuilds on notify.
  final GeoStyleController? controller;

  final List<GeoJsonFeature> features;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);

    Widget paintWith(StyleSpec spec) => RepaintBoundary(
          child: CustomPaint(
            painter: _StyleVectorPainter(
              style: spec,
              features: features,
              camera: camera,
              opacity: opacity,
            ),
            child: const SizedBox.expand(),
          ),
        );

    final c = controller;
    if (c == null) return paintWith(style!);
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) => paintWith(c.document.toSpec()),
    );
  }
}

class _StyleVectorPainter extends CustomPainter {
  _StyleVectorPainter({
    required this.style,
    required this.features,
    required this.camera,
    required this.opacity,
  });

  final StyleSpec style;
  final List<GeoJsonFeature> features;
  final MapCamera camera;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final flat = camera.projectionDelegate is FlatProjectionDelegate;
    final projector =
        flat ? const MercatorProjector() : const OrthographicProjector();
    final state = CameraState(
      center: camera.center,
      zoom: camera.zoom,
      size: ViewportSize(size.width, size.height),
    );

    final clip = projector.clipCircle(state);
    if (clip != null) {
      canvas.save();
      canvas.clipPath(Path()
        ..addOval(Rect.fromCircle(
          center: Offset(clip.center.x, clip.center.y),
          radius: clip.radius,
        )));
    }

    for (final layer in style.layers) {
      if (!layer.isSupported || !layer.isVisibleAt(camera.zoom)) continue;
      final layerCtx = ExpressionContext(zoom: camera.zoom);

      for (final feature in features) {
        if (!layer.filter(feature.properties)) continue;
        final paths = _pathsFor(feature.geometry, projector, state, flat);
        if (paths == null) continue;
        final ctx = ExpressionContext(
          zoom: camera.zoom,
          properties: feature.properties,
        );

        if (layer.type == 'fill') {
          final c = layer.color('fill-color', ctx) ??
              layer.color('fill-color', layerCtx);
          final o = (layer.number('fill-opacity', ctx) ?? 1) * opacity;
          if (c == null || o <= 0) continue;
          canvas.drawPath(
            paths.fill,
            Paint()
              ..style = PaintingStyle.fill
              ..color = _color(c, o),
          );
        } else if (layer.type == 'line') {
          final c = layer.color('line-color', ctx) ??
              layer.color('line-color', layerCtx);
          final w = layer.number('line-width', ctx) ?? 1;
          final o = (layer.number('line-opacity', ctx) ?? 1) * opacity;
          if (c == null || o <= 0 || w <= 0) continue;
          canvas.drawPath(
            paths.stroke,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = _color(c, o),
          );
        }
      }
    }

    if (clip != null) canvas.restore();
  }

  static ui.Color _color(StyleColor c, double opacity) =>
      ui.Color.fromRGBO(c.r, c.g, c.b, (c.a / 255.0) * opacity);

  /// Screen-space paths for one feature.
  ///
  /// Fill and stroke differ on the globe: a fill must close along the limb
  /// (`clipRingToHorizon`) so it never chords through the sphere, while a
  /// stroke follows only the real edges. On the flat map both are the same
  /// path.
  _FeaturePaths? _pathsFor(
    GeoJsonGeometry geometry,
    GeoProjector projector,
    CameraState state,
    bool flat,
  ) {
    final fill = Path();
    final stroke = Path();
    var any = false;

    // A long edge must be split before projecting or it is drawn as a straight
    // screen chord that cuts through the sphere (a route from Europe to Asia
    // visibly leaves the surface). The split is linear in **Mercator** space,
    // like MapLibre's tile-space subdivision — a great circle would bow a
    // constant-latitude edge towards the pole. Mercator's own projection is
    // affine, so on the flat map the raw vertices are already exact.
    final stepRad = projector.densifyStepRad(state);
    final onSphere = stepRad > 0;

    void addLine(List<LatLng> points, {required bool close}) {
      final dense =
          onSphere ? subdivideSpherePolyline(points, closed: close) : points;
      Offset? previous;
      for (final ll in dense) {
        final v = projector.project(ll, state);
        if (v == null) {
          previous = null;
          continue;
        }
        final o = Offset(v.x, v.y);
        if (previous == null) {
          fill.moveTo(o.dx, o.dy);
          stroke.moveTo(o.dx, o.dy);
        } else {
          fill.lineTo(o.dx, o.dy);
          stroke.lineTo(o.dx, o.dy);
        }
        previous = o;
        any = true;
      }
      if (close && previous != null) {
        fill.close();
        stroke.close();
      }
    }

    void addRing(List<LatLng> ring) {
      if (flat) {
        addLine(ring, close: true);
        return;
      }
      // The ring is split first: `clipRingToHorizon` walks segment by segment,
      // so a coarse ring chords across the limb instead of following it.
      final dense = subdivideSpherePolyline(ring, closed: true);
      final clipped = clipRingToHorizon(dense, state);
      if (clipped == null) return;
      fill.addPolygon(
        [for (final p in clipped.fill) Offset(p.x, p.y)],
        true,
      );
      for (final run in clipped.strokeRuns) {
        if (run.length < 2) continue;
        stroke.moveTo(run.first.x, run.first.y);
        for (var i = 1; i < run.length; i++) {
          stroke.lineTo(run[i].x, run[i].y);
        }
      }
      any = true;
    }

    switch (geometry) {
      case LineStringGeometry(:final points):
        addLine(points, close: false);
      case PolygonGeometry(:final rings):
        for (final ring in rings) {
          addRing(ring);
        }
      case MultiLineStringGeometry(:final lines):
        for (final line in lines) {
          addLine(line, close: false);
        }
      case MultiPolygonGeometry(:final polygons):
        for (final polygon in polygons) {
          for (final ring in polygon) {
            addRing(ring);
          }
        }
      case PointGeometry():
        return null; // M1 draws fill/line only; points are M3 (symbol).
    }

    return any ? _FeaturePaths(fill, stroke) : null;
  }

  @override
  bool shouldRepaint(covariant _StyleVectorPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.camera != camera ||
      oldDelegate.features != features ||
      oldDelegate.opacity != opacity;
}

class _FeaturePaths {
  const _FeaturePaths(this.fill, this.stroke);

  final Path fill;
  final Path stroke;
}
