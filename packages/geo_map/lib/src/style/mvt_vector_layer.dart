/// Vector-tile (MVT) rendering layer.
///
/// Pipeline, mirroring MapLibre but adapted to Canvas:
///
/// 1. **Cover** — `TileSelector.select` picks the tiles the viewport needs,
///    with the source's min/max zoom and overzoom state (same core code the
///    raster layer uses).
/// 2. **Fetch + decode** — the injected [GeoTileSource] returns pbf bytes;
///    `decodeMvtTile` parses them once and the result is cached per tile.
///    Transient failures are retried after a TTL instead of being blacklisted.
/// 3. **Bucket** — each source layer is classified into fill polygons (outer +
///    holes) and polylines at decode time, so painting does no geometry work.
/// 4. **Batch** — all features of one style layer that share a paint value are
///    merged into a single `Path` and drawn with one `drawPath`. That is the
///    Canvas equivalent of MapLibre's "one vertex buffer, one draw call per
///    layer": constant paint collapses to one path, data-driven paint groups
///    by resolved color.
/// 5. **Repeat** — on the flat map a tile is drawn once per world copy that
///    intersects the viewport (`visibleWorldCopies`, mirroring MapLibre's
///    `getVisibleUnwrappedCoordinates`), so panning past ±180° keeps showing
///    data instead of empty space.
///
/// Coordinates: buckets are normalized to the tile's `[0,1]` square. On the
/// flat map a tile is an affine parallelogram, so points are mapped with a
/// per-tile basis built from the NW corner and the constant tile span. On the
/// globe a tile is a curved quad, so points go through
/// `mvtTilePointToLatLng` + the orthographic projector.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../globe/tile_source.dart' show HttpTileSource;
import '../vendor/flutter_map_camera/flutter_map_camera.dart';
import 'style_controller.dart';

/// What the layer is currently doing, for a debug HUD.
///
/// [dataZoom] is the level tiles are fetched at (0..source.maxZoom), which is
/// `round(camera zoom)` — not the continuous camera zoom the HUD usually shows.
/// [readyCount] / [tileCount] say how many visible tiles are decoded, and
/// [lastStatusCode] surfaces the transport status when the source is HTTP.
class MvtDiagnostics {
  const MvtDiagnostics({
    required this.dataZoom,
    required this.tileCount,
    required this.readyCount,
    required this.failedCount,
    this.lastStatusCode,
  });

  final int dataZoom;
  final int tileCount;
  final int readyCount;
  final int failedCount;
  final int? lastStatusCode;

  @override
  bool operator ==(Object other) =>
      other is MvtDiagnostics &&
      other.dataZoom == dataZoom &&
      other.tileCount == tileCount &&
      other.readyCount == readyCount &&
      other.failedCount == failedCount &&
      other.lastStatusCode == lastStatusCode;

  @override
  int get hashCode =>
      Object.hash(dataZoom, tileCount, readyCount, failedCount, lastStatusCode);

  @override
  String toString() => 'MvtDiagnostics(z$dataZoom, $readyCount/$tileCount, '
      'failed $failedCount, http $lastStatusCode)';
}

/// Vector tiles rendered through a [StyleSpec].
///
/// Transport is injected as a [GeoTileSource] so the same layer works with
/// HTTP, MBTiles or a test fixture.
class MvtVectorLayer extends StatefulWidget {
  const MvtVectorLayer({
    super.key,
    required this.source,
    this.style,
    this.controller,
    this.opacity = 1.0,
    this.maxCachedTiles = 160,
    this.renderWorldCopies = true,
    this.onDiagnostics,
  }) : assert(style != null || controller != null,
            'provide either style or controller');

  final GeoTileSource source;

  /// A static style. Ignored when [controller] is provided.
  final StyleSpec? style;

  /// A runtime style controller (M1.4); the layer rebuilds on notify.
  final GeoStyleController? controller;

  final double opacity;
  final int maxCachedTiles;

  /// Draw the world once per visible copy when panning past ±180°.
  ///
  /// Defaults to `true` (MapLibre's `renderWorldCopies`). Set `false` for a
  /// fixed single-world view: off-screen data is clipped instead of repeated.
  final bool renderWorldCopies;

  /// Called after a frame when the diagnostics change (for a debug HUD).
  final ValueChanged<MvtDiagnostics>? onDiagnostics;

  @override
  State<MvtVectorLayer> createState() => _MvtVectorLayerState();
}

class _MvtVectorLayerState extends State<MvtVectorLayer> {
  /// Maximum requests in flight. The public demo tile server rate-limits
  /// bursts, so the edge tiles used to fail and never come back.
  static const int _maxConcurrent = 6;

  final Map<TileKey, _DecodedTile> _decoded = {};
  final Set<TileKey> _pending = {};

  /// When a tile may be retried; failures are no longer permanent.
  final Map<TileKey, DateTime> _retryAfter = {};

  int _inFlight = 0;
  int _revision = 0;
  Timer? _retryTimer;
  MvtDiagnostics? _lastDiag;

  @override
  void didUpdateWidget(covariant MvtVectorLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _decoded.clear();
      _pending.clear();
      _retryAfter.clear();
      _retryTimer?.cancel();
      _retryTimer = null;
      _revision++;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _ensureTile(TileKey key) async {
    if (_decoded.containsKey(key) || _pending.contains(key)) return;

    final now = DateTime.now();
    final until = _retryAfter[key];
    if (until != null) {
      if (now.isBefore(until)) return;
      _retryAfter.remove(key);
    }
    if (_inFlight >= _maxConcurrent) return;

    _pending.add(key);
    _inFlight++;
    try {
      final result = await widget.source.fetch(key.z, key.x, key.y);
      if (!mounted) return;
      final bytes = result.bytes;
      if (result.isOk && bytes != null) {
        // Parse off the UI isolate: a z0 world tile is ~34k vertices.
        final tile = await decodeMvtTileAsync(bytes);
        if (!mounted) return;
        _decoded[key] = _DecodedTile(tile);
        while (_decoded.length > widget.maxCachedTiles) {
          _decoded.remove(_decoded.keys.first);
        }
        setState(() => _revision++);
      } else {
        _retryAfter[key] = DateTime.now().add(
          Duration(
            milliseconds: result.isNotFound
                ? GeoEngineTuning.notFoundTtlMs
                : GeoEngineTuning.networkFailureTtlMs,
          ),
        );
        _ensureRetryTimer();
        // Kick the next queued tile now instead of waiting for the retry tick.
        if (mounted) setState(() => _revision++);
      }
    } catch (_) {
      _retryAfter[key] = DateTime.now().add(
          const Duration(milliseconds: GeoEngineTuning.networkFailureTtlMs));
      _ensureRetryTimer();
      if (mounted) setState(() => _revision++);
    } finally {
      _pending.remove(key);
      _inFlight--;
    }
  }

  /// Polls once a second while any tile is waiting for its retry window; the
  /// TTL itself decides which tiles actually get re-requested.
  void _ensureRetryTimer() {
    _retryTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retryAfter.isEmpty) {
        timer.cancel();
        _retryTimer = null;
        return;
      }
      setState(() => _revision++);
    });
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

    _reportDiagnostics(selection);

    return RepaintBoundary(
      child: CustomPaint(
        painter: _MvtPainter(
          style: spec,
          camera: camera,
          tiles: selection.tiles,
          decoded: _decoded,
          revision: _revision,
          opacity: widget.opacity,
          renderWorldCopies: widget.renderWorldCopies,
          sourceMinZoom: widget.source.minZoom,
          sourceMaxZoom: widget.source.maxZoom,
          scheme: widget.source.scheme,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _reportDiagnostics(TileSelection selection) {
    final callback = widget.onDiagnostics;
    if (callback == null) return;
    var ready = 0;
    var failed = 0;
    for (final key in selection.tiles) {
      if (_decoded.containsKey(key)) {
        ready++;
      } else if (_retryAfter.containsKey(key)) {
        failed++;
      }
    }
    final source = widget.source;
    final diag = MvtDiagnostics(
      dataZoom: selection.dataZoom,
      tileCount: selection.tiles.length,
      readyCount: ready,
      failedCount: failed,
      lastStatusCode: source is HttpTileSource ? source.lastStatusCode : null,
    );
    if (diag == _lastDiag) return;
    _lastDiag = diag;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(diag);
    });
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

/// How one tile maps to the screen: a point mapper plus the world copies.
class _TileMapping {
  const _TileMapping(
    this.project,
    this.copies,
    this.worldSize, {
    this.toLatLng,
    this.projectGeo,
    this.densifyStepRad = 0,
  });

  final Vec2? Function(Vec2) project;

  /// Inclusive copy indices; each copy is offset by `k * worldSize` in x.
  final (int, int) copies;
  final double worldSize;

  /// Globe only: normalized tile point → geographic point.
  final LatLng Function(Vec2)? toLatLng;

  /// Globe only: geographic point → screen.
  final Vec2? Function(LatLng)? projectGeo;

  /// Globe only: great-circle step; 0 on the affine flat map.
  final double densifyStepRad;
}

class _MvtPainter extends CustomPainter {
  _MvtPainter({
    required this.style,
    required this.camera,
    required this.tiles,
    required this.decoded,
    required this.revision,
    required this.opacity,
    required this.renderWorldCopies,
    required this.sourceMinZoom,
    required this.sourceMaxZoom,
    required this.scheme,
  });

  final StyleSpec style;
  final MapCamera camera;
  final List<TileKey> tiles;
  final Map<TileKey, _DecodedTile> decoded;
  final int revision;
  final double opacity;
  final bool renderWorldCopies;
  final int sourceMinZoom;
  final int sourceMaxZoom;
  final TileSchemeKind scheme;

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

    // Placeholders (loaded ancestors) first, then exact tiles / child
    // generations, so a loaded tile always wins over its coarse stand-in.
    final draw = resolveVectorDrawTiles(
      visible: tiles,
      isLoaded: decoded.containsKey,
      sourceMinZoom: sourceMinZoom,
      sourceMaxZoom: sourceMaxZoom,
      scheme: scheme,
    );
    final drawTiles = draw.drawOrder;

    for (final layer in style.layers) {
      if (!layer.isSupported || !layer.isVisibleAt(camera.zoom)) continue;
      final sourceLayer = layer.sourceLayer;
      if (sourceLayer == null) continue;
      if (layer.type == 'fill') {
        _paintFills(canvas, layer, sourceLayer, projector, state, flat, drawTiles);
      } else if (layer.type == 'line') {
        _paintLines(canvas, layer, sourceLayer, projector, state, flat, drawTiles);
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
    List<TileKey> drawTiles,
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
      for (final key in drawTiles) {
        final buckets = decoded[key]?.fills[sourceLayer];
        if (buckets == null) continue;
        final mapping = _mappingFor(key, projector, state, flat);
        if (mapping == null) continue;
        for (final polygon in buckets) {
          if (!layer.filter(polygon.properties)) continue;
          any = _addPolygon(path, polygon, mapping) || any;
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
    for (final key in drawTiles) {
      final buckets = decoded[key]?.fills[sourceLayer];
      if (buckets == null) continue;
      final mapping = _mappingFor(key, projector, state, flat);
      if (mapping == null) continue;
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
        _addPolygon(path, polygon, mapping);
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
    List<TileKey> drawTiles,
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
      final dash = _dashPattern(layer, ctx);
      final patternPx =
          dash == null ? null : [for (final v in dash) v * width];
      final path = Path();
      var any = false;
      for (final key in drawTiles) {
        final buckets = decoded[key]?.lines[sourceLayer];
        if (buckets == null) continue;
        final mapping = _mappingFor(key, projector, state, flat);
        if (mapping == null) continue;
        for (final line in buckets) {
          if (!layer.filter(line.properties)) continue;
          any = _addPolyline(path, line, mapping, patternPx) || any;
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

    // Data-driven stroke: batch by (color, width, dash pattern).
    final groups = <(int, double, String), Path>{};
    for (final key in drawTiles) {
      final buckets = decoded[key]?.lines[sourceLayer];
      if (buckets == null) continue;
      final mapping = _mappingFor(key, projector, state, flat);
      if (mapping == null) continue;
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
        final dash = _dashPattern(layer, fctx);
        final patternPx =
            dash == null ? null : [for (final v in dash) v * width];
        final groupKey = (
          _argb(color, alpha),
          width,
          patternPx?.join(',') ?? '',
        );
        final path = groups.putIfAbsent(groupKey, Path.new);
        _addPolyline(path, line, mapping, patternPx);
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

  /// How a tile maps to the screen, or `null` when it cannot be projected.
  ///
  /// Flat: one affine basis per tile plus the world-copy range. Globe: a point
  /// mapper through lat/lng and exactly one copy (the sphere has no seam).
  _TileMapping? _mappingFor(
    TileKey key,
    GeoProjector projector,
    CameraState state,
    bool flat,
  ) {
    if (!flat) {
      LatLng toLatLng(Vec2 p) => _latLng(key, key.x, p.x, p.y);
      Vec2? project(Vec2 p) => projector.project(toLatLng(p), state);
      return _TileMapping(
        project,
        (0, 0),
        state.worldSize,
        toLatLng: toLatLng,
        projectGeo: (ll) => projector.project(ll, state),
        densifyStepRad: projector.densifyStepRad(state),
      );
    }
    final affine = tileAffine(projector, state, z: key.z, x: key.x, y: key.y);
    if (affine == null) return null;
    final copies = renderWorldCopies
        ? visibleWorldCopies(
            baseX: affine.origin.x,
            spanPx: affine.ux,
            worldSize: state.worldSize,
            viewportWidth: state.size.width,
          )
        : (0, 0);
    return _TileMapping(affine.map, copies, state.worldSize);
  }

  LatLng _latLng(TileKey key, int x, double u, double v) =>
      mvtTilePointToLatLng(
        Vec2(u, v),
        z: key.z,
        tileX: x,
        tileY: key.y,
        extent: 1,
      );

  bool _addPolygon(Path path, MvtFillPolygon polygon, _TileMapping mapping) {
    var any = false;
    for (var k = mapping.copies.$1; k <= mapping.copies.$2; k++) {
      final dx = k * mapping.worldSize;
      for (final ring in polygon.rings) {
        any = _addRing(path, ring, mapping.project, dx) || any;
      }
    }
    return any;
  }

  bool _addRing(
    Path path,
    List<Vec2> ring,
    Vec2? Function(Vec2) project,
    double dx,
  ) {
    var started = false;
    for (final p in ring) {
      final s = project(p);
      if (s == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(s.x + dx, s.y);
        started = true;
      } else {
        path.lineTo(s.x + dx, s.y);
      }
    }
    if (started) path.close();
    return started;
  }

  bool _addPolyline(
    Path path,
    MvtPolyline line,
    _TileMapping mapping, [
    List<double>? dashPx,
  ]) {
    var any = false;
    for (var k = mapping.copies.$1; k <= mapping.copies.$2; k++) {
      final dx = k * mapping.worldSize;
      final run = <Vec2>[];

      void flush() {
        if (run.length < 2) {
          run.clear();
          return;
        }
        if (dashPx == null) {
          path.moveTo(run.first.x + dx, run.first.y);
          for (var i = 1; i < run.length; i++) {
            path.lineTo(run[i].x + dx, run[i].y);
          }
          any = true;
        } else {
          for (final dash in dashPolyline(run, dashPx)) {
            path.moveTo(dash.first.x + dx, dash.first.y);
            for (var i = 1; i < dash.length; i++) {
              path.lineTo(dash[i].x + dx, dash[i].y);
            }
            any = true;
          }
        }
        run.clear();
      }

      final toLatLng = mapping.toLatLng;
      final projectGeo = mapping.projectGeo;
      if (toLatLng != null &&
          projectGeo != null &&
          mapping.densifyStepRad > 0) {
        // Same recipe as the graticule: densify the great circle *before*
        // projecting. A sparse MVT segment is otherwise a screen chord, and
        // two adjacent tiles meet at a visible step on the globe.
        final geo = [for (final p in line.points) toLatLng(p)];
        final dense = densifyGreatCircle(
          geo,
          stepRad: mapping.densifyStepRad,
        );
        for (final ll in dense) {
          final s = projectGeo(ll);
          if (s == null) {
            flush();
            continue;
          }
          run.add(s);
        }
      } else {
        for (final p in line.points) {
          final s = mapping.project(p);
          if (s == null) {
            flush();
            continue;
          }
          run.add(s);
        }
      }
      flush();    }
    return any;
  }

  /// Resolves `line-dasharray` (line-width multiples) to a validated list.
  List<double>? _dashPattern(StyleLayer layer, ExpressionContext ctx) {
    final raw = layer.valueOf('line-dasharray', ctx);
    if (raw is! List || raw.length < 2) return null;
    final out = <double>[];
    var sum = 0.0;
    for (final value in raw) {
      if (value is! num || value < 0) return null;
      out.add(value.toDouble());
      sum += value;
    }
    return sum <= 0 ? null : out;
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
      oldDelegate.opacity != opacity ||
      oldDelegate.renderWorldCopies != renderWorldCopies;
}
