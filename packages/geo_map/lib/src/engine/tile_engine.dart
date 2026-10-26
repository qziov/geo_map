/// The shared raster tile engine — one implementation for the 2D and the 3D
/// rendering stack.
///
/// The engine owns everything that is *not* projection specific:
///
/// * tile **selection** (window based, `TileSelector.visible`),
/// * the **data / render zoom split** (MapLibre `OverscaledTileID` overzoom
///   semantics: the canonical tile is the *data* layer, the screen scale comes
///   from the camera zoom — the texture is stretched, never re-cut),
/// * **requesting** (failure grading, TTL / exponential backoff, concurrency
///   gate — MapLibre never blacklists a 404, it just keeps falling back),
/// * the **decode cache** (byte budget instead of a tile count),
/// * **fallback resolution** (exact → loaded descendants → loaded ancestors),
/// * **polar cap** bookkeeping (mercator's ±85.05° blind spot).
///
/// Only the *geometry* differs between 2D and 3D: the 3D renderer projects a
/// spherical mesh, the 2D renderer projects an affine mercator rect. Both
/// consume the very same [TileDraw] commands produced here, so a bug can
/// never be fixed in one mode and remain broken in the other.
///
/// ### UV semantics (the classic source of "mosaic blocks")
///
/// A [TileDraw] separates two things that used to be conflated:
///
/// * `geoKey` — the **footprint**: which piece of the world is covered;
/// * `u0/v0/spanU/spanV` — the **texture region** inside the image.
///
/// For an exact tile the texture is the whole image. For an ancestor fallback
/// the footprint is the *fine* tile while the texture is the ancestor's
/// sub-rectangle (`parentUvRect`) — the other way round stretches a quarter
/// of the ancestor over the whole footprint. This is MapLibre's
/// `getFadeProperties` (`parentScaleBy` / `parentTopLeft`) expressed directly.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:geo_map_core/geo_map_core.dart';

import '../globe/tile_source.dart';

/// A decoded tile image plus its shader.
class TileImage {
  TileImage(this.image, this.shader, {this.loadedAt});

  final ui.Image image;
  final ui.ImageShader shader;

  /// Wall-clock time (ms) the image finished decoding, used for the self
  /// fade-in (MapLibre `fadeDuration`). `null` marks a pre-settled image that
  /// always draws at full opacity.
  final int? loadedAt;

  int get bytes => image.width * image.height * 4;

  void dispose() {
    shader.dispose();
    image.dispose();
  }
}

/// How a screen tile is going to be filled.
///
/// * [exact] — the requested tile itself is available.
/// * [ancestor] — a coarser tile is stretched over the requested footprint;
///   [ancestorDz] tells how many levels up it lives (UV = sub-rect).
/// * [descendants] — finer tiles are already loaded and cover the requested
///   footprint (MapLibre `_retainLoadedChildren`).
class TileResolution {
  const TileResolution.exact(this.image)
      : ancestor = null,
        ancestorDz = 0,
        descendants = const [],
        descendantImages = const [];

  const TileResolution.ancestor(this.image, this.ancestorDz)
      : ancestor = image,
        descendants = const [],
        descendantImages = const [];

  const TileResolution.descendants(this.descendants, this.descendantImages)
      : image = null,
        ancestor = null,
        ancestorDz = 0;

  /// The exact tile (if any).
  final TileImage? image;

  /// The ancestor used as a fallback (if any).
  final TileImage? ancestor;

  /// How many zoom levels up [ancestor] is.
  final int ancestorDz;

  /// Loaded descendants covering the footprint.
  final List<TileKey> descendants;

  /// The images of [descendants] (same order).
  final List<TileImage> descendantImages;

  bool get isEmpty => image == null && ancestor == null && descendants.isEmpty;
}

/// One drawing instruction for a screen tile.
///
/// [geoKey] is the **footprint** (which piece of the world is covered),
/// the UV values are the **texture region** inside [image] (in image pixels).
class TileDraw {
  const TileDraw({
    required this.geoKey,
    required this.sourceKey,
    required this.image,
    required this.u0,
    required this.v0,
    required this.spanU,
    required this.spanV,
  });

  /// The tile whose geographic footprint is drawn.
  final TileKey geoKey;

  /// The tile the [image] was decoded from (an ancestor when falling back).
  final TileKey sourceKey;

  final TileImage image;

  /// Texture origin (image pixels).
  final double u0;

  /// Texture origin (image pixels).
  final double v0;

  /// Texture extent (image pixels).
  final double spanU;

  /// Texture extent (image pixels).
  final double spanV;

  /// The source rect inside the image.
  ui.Rect get sourceRect => ui.Rect.fromLTWH(u0, v0, spanU, spanV);
}

/// A polar-cap drawing instruction (mercator only).
///
/// A cap instruction covers a **longitude interval**, not a single column.
/// That makes the two regimes the same shape:
///
/// * one column wide (`spanLng == grid.tileWidthDeg`) — a crisp wedge
///   textured with that column's own tile;
/// * up to `360°` — a smeared strip textured with a single image, used when
///   the camera sits inside the cap.
class CapDraw {
  const CapDraw({
    required this.zoom,
    required this.north,
    required this.startLng,
    required this.spanLng,
    required this.sourceKey,
    required this.image,
    required this.u0,
    required this.spanU,
    required this.v0,
    required this.vSpan,
  });

  /// The data-zoom level the cap belongs to.
  final int zoom;

  /// Northern or southern cap.
  final bool north;

  /// West edge of the interval (degrees, unwrapped).
  final double startLng;

  /// Width of the interval (degrees).
  final double spanLng;

  /// The tile the [image] was decoded from (for eviction protection).
  final TileKey sourceKey;

  final TileImage image;

  /// Texture region (image pixels).
  final double u0;

  /// Texture extent (image pixels).
  final double spanU;

  /// Texture origin (image pixels).
  final double v0;

  /// Texture extent (image pixels).
  final double vSpan;
}

/// The tile engine: selection, requests, cache, fallback.
class TileEngine extends ChangeNotifier {
  TileEngine({required this.source})
      : _policy = TileCachePolicy(
          maxConcurrentRequests: source.maxConcurrentRequests,
        );

  final GlobeRasterSource source;

  final TileCachePolicy<String> _policy;
  final Map<String, TileImage> _images = {};
  final Set<String> _pending = {};
  final Set<String> _requested = {};
  final TileScheduler _scheduler = TileScheduler();

  bool _disposed = false;

  /// Draw commands of the previous frame — drawn underneath the current frame
  /// so a zoom transition never flashes black.
  List<TileDraw> _previousDraws = const [];

  /// Failure / retry bookkeeping (exposed for the diagnostics HUD).
  TileCachePolicy<String> get policy => _policy;

  /// Scheduler (exposed so the host can flag camera gestures).
  TileScheduler get scheduler => _scheduler;

  int get imageCount => _images.length;
  int get pendingCount => _pending.length;
  int get inFlight => _policy.inFlight;
  int get queuedCount => _scheduler.pendingCount;
  int get requestedCount => _requested.length;
  int get previousDrawCount => _previousDraws.length;

  static String keyOf(TileKey key) => '${key.z}/${key.x}/${key.y}';

  /// The decoded image of a tile, or `null`.
  TileImage? imageOf(TileKey key) => _images[keyOf(key)];

  /// Whether a tile was ever requested (MapLibre `wasRequested`).
  bool wasRequested(TileKey key) => _requested.contains(keyOf(key));

  /// Whether the image behind a draw command is still cached.
  bool isLive(TileDraw draw) => _images[keyOf(draw.sourceKey)] == draw.image;

  // --- requesting ---------------------------------------------------------------

  /// How long a queued (not yet dispatched) request may wait before it is
  /// reclaimed, so a starved slot can never pin a tile in the queue forever.
  static const int _queueTimeoutMs = 5000;

  /// Request a tile (idempotent; failures are graded, never blacklisted).
  ///
  /// The tile is **enqueued** on the [TileScheduler] priority queue and a pump
  /// dispatches as many as the concurrency gate allows. A tile that finds every
  /// slot busy is no longer silently dropped (and re-requested next frame) — it
  /// waits its turn and is dispatched the moment a slot frees.
  void request(TileKey key) {
    if (_disposed) return;
    final k = keyOf(key);
    if (_pending.contains(k) ||
        _images.containsKey(k) ||
        _scheduler.isQueued(key)) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    // A failed tile is retried only after its TTL / backoff window.
    final retryAfter = _policy.retryAfter(k);
    if (retryAfter != null && now < retryAfter) return;

    _scheduler.enqueue(key, now);
    _pump();
  }

  /// Dispatch queued tiles while the concurrency gate allows.
  void _pump() {
    while (!_disposed && _policy.tryAcquireSlot()) {
      final key = _scheduler.takeNext();
      if (key == null) {
        _policy.releaseSlot();
        break;
      }
      _dispatch(key);
    }
  }

  /// Start one fetch. The caller already holds a concurrency slot.
  void _dispatch(TileKey key) {
    final k = keyOf(key);
    _pending.add(k);
    _requested.add(k);

    () async {
      try {
        final result = await source.fetch(key.z, key.x, key.y);
        if (_disposed) return;
        if (result.isOk) {
          await _decode(k, result.bytes!);
        } else {
          // A 404 is *not* a blacklist: MapLibre keeps the tile in the ideal
          // set and keeps falling back to parents / children.
          _policy.markFailure(
            k,
            result.failure ?? TileFailureKind.network,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
        }
      } catch (e) {
        _policy.markFailure(
          k,
          TileFailureKind.network,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
      } finally {
        _pending.remove(k);
        _policy.releaseSlot();
        // A slot just freed — dispatch the next queued tile.
        if (!_disposed) _pump();
      }
    }();
  }

  Future<void> _decode(String key, Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      final image = frame.image;
      final shader = ui.ImageShader(
        image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        _identity(),
        filterQuality: ui.FilterQuality.low,
      );
      _images[key] = TileImage(
        image,
        shader,
        loadedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _policy.put(key, image.width * image.height * 4);
      _policy.clearFailure(key);
      for (final evicted in _policy.trim()) {
        _images.remove(evicted)?.dispose();
      }
      notifyListeners();
    } catch (e) {
      _policy.markFailure(
        key,
        TileFailureKind.decode,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  // --- fallback resolution ------------------------------------------------------

  /// Resolve one ideal tile: exact → descendants → ancestors.
  ///
  /// The **ideal** tile is always requested (MapLibre `_updateRetainedTiles`
  /// → `_addTile(idealID)`), *even when a fallback is already drawable*. This
  /// is not an optimisation detail: requesting only when nothing at all is
  /// cached means that the moment a coarse tile is in the cache — which is
  /// true after **every** zoom-in — the finer tile is never fetched and the
  /// view stays pinned to the coarse level forever.
  ///
  /// The **ancestor chain** is different: it escalates one level per round and
  /// only after the level below has actually failed (MapLibre
  /// `parentWasRequested`). Requesting the whole pyramid at once is what
  /// produced request storms (and the black holes that followed).
  TileResolution resolve(TileKey key, int dataZoom) {
    // Request planning (what to fetch) is separate from resolution (what to
    // draw). The ideal tile is always requested; the ancestor chain only
    // escalates through levels that already failed. Both halves live in
    // [planTileRequest] so they are testable.
    final plan = planTileRequest(
      ideal: key,
      sourceMinZoom: source.minZoom,
      isLoaded: (k) => _images.containsKey(keyOf(k)),
      failureOf: (k) => _policy.failureKind(keyOf(k)),
      // While zooming, fetch the ideal tile but do not spawn parent requests.
      suspendAncestors: isZooming,
    );
    final ideal = plan.ideal;
    if (ideal != null) request(ideal);
    for (final ancestor in plan.ancestors) {
      request(ancestor);
    }

    // What to draw: exact → complete children → nearest ancestor → none. The
    // whole decision lives in [planTileResolution] (pure, unit-tested).
    final decision = planTileResolution(
      ideal: key,
      sourceMinZoom: source.minZoom,
      sourceMaxZoom: source.maxZoom,
      scheme: source.scheme,
      isLoaded: (k) => _images.containsKey(keyOf(k)),
    );
    switch (decision.kind) {
      case TileFallbackKind.exact:
        _policy.touch(keyOf(key));
        return TileResolution.exact(_images[keyOf(key)]!);
      case TileFallbackKind.descendants:
        final keys = decision.children;
        final images = [for (final k in keys) _images[keyOf(k)]!];
        return TileResolution.descendants(keys, images);
      case TileFallbackKind.ancestor:
        final ancestor = decision.ancestor!;
        _policy.touch(keyOf(ancestor));
        return TileResolution.ancestor(_images[keyOf(ancestor)]!, decision.dz);
      case TileFallbackKind.none:
        return const TileResolution.descendants([], []);
    }
  }

  // --- drawing commands ---------------------------------------------------------

  /// The drawing commands for one ideal tile.
  ///
  /// * exact hit → one command (whole texture);
  /// * loaded descendants → one command per child (they tile the footprint);
  /// * loaded ancestor → one command: the *fine* footprint with the
  ///   ancestor's sub-rectangle as texture region.
  ///
  /// An empty list means "nothing available yet" — the caller keeps the
  /// previous frame underneath so the screen never flashes black.
  List<TileDraw> drawsFor(TileKey key, int dataZoom) {
    final resolution = resolve(key, dataZoom);
    if (resolution.image != null) {
      final image = resolution.image!;
      return [
        TileDraw(
          geoKey: key,
          sourceKey: key,
          image: image,
          u0: 0,
          v0: 0,
          spanU: image.image.width.toDouble(),
          spanV: image.image.height.toDouble(),
        ),
      ];
    }
    if (resolution.descendants.isNotEmpty) {
      final out = <TileDraw>[];
      for (var i = 0; i < resolution.descendants.length; i++) {
        final image = resolution.descendantImages[i];
        out.add(TileDraw(
          geoKey: resolution.descendants[i],
          sourceKey: resolution.descendants[i],
          image: image,
          u0: 0,
          v0: 0,
          spanU: image.image.width.toDouble(),
          spanV: image.image.height.toDouble(),
        ));
      }
      return out;
    }
    if (resolution.ancestor != null) {
      // Geometry = the fine footprint, texture = the ancestor's sub-rect.
      final image = resolution.ancestor!;
      final dz = resolution.ancestorDz;
      final ancestorKey = TileKey(dataZoom - dz, key.x >> dz, key.y >> dz);
      final rect = parentUvRect(
        childX: key.x,
        childY: key.y,
        dz: dz,
        parentWidth: image.image.width.toDouble(),
        parentHeight: image.image.height.toDouble(),
      );
      return [
        TileDraw(
          geoKey: key,
          sourceKey: ancestorKey,
          image: image,
          u0: rect.u0,
          v0: rect.v0,
          spanU: rect.spanU,
          spanV: rect.spanV,
        ),
      ];
    }
    return const [];
  }

  /// The polar caps that should be drawn for the current camera.
  ///
  /// Only mercator has a blind spot (|lat| > 85.05°); the cap stretches the
  /// edge pixel row of the first / last tile row onto the pole.
  ///
  /// Two regimes, chosen by [PolarCapBuilder.columnCountFor]:
  ///
  /// * **wedge** — the span is a handful of columns wide: each column is drawn
  ///   as its own strip, textured with its own tile. Crisp, and the request
  ///   count is proportional to the visible cap.
  /// * **smeared** — the span needs more columns than
  ///   [GeoEngineTuning.maxPolarCapColumns] allows (the camera is inside the
  ///   cap, so the arc wraps the pole): **one** strip, one image. Drawing a
  ///   wedge per column there meant 4096 meshes per frame, each with a
  ///   different picture, i.e. a sunburst across the whole viewport.
  List<CapDraw> capDraws({
    required CameraState camera,
    required int dataZoom,
  }) {
    if (source.scheme != TileSchemeKind.webMercator) return const [];
    final grid = TileGrid.of(source.scheme, dataZoom);
    final out = <CapDraw>[];
    for (final north in [true, false]) {
      if (!PolarCapBuilder.isVisible(camera: camera, north: north)) continue;
      final span = PolarCapBuilder.visibleSpan(
        camera: camera,
        north: north,
      );
      if (span == null) continue;
      final row = north ? 0 : grid.rows - 1;

      if (PolarCapBuilder.columnCountFor(grid, span) >
          GeoEngineTuning.maxPolarCapColumns) {
        // Smeared regime: one strip, one image.
        final tile = _capTile(grid, camera.center.longitude, row, dataZoom);
        if (tile == null) continue;
        final edge = PolarCapBuilder.edgeBand(
          north: north,
          imageHeightPx: tile.image.image.height.toDouble(),
          rowOrder: TileRowOrder.xyzTopDown,
        );
        out.add(CapDraw(
          zoom: dataZoom,
          north: north,
          startLng: span.startLng,
          spanLng: span.spanLng,
          sourceKey: tile.key,
          image: tile.image,
          u0: tile.u0,
          spanU: tile.spanU,
          v0: edge.v0,
          vSpan: edge.height,
        ));
        continue;
      }

      // Wedge regime: one strip per visible column, each with its own texture.
      for (final column in PolarCapBuilder.columnsForSpan(
        grid: grid,
        span: span,
        nearLng: camera.center.longitude,
      )) {
        final key = TileKey(dataZoom, column, row);
        // The cap is a *decoration* of the edge row: when the tile is missing
        // the engine still resolves the ancestor chain so a coarser tile can
        // stand in — and the ideal tile is requested either way.
        final resolution = resolve(key, dataZoom);
        final TileImage? exact = resolution.image;
        final TileImage? ancestor = resolution.ancestor;
        if (exact == null && ancestor == null) continue;

        final tile = exact ?? ancestor!;
        final iw = tile.image.width.toDouble();
        final ih = tile.image.height.toDouble();

        double u0 = 0;
        double spanU = iw;
        var sourceKey = key;
        if (exact == null) {
          // The cap is stretched from an ancestor: take the ancestor's
          // sub-rectangle for this column.
          final dz = resolution.ancestorDz;
          final rect = parentUvRect(
            childX: column,
            childY: row,
            dz: dz,
            parentWidth: iw,
            parentHeight: ih,
          );
          u0 = rect.u0;
          spanU = rect.spanU;
          sourceKey = TileKey(dataZoom - dz, column >> dz, row >> dz);
        }

        // The decoded image is always north-up (the TMS / MBTiles flip applies
        // to the *row address*, not to the pixels), so the northern cap uses
        // the top row of the image.
        final band = PolarCapBuilder.edgeBand(
          north: north,
          imageHeightPx: ih,
          rowOrder: TileRowOrder.xyzTopDown,
        );
        out.add(CapDraw(
          zoom: dataZoom,
          north: north,
          startLng: grid.west(column),
          spanLng: grid.tileWidthDeg,
          sourceKey: sourceKey,
          image: tile,
          u0: u0,
          spanU: spanU,
          v0: band.v0,
          vSpan: band.height,
        ));
      }
    }
    return out;
  }

  /// The tile used to texture a smeared cap strip.
  ///
  /// The camera meridian is the interesting one, so it is resolved properly
  /// (which also issues its request). Neighbours are only *read* from the
  /// cache — a placeholder must never trigger a request of its own.
  ({TileKey key, TileImage image, double u0, double spanU})? _capTile(
    TileGrid grid,
    double nearLng,
    int row,
    int dataZoom,
  ) {
    final anchorColumn = grid.wrapX(grid.xOf(nearLng));
    final anchorKey = TileKey(dataZoom, anchorColumn, row);
    final resolution = resolve(anchorKey, dataZoom);

    final exact = resolution.image;
    if (exact != null) {
      return (
        key: anchorKey,
        image: exact,
        u0: 0,
        spanU: exact.image.width.toDouble(),
      );
    }
    final ancestor = resolution.ancestor;
    if (ancestor != null) {
      final iw = ancestor.image.width.toDouble();
      final dz = resolution.ancestorDz;
      final rect = parentUvRect(
        childX: anchorColumn,
        childY: row,
        dz: dz,
        parentWidth: iw,
        parentHeight: ancestor.image.height.toDouble(),
      );
      return (
        key: TileKey(dataZoom - dz, anchorColumn >> dz, row >> dz),
        image: ancestor,
        u0: rect.u0,
        spanU: rect.spanU,
      );
    }

    for (final delta in const [1, -1, 2, -2, 4, -4, 8, -8, 16, -16, 32, -32]) {
      final key = TileKey(dataZoom, grid.wrapX(anchorColumn + delta), row);
      final image = _images[keyOf(key)];
      if (image == null) continue;
      return (
        key: key,
        image: image,
        u0: 0,
        spanU: image.image.width.toDouble(),
      );
    }
    return null;
  }

  // --- fade-in (MapLibre `fadeDuration`) ----------------------------------------

  /// Self-fade window for a freshly decoded raster tile (ms). Mirrors
  /// MapLibre's `fadeDuration` (default 300).
  static const int fadeDurationMs = 300;

  /// Linear self-fade opacity (0→1) for [image] at wall-clock [now].
  ///
  /// A `null` [TileImage.loadedAt] (e.g. a pre-cached image) is always 1. This
  /// is the raster-only "load fade" of MapLibre — a tile is blended in from
  /// transparent to opaque instead of popping in (see `draw_raster.ts`
  /// `getSelfFadeValues`). The math lives in `geo_map_core` so it is
  /// unit-testable without `dart:ui`.
  double fadeOpacity(TileImage image, int now) =>
      selfFadeOpacity(image.loadedAt, now, fadeDurationMs);

  /// Whether any cached tile is still inside its fade window at [now].
  ///
  /// Drives the per-frame repaint loop: while this is true the layer keeps
  /// redrawing so the fade actually animates (MapLibre keeps `triggerRepaint`
  /// alive while `hasRasterTransition`).
  bool hasFadingTiles([int? now]) {
    final t = now ?? DateTime.now().millisecondsSinceEpoch;
    for (final img in _images.values) {
      final loadedAt = img.loadedAt;
      if (loadedAt != null && t - loadedAt < fadeDurationMs) return true;
    }
    return false;
  }

  // --- cross-fade (MapLibre zoom transition) ------------------------------------

  /// Duration of a zoom-level cross-fade (ms). Mirrors MapLibre's
  /// `fadeDuration`-based zoom transition between a parent and its child.
  static const int crossFadeDurationMs = 300;

  /// The data level shown on the previous frame. Drives the cross-fade.
  int? _prevDataZoom;

  /// The level we are fading *from* during a zoom step (null = not fading).
  int? _crossFadeFrom;

  /// Wall-clock time (ms) the current zoom transition began.
  int _crossFadeStartMs = 0;

  /// Notifies the host when a new zoom transition starts, so it can begin the
  /// per-frame repaint loop even while the camera is otherwise stationary.
  VoidCallback? onCrossFadeStart;

  /// Record the data level of this frame. When it differs from the previous
  /// frame a cross-fade begins; returns true on the first frame of a transition.
  bool noteDataZoom(int dataZoom, int now) {
    _nowMs = now;
    final prev = _prevDataZoom;
    _prevDataZoom = dataZoom;
    if (prev != null && prev != dataZoom) {
      _crossFadeFrom = prev;
      _crossFadeStartMs = now;
      // Queued tiles belong to the old level; drop them so the new level's
      // requests (enqueued later this frame) are not stuck behind stale ones.
      _scheduler.clearQueue();
      onCrossFadeStart?.call();
      return true;
    }
    return false;
  }

  /// The level currently being faded *from*, or null when not cross-fading.
  int? get crossFadeFromZoom => _crossFadeFrom;

  /// Cross-fade progress (0→1) at [now]; 1 means the transition is complete.
  double crossFadeProgressAt(int now) {
    if (_crossFadeFrom == null) return 1.0;
    return crossFadeProgress(_crossFadeStartMs, now, crossFadeDurationMs);
  }

  /// Whether a zoom cross-fade is still animating at [now].
  bool isCrossFading(int now) =>
      _crossFadeFrom != null &&
      isWithinFade(_crossFadeStartMs, now, crossFadeDurationMs);

  // --- zoom activity (parent-request suspension) --------------------------------

  /// How long after the last zoom change the camera is still treated as
  /// "zooming" (ms). Long enough to cover a continuous pinch, short enough to
  /// resume parent requests promptly after the finger lifts.
  static const int zoomSettleMs = 250;

  int _nowMs = 0;
  double? _lastRenderZoom;
  int _zoomingUntilMs = 0;

  /// Record the render zoom of this frame. Any change of zoom marks the camera
  /// as zooming until [zoomSettleMs] after the last change.
  void noteRenderZoom(double zoom, int now) {
    _nowMs = now;
    final last = _lastRenderZoom;
    _lastRenderZoom = zoom;
    if (last != null && zoom != last) {
      _zoomingUntilMs = now + zoomSettleMs;
    }
  }

  /// Whether the camera is currently zooming (within [zoomSettleMs] of the last
  /// zoom change). Drives [planTileRequest]'s `suspendAncestors`.
  bool get isZooming => _nowMs < _zoomingUntilMs;

  // --- frame bookkeeping --------------------------------------------------------

  /// Start a frame: the *previous* render set stays protected, the current one
  /// is rebuilt. Also reclaims stuck queue entries and pumps the queue once.
  void beginFrame() {
    _policy.beginFrame();
    _scheduler.reclaim(DateTime.now().millisecondsSinceEpoch, _queueTimeoutMs);
    _pump();
  }

  /// Mark a tile as drawn this frame (protects it from eviction).
  void markRendered(TileKey key) => _policy.addRenderTile(keyOf(key));

  /// The draw commands of the previous frame (still cached ones only).
  List<TileDraw> get previousDraws =>
      _previousDraws.where(isLive).toList(growable: false);

  /// Promote the current frame's draws to the "previous" underlay.
  void commitFrame(List<TileDraw> draws) {
    _policy.commitFrame();
    // An empty frame must not wipe the underlay (that would flash black).
    if (draws.isEmpty) return;
    _previousDraws = List.of(draws);
  }

  // --- lifecycle ----------------------------------------------------------------

  /// Note a camera interaction (used for the request debounce).
  void noteCameraChange({required bool interacting}) {
    _scheduler.noteCameraChange(
      DateTime.now().millisecondsSinceEpoch,
      interacting: interacting,
    );
  }

  /// Drop in-flight results of an older camera generation, and clear queued
  /// requests that belong to the old view.
  void invalidate() {
    _scheduler.invalidate();
    _scheduler.clearQueue();
  }

  static Float64List _identity() {
    final m = Float64List(16);
    m[0] = 1;
    m[5] = 1;
    m[10] = 1;
    m[15] = 1;
    return m;
  }

  @override
  void dispose() {
    _disposed = true;
    _scheduler.clearQueue();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
