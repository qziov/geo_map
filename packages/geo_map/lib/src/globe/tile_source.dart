import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../platform/http_get.dart';

import 'package:geo_map_core/geo_map_core.dart'
    show
        GeoEngineTuning,
        GeoTileSource,
        TileFailureKind,
        TileFetchResult,
        TileRowOrder,
        TileSchemeKind,
        TileUrlBuilder;

/// The source **contract** ([GeoTileSource]) and [TileFetchResult] now live in
/// `geo_map_core`; re-export them so existing
/// `import '../globe/tile_source.dart'` keep working.
export 'package:geo_map_core/geo_map_core.dart'
    show
        GeoTileSource,
        TileFetchResult,
        TileUrlBuilder,
        TileSchemeKind,
        TileRowOrder;

/// Backwards-compatible name for [GeoTileSource].
typedef GlobeRasterSource = GeoTileSource;

/// WMTS / XYZ over HTTP.
///
/// URL building (templates, TMS flip, quadkey, bbox, subdomains, ratio) is
/// delegated to the pure [TileUrlBuilder] in core, so it is unit-tested there.
/// This class only owns the 404-vs-network failure split; the socket itself is
/// the shared transport in `platform/http_get.dart`, which has a browser
/// implementation so this file compiles for web.
///
/// [urlTemplate] supports `{z}`, `{x}`, `{y}`, `{TileMatrix}`, `{TileRow}`,
/// `{TileCol}`, `{prefix}`, `{ratio}`, `{quadkey}`, `{bbox}`,
/// `{bbox-epsg-3857}`. Both RESTful WMTS and plain XYZ templates work, e.g.:
///
/// ```
/// WMTS (EPSG:4326, NASA GIBS):
/// https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/MODIS_Terra_CorrectedReflectance_TrueColor/default/2026-10-20/250m/{z}/{y}/{x}.jpg
///
/// XYZ:
/// https://tile.openstreetmap.org/{z}/{x}/{y}.png
/// ```
class HttpTileSource implements GlobeRasterSource {
  HttpTileSource({
    required this.urlTemplate,
    required this.scheme,
    required this.maxZoom,
    this.minZoom = 0,
    this.attribution = '',
    this.headers = const {},
    this.rowOrder = TileRowOrder.xyzTopDown,
    this.userAgent = 'geo_map/0.1',
    this.subdomains = const [],
    this.tileRatio = 1,
  });

  final String urlTemplate;

  @override
  final TileSchemeKind scheme;

  @override
  final TileRowOrder rowOrder;

  @override
  final int minZoom;

  @override
  final int maxZoom;

  @override
  final String attribution;

  /// HTTP tiles are the classic case: full parallelism.
  @override
  int get maxConcurrentRequests => GeoEngineTuning.maxParallelRequests;

  final Map<String, String> headers;

  final String userAgent;

  /// Subdomains spread by `{prefix}` (empty disables it).
  final List<String> subdomains;

  /// Pixel ratio rendered by `{ratio}` (`> 1` → `@Nx`).
  final int tileRatio;

  /// Last transport error, surfaced in the debug HUD (DNS failure, timeout…).
  String? lastError;

  /// Last HTTP status code that was **not** 200 (`null` after a success).
  int? lastStatusCode;

  /// Pure URL building, delegated to core.
  late final TileUrlBuilder _urls = TileUrlBuilder(
    templates: urlTemplate,
    subdomains: subdomains,
    tileRatio: tileRatio,
    scheme: scheme,
    rowOrder: rowOrder,
  );

  String urlFor(int z, int x, int y) => _urls.urlFor(z, x, y);

  @override
  Future<TileFetchResult> fetch(int z, int x, int y) async {
    final result = await httpGetBytes(
      Uri.parse(urlFor(z, x, y)),
      headers: headers,
      userAgent: userAgent,
    );
    lastStatusCode = result.statusCode;
    if (result.error != null) {
      lastError = result.error;
      return const TileFetchResult.failed(TileFailureKind.network);
    }
    if (result.statusCode != 200) {
      lastError = 'HTTP ${result.statusCode}';
      // 404 / 410: the tile genuinely does not exist. MapLibre does **not**
      // blacklist those — it keeps falling back to parent/child tiles.
      if (result.statusCode == 404 || result.statusCode == 410) {
        return const TileFetchResult.failed(TileFailureKind.notFound);
      }
      return const TileFetchResult.failed(TileFailureKind.network);
    }
    final bytes = result.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const TileFetchResult.failed(TileFailureKind.empty);
    }
    lastError = null;
    return TileFetchResult.ok(bytes);
  }

  /// NASA GIBS daily true-colour mosaic (no API key, EPSG:4326 WMTS).
  ///
  /// Good demo for the 2:1 matrix set: coastlines must line up with the
  /// bundled MBTiles basemap when both are visible.
  factory HttpTileSource.gibsTrueColor({DateTime? date}) {
    final day = (date ?? DateTime.now().subtract(const Duration(days: 2)));
    final stamp =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    return HttpTileSource(
      urlTemplate:
          'https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/'
          'MODIS_Terra_CorrectedReflectance_TrueColor/default/$stamp/'
          '250m/{z}/{y}/{x}.jpg',
      scheme: TileSchemeKind.epsg4326wmts,
      minZoom: 0,
      maxZoom: 7,
      attribution: 'NASA GIBS / MODIS',
    );
  }

  /// Plain XYZ raster (OSM). Only for smoke tests — respect the tile policy.
  factory HttpTileSource.osm() => HttpTileSource(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        scheme: TileSchemeKind.webMercator,
        minZoom: 0,
        maxZoom: 18,
        attribution: '© OpenStreetMap contributors',
      );

  static Uint8List? decodeBase64(String value) => base64Decode(value);

  /// The transport is shared and process-wide, so there is nothing per-source
  /// to tear down here.
  @override
  void dispose() {}
}
