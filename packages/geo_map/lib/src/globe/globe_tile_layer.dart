import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../vendor/flutter_map_camera/flutter_map_camera.dart';

import '../diagnostics/geo_diagnostics.dart';

import 'tile_source.dart';

/// Draws raster tiles on the globe.
///
/// Not flutter_map's `TileLayer`: that one selects tiles in world pixel space,
/// which a sphere cannot provide. Here tessellation and tile selection are done
/// against the delegate's screen-space projection, but the layer is still an
/// ordinary `FlutterMap.children` widget sharing the same `MapCamera`.
///
/// Supports both [TileScheme.webMercator] (MBTiles/XYZ) and
/// [TileScheme.geodetic] (WMTS `EPSG:4326`).
class GlobeTileLayer extends StatefulWidget {
  const GlobeTileLayer({super.key, required this.source});

  final GlobeRasterSource source;

  @override
  State<GlobeTileLayer> createState() => _GlobeTileLayerState();
}

class _GlobeTileLayerState extends State<GlobeTileLayer> {
  late _TileCache _cache = _TileCache(widget.source);

  @override
  void didUpdateWidget(GlobeTileLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      final oldCache = _cache;
      _cache = _TileCache(widget.source);
      // Disposing a ChangeNotifier that listeners are still attached to can
      // notify deactivated elements; let the tree finish rebuilding first.
      WidgetsBinding.instance.addPostFrameCallback((_) => oldCache.dispose());
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
        listenable: _cache,
        builder: (context, _) => CustomPaint(
          size: Size(camera.size.x, camera.size.y),
          painter: _GlobeTilePainter(
            camera: camera,
            cache: _cache,
            revision: _cache.revision,
          ),
        ),
      ),
    );
  }
}

class _GlobeTilePainter extends CustomPainter {
  _GlobeTilePainter({
    required this.camera,
    required this.cache,
    required this.revision,
  });

  final MapCamera camera;
  final _TileCache cache;
  final int revision;

  static const double _eps = 0.02;

  /// Cells touching a vertex deeper than this are dropped, not clamped.

  TileScheme get _scheme => cache.source.scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final lat0 = camera.center.latitude * math.pi / 180;
    final lng0 = camera.center.longitude * math.pi / 180;
    // Same formula as the delegate: zoom only, no latitude factor (otherwise
    // the globe would grow when dragging towards the poles).
    final radius = 256 * math.pow(2, camera.zoom) / (2 * math.pi);
    if (radius <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final zoom = _pickZoom(
      radius,
      lat0,
    ).clamp(cache.source.minZoom, cache.source.maxZoom);

    final grid = TileGrid.of(_scheme, zoom);
    final tileScreenPx = 2 * math.pi * radius / grid.cols;
    final subdivisions = _subdivisionsFor(tileScreenPx);

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );

    final paint = Paint()..isAntiAlias = true;

    // ★ MapLibre `_updateRetainedTiles` 语义（tile_manager.ts L682，逐条对齐）：
    //   ① ideal 瓦片无论有无数据都先占渲染集；
    //   ② miss 的 ideal：先找已加载**子孙**放大垫住（≤ overscaledZ+3，整代齐全才画）；
    //   ③ 再沿祖先向上（≤ maxUnderzooming=10，下界 source.minZoom）找**已加载**祖先；
    //      父未加载但被请求过 → 继续向上请求（parentWasRequested，断链不断请求）；
    //   ④ 所有画过的（ideal + 子孙 + 祖先）都进渲染集。
    //   只要金字塔任一祖/孙有数据，屏幕必有覆盖 —— 黑瓦不可能出现。
    final visible = _visibleTiles(zoom, grid, lng0, lat0, size, radius);
    var drawn = 0;
    var missed = 0;
    var kidTiles = 0;
    var fallbackTiles = 0;
    final missDetails = <String>[];

    for (final (tx, ty) in visible) {
      var covered = false;

      // ideal 命中
      final entry = cache.lookupRetained(zoom, tx, ty);
      if (entry != null) {
        final vertices = _buildVertices(
          grid: grid,
          x: tx,
          y: ty,
          lat0: lat0,
          lng0: lng0,
          radius: radius,
          center: center,
          image: entry.image,
          subdivisions: subdivisions,
        );
        if (vertices != null) {
          paint.shader = entry.shader;
          canvas.drawVertices(vertices, BlendMode.srcOver, paint);
          vertices.dispose();
        }
        drawn++;
        covered = true;
      } else {
        missed++;
        // ★ MapLibre `_addTile(idealID)`：ideal 瓦片无条件请求（这是加载的
        //   唯一入口）。漏掉它 = 永远没有瓦片可解码（首帧日志实锤）。
        cache.request(zoom, tx, ty);
        if (missDetails.length < 5) {
          missDetails.add('$zoom/$tx/$ty=${cache.explainMiss(zoom, tx, ty)}');
        }
      }

      // ① 子代保留（maxOverzooming=+3）：缩放进入时用已加载的更细瓦片放大垫住
      if (!covered) {
        for (var d = 1;
            d <= GeoDiagnostics.maxOverzooming && zoom + d <= cache.source.maxZoom;
            d++) {
          final scale = 1 << d;
          final childGrid = TileGrid.of(_scheme, zoom + d);
          final childSub = _subdivisionsFor(tileScreenPx / scale);
          final kids = <(int, int)>[];
          var allLoaded = true;
          for (var j = 0; j < scale && allLoaded; j++) {
            for (var i = 0; i < scale; i++) {
              final cx = tx * scale + i;
              final cy = ty * scale + j;
              if (cy >= childGrid.rows ||
                  cache.lookupRetained(zoom + d, cx, cy) == null) {
                allLoaded = false;
                break;
              }
              kids.add((cx, cy));
            }
          }
          if (!allLoaded) continue;
          for (final (cx, cy) in kids) {
            final childEntry = cache.lookupRetained(zoom + d, cx, cy)!;
            final vertices = _buildVertices(
              grid: childGrid,
              x: cx,
              y: cy,
              lat0: lat0,
              lng0: lng0,
              radius: radius,
              center: center,
              image: childEntry.image,
              subdivisions: childSub,
            );
            if (vertices == null) continue;
            paint.shader = childEntry.shader;
            canvas.drawVertices(vertices, BlendMode.srcOver, paint);
            vertices.dispose();
            kidTiles++;
          }
          covered = true;
          break;
        }
      }

      // ② 父代回退（maxUnderzooming=10，下界 source.minZoom）
      if (!covered) {
        var requested = cache.wasRequested('$zoom/$tx/$ty');
        for (var dz = 1;
            zoom - dz >= cache.source.minZoom &&
                dz <= GeoDiagnostics.maxUnderzooming;
            dz++) {
          final scale = 1 << dz;
          final px = tx ~/ scale;
          final py = ty ~/ scale;
          final pk = '${zoom - dz}/$px/$py';
          final pEntry = cache.lookupRetained(zoom - dz, px, py);
          if (pEntry != null) {
            final pGrid = TileGrid.of(_scheme, zoom - dz);
            final vertices = _buildVertices(
              grid: pGrid,
              x: px,
              y: py,
              lat0: lat0,
              lng0: lng0,
              radius: radius,
              center: center,
              image: pEntry.image,
              subdivisions: _subdivisionsFor(tileScreenPx / scale),
              uvOrigin: dz == 0 ? Offset.zero : _uvOrigin(tx, ty, dz),
              uvSpan: 1 / scale,
            );
            if (vertices != null) {
              paint.shader = pEntry.shader;
              canvas.drawVertices(vertices, BlendMode.srcOver, paint);
              vertices.dispose();
            }
            drawn++;
            fallbackTiles++;
            covered = true;
            break;
          }
          if (requested && !cache.wasRequested(pk)) {
            cache.request(zoom - dz, px, py);
          }
          requested = cache.wasRequested(pk);
        }
      }
    }

    GeoDiagnostics.frame(
        '[geo_map:frame] dataZ=$zoom visible=${visible.length} drawn=$drawn '
        'missed=$missed fallback=$fallbackTiles kids=$kidTiles '
        'img=${cache.entryCount} pend=${cache.pendingCount} '
        'c=${camera.center.latitude.toStringAsFixed(1)},'
        '${camera.center.longitude.toStringAsFixed(1)} '
        'z${camera.zoom.toStringAsFixed(2)}');
    if (missDetails.isNotEmpty) {
      GeoDiagnostics.missDetail('[geo_map:miss] ${missDetails.join(' ')}');
    }

    // MapLibre 规则③：极帽拉伸。Web Mercator 只覆盖到 ±85.05°，拉向两极时
    // 极帽（85°→90°）无任何瓦片 —— 用行 0/末行的边缘像素向极点方向拉伸填充，
    // 消除极区黑帽（与 MapLibre 对 mercator 源的极区处理同思路）。
    _paintPolarCaps(
      canvas,
      radius: radius,
      center: center,
      lat0: lat0,
      lng0: lng0,
      zoom: zoom,
      grid: grid,
      subdivisions: subdivisions,
      cache: cache,
      paint: paint,
    );

    canvas.restore();
  }

  /// 极帽填充：对可见的每一列，把行 0（北）/末行（南）瓦片的边缘 1px
  /// 沿纬度拉伸到极点。深度测试沿用 culled indices（极点 z = sin(lat0)，
  /// 背面极帽自动整块剔除）。
  void _paintPolarCaps(
    Canvas canvas, {
    required double radius,
    required Offset center,
    required double lat0,
    required double lng0,
    required int zoom,
    required TileGrid grid,
    required int subdivisions,
    required _TileCache cache,
    required Paint paint,
  }) {
    if (_scheme != TileScheme.webMercator) return;
    final sinLat0 = math.sin(lat0);
    if (sinLat0.abs() <= _eps) return; // 相机在赤道附近：极帽在轮廓上，无需画
    final north = sinLat0 > 0;
    final capLat = 85.0511 * math.pi / 180.0;
    final poleLat = math.pi / 2.0;

    for (var x = 0; x < grid.cols; x++) {
      final row = north ? 0 : grid.rows - 1;
      final hit = cache.lookupWithFallback(zoom, x, row, cache.source.minZoom);
      if (hit == null) continue;
      final (entry, dz) = hit;

      // UV：u 取本列在 dz 级祖先里的子区间；v 取 1px 边缘行做纵向拉伸。
      final scale = 1 << dz;
      final iw = entry.image.width.toDouble();
      final ih = entry.image.height.toDouble();
      final u0px = dz == 0 ? 0.0 : (x % scale) / scale * iw;
      final uSpanPx = iw / scale;
      final v0px = north ? 0.0 : ih - 1.0;

      final n = subdivisions.clamp(4, 12);
      final west = grid.west(x);
      final lngSpan = grid.east(x) - west;

      final vertexCount = (n + 1) * (n + 1);
      final positions = Float32List(vertexCount * 2);
      final uvs = Float32List(vertexCount * 2);
      final depths = Float32List(vertexCount);

      for (var j = 0; j <= n; j++) {
        // 纬度线性插值：85.05° → 极点。极点处所有经线收敛于一点。
        final t = j / n;
        final lat = north
            ? capLat + (poleLat - capLat) * t
            : -(capLat + (poleLat - capLat) * t);
        for (var i = 0; i <= n; i++) {
          final lng = _deg2rad(west + lngSpan * (i / n));
          final v = _view(lng, lat, lat0, lng0);
          final index = j * (n + 1) + i;
          depths[index] = v.$3;
          positions[index * 2] = center.dx + v.$1 * radius;
          positions[index * 2 + 1] = center.dy - v.$2 * radius;
          uvs[index * 2] = u0px + (i / n) * uSpanPx;
          uvs[index * 2 + 1] = v0px;
        }
      }

      final indices = _culledIndices(n, depths, (j, i) => j * (n + 1) + i);
      if (indices == null) continue;
      paint.shader = entry.shader;
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          positions,
          textureCoordinates: uvs,
          indices: indices,
        ),
        BlendMode.srcOver,
        paint,
      );
    }
  }

  /// 本瓦片在 dz 级祖先图中的 UV 左上角（0..1）。
  static Offset _uvOrigin(int x, int y, int dz) {
    final scale = 1 << dz;
    return Offset((x % scale) / scale, (y % scale) / scale);
  }

  static int _subdivisionsFor(double tileScreenPx) =>
      (tileScreenPx / 20).ceil().clamp(6, 16);

  /// Geodetic grids cover 360° regardless of latitude; mercator additionally
  /// scales with `cos(lat)` because its world height is `2πR·cos(lat)`.
  int _pickZoom(double radius, double lat0) {
    // Near the poles Web Mercator's scale factor explodes; without a floor the
    // chosen level jumps to absurd values (and we have no tiles past z5 anyway).
    final cosLat = math.max(math.cos(lat0).abs(), 0.2);
    final worldPx = _scheme == TileScheme.geodetic
        ? 2 * math.pi * radius
        : 2 * math.pi * radius * cosLat;
    return (math.log(worldPx / 256) / math.ln2).round();
  }

  List<(int, int)> _visibleTiles(
    int z,
    TileGrid grid,
    double lng0,
    double lat0,
    Size size,
    double radius,
  ) {
    final seen = <(int, int)>{};
    // 余量随瓦片屏幕尺寸走：z5 单瓦片 ~256px，64px 的固定余量会让
    // 新月形投影的近轮廓瓦片整块漏判（黑块）。
    final margin = math.max(64.0, 2 * math.pi * radius / grid.cols / 2);

    for (var y = 0; y < grid.rows; y++) {
      final phiN = _deg2rad(grid.north(y));
      final phiS = _deg2rad(grid.south(y));
      final dLng = math.max(_span(phiN, lat0), _span(phiS, lat0));
      if (dLng <= 0) continue;

      final dLngDeg = dLng * 180 / math.pi;
      final lngDeg = lng0 * 180 / math.pi;
      final x0 = (((lngDeg - dLngDeg) + 180) / 360 * grid.cols).floor();
      final x1 = (((lngDeg + dLngDeg) + 180) / 360 * grid.cols).floor();
      for (var x = x0; x <= x1; x++) {
        final wrapped = ((x % grid.cols) + grid.cols) % grid.cols;
        if (_onScreen(grid, wrapped, y, lat0, lng0, size, radius, margin)) {
          seen.add((wrapped, y));
        }
      }
    }
    return seen.toList();
  }

  double _span(double phi, double lat0) {
    final t = -math.tan(phi) * math.tan(lat0);
    if (t <= -1) return math.pi;
    if (t >= 1) return 0;
    return math.acos(t);
  }

  bool _onScreen(
    TileGrid grid,
    int x,
    int y,
    double lat0,
    double lng0,
    Size size,
    double radius,
    double margin,
  ) {
    final west = grid.west(x);
    final east = grid.east(x);
    final north = grid.north(y);
    final south = grid.south(y);

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var anyVisible = false;

    void include(double lng, double lat) {
      final v = _view(lng * math.pi / 180, lat * math.pi / 180, lat0, lng0);
      if (v.$3 <= _eps) return;
      anyVisible = true;
      final sx = size.width / 2 + v.$1 * radius;
      final sy = size.height / 2 - v.$2 * radius;
      if (sx < minX) minX = sx;
      if (sx > maxX) maxX = sx;
      if (sy < minY) minY = sy;
      if (sy > maxY) maxY = sy;
    }

    // 边界采样加密到每边 4 点：z5 圆盘大于屏幕时，轮廓附近的瓦片投影呈
    // 新月形，仅 4 角采样会让角点全部落在屏幕外而误判不可见（黑块）。
    const steps = 4;
    void includeEdge(double lngA, double latA, double lngB, double latB) {
      for (var k = 0; k <= steps; k++) {
        final t = k / steps;
        include(lngA + (lngB - lngA) * t, latA + (latB - latA) * t);
      }
    }

    includeEdge(west, north, east, north);
    includeEdge(east, north, east, south);
    includeEdge(east, south, west, south);
    includeEdge(west, south, west, north);
    include((west + east) / 2, (north + south) / 2);

    if (!anyVisible) return false;
    return !(maxX < -margin ||
        maxY < -margin ||
        minX > size.width + margin ||
        minY > size.height + margin);
  }

  ui.Vertices? _buildVertices({
    required TileGrid grid,
    required int x,
    required int y,
    required double lat0,
    required double lng0,
    required double radius,
    required Offset center,
    required ui.Image image,
    required int subdivisions,
    Offset uvOrigin = Offset.zero,
    double uvSpan = 1,
  }) {
    final n = subdivisions;
    final vertexCount = (n + 1) * (n + 1);
    final positions = Float32List(vertexCount * 2);
    final uvs = Float32List(vertexCount * 2);
    final depths = Float32List(vertexCount);

    final west = grid.west(x);
    final lngSpan = grid.east(x) - west;

    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    var allFront = true;
    var anyFront = false;

    for (var j = 0; j <= n; j++) {
      final t = j / n;
      final lat = _deg2rad(_latitudeAt(grid, y, t));
      for (var i = 0; i <= n; i++) {
        final s = i / n;
        final lng = _deg2rad(west + lngSpan * s);
        final v = _view(lng, lat, lat0, lng0);
        final index = j * (n + 1) + i;

        depths[index] = v.$3;

        var vx = v.$1;
        var vy = v.$2;
        if (v.$3 <= _eps) {
          allFront = false;
          final len = math.sqrt(vx * vx + vy * vy);
          if (len < 1e-6) {
            vx = 0;
            vy = 0;
          } else {
            vx /= len;
            vy /= len;
          }
        } else {
          anyFront = true;
        }

        positions[index * 2] = center.dx + vx * radius;
        positions[index * 2 + 1] = center.dy - vy * radius;

        uvs[index * 2] = (uvOrigin.dx + (i / n) * uvSpan) * imageWidth;
        uvs[index * 2 + 1] = (uvOrigin.dy + (j / n) * uvSpan) * imageHeight;
      }
    }

    if (!anyFront) return null;

    final indices = allFront
        ? _staticIndices(n)
        : _culledIndices(n, depths, (j, i) => j * (n + 1) + i);
    if (indices == null) return null;

    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: uvs,
      indices: indices,
    );
  }

  static Uint16List? _culledIndices(
    int n,
    Float32List depths,
    int Function(int row, int col) indexOf,
  ) {
    final out = <int>[];
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final i00 = indexOf(j, i);
        final i10 = indexOf(j, i + 1);
        final i01 = indexOf(j + 1, i);
        final i11 = indexOf(j + 1, i + 1);

        final z00 = depths[i00];
        final z10 = depths[i10];
        final z01 = depths[i01];
        final z11 = depths[i11];

        if (z00 <= _eps && z10 <= _eps && z01 <= _eps && z11 <= _eps) {
          continue;
        }
        // ⚠️ 不做 "任一角 < -0.12 整块丢弃" 的防鳍规则：地平线附近跨面三角形
        // 被整片丢掉会留下沿经纬网的楔形黑洞。背面顶点在构建时已径向钳到
        // 轮廓上，保留三角形只是轻微包边（子division ≥6 时无鳍）。

        out.addAll([i00, i10, i11, i00, i11, i01]);
      }
    }
    if (out.isEmpty) return null;
    return Uint16List.fromList(out);
  }

  static final Map<int, Uint16List> _indexCache = {};

  static Uint16List _staticIndices(int n) => _indexCache.putIfAbsent(n, () {
    final indices = <int>[];
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final i00 = j * (n + 1) + i;
        final i10 = i00 + 1;
        final i01 = i00 + n + 1;
        final i11 = i01 + 1;
        indices.addAll([i00, i10, i11, i00, i11, i01]);
      }
    }
    return Uint16List.fromList(indices);
  });

  /// Latitude inside a tile row, at fraction [t] from the top.
  double _latitudeAt(TileGrid grid, int y, double t) {
    if (_scheme == TileScheme.geodetic) {
      return 90 - (y + t) / grid.rows * 180;
    }
    // Mercator: uniform in mercator-y, not in latitude.
    final mercY = (y + t) / grid.rows;
    return math.atan(_sinh(math.pi * (1 - 2 * mercY))) * 180 / math.pi;
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

  static double _deg2rad(double d) => d * math.pi / 180;

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

  @override
  bool shouldRepaint(covariant _GlobeTilePainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.cache != cache ||
      oldDelegate.revision != revision;
}

class _TileEntry {
  _TileEntry(this.image, this.shader);

  final ui.Image image;
  final ui.ImageShader shader;
  int lastUsed = 0;

  void dispose() {
    shader.dispose();
    image.dispose();
  }
}

class _TileCache extends ChangeNotifier {
  _TileCache(this.source);

  final GlobeRasterSource source;
  final Map<String, _TileEntry> _entries = {};
  final Set<String> _pending = {};

  /// MapLibre 语义：无永久拉黑。missing 带 TTL（30s 后允许重试）；
  /// [_requested] 记录所有曾请求过的 key（`wasRequested` 供父级上升链判断）。
  final Map<String, int> _missing = {};
  final Set<String> _requested = {};

  static const int _missingTtlMs = 30000;

  bool _isMissing(String key) {
    final at = _missing[key];
    if (at == null) return false;
    if (DateTime.now().millisecondsSinceEpoch - at > _missingTtlMs) {
      _missing.remove(key); // TTL 过期：允许重试
      return false;
    }
    return true;
  }

  bool wasRequested(String key) =>
      _requested.contains(key) || _pending.contains(key);

  int get pendingCount => _pending.length;
  int get entryCount => _entries.length;

  String explainMiss(int z, int x, int y) {
    final key = '$z/$x/$y';
    if (_pending.contains(key)) return 'decoding';
    if (_isMissing(key)) return 'missing';
    return 'notRequested';
  }

  /// 主动请求（父级上升链用）。
  void request(int z, int x, int y) {
    final key = '$z/$x/$y';
    if (_disposed || _pending.contains(key) || _entries.containsKey(key)) return;
    if (_isMissing(key)) return;
    _pending.add(key);
    unawaited(_decode(key, z, x, y));
  }

  static const _maxImages = 384;

  int _revision = 0;
  int _frame = 0;
  bool _disposed = false;

  int get revision => _revision;

  /// 只读查询（不触发解码/通知）。
  _TileEntry? lookupRetained(int z, int x, int y) {
    final entry = _entries['$z/$x/$y'];
    if (entry != null) {
      entry.lastUsed = ++_frame;
      return entry;
    }
    return null;
  }

  _TileEntry? lookup(int z, int x, int y) {
    final key = '$z/$x/$y';
    final existing = _entries[key];
    if (existing != null) {
      existing.lastUsed = ++_frame;
      return existing;
    }
    if (_isMissing(key) || _pending.contains(key)) return null;
    _pending.add(key);
    unawaited(_decode(key, z, x, y));
    return null;
  }

  /// 带父级回退的查找：本瓦片已解码 → 原样返回（dz=0）。
  ///
  /// 未就绪 → 沿祖先链找**已解码**的最近祖先（UV 取对应子区域）。
  /// 祖先解码的纪律（防止通知风暴 + LRU 驱逐抖动）：
  /// ① 只有直接父级（dz==1）允许触发解码——可见瓦片的父级数量有限（几十个），
  ///    不会重演当初 840 键的通知风暴；
  /// ② 更深的祖先只复用已缓存条目，绝不主动深挖。
  /// 父级与本级解码完成都会 notify：父级到位填掉黑块，本级到位切回清晰图
  /// （渐进细化），停止缩放后画面也会自动补全。
  (_TileEntry, int)? lookupWithFallback(int z, int x, int y, int minZoom) {
    final exact = lookup(z, x, y);
    if (exact != null) return (exact, 0);

    for (var dz = 1; z - dz >= minZoom; dz++) {
      final scale = 1 << dz;
      final px = x ~/ scale;
      final py = y ~/ scale;
      final key = '${z - dz}/$px/$py';
      final entry = _entries[key];
      if (entry != null) {
        entry.lastUsed = ++_frame;
        return (entry, dz);
      }
      // 父级解码完成后必须 notify：否则停止缩放后没有任何重绘，
      // 回退图会一直留在屏幕上（黑块不消失）。可见瓦片的父级数量有限
      // （几十个），不会重演当初 840 键的通知风暴。
      if (dz == 1 && !_isMissing(key) && !_pending.contains(key)) {
        _pending.add(key);
        unawaited(_decode(key, z - 1, px, py));
      }
    }
    return null;
  }

  Future<void> _decode(
    String key,
    int z,
    int x,
    int y, {
    bool notify = true,
  }) async {
    _requested.add(key);
    try {
      final bytes = await source.fetch(z, x, y);
      if (bytes == null || bytes.isEmpty) {
        _missing[key] = DateTime.now().millisecondsSinceEpoch;
        return;
      }

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      codec.dispose();

      final shader = ui.ImageShader(
        image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        _identity(),
        filterQuality: ui.FilterQuality.low,
      );
      if (_disposed) {
        // The layer may have been disposed while the decode was in flight.
        shader.dispose();
        image.dispose();
        return;
      }
      _entries[key] = _TileEntry(image, shader)..lastUsed = ++_frame;
      _revision++;
      _evict();
      // 本级瓦片完成才通知重绘（渐进细化）；祖先的静默解码由下一次
      // 自然重绘拾取 —— 否则几十上百次 notify 会把主线程塞死。
      if (notify) notifyListeners();
    } catch (e) {
      debugPrint('[geo_map:tile] decode ERROR $key: $e');
      _missing[key] = DateTime.now().millisecondsSinceEpoch;
    } finally {
      _pending.remove(key);
    }
  }

  void _evict() {
    while (_entries.length > _maxImages) {
      String? oldestKey;
      var oldestUse = 1 << 62;
      _entries.forEach((key, entry) {
        if (entry.lastUsed < oldestUse) {
          oldestUse = entry.lastUsed;
          oldestKey = key;
        }
      });
      if (oldestKey == null) return;
      _entries.remove(oldestKey)?.dispose();
    }
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
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    super.dispose();
  }
}
