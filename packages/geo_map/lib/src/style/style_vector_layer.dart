/// A style-driven fill/line layer for the M1 subset.
///
/// Reads a [StyleSpec] + parsed GeoJSON features, evaluates each layer's
/// paint properties (constants or expressions) per feature, projects with the
/// **same** core [GeoProjector] the tile layer uses (so 2D and 3D share the
/// math), and draws with Canvas. It is intentionally a `children` overlay for
/// M1; M1.3/M1.4 move it to a first-class ordered layer stack.
///
/// **A layer only sees the features of its own `source`.** Use
/// [StyleVectorLayer.ofSources] for a multi-source style; the plain constructor
/// takes one feature list and applies it to every layer, which is only correct
/// when the style has a single source (or when the layers carry no `source`).
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../vendor/flutter_map_camera/flutter_map_camera.dart';
import 'sprite_atlas.dart';
import 'style_controller.dart';
import 'symbol_painter.dart';
import 'symbol_style.dart';

class StyleVectorLayer extends StatelessWidget {
  const StyleVectorLayer({
    super.key,
    this.style,
    this.controller,
    required this.features,
    this.opacity = 1.0,
    this.sprite,
  })  : sources = null,
        assert(style != null || controller != null,
            'provide either style or controller');

  /// Multi-source variant: each style layer draws only `sources[layer.source]`.
  ///
  /// Without this, a style with two sources draws every feature twice — a
  /// `line` layer would happily stroke the polygons that belong to a different
  /// source, which reads as a stray outline in the wrong colour.
  const StyleVectorLayer.ofSources({
    super.key,
    this.style,
    this.controller,
    required Map<String, List<GeoJsonFeature>> this.sources,
    this.opacity = 1.0,
    this.sprite,
  })  : features = const [],
        assert(style != null || controller != null,
            'provide either style or controller');

  /// A static style. Ignored when [controller] is provided.
  final StyleSpec? style;

  /// A runtime style controller (M1.4); the layer rebuilds on notify.
  final GeoStyleController? controller;

  final List<GeoJsonFeature> features;

  /// Features keyed by style source id (see [StyleVectorLayer.ofSources]).
  final Map<String, List<GeoJsonFeature>>? sources;

  final double opacity;

  /// Icons for `icon-image`; without one the labels are still drawn.
  final SpriteAtlas? sprite;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);

    Widget paintWith(StyleSpec spec) => RepaintBoundary(
          child: CustomPaint(
            painter: _StyleVectorPainter(
              style: spec,
              features: features,
              sources: sources,
              sprite: sprite,
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
    required this.sources,
    required this.sprite,
    required this.camera,
    required this.opacity,
  });

  final StyleSpec style;
  final List<GeoJsonFeature> features;
  final Map<String, List<GeoJsonFeature>>? sources;
  final SpriteAtlas? sprite;
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

    // Labels are collected while walking the layers but painted last: a symbol
    // layer is meant to sit on top of the geometry regardless of where it is in
    // the style, and one placer must see every candidate to arbitrate between
    // them.
    final symbols = <SymbolSpec>[];
    var symbolOrder = 0;
    var collisionGroup = 0;

    for (final layer in style.layers) {
      if (!layer.isVisibleAt(camera.zoom)) continue;
      final layerCtx = ExpressionContext(zoom: camera.zoom);

      if (layer.type == 'symbol') {
        final feats = sources == null
            ? features
            : (sources![layer.source] ?? const <GeoJsonFeature>[]);
        for (final feature in feats) {
          if (!layer.matches(feature.properties, camera.zoom)) continue;
          final geometry = feature.geometry;
          if (geometry is! PointGeometry) continue;
          final anchor = projector.project(geometry.point, state);
          if (anchor == null) continue;
          final ctx = ExpressionContext(
            zoom: camera.zoom,
            properties: feature.properties,
          );
          symbols.addAll(resolveSymbols(
            layer: layer,
            ctx: ctx,
            anchor: anchor,
            sprite: sprite,
            order: symbolOrder,
            collisionGroup: ++collisionGroup,
            // A GeoJSON source is drawn once per layer, so there is no
            // cross-tile duplicate to suppress; the feature id still seeds the
            // key so two symbol layers over the same source stay distinct, and
            // point features are upright (no local segment to follow).
            lineAngle: 0,
            baseKey: feature.id,
            sourceLayer: layer.source ?? '',
          ));
          symbolOrder += 2;
        }
        continue;
      }

      if (!layer.isSupported) continue;

      // A layer draws its own source only. `sources == null` is the
      // single-source shorthand and keeps the old behaviour.
      final layerFeatures = sources == null
          ? features
          : (sources![layer.source] ?? const <GeoJsonFeature>[]);
      for (final feature in layerFeatures) {
        if (!layer.matches(feature.properties, camera.zoom)) continue;
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
          // `fill_outline`: a 1 px band on every ring edge, coloured by
          // `fill-outline-color`, which **defaults to `fill-color`** rather than
          // to nothing (MapLibre `fill_style_layer.ts:30-32`).
          final antialias =
              layer.valueOf('fill-antialias', layerCtx) != false;
          final outline =
              (antialias && paths.stroke.getBounds().isEmpty == false)
                  ? (layer.color('fill-outline-color', ctx) ?? c)
                  : null;
          void draw() {
            canvas.drawPath(
              paths.fill,
              Paint()
                ..style = PaintingStyle.fill
                ..color = _color(c, o),
            );
            final oc = outline;
            if (oc != null && oc.a > 0) {
              canvas.drawPath(
                // `paths.stroke` holds the real edges only — on the globe it
                // excludes the synthetic limb arc.
                paths.stroke,
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1
                  ..color = _color(oc, o),
              );
            }
          }

          _drawWithCopies(draw, paths, flat, state, size, canvas);
        } else if (layer.type == 'line') {
          final c = layer.color('line-color', ctx) ??
              layer.color('line-color', layerCtx);
          final w = layer.number('line-width', ctx) ?? 1;
          final o = (layer.number('line-opacity', ctx) ?? 1) * opacity;
          if (c == null || o <= 0 || w <= 0) continue;
          void draw() {
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

          _drawWithCopies(draw, paths, flat, state, size, canvas);
        }
      }
    }

    // Symbols are painted **outside** the disc clip, matching MapLibre: it never
    // clips a label at the horizon, it decides per symbol whether the anchor is
    // on the visible hemisphere (`collision_index.ts:166`: `unplaceable =
    // occluded`) and then draws the whole label, glyphs and all. `project()`
    // already returns null for an anchor behind the globe, so a partly visible
    // label near the limb keeps its full outline instead of being sliced by the
    // silhouette.
    if (clip != null) canvas.restore();

    if (symbols.isNotEmpty) {
      SymbolPainter(viewport: size).paint(canvas, symbols);
    }
  }

  static ui.Color _color(StyleColor c, double opacity) =>
      ui.Color.fromRGBO(c.r, c.g, c.b, (c.a / 255.0) * opacity);

  /// Draw [draw] once per visible world copy when flat.
  ///
  /// The geometry is built with continuous (unwrapped) screen x, so a shape that
  /// extends past one world edge never jumps; repeating it at `k * worldSize`
  /// is exactly MapLibre's `getVisibleUnwrappedCoordinates` behaviour (the tile
  /// path already does this). The globe has a single copy.
  void _drawWithCopies(
    void Function() draw,
    _FeaturePaths paths,
    bool flat,
    CameraState state,
    Size size,
    Canvas canvas,
  ) {
    if (!flat) {
      draw();
      return;
    }
    final b = paths.bounds;
    if (b.isEmpty) {
      draw();
      return;
    }
    final (k0, k1) = visibleWorldCopies(
      baseX: b.left,
      spanPx: b.width,
      worldSize: state.worldSize,
      viewportWidth: size.width,
    );
    for (var k = k0; k <= k1; k++) {
      canvas.save();
      canvas.translate(k * state.worldSize, 0);
      draw();
      canvas.restore();
    }
  }

  /// Normalise ring winding so a `nonZero` fill punches holes correctly.
  ///
  /// The outer ring keeps its orientation; holes are reversed when they share
  /// the outer sign (MapLibre's `fill_bucket` does the same). The algorithm
  /// lives in `geo_map_core` so the renderer and the feature query read the
  /// same winding semantics — signed area is measured on unwrapped longitudes
  /// so rings near ±180° do not flip sign.
  static List<List<LatLng>> _normalizeRings(List<List<LatLng>> rings) =>
      normalizeRingWinding(rings);

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

    Offset? projectOrNull(LatLng ll) {
      final v = projector.project(ll, state);
      return v == null ? null : Offset(v.x, v.y);
    }

    /// Flat-only projection with continuous x.
    ///
    /// Unwrap the longitudes, anchor the whole sequence to the world copy
    /// nearest the camera, then map longitude → x linearly. Latitude (y) has no
    /// wrap, so it comes straight from the projector.
    List<Offset?> projectContinuous(List<LatLng> pts) {
      if (pts.isEmpty) return const <Offset?>[];
      final lons = unwrapLongitudes([for (final p in pts) p.longitude]);
      final m = ((lons.first - state.center.longitude) / 360.0).round();
      final world = state.worldSize;
      final cx = state.size.width / 2;
      final out = <Offset?>[];
      for (var i = 0; i < pts.length; i++) {
        final v = projector.project(pts[i], state);
        if (v == null) {
          out.add(null);
          continue;
        }
        final x = cx +
            ((lons[i] - 360.0 * m) - state.center.longitude) / 360.0 * world;
        out.add(Offset(x, v.y));
      }
      return out;
    }

    void addLine(List<LatLng> points, {required bool close}) {
      final dense =
          onSphere ? subdivideSpherePolyline(points, closed: close) : points;
      // Flat: build a continuous screen polyline from unwrapped longitudes
      // instead of trusting the projector's per-vertex world wrap. Otherwise a
      // ring/line whose vertices straddle the camera-relative seam gets a chord
      // spanning a whole world — the "fill across the screen" bug.
      final offsets = onSphere
          ? [for (final ll in dense) projectOrNull(ll)]
          : projectContinuous(dense);
      Offset? previous;
      for (final o in offsets) {
        if (o == null) {
          previous = null;
          continue;
        }
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
        for (final ring in _normalizeRings(rings)) {
          addRing(ring);
        }
      case MultiLineStringGeometry(:final lines):
        for (final line in lines) {
          addLine(line, close: false);
        }
      case MultiPolygonGeometry(:final polygons):
        for (final polygon in polygons) {
          for (final ring in _normalizeRings(polygon)) {
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

  /// Union of the fill and stroke bounding boxes (used to pick visible world
  /// copies in flat mode).
  Rect get bounds {
    final a = fill.getBounds();
    final b = stroke.getBounds();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return a.expandToInclude(b);
  }
}
