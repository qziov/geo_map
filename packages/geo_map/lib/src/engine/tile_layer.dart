/// The one raster layer — 2D and 3D share the same code path.
///
/// The layer is a thin shell around three collaborators:
///
/// * [TileEngine] — projection-independent: requests, decode cache, failure
///   grading, fallback resolution (exact → descendants → ancestors).
/// * [GeoProjector] — where a coordinate lands on screen (mercator plane or
///   orthographic globe).
/// * [TileGeometry] — how the pixels are placed (affine rect or spherical
///   mesh).
///
/// Because the *engine* and the *commands* are shared, a bug can no longer be
/// fixed in one mode and stay broken in the other: 2D and 3D consume the very
/// same [TileDraw] list.
///
/// ### Overzoom (MapLibre `OverscaledTileID`)
///
/// The camera asks for a level, the source can only deliver up to
/// `source.maxZoom`. The two are kept apart:
///
/// * **data level** (`dataZoom`) — the level the tiles are *fetched* at and the
///   level whose **geographic footprint** is drawn;
/// * **render level** — the camera's zoom, which sets the *screen size*.
///
/// The magnification is therefore `2^(renderZoom - dataZoom)` — exactly what
/// MapLibre's `calculateTileMatrix` produces (`scale = worldSize /
/// zoomScale(canonical.z)`), with the texture stretched over the enlarged
/// footprint. The texture is **not** cut into sub-cells: MapLibre's
/// `draw_raster.ts` builds the mesh from `coord.canonical` and samples the
/// whole texture over it.
library;

import 'package:flutter/widgets.dart';
import 'package:geo_map_core/geo_map_core.dart';

import '../diagnostics/geo_diagnostics.dart';
import '../globe/tile_source.dart';
import '../vendor/flutter_map_camera/flutter_map_camera.dart';
import 'tile_engine.dart';
import 'tile_geometry.dart';

/// Which projection the layer renders with.
enum TileLayerMode {
  /// Web Mercator plane.
  mercator,

  /// Orthographic globe.
  globe,
}

/// Raster tile layer for both 2D and 3D.
///
/// ### Engine ownership
///
/// The layer accepts an optional [engine]. When one is injected, **it belongs
/// to the host** and the layer must never dispose it: the whole point of the
/// shared engine is that the 2D and 3D layers trade places without dropping
/// the cache, and the layer that is being unmounted has no idea whether a
/// sibling is about to mount with the same engine.
///
/// Getting this backwards is not subtle — disposing the injected engine kills
/// every in-flight decode (`_decode` drops the frame on `_disposed`) and the
/// very next build asserts `A TileEngine was used after being disposed`, which
/// surfaces as "the globe basemap never loads".
class TileLayer extends StatefulWidget {
  const TileLayer({
    required this.source,
    required this.mode,
    this.engine,
    super.key,
  });

  final GlobeRasterSource source;

  /// The shared engine. When `null` the layer creates one and owns it.
  final TileEngine? engine;

  final TileLayerMode mode;

  @override
  State<TileLayer> createState() => _TileLayerState();
}

class _TileLayerState extends State<TileLayer> {
  /// The unit-mesh cache is shared between frames: the unit sphere does not
  /// depend on the projection, so panning does not rebuild geometry.
  final TileMeshBuilder _meshBuilder = TileMeshBuilder();

  /// The engine **this layer** created. Never the injected one.
  TileEngine? _owned;

  TileEngine get _engine => widget.engine ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.engine == null) {
      _owned = TileEngine(source: widget.source);
    }
  }

  @override
  void didUpdateWidget(TileLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.engine != null) {
      // The host took over — retire ours, do not touch theirs.
      _retireOwned();
      return;
    }
    if (oldWidget.source != widget.source ||
        oldWidget.engine != widget.engine) {
      // Either the data changed, or the host withdrew its engine and we have
      // to start owning one again.
      _retireOwned();
      _owned = TileEngine(source: widget.source);
    }
  }

  /// Drop the engine we own after the frame: the current `ListenableBuilder`
  /// is still attached to it while the tree rebuilds.
  void _retireOwned() {
    final old = _owned;
    if (old == null) return;
    _owned = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final engine = _engine;
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: engine,
        builder: (context, _) => CustomPaint(
          size: Size(camera.size.x, camera.size.y),
          painter: _TilePainter(
            engine: engine,
            mode: widget.mode,
            camera: camera,
            meshBuilder: _meshBuilder,
          ),
        ),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  _TilePainter({
    required this.engine,
    required this.mode,
    required this.camera,
    required this.meshBuilder,
  });

  final TileEngine engine;
  final TileLayerMode mode;
  final MapCamera camera;
  final TileMeshBuilder meshBuilder;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final source = engine.source;
    final scheme = source.scheme;

    // ── Camera ──────────────────────────────────────────────────────────────
    // The vendored `MapCamera` speaks in screen space for the globe and in
    // world space for the plane; the core speaks one language: a centre, a
    // zoom and a viewport. Both delegates use `worldSize = 256 · 2^zoom`
    // (the globe's circumference is exactly that), so the zoom maps over
    // unchanged and the magnification factor is identical in both modes.
    final state = CameraState(
      center: camera.center,
      zoom: camera.zoom,
      size: ViewportSize(size.width, size.height),
    );

    // ── Zoom selection (MapLibre `coveringZoomLevel`) ───────────────────────
    // No latitude factor: the globe must not shrink when the camera moves
    // towards the poles, and MapLibre's globe projection uses the same rule.
    final desiredZ = TileSelector.coveringZoomLevel(state);
    // The data level is clamped to what the source can deliver; the render
    // level is not — that gap *is* the overzoom magnification.
    final dataZoom = desiredZ.clamp(source.minZoom, source.maxZoom);

    final projector = mode == TileLayerMode.globe
        ? const OrthographicProjector()
        : const MercatorProjector();
    final geometry = mode == TileLayerMode.globe
        ? SphericalGeometry(
            projector: projector,
            scheme: scheme,
            meshBuilder: meshBuilder,
          )
        : AffineGeometry(scheme: scheme);

    // ── Selection ───────────────────────────────────────────────────────────
    // Window based (`TileSelector.visible`), then per-tile verification
    // against the actual projection — the same discipline as MapLibre's
    // `coveringTiles` + `isTileVisible`.
    final selection = TileSelector.select(
      projector: projector,
      camera: state,
      desiredZ: desiredZ,
      sourceMinZoom: source.minZoom,
      sourceMaxZoom: source.maxZoom,
      scheme: scheme,
    );

    // ── Draw ────────────────────────────────────────────────────────────────
    canvas.save();
    if (mode == TileLayerMode.globe) {
      // The globe is a disc: everything outside the silhouette is off-map.
      final clip = projector.clipCircle(state);
      if (clip != null) {
        canvas.clipPath(
          Path()
            ..addOval(
              Rect.fromCircle(
                center: Offset(clip.center.x, clip.center.y),
                radius: clip.radius,
              ),
            ),
        );
      }
    } else {
      canvas.clipRect(Offset.zero & size);
    }

    engine.beginFrame();

    var drawn = 0;
    var missed = 0;
    final missDetails = <String>[];
    final frameDraws = <TileDraw>[];

    // The previous frame is painted underneath, so a zoom transition never
    // flashes black. Only tiles of the *current* data level are reused: a
    // different level would carry a different magnification.
    for (final draw in engine.previousDraws) {
      if (draw.geoKey.z != dataZoom) continue;
      geometry.drawTile(canvas, draw, camera: state, opacity: 1);
    }

    for (final key in selection.tiles) {
      final draws = engine.drawsFor(key, dataZoom);
      if (draws.isEmpty) {
        missed++;
        if (missDetails.length < 5) {
          missDetails.add('${key.z}/${key.x}/${key.y}');
        }
        continue;
      }
      for (final draw in draws) {
        geometry.drawTile(canvas, draw, camera: state, opacity: 1);
        engine.markRendered(draw.sourceKey);
        frameDraws.add(draw);
        drawn++;
      }
    }

    // ── Polar caps ──────────────────────────────────────────────────────────
    // Web Mercator stops at ±85.05°; the cap fills the remaining wedge up to
    // the pole. Only the globe has a pole, and only mercator has a blind spot.
    if (mode == TileLayerMode.globe) {
      for (final cap in engine.capDraws(
        camera: state,
        dataZoom: dataZoom,
      )) {
        geometry.drawCap(canvas, cap, camera: state, opacity: 1);
        // The cap samples a real tile: protect it from eviction like any other
        // tile that was on screen this frame.
        engine.markRendered(cap.sourceKey);
      }
    }

    canvas.restore();

    // ── Frame bookkeeping ───────────────────────────────────────────────────
    engine.commitFrame(frameDraws);

    GeoDiagnostics.frame(
      '[geo_map:frame] mode=${mode.name} dataZ=$dataZoom '
      'renderZ=$desiredZ visible=${selection.tiles.length} drawn=$drawn '
      'missed=$missed img=${engine.imageCount} pend=${engine.pendingCount} '
      'inflight=${engine.inFlight} '
      'c=${camera.center.latitude.toStringAsFixed(1)},'
      '${camera.center.longitude.toStringAsFixed(1)} '
      'z${camera.zoom.toStringAsFixed(2)}',
    );
    if (missDetails.isNotEmpty) {
      GeoDiagnostics.missDetail('[geo_map:miss] ${missDetails.join(' ')}');
    }
  }

  @override
  bool shouldRepaint(covariant _TilePainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.engine != engine ||
      oldDelegate.mode != mode;
}
