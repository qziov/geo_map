/// Flat (Web Mercator) tile layer for 2D mode — same data semantics as the
/// globe layer: data-zoom clamp (over/under-zoom), parent-tile fallback with UV
/// sub-rects, previous-render-set underlay, missing blacklist.
///
/// Rendering is plain `drawImageRect` (no mesh subdivision needed in an affine
/// projection). Antimeridian: the world copy closest to the camera is drawn.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../vendor/flutter_map_camera/flutter_map_camera.dart';
import 'tile_source.dart';

class _FlatEntry {
  _FlatEntry(this.image, this.shader);

  final ui.Image image;
  final ui.ImageShader shader;

  void dispose() {
    shader.dispose();
    image.dispose();
  }
}

/// Decode cache with the same state machine as the globe engine
/// (pending dedup, 2-strike blacklist, previous-render-set underlay).
class _FlatCache {
  _FlatCache(this.source);

  final GlobeRasterSource source;
  final Map<String, _FlatEntry> entries = {};
  final Set<String> _pending = {};
  final Map<String, int> _failCounts = {};
  final List<(int, int, int)> previousSet = [];
  final ValueNotifier<int> revision = ValueNotifier(0);
  bool _disposed = false;

  static const int _maxEntries = 512;

  bool _isBlacklisted(String k) => (_failCounts[k] ?? 0) >= 2;

  void _markFail(String k) {
    final n = (_failCounts[k] ?? 0) + 1;
    _failCounts[k] = n;
    if (n == 2) {
      debugPrint('[geo_map:tile] blacklisted after 2 failures: $k');
    }
  }

  _FlatEntry? lookupRetained(int z, int x, int y) => entries['$z/$x/$y'];

  void addRenderTile(int z, int x, int y) => _frameSet.add((z, x, y));

  final List<(int, int, int)> _frameSet = [];

  void commitFrame() {
    if (_frameSet.isEmpty) return; // 空帧不覆盖垫底集（防持续黑）
    previousSet
      ..clear()
      ..addAll(_frameSet);
    _frameSet.clear();
  }

  void beginFrame() => _frameSet.clear();

  /// Exact → ancestor chain (dz>0 → UV sub-rect); missing tiles requested.
  (_FlatEntry, int)? lookupWithFallback(int zoom, int x, int y) {
    final k = '$zoom/$x/$y';
    final exact = entries[k];
    if (exact != null) return (exact, 0);
    if (_isBlacklisted(k) || _pending.contains(k)) return null;
    _request(zoom, x, y);

    for (var dz = 1; zoom - dz >= source.minZoom; dz++) {
      final scale = 1 << dz;
      final ax = x ~/ scale;
      final ay = y ~/ scale;
      final ak = '${zoom - dz}/$ax/$ay';
      final entry = entries[ak];
      if (entry != null) return (entry, dz);
      if (!_isBlacklisted(ak) && !_pending.contains(ak)) {
        _request(zoom - dz, ax, ay);
      }
    }
    return null;
  }

  void _request(int z, int x, int y) {
    final k = '$z/$x/$y';
    if (_disposed || _pending.contains(k) || _isBlacklisted(k)) return;
    _pending.add(k);
    () async {
      try {
        Uint8List? bytes;
        try {
          bytes = await source.fetch(z, x, y);
        } catch (e) {
          debugPrint('[geo_map:tile] fetch ERROR $k: $e');
        }
        if (_disposed) return;
        if (bytes == null || bytes.isEmpty) {
          _markFail(k);
          return;
        }
        try {
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
          entries[k] = _FlatEntry(
            frame.image,
            ui.ImageShader(
              frame.image,
              ui.TileMode.clamp,
              ui.TileMode.clamp,
              matrix,
              filterQuality: ui.FilterQuality.low,
            ),
          );
          _evict();
          revision.value++;
        } catch (e) {
          debugPrint('[geo_map:tile] decode ERROR $k: $e');
          _markFail(k);
        }
      } finally {
        _pending.remove(k);
      }
    }();
  }

  void _evict() {
    while (entries.length > _maxEntries) {
      final oldest = entries.keys.first;
      entries.remove(oldest)?.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    for (final e in entries.values) {
      e.dispose();
    }
    entries.clear();
  }
}

class FlatTileLayer extends StatefulWidget {
  const FlatTileLayer({required this.source, super.key});

  final GlobeRasterSource source;

  @override
  State<FlatTileLayer> createState() => _FlatTileLayerState();
}

class _FlatTileLayerState extends State<FlatTileLayer> {
  late _FlatCache _cache = _FlatCache(widget.source);

  @override
  void didUpdateWidget(FlatTileLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _cache.dispose();
      _cache = _FlatCache(widget.source);
    }
  }

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: _cache.revision,
        builder: (context, _) => CustomPaint(
          size: Size(camera.size.x, camera.size.y),
          painter: _FlatTilePainter(camera: camera, cache: _cache),
        ),
      ),
    );
  }
}

class _FlatTilePainter extends CustomPainter {
  _FlatTilePainter({required this.camera, required this.cache});

  final MapCamera camera;
  final _FlatCache cache;

  @override
  void paint(Canvas canvas, Size size) {
    final source = cache.source;
    // over/under-zoom：数据层级 = round(camera.zoom) 钳到真实有瓦层级，
    // 绘制尺寸按 camera.zoom 缩放（即 maplibre 的 overscale 语义）。
    final zoom = camera.zoom.round().clamp(source.minZoom, source.maxZoom);
    final cols = 1 << zoom;
    final tileScreen = 256.0 * math.pow(2, camera.zoom - zoom);

    final worldCenter = camera.crs.latLngToPoint(camera.center, camera.zoom);
    final topLeftX = worldCenter.x - size.width / 2;
    final topLeftY = worldCenter.y - size.height / 2;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final paint = Paint()..isAntiAlias = true;

    // ① 上一渲染集垫底：缩放切换时旧层级瓦片先画（只复用已解码条目）。
    for (final (pz, px, py) in cache.previousSet) {
      if (pz == zoom) continue;
      final entry = cache.lookupRetained(pz, px, py);
      if (entry == null) continue;
      final pTile = 256.0 * math.pow(2, camera.zoom - pz);
      final dst = Rect.fromLTWH(
          px * pTile - topLeftX, py * pTile - topLeftY, pTile, pTile);
      if (!dst.overlaps(Offset.zero & size)) continue;
      paint.shader = entry.shader;
      canvas.drawRect(dst, paint);
    }

    // ② 当前层级 + 父级回退；x 环绕世界副本，y 夹取。
    final x0 = (topLeftX / tileScreen).floor() - 1;
    final x1 = ((topLeftX + size.width) / tileScreen).ceil() + 1;
    final y0 = (topLeftY / tileScreen).floor();
    final y1 = ((topLeftY + size.height) / tileScreen).ceil();

    cache.beginFrame();
    for (var ty = math.max(y0, 0); ty <= math.min(y1, cols - 1); ty++) {
      for (var tx = x0; tx <= x1; tx++) {
        final wrappedX = ((tx % cols) + cols) % cols;
        final hit = cache.lookupWithFallback(zoom, wrappedX, ty);
        if (hit == null) continue;
        cache.addRenderTile(zoom, wrappedX, ty);
        final (entry, dz) = hit;
        final scale = 1 << dz;

        final dst = Rect.fromLTWH(
            tx * tileScreen - topLeftX,
            ty * tileScreen - topLeftY,
            tileScreen,
            tileScreen);
        if (!dst.overlaps(Offset.zero & size)) continue;

        final iw = entry.image.width.toDouble();
        final ih = entry.image.height.toDouble();
        final src = dz == 0
            ? Rect.fromLTWH(0, 0, iw, ih)
            : Rect.fromLTWH(
                (wrappedX % scale) / scale * iw,
                (ty % scale) / scale * ih,
                iw / scale,
                ih / scale,
              );

        paint.shader = entry.shader;
        canvas.drawImageRect(entry.image, src, dst, paint);
      }
    }
    canvas.restore();
    cache.commitFrame();
  }

  @override
  bool shouldRepaint(covariant _FlatTilePainter oldDelegate) =>
      oldDelegate.camera != camera;
}
