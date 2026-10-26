/// The tile **source contract** plus **pure URL building**, shared by 2D/3D.
///
/// Kept free of `dart:io` / `dart:ui` so the URL logic (templates, TMS flip,
/// quadkey, bbox) is unit-testable. Transport (HTTP, MBTiles) lives in
/// `geo_map`, which implements [GeoTileSource] and uses [TileUrlBuilder].
library;

import 'dart:async';
import 'dart:typed_data';

import '../math/projections.dart' show mercatorTAt;
import '../tuning/geo_engine_tuning.dart';
import 'tile_cache_policy.dart' show TileFailureKind;
import 'tile_scheme.dart';

/// The outcome of a single tile fetch.
///
/// MapLibre draws a hard line between "the server says there is no such tile"
/// (404 — never blacklisted, the engine keeps falling back) and "the request
/// broke" (network error — retried quickly). Collapsing both into `null` is
/// what made the old engine blacklist tiles after two failures.
class TileFetchResult {
  const TileFetchResult.ok(this.bytes) : failure = null;

  const TileFetchResult.failed(this.failure) : bytes = null;

  /// The decoded payload, or `null` when [failure] is set.
  final Uint8List? bytes;

  /// Why the tile could not be produced (`null` on success).
  final TileFailureKind? failure;

  bool get isOk => failure == null && bytes != null;

  bool get isNotFound => failure == TileFailureKind.notFound;

  @override
  String toString() => isOk
      ? 'TileFetchResult.ok(${bytes?.length} bytes)'
      : 'TileFetchResult.failed($failure)';
}

/// A raster tile provider (HTTP, MBTiles, …).
abstract class GeoTileSource {
  int get minZoom;

  int get maxZoom;

  /// The tile grid geometry of this source.
  TileSchemeKind get scheme;

  /// Row order used **on the wire** (TMS / MBTiles count rows from south).
  TileRowOrder get rowOrder => TileRowOrder.xyzTopDown;

  /// How many requests may be in flight at the same time. A local sqlite file
  /// gains nothing from parallel reads, so MBTiles overrides this with a much
  /// smaller number.
  int get maxConcurrentRequests => GeoEngineTuning.maxParallelRequests;

  /// Fetch one tile. [x] / [y] are canonical XYZ (row 0 = north); the source
  /// converts to its own wire order internally.
  Future<TileFetchResult> fetch(int z, int x, int y);

  /// Attribution shown in debug UI.
  String get attribution;

  /// Release any resource held by the source (sqlite handle, http client).
  void dispose() {}
}

/// Builds tile URLs from one or more templates.
///
/// Supported placeholders:
///
/// - `{z}` `{x}` `{y}` — tile address (TMS flips `y` when [rowOrder] says so);
/// - `{TileMatrix}` `{TileRow}` `{TileCol}` — the WMTS spellings of the above;
/// - `{prefix}` — subdomain spread (`tileDomain = subdomains[(x+y) % n]`);
/// - `{ratio}` — pixel-ratio suffix (`@2x` when [tileRatio] > 1, else empty);
/// - `{quadkey}` — Bing quadkey (canonical XYZ, never TMS-flipped);
/// - `{bbox}` — `west,south,east,north` in degrees (y-axis up);
/// - `{bbox-epsg-3857}` — `minx,miny,maxx,maxy` in EPSG:3857 metres (y-axis up).
///
/// When several [templates] are given they rotate per tile, which spreads load
/// across mirrored hosts (MapLibre's `tiles` array).
class TileUrlBuilder {
  TileUrlBuilder({
    required Object templates,
    this.subdomains = const <String>[],
    this.tileRatio = 1,
    this.scheme = TileSchemeKind.webMercator,
    this.rowOrder = TileRowOrder.xyzTopDown,
  })  : assert(templates is String || (templates as List).isNotEmpty),
        templates = templates is String
            ? [templates]
            : List<String>.from(templates as List);

  /// One or more URL templates.
  final List<String> templates;

  /// Subdomains for `{prefix}` (empty disables it).
  final List<String> subdomains;

  /// Pixel ratio; `> 1` renders `{ratio}` as `@Nx`.
  final int tileRatio;

  /// Grid used to compute `{bbox}` / `{bbox-epsg-3857}`.
  final TileSchemeKind scheme;

  /// Wire row order (TMS flips `y`).
  final TileRowOrder rowOrder;

  /// Build the URL for canonical tile `(z, x, y)`.
  String urlFor(int z, int x, int y) {
    final template = templates[(x + y) % templates.length];
    final row = rowOrder == TileRowOrder.tmsBottomUp ? (1 << z) - 1 - y : y;
    final grid = TileGrid.of(scheme, z);
    final west = grid.west(x);
    final east = grid.east(x);
    final north = grid.north(y);
    final south = grid.south(y);
    final prefix =
        subdomains.isEmpty ? '' : subdomains[(x + y) % subdomains.length];
    final ratio = tileRatio > 1 ? '@${tileRatio}x' : '';
    final bbox = '${_fmt(west)},${_fmt(south)},${_fmt(east)},${_fmt(north)}';
    final bbox3857 =
        '${_fmt(_mX(west))},${_fmt(_mY(south))},${_fmt(_mX(east))},${_fmt(_mY(north))}';
    final quadkey = _quadkey(z, x, y);
    return template
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$row')
        .replaceAll('{TileMatrix}', '$z')
        .replaceAll('{TileRow}', '$row')
        .replaceAll('{TileCol}', '$x')
        .replaceAll('{prefix}', prefix)
        .replaceAll('{ratio}', ratio)
        .replaceAll('{bbox}', bbox)
        .replaceAll('{bbox-epsg-3857}', bbox3857)
        .replaceAll('{quadkey}', quadkey);
  }
}

/// EPSG:3857 world circumference in metres (`2πR`, `R = 6378137`).
const double _earthCircumference = 40075016.68557849;

/// Web-Mercator x in metres (y-axis up; `lng = 0` → 0).
double _mX(double lng) => _earthCircumference * lng / 360.0;

/// Web-Mercator y in metres (y-axis up; north positive). Latitude is clamped
/// to the Mercator limit so the poles never produce NaN/Infinity.
double _mY(double lat) {
  final clamped = lat.clamp(-85.05112878, 85.05112878).toDouble();
  // mercatorTAt: 0.5 at the equator, < 0.5 north, > 0.5 south.
  final l = 3.141592653589793 * (1 - 2 * mercatorTAt(clamped));
  return _earthCircumference / (2 * 3.141592653589793) * l;
}

/// Bing quadkey for canonical `(z, x, y)`.
String _quadkey(int z, int x, int y) {
  final buffer = StringBuffer();
  for (var i = z; i > 0; i--) {
    var digit = 0;
    final mask = 1 << (i - 1);
    if ((x & mask) != 0) digit += 1;
    if ((y & mask) != 0) digit += 2;
    buffer.write(digit);
  }
  return buffer.toString();
}

/// Format a degree/metre value without trailing zeros or exponent noise.
String _fmt(double v) {
  var s = v.toStringAsFixed(6);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}
