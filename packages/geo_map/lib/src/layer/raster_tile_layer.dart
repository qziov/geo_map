/// Raster tile layer: the 2D/3D shared rendering pipeline.
///
/// Per frame:
///   1. previous render set → underlay (zoom-switch continuity)
///   2. current render set  → parent-tile fallback + per-tile mesh
///   3. polar caps          → mercator's ±85.05° blind spot
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:geo_map_core/geo_map_core.dart';

import '../camera/geo_map_controller.dart';
import '../source/tile_source.dart';

class _TileEntry {
  _TileEntry(this.image, this.shader);

  final ui.Image image;
  final ui.ImageShader shader;

  int get bytes => image.width * image.height * 4;

  void dispose() {
    shader.dispose();
    image.dispose();
  }
}

/// Owns the tile engine state (decode, cache, mesh cache). One per [GeoMap].
class GeoTileEngine {
  GeoTileEngine({required this.source});

  final GeoTileSource source;

  final TileMeshBuilder _mesh = TileMeshBuilder();
  final TileCachePolicy<String> _cache = TileCachePolicy();
  final Map<String, _TileEntry> _entries = {};
  final Set<String> _pending = {};
  final Set<String> _missing = {};
  final TileScheduler _scheduler = TileScheduler();

  List<TileKey> _previousKeys = const [];

  bool _disposed = false;

  /// Fired when a tile finished decoding and the layer should repaint.
  VoidCallback? onNeedsPaint;

  int get cachedTiles => _cache.length;
  int get pendingRequests => _pending.length;

  void dispose() {
    _disposed = true;
    for (final e in _entries.values) {
      e.dispose();
    }
    _entries.clear();
    source.dispose();
  }

  // --- frame ------------------------------------------------------------------

  void paintFrame(
    Canvas canvas,
    CameraState camera,
    GeoProjector projector,
    double opacity,
  ) {
    final zoom = _pickZoom(camera).round();
    final grid = TileGrid.of(source.scheme, zoom);
    final keys = TileSelector.visible(
      projector: projector,
      camera: camera,
      grid: grid,
    );

    _cache.beginFrame();

    canvas.save();
    final clip = projector.clipCircle(camera);
    if (clip != null) {
      canvas.clipPath(
        Path()
          ..addOval(Rect.fromCircle(
              center: Offset(clip.center.x, clip.center.y), radius: clip.radius)),
      );
    } else {
      canvas.clipRect(
          Rect.fromLTWH(0, 0, camera.size.width, camera.size.height));
    }

    final paint = Paint()..isAntiAlias = true;

    // ① Underlay: the previous zoom level's tiles, drawn with the current camera.
    for (final key in _previousKeys) {
      if (key.z == zoom) continue;
      final entry = _entries['$key'];
      if (entry == null) continue;
      final pGrid = TileGrid.of(source.scheme, key.z);
      final unit = _mesh.unitMesh(pGrid, key.x, key.y, _subdiv(camera, pGrid));
      final buffers = _mesh.project(unit, projector, camera);
      _draw(canvas, buffers, entry.shader, opacity);
    }

    // ② Current level with parent fallback.
    for (final key in keys) {
      _cache.addRenderTile('$key');
      final hit = _lookupWithFallback(key, zoom.round(), grid);
      if (hit == null) continue;
      final (entry, dz) = hit;

      final unit = _mesh.unitMesh(grid, key.x, key.y, _subdiv(camera, grid));
      final scale = 1 << dz;
      final buffers = _mesh.project(
        unit,
        projector,
        camera,
        uvOriginX: dz == 0
            ? 0
            : (key.x % scale) / scale * entry.image.width,
        uvOriginY: dz == 0 ? 0 : (key.y % scale) / scale * entry.image.height,
        uvSpan: entry.image.width / scale,
      );
      _draw(canvas, buffers, entry.shader, opacity);
    }

    // ③ Polar caps (mercator only).
    if (source.scheme == TileSchemeKind.webMercator) {
      _paintPolarCaps(
          canvas, camera, grid, keys, projector, projector.clipCircle(camera), paint, opacity);
    }

    canvas.restore();
    _cache.commitFrame();
    _previousKeys = keys;
  }

  // --- internals ---------------------------------------------------------------

  double _pickZoom(CameraState camera) {
    final cosLat = math
        .max(
            math.cos(rad(camera.clampedLatitude)).abs(),
            GeoEngineTuning.pickZoomCosFloor)
        .toDouble();
    final worldPx = camera.worldSize * cosLat;
    final z = math.log(worldPx / GeoEngineTuning.tileSize) / math.ln2;
    return z
        .clamp(source.minZoom.toDouble(), source.maxZoom.toDouble())
        .toDouble();
  }

  int _subdiv(CameraState camera, TileGrid grid) {
    final tileScreenPx = 2 * math.pi * camera.radiusPx / grid.cols;
    return (tileScreenPx / GeoEngineTuning.subdivPx)
        .ceil()
        .clamp(GeoEngineTuning.subdivMin, GeoEngineTuning.subdivMax);
  }

  /// Exact tile → parent fallback. Returns `(entry, dz)` or null.
  (_TileEntry, int)? _lookupWithFallback(TileKey key, int zoom, TileGrid grid) {
    final k = '$key';
    final exact = _entries[k];
    if (exact != null) {
      _cache.touch(k);
      return (exact, 0);
    }
    if (_missing.contains(k) || _pending.contains(k)) return null;
    _request(key);

    for (var dz = 1; zoom - dz >= source.minZoom; dz++) {
      final scale = 1 << dz;
      final ancestor = TileKey(zoom - dz, key.x ~/ scale, key.y ~/ scale);
      final entry = _entries['$ancestor'];
      if (entry != null) {
        _cache.touch('$ancestor');
        return (entry, dz);
      }
      // Only the direct parent is fetched (silently): bounded request count.
      if (dz == 1 &&
          !_missing.contains('$ancestor') &&
          !_pending.contains('$ancestor')) {
        _request(ancestor);
      }
    }
    return null;
  }

  void _request(TileKey key) {
    final k = '$key';
    if (_disposed || _pending.contains(k) || _missing.contains(k)) return;
    _pending.add(k);
    final gen = _scheduler.generation;
    () async {
      final bytes = await source.fetch(key.z, key.x, key.y);
      if (_disposed) return;
      if (bytes == null || bytes.isEmpty) {
        _missing.add(k);
        return;
      }
      if (_scheduler.isStale(gen)) return;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      final matrix = Float64List(16)
        ..[0] = 1
        ..[5] = 1
        ..[10] = 1
        ..[15] = 1;
      final shader = ui.ImageShader(
        frame.image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        matrix,
        filterQuality: ui.FilterQuality.low,
      );
      _entries[k] = _TileEntry(frame.image, shader);
      _cache.put(k, frame.image.width * frame.image.height * 4);
      for (final evicted in _cache.trim()) {
        _entries.remove(evicted)?.dispose();
      }
      onNeedsPaint?.call();
    }().whenComplete(() => _pending.remove(k));
  }

  void _draw(
      Canvas canvas, MeshBuffers buffers, ui.ImageShader shader, double opacity) {
    if (buffers.indices.isEmpty) return;
    final paint = Paint()
      ..isAntiAlias = true
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        buffers.positions,
        textureCoordinates: buffers.uvs,
        indices: buffers.indices,
      ),
      BlendMode.srcOver,
      paint,
    );
  }

  void _paintPolarCaps(
    Canvas canvas,
    CameraState camera,
    TileGrid grid,
    List<TileKey> keys,
    GeoProjector projector,
    CircleClip? clip,
    Paint paint,
    double opacity,
  ) {
    if (keys.isEmpty) return;
    final zoom = keys.first.z;
    final columns = <int>{for (final k in keys) k.x};
    final cx = camera.size.width / 2;
    final cy = camera.size.height / 2;

    for (final north in [true, false]) {
      if (!PolarCapBuilder.isVisible(camera: camera, north: north)) continue;
      final row = north ? 0 : grid.rows - 1;

      for (final x in columns) {
        final entry = _entries['${TileKey(zoom, x, row)}'];
        if (entry == null) continue;

        final cap = PolarCapBuilder.build(grid: grid, x: x, north: north);
        final n = (math.sqrt(cap.vertexCount) - 1).round();
        final iw = entry.image.width.toDouble();
        final band = PolarCapBuilder.edgeBand(
            north: north, imageHeightPx: entry.image.height.toDouble());

        final count = cap.vertexCount;
        final positions = Float32List(count * 2);
        final uvs = Float32List(count * 2);
        final depths = Float32List(count);

        for (var j = 0; j <= n; j++) {
          for (var i = 0; i <= n; i++) {
            final idx = j * (n + 1) + i;
            final unit =
                Vec3(cap.unit[idx * 3], cap.unit[idx * 3 + 1], cap.unit[idx * 3 + 2]);
            final depth = projector.depthOf(unit.toLatLng(), camera);
            depths[idx] = depth;
            final p = depth > GeoEngineTuning.epsDepth
                ? projector.projectUnit(unit, camera)
                : null;
            if (p != null) {
              positions[idx * 2] = p.x;
              positions[idx * 2 + 1] = p.y;
            } else {
              final len = math.sqrt(unit.x * unit.x + unit.y * unit.y);
              final rr = clip?.radius ?? 0;
              positions[idx * 2] = len < 1e-9 ? cx : cx + unit.x / len * rr;
              positions[idx * 2 + 1] =
                  len < 1e-9 ? cy : cy - unit.y / len * rr;
            }
            uvs[idx * 2] = i / n * iw;
            uvs[idx * 2 + 1] = band.v0 + (j / n) * band.height;
          }
        }

        final indices = TileMeshBuilder.cullIndices(cap.indices, depths);
        if (indices.isEmpty) continue;
        final capPaint = Paint()
          ..isAntiAlias = true
          ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
        canvas.drawVertices(
          ui.Vertices.raw(
            ui.VertexMode.triangles,
            positions,
            textureCoordinates: uvs,
            indices: indices,
          ),
          BlendMode.srcOver,
          capPaint,
        );
      }
    }
  }
}

/// Raster tile layer widget. Add it as the first child of [GeoMap].
class RasterTileLayer extends StatelessWidget {
  const RasterTileLayer({
    required this.controller,
    required this.engine,
    this.opacity = 1.0,
    super.key,
  });

  final GeoMapController controller;
  final GeoTileEngine engine;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RasterPainter(
        controller: controller,
        engine: engine,
        opacity: opacity,
      ),
      size: Size.infinite,
    );
  }
}

class _RasterPainter extends CustomPainter {
  _RasterPainter({
    required this.controller,
    required this.engine,
    required this.opacity,
  }) : super(repaint: controller);

  final GeoMapController controller;
  final GeoTileEngine engine;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    engine.paintFrame(canvas, controller.value, controller.projector, opacity);
  }

  @override
  bool shouldRepaint(covariant _RasterPainter oldDelegate) => false;
}
