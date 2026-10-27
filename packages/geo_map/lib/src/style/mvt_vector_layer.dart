/// Vector-tile (MVT) rendering layer.
///
/// Pipeline, mirroring MapLibre but adapted to Canvas:
///
/// 1. **Cover** — `TileSelector.select` picks the tiles the viewport needs,
///    with the source's min/max zoom and overzoom state (same core code the
///    raster layer uses).
/// 2. **Fetch + decode** — the injected [GeoTileSource] returns pbf bytes;
///    `decodeMvtTile` parses them once and the result is cached per tile.
/// 3. **Bucket** — each source layer is classified into fill polygons (outer +
///    holes) and polylines at decode time, so painting does no geometry work.
/// 4. **Batch** — all features of one style layer that share a paint value are
///    merged into a single `Path` and drawn with one `drawPath`. That is the
///    Canvas equivalent of MapLibre's "one vertex buffer, one draw call per
///    layer": constant paint collapses to one path, data-driven paint groups
///    by resolved color.
///
/// Coordinates: buckets are normalized to the tile's `[0,1]` square. On the
/// flat map a tile is an affine parallelogram, so points are mapped with a
/// per-tile basis (exact, no per-vertex trig). On the globe a tile is a curved
/// quad, so points go through `mvtTilePointToLatLng` + the orthographic
/// projector, exactly like the M1 vector layer.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../vendor/flutter_map_camera/flutter_map_camera.dart';
import 'style_controller.dart';

/// Supplies vector tiles as raw pbf bytes.
///
/// The layer is transport-agnostic so it works with HTTP, MBTiles or a test
/// fixture; picking the transport is the app's job.
class MvtVectorLayer extends StatefulWidget {
  const MvtVectorLayer({
    super.key,
    required this.source,
    this.style,
    this.controller,
    this.opacity = 1.0,
    this.maxCachedTiles = 160,
  }) : assert(style != null || controller != null,
            'provide either style or controller');

  final GeoTileSource source;

  /// A static style. Ignored when [controller] is provided.
  final StyleSpec? style;

  /// A runtime style controller (M1.4); the layer rebuilds on notify.
  final GeoStyleController? controller;

  final double opacity;
  final int maxCachedTiles;

  @override
  State<MvtVectorLayer> createState() => _MvtVectorLayerState();
}

class _MvtVectorLayerState extends State<MvtVectorLayer> {
  final Map<TileKey, _DecodedTile> _decoded = {};
  final Set<TileKey> _pending = {};
  final Set<TileKey> _failed = {};
  int _revision = 0;

  @override
  void didUpdateWidget(covariant MvtVectorLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _decoded.clear();
      _pending.clear();
      _failed.clear();
      _revision++;
    }
  }

  Future<void> _ensureTile(TileKey key) async {
    if (_decoded.containsKey(key) || _pending.contains(key) || _failed.contains(key)) {
      return;
    }
    _pending.add(key);
    try {
      final result = await widget.source.fetch(key.z, key.x, key.y);
      if (!mounted) return;
      final bytes = result.bytes;
      if (result.isOk && bytes != null) {
        _decoded[key] = _DecodedTile(decodeMvtTile(bytes));
        while (_decoded.length > widget.maxCachedTiles) {
          _decoded.remove(_decoded.keys.first);
        }
        setState(() => _revision++);
      } else {
        _failed.add(key);
      }
    } catch (_) {
      _failed.add(key);
    } finally {
      _pending.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final size = camera.nonRotatedSize;
    if (size.x <= 0 || size.y <= 0) return const SizedBox.shrink();

    final controller = widget.controller;
    if (controller == null) {
      return _layerWith(camera, widget.style!);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => _layerWith(camera, controller.document.toSpec()),
    );
  }

  Widget _layerWith(MapCamera camera, StyleSpec spec) {
    final flat = camera.projectionDelegate is FlatProjectionDelegate;
    final projector =
        flat ? const MercatorProjector() : const OrthographicProjector();
    final state = CameraState(
      center: camera.center,
      zoom: camera.zoom,
      size: ViewportSize(camera.nonRotatedSize.x, camera.nonRotatedSize.y),
    );

    final desiredZ = TileSelector.coveringZoomLevel(state);
    final selection = TileSelector.select(
      projector: projector,
      camera: state,
      desiredZ: desiredZ,
      sourceMinZoom: widget.source.minZoom,
      sourceMaxZoom: widget.source.maxZoom,
    );
    for (final key in selection.tiles) {
      // Fire-and-forget; guards prevent duplicate requests and setState happens
      // when bytes arrive, not during build.
      _ensureTile(key);
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _MvtPainter(
          style: spec,
          camera: camera,
          tiles: selection.tiles,
          decoded: _decoded,
          revision: _revision,
          opacity: widget.opacity,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// One tile's decoded geometry, bucketed per source layer at decode time.
class _DecodedTile {
  _DecodedTile(this.tile) {
    for (final layer in tile.layers) {
      fills[layer.name] = buildMvtFillBucket(layer);
      lines[layer.name] = buildMvtLineBucket(layer);
    }
  }

  final MvtTile tile;
  final Map<String, List<MvtFillPolygon>> fills = {};
  final Map<String, List<MvtPolyline>> lines = {};
}

class _MvtPainter extends CustomPainter {
  _MvtPainter({
    required this.style,
    required this.camera,
    required this.tiles,
    required this.decoded,
    required this.revision,
    required this.opacity,
  });

  final StyleSpec style;
  final MapCamera camera;
  final List<TileKey> tiles;
  final Map<TileKey, _DecodedTile> decoded;
  final int revision;
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
      final sourceLayer = layer.sourceLayer;
      if (sourceLayer == null) continue;
      if (layer.type == 'fill') {
        _paintFills(canvas, layer, sourceLayer, projector, state, flat);
      } else if (layer.type == 'line') {
        _paintLines(canvas, layer, sourceLayer, projector, state, flat);
      }
    }

    if (clip != null) canvas.restore();
  }

  // --- fill ------------------------------------------------------------------

  void _paintFills(
    Canvas canvas,
    StyleLayer layer,
    String sourceLayer,
    GeoProjector projector,
    CameraState state,
    bool flat,
  ) {
    final colorProp = layer.paint['fill-color'];
    final opacityProp = layer.paint['fill-opacity'];
    final constant = (colorProp?.isFeatureConstant ?? true) &&
        (opacityProp?.isFeatureConstant ?? true);

    if (constant) {
      final ctx = ExpressionContext(zoom: camera.zoom);
      final color = layer.color('fill-color', ctx);
      final alpha = (layer.number('fill-opacity', ctx) ?? 1) * opacity;
      if (color == null || alpha <= 0) return;
      final path = Path()..fillType = PathFillType.nonZero;
      var any = false;
      for (final key in tiles) {
        final buckets = decoded[key]?.fills[sourceLayer];
        if (buckets == null) continue;
        final project = _tileProjector(key, projector, state, flat);
        for (final polygon in buckets) {
          if (!layer.filter(polygon.properties)) continue;
          any = _addPolygon(path, polygon, project) || any;
        }
      }
      if (!any) return;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = ui.Color(_argb(color, alpha)),
      );
      return;
    }

    // Data-driven paint: batch by resolved color.
    final paths = <int, Path>{};
    for (final key in tiles) {
      final buckets = decoded[key]?.fills[sourceLayer];
      if (buckets == null) continue;
      final project = _tileProjector(key, projector, state, flat);
      for (final polygon in buckets) {
        if (!layer.filter(polygon.properties)) continue;
        final ctx = ExpressionContext(
          zoom: camera.zoom,
          properties: polygon.properties,
        );
        final color = layer.color('fill-color', ctx);
        final alpha = (layer.number('fill-opacity', ctx) ?? 1) * opacity;
        if (color == null || alpha <= 0) continue;
        final argb = _argb(color, alpha);
        final path =
            paths[argb] ??= Path()..fillType = PathFillType.nonZero;
        _addPolygon(path, polygon, project);
      }
    }
    paths.forEach((argb, path) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = ui.Color(argb),
      );
    });
  }

  // --- line ------------------------------------------------------------------

  void _paintLines(
    Canvas canvas,
    StyleLayer layer,
    String sourceLayer,
    GeoProjector projector,
    CameraState state,
    bool flat,
  ) {
    final ctx = ExpressionContext(zoom: camera.zoom);
    final cap = _strokeCap(layer.string('line-cap', ctx));
    final join = _strokeJoin(layer.string('line-join', ctx));

    final colorProp = layer.paint['line-color'];
    final widthProp = layer.paint['line-width'];
    final opacityProp = layer.paint['line-opacity'];
    final constant = (colorProp?.isFeatureConstant ?? true) &&
        (widthProp?.isFeatureConstant ?? true) &&
        (opacityProp?.isFeatureConstant ?? true);

    if (constant) {
      final color = layer.color('line-color', ctx);
      final width = layer.number('line-width', ctx) ?? 1;
      final alpha = (layer.number('line-opacity', ctx) ?? 1) * opacity;
      if (color == null || alpha <= 0 || width <= 0) return;
      final path = Path();
      var any = false;
      for (final key in tiles) {
        final buckets = decoded[key]?.lines[sourceLayer];
        if (buckets == null) continue;
        final project = _tileProjector(key, projector, state, flat);
        for (final line in buckets) {
          if (!layer.filter(line.properties)) continue;
          any = _addPolyline(path, line, project) || any;
        }
      }
      if (!any) return;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = cap
          ..strokeJoin = join
          ..color = ui.Color(_argb(color, alpha)),
      );
      return;
    }

    // Data-driven stroke: batch by (color, width).
    final groups = <(int, double), Path>{};
    for (final key in tiles) {
      final buckets = decoded[key]?.lines[sourceLayer];
      if (buckets == null) continue;
      final project = _tileProjector(key, projector, state, flat);
      for (final line in buckets) {
        if (!layer.filter(line.properties)) continue;
        final fctx = ExpressionContext(
          zoom: camera.zoom,
          properties: line.properties,
        );
        final color = layer.color('line-color', fctx);
        final width = layer.number('line-width', fctx) ?? 1;
        final alpha = (layer.number('line-opacity', fctx) ?? 1) * opacity;
        if (color == null || alpha <= 0 || width <= 0) continue;
        final groupKey = (_argb(color, alpha), width);
        final path = groups.putIfAbsent(groupKey, Path.new);
        _addPolyline(path, line, project);
      }
    }
    groups.forEach((group, path) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = group.$2
          ..strokeCap = cap
          ..strokeJoin = join
          ..color = ui.Color(group.$1),
      );
    });
  }

  // --- geometry --------------------------------------------------------------

  /// Returns a mapper from normalized tile space to screen space.
  ///
  /// Flat: one affine basis per tile — exact because Web Mercator is linear in
  /// tile space, and it avoids a `project`/trig call per vertex.
  /// Globe: project every point through lat/lng; points on the far side return
  /// `null` and the caller breaks the subpath there.
  Vec2? Function(Vec2) _tileProjector(
    TileKey key,
    GeoProjector projector,
    CameraState state,
    bool flat,
  ) {
    final x = TileGrid.unwrapX(key.x, key.z, camera.center.longitude);
    if (flat) {
      final affine = tileAffine(projector, state, z: key.z, x: x, y: key.y);
      if (affine == null) return (_) => null;
      return affine.map;
    }
    return (p) => projector.project(_latLng(key, x, p.x, p.y), state);
  }

  LatLng _latLng(TileKey key, int x, double u, double v) =>
      mvtTilePointToLatLng(
        Vec2(u, v),
        z: key.z,
        tileX: x,
        tileY: key.y,
        extent: 1,
      );

  bool _addPolygon(
    Path path,
    MvtFillPolygon polygon,
    Vec2? Function(Vec2) project,
  ) {
    var any = false;
    for (final ring in polygon.rings) {
      any = _addRing(path, ring, project) || any;
    }
    return any;
  }

  bool _addRing(Path path, List<Vec2> ring, Vec2? Function(Vec2) project) {
    var started = false;
    for (final p in ring) {
      final s = project(p);
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
    if (started) path.close();
    return started;
  }

  bool _addPolyline(Path path, MvtPolyline line, Vec2? Function(Vec2) project) {
    var started = false;
    var any = false;
    for (final p in line.points) {
      final s = project(p);
      if (s == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(s.x, s.y);
        started = true;
      } else {
        path.lineTo(s.x, s.y);
        any = true;
      }
    }
    return any;
  }

  static int _argb(StyleColor color, double opacity) {
    final a = (color.a * opacity).round().clamp(0, 255);
    return (a << 24) |
        ((color.r & 0xff) << 16) |
        ((color.g & 0xff) << 8) |
        (color.b & 0xff);
  }

  static StrokeCap _strokeCap(String? value) => switch (value) {
        'round' => StrokeCap.round,
        'square' => StrokeCap.square,
        _ => StrokeCap.butt,
      };

  static StrokeJoin _strokeJoin(String? value) => switch (value) {
        'round' => StrokeJoin.round,
        'bevel' => StrokeJoin.bevel,
        _ => StrokeJoin.miter,
      };

  @override
  bool shouldRepaint(covariant _MvtPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.style != style ||
      oldDelegate.camera != camera ||
      oldDelegate.opacity != opacity;
}
