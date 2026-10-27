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
/// `mvtTilePointToLatLng` + the orthographic projector, and the bucket is
/// pre-split on a tile-space grid (`subdivideTilePolyline`) so those points are
/// dense enough for the curvature to show.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../globe/tile_source.dart' show HttpTileSource;
import '../vendor/flutter_map_camera/flutter_map_camera.dart';
import 'sprite_atlas.dart';
import 'style_controller.dart';
import 'symbol_painter.dart';
import 'symbol_style.dart';

/// What the layer is currently doing, for a debug HUD.
///
/// [dataZoom] is the level tiles are fetched at (0..source.maxZoom), which is
/// `round(camera zoom)` — not the continuous camera zoom the HUD usually shows.
/// [readyCount] / [tileCount] say how many visible tiles are decoded, and
/// [lastStatusCode] surfaces the transport status when the source is HTTP.
///
/// [firstFailed] names the tile behind [failedCount] (`z/x/y · status`). Without
/// it a "one tile failed" report is not diagnosable — the key is what tells you
/// whether it is an edge tile, an out-of-range coordinate or a rate limit.
class MvtDiagnostics {
  const MvtDiagnostics({
    required this.dataZoom,
    required this.tileCount,
    required this.readyCount,
    required this.failedCount,
    this.lastStatusCode,
    this.firstFailed,
  });

  final int dataZoom;
  final int tileCount;
  final int readyCount;
  final int failedCount;
  final int? lastStatusCode;
  final String? firstFailed;

  @override
  bool operator ==(Object other) =>
      other is MvtDiagnostics &&
      other.dataZoom == dataZoom &&
      other.tileCount == tileCount &&
      other.readyCount == readyCount &&
      other.failedCount == failedCount &&
      other.lastStatusCode == lastStatusCode &&
      other.firstFailed == firstFailed;

  @override
  int get hashCode => Object.hash(dataZoom, tileCount, readyCount, failedCount,
      lastStatusCode, firstFailed);

  @override
  String toString() => 'MvtDiagnostics(z$dataZoom, $readyCount/$tileCount, '
      'failed $failedCount${firstFailed == null ? '' : ' ($firstFailed)'}, '
      'http $lastStatusCode)';
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
    this.sprite,
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

  /// Icons for `icon-image`; without one the labels are still drawn.
  final SpriteAtlas? sprite;

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

  /// How many times a key has failed, for the backoff curve.
  final Map<TileKey, int> _failures = {};

  /// Transport status of the last failure, for the HUD.
  final Map<TileKey, int?> _failureStatus = {};

  /// Ancestors fetched *as a fallback* for a hole. When one of these fails too,
  /// the next pass climbs another level — that is how the ascent reaches a zoom
  /// level that actually has data.
  final Set<TileKey> _fallback = {};

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
      _failures.clear();
      _failureStatus.clear();
      _fallback.clear();
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
        _decoded[key] = _DecodedTile(tile, z: key.z);
        _failures.remove(key);
        _failureStatus.remove(key);
        _fallback.remove(key);
        while (_decoded.length > widget.maxCachedTiles) {
          _decoded.remove(_decoded.keys.first);
        }
        setState(() => _revision++);
      } else {
        _recordFailure(key, notFound: result.isNotFound);
      }
    } catch (_) {
      _recordFailure(key, notFound: false);
    } finally {
      _pending.remove(key);
      _inFlight--;
    }
  }

  /// Records a failure and schedules the next attempt on a doubling curve.
  ///
  /// A fixed one-second retry against a rate-limited server is what turned one
  /// bad tile into a permanent hole: every tick re-hit the limit and the tile
  /// never loaded. [tileRetryDelay] backs off instead.
  void _recordFailure(TileKey key, {required bool notFound}) {
    final attempts = (_failures[key] ?? 0) + 1;
    _failures[key] = attempts;
    _failureStatus[key] = widget.source is HttpTileSource
        ? (widget.source as HttpTileSource).lastStatusCode
        : null;
    final delay = tileRetryDelay(
      attempts,
      baseMs: notFound
          ? GeoEngineTuning.notFoundTtlMs
          : GeoEngineTuning.networkFailureTtlMs,
    );
    _retryAfter[key] = DateTime.now().add(delay);
    _ensureRetryTimer();
    // Kick the next queued tile now instead of waiting for the retry tick.
    if (mounted) setState(() => _revision++);
  }

  /// `z/x/y · 429 · attempt 3` for the HUD.
  String _describeFailure(TileKey key) {
    final status = _failureStatus[key];
    final attempts = _failures[key] ?? 1;
    final buffer = StringBuffer(key.toString());
    if (status != null) buffer.write(' · $status');
    if (attempts > 1) buffer.write(' · try $attempts');
    return buffer.toString();
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

    // What this frame can actually draw. Resolving here (instead of inside the
    // painter) is what lets us answer the follow-up question: for the tiles with
    // nothing at all, should a coarser tile be fetched so the gap gets covered?
    final draw = resolveVectorDrawTiles(
      visible: selection.tiles,
      isLoaded: _decoded.containsKey,
      sourceMinZoom: widget.source.minZoom,
      sourceMaxZoom: widget.source.maxZoom,
      scheme: widget.source.scheme,
    );
    for (final ancestor in planAncestorRequests(
      // Only a tile that was actually requested can be "missing": one still
      // queued behind the concurrency cap is late, not lost (MapLibre's
      // `parentWasRequested`). A fallback ancestor that failed counts as
      // missing too, so the ascent keeps climbing one level per pass.
      missing: [
        ...draw.missing.where(
          (key) => _pending.contains(key) || _retryAfter.containsKey(key),
        ),
        ..._fallback.where(_retryAfter.containsKey),
      ],
      isAvailable: (key) =>
          _decoded.containsKey(key) || _pending.contains(key),
      sourceMinZoom: widget.source.minZoom,
    )) {
      _fallback.add(ancestor);
      _ensureTile(ancestor);
    }

    _reportDiagnostics(selection);

    return RepaintBoundary(
      child: CustomPaint(
        painter: _MvtPainter(
          style: spec,
          camera: camera,
          drawTiles: draw,
          decoded: _decoded,
          revision: _revision,
          opacity: widget.opacity,
          sprite: widget.sprite,
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
    String? firstFailed;
    for (final key in selection.tiles) {
      if (_decoded.containsKey(key)) {
        ready++;
      } else if (_retryAfter.containsKey(key)) {
        failed++;
        firstFailed ??= _describeFailure(key);
      }
    }
    final source = widget.source;
    final diag = MvtDiagnostics(
      dataZoom: selection.dataZoom,
      tileCount: selection.tiles.length,
      readyCount: ready,
      failedCount: failed,
      lastStatusCode: source is HttpTileSource ? source.lastStatusCode : null,
      firstFailed: firstFailed,
    );
    if (diag == _lastDiag) return;
    _lastDiag = diag;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(diag);
    });
  }
}

/// One tile's decoded geometry, bucketed per source layer at decode time.
///
/// The globe projector maps vertices one by one, so a sparse segment is a screen
/// chord that cuts across the sphere and steps at tile boundaries. MapLibre
/// fixes this by splitting geometry on a tile-space grid while building the
/// bucket (`render/subdivision.ts:757-868`), with the granularity derived from
/// the tile's zoom — so the work happens once per tile, never per frame. We use
/// the same presets, which is why buckets are built with [z] here.
class _DecodedTile {
  _DecodedTile(this.tile, {required int z}) {
    final lineGranularity = mvtSubdivisionGranularity(z);
    final fillGranularity = mvtSubdivisionGranularity(
      z,
      base: mvtFillBaseGranularity,
      min: mvtFillMinGranularity,
    );
    for (final layer in tile.layers) {
      fills[layer.name] = buildMvtFillBucket(layer, granularity: fillGranularity);
      lines[layer.name] = buildMvtLineBucket(layer, granularity: lineGranularity);
    }
  }

  final MvtTile tile;
  final Map<String, List<MvtFillPolygon>> fills = {};
  final Map<String, List<MvtPolyline>> lines = {};
  final Map<String, List<MvtSymbol>> _symbols = {};

  /// Label anchors for one source layer, built on first use.
  ///
  /// Symbols are cheap (one `Vec2` + the feature's properties per point) but
  /// most layers never need them, so this stays lazy until the glyph painter
  /// exists.
  List<MvtSymbol> symbolsFor(String sourceLayer) {
    final cached = _symbols[sourceLayer];
    if (cached != null) return cached;
    final layer = tile.layers
        .where((l) => l.name == sourceLayer)
        .firstOrNull;
    return _symbols[sourceLayer] =
        layer == null ? const [] : buildMvtSymbolBucket(layer);
  }
}

/// How one tile maps to the screen: a point mapper plus the world copies.
///
/// Geometry curvature on the globe is *not* handled here — sparse segments are
/// split in tile space when the bucket is built (`_DecodedTile`), exactly like
/// MapLibre's `subdivideVertexLine`, so the painter only ever projects vertices.
class _TileMapping {
  const _TileMapping(
    this.project,
    this.copies,
    this.worldSize, {
    this.dashSeed,
    this.clipRing,
  });

  final Vec2? Function(Vec2) project;

  /// Inclusive copy indices; each copy is offset by `k * worldSize` in x.
  final (int, int) copies;
  final double worldSize;

  /// Dash phase (px) at a tile-space point, anchored to a global origin so a
  /// pattern continues across tile edges instead of restarting. See
  /// `dashPhaseSeed`.
  final double Function(Vec2 start, bool horizontal)? dashSeed;

  /// Globe only: closes a tile-space ring **along the limb**. `null` means the
  /// ring is entirely behind the globe.
  ///
  /// Plain projection is not enough here. A ring that crosses the horizon has
  /// its hidden vertices dropped and each visible run closed with a chord; with
  /// `PathFillType.nonZero` those chords have opposite winding and cancel most
  /// of the polygon — measured on a limb-straddling test ring: 634 px covered
  /// by the chord version vs 2257 px by the clipped version. The visible result
  /// is a straight-edged bite taken out of the fill near the limb.
  final HorizonClippedRing? Function(List<Vec2> ring)? clipRing;
}

class _MvtPainter extends CustomPainter {
  _MvtPainter({
    required this.style,
    required this.camera,
    required this.drawTiles,
    required this.decoded,
    required this.revision,
    required this.opacity,
    required this.sprite,
    required this.renderWorldCopies,
    required this.sourceMinZoom,
    required this.sourceMaxZoom,
    required this.scheme,
  });

  final StyleSpec style;
  final MapCamera camera;

  /// Resolved by the layer so the same pass can drive fallback requests.
  final VectorDrawTiles drawTiles;
  final Map<TileKey, _DecodedTile> decoded;
  final int revision;
  final double opacity;
  final SpriteAtlas? sprite;
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
    final drawOrder = drawTiles.drawOrder;

    for (final layer in style.layers) {
      if (!layer.isSupported || !layer.isVisibleAt(camera.zoom)) continue;
      final sourceLayer = layer.sourceLayer;
      if (sourceLayer == null) continue;
      if (layer.type == 'fill') {
        _paintFills(canvas, layer, sourceLayer, projector, state, flat, drawOrder);
      } else if (layer.type == 'line') {
        _paintLines(canvas, layer, sourceLayer, projector, state, flat, drawOrder);
      } else if (layer.type == 'symbol') {
        _paintSymbols(canvas, layer, sourceLayer, projector, state, flat, drawOrder);
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
    final ctx0 = ExpressionContext(zoom: camera.zoom);
    // MapLibre draws a fill as two programs: the fill itself, and `fill_outline`,
    // a 1 px antialiased band along every ring edge
    // (`shaders/glsl/fill_outline.fragment.glsl:16-18` — distance to the edge,
    // `1 - smoothstep(0, 1, dist)`). Two consequences:
    //
    //  * an unset `fill-outline-color` means "outline in the fill's own colour",
    //    not "no outline" — `style/properties.ts:616-620` leaves it undefined and
    //    `style/style_layer/fill_style_layer.ts:30-32` copies `fill-color` in;
    //  * `fill-antialias: false` turns the band off.
    //
    // Canvas has no vertex-shader trick for it, so the band becomes a 1 px
    // `stroke` of the same rings. Close enough: same colour, same width, the
    // stroke straddles the edge instead of hugging it.
    final antialias = layer.valueOf('fill-antialias', ctx0) != false;

    final fills = <(int, int), Path>{};
    final outlines = <(int, int), Path>{};
    final order = <(int, int)>[];

    for (final key in drawTiles) {
      final buckets = decoded[key]?.fills[sourceLayer];
      if (buckets == null) continue;
      final mapping = _mappingFor(key, projector, state, flat);
      if (mapping == null) continue;
      for (final polygon in buckets) {
        if (!layer.matches(polygon.properties, camera.zoom)) continue;
        final ctx = ExpressionContext(
          zoom: camera.zoom,
          properties: polygon.properties,
        );
        final color = layer.color('fill-color', ctx);
        final alpha = (layer.number('fill-opacity', ctx) ?? 1) * opacity;
        if (color == null || alpha <= 0) continue;

        final outlineColor = layer.color('fill-outline-color', ctx) ?? color;
        final fillArgb = _argb(color, alpha);
        final outlineArgb = _argb(outlineColor, alpha);

        var group = (fillArgb, outlineArgb);
        var fillPath = fills[group];
        if (fillPath == null) {
          fillPath = fills[group] = Path()..fillType = PathFillType.nonZero;
          if (antialias) {
            outlines[group] = Path()..fillType = PathFillType.nonZero;
          }
          order.add(group);
        }
        _addPolygon(fillPath, outlines[group], polygon, mapping);
      }
    }

    for (final group in order) {
      canvas.drawPath(
        fills[group]!,
        Paint()
          ..style = PaintingStyle.fill
          ..color = ui.Color(group.$1),
      );
      final outline = outlines[group];
      // Alpha 0 means "no visible band"; skip the draw call entirely.
      if (outline != null && (group.$2 >>> 24) != 0) {
        canvas.drawPath(
          outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = ui.Color(group.$2),
        );
      }
    }
  }

  // --- symbol ----------------------------------------------------------------

  /// Labels from every drawn tile through one placer.
  ///
  /// One placer per layer per frame is the point: a label in tile A has to be
  /// able to hide a label in tile B, and only a grid shared by all of them can
  /// arbitrate that.
  void _paintSymbols(
    Canvas canvas,
    StyleLayer layer,
    String sourceLayer,
    GeoProjector projector,
    CameraState state,
    bool flat,
    List<TileKey> drawTiles,
  ) {
    final symbols = <SymbolSpec>[];
    var order = 0;
    var collisionGroup = 0;
    for (final key in drawTiles) {
      final decodedTile = decoded[key];
      if (decodedTile == null) continue;
      final mapping = _mappingFor(key, projector, state, flat);
      if (mapping == null) continue;
      for (final symbol in decodedTile.symbolsFor(sourceLayer)) {
        if (!layer.matches(symbol.properties, camera.zoom)) continue;
        final anchor = mapping.project(symbol.anchor);
        if (anchor == null) continue; // behind the globe
        final ctx = ExpressionContext(
          zoom: camera.zoom,
          properties: symbol.properties,
        );
        symbols.addAll(resolveSymbols(
          layer: layer,
          ctx: ctx,
          anchor: anchor,
          sprite: sprite,
          order: order,
          collisionGroup: ++collisionGroup,
        ));
        order += 2;
      }
    }
    if (symbols.isEmpty) return;
    SymbolPainter(viewport: Size(state.size.width, state.size.height))
        .paint(canvas, symbols);
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
          if (!layer.matches(line.properties, camera.zoom)) continue;
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
        if (!layer.matches(line.properties, camera.zoom)) continue;
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
        clipRing: (ring) => clipRingToHorizon(
          [for (final p in ring) toLatLng(p)],
          state,
        ),
        dashSeed: (start, horizontal) => dashPhaseSeed(
          start,
          z: key.z,
          tileX: key.x,
          tileY: key.y,
          horizontal: horizontal,
          sphere: true,
          worldSize: state.worldSize,
          radiusPx: state.radiusPx,
        ),
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
    return _TileMapping(
      affine.map,
      copies,
      state.worldSize,
      dashSeed: (start, horizontal) => dashPhaseSeed(
        start,
        z: key.z,
        tileX: key.x,
        tileY: key.y,
        horizontal: horizontal,
        sphere: false,
        worldSize: state.worldSize,
        radiusPx: state.radiusPx,
      ),
    );
  }

  LatLng _latLng(TileKey key, int x, double u, double v) =>
      mvtTilePointToLatLng(
        Vec2(u, v),
        z: key.z,
        tileX: x,
        tileY: key.y,
        extent: 1,
      );

  /// Adds one polygon to [fill] and, when [outline] is given, its edges to
  /// [outline] as well.
  ///
  /// The two paths differ on the globe: the fill closes along the limb, while the
  /// outline must follow only the real edges — a stroke along the limb would draw
  /// a rim around the planet that MapLibre never shows.
  bool _addPolygon(
    Path fill,
    Path? outline,
    MvtFillPolygon polygon,
    _TileMapping mapping,
  ) {
    var any = false;
    final clipRing = mapping.clipRing;
    if (clipRing != null) {
      for (final ring in polygon.rings) {
        final clipped = clipRing(ring);
        if (clipped == null || clipped.fill.length < 3) continue;
        fill.addPolygon([for (final p in clipped.fill) Offset(p.x, p.y)], true);
        if (outline != null) {
          for (final run in clipped.strokeRuns) {
            if (run.length < 2) continue;
            outline.moveTo(run.first.x, run.first.y);
            for (var i = 1; i < run.length; i++) {
              outline.lineTo(run[i].x, run[i].y);
            }
          }
        }
        any = true;
      }
      return any;
    }

    for (var k = mapping.copies.$1; k <= mapping.copies.$2; k++) {
      final dx = k * mapping.worldSize;
      for (final ring in polygon.rings) {
        any = _addRing(fill, outline, ring, mapping.project, dx) || any;
      }
    }
    return any;
  }

  bool _addRing(
    Path fill,
    Path? outline,
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
        fill.moveTo(s.x + dx, s.y);
        outline?.moveTo(s.x + dx, s.y);
        started = true;
      } else {
        fill.lineTo(s.x + dx, s.y);
        outline?.lineTo(s.x + dx, s.y);
      }
    }
    if (started) {
      fill.close();
      outline?.close();
    }
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
      // Tile-space ends of the current run, needed for the dash phase anchor.
      Vec2? runStart;
      Vec2? runLast;

      void flush() {
        if (run.length < 2) {
          run.clear();
          runStart = null;
          runLast = null;
          return;
        }
        if (dashPx == null) {
          path.moveTo(run.first.x + dx, run.first.y);
          for (var i = 1; i < run.length; i++) {
            path.lineTo(run[i].x + dx, run[i].y);
          }
          any = true;
        } else {
          // Without a global anchor the pattern would restart at 0 for every
          // tile, putting a visible step in the dashes at each tile edge.
          final seed = mapping.dashSeed;
          final double phase;
          if (seed == null || runStart == null || runLast == null) {
            phase = 0;
          } else {
            phase = seed(
              runStart!,
              (runLast!.x - runStart!.x).abs() >= (runLast!.y - runStart!.y).abs(),
            );
          }
          for (final dash in dashPolyline(run, dashPx, phase: phase)) {
            path.moveTo(dash.first.x + dx, dash.first.y);
            for (var i = 1; i < dash.length; i++) {
              path.lineTo(dash[i].x + dx, dash[i].y);
            }
            any = true;
          }
        }
        run.clear();
        runStart = null;
        runLast = null;
      }

      // Points are already subdivided in tile space (see `_DecodedTile`), so
      // projecting them one by one follows the sphere on both projections.
      for (final p in line.points) {
        final s = mapping.project(p);
        if (s == null) {
          flush();
          continue;
        }
        runStart ??= p;
        runLast = p;
        run.add(s);
      }
      flush();
    }
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
