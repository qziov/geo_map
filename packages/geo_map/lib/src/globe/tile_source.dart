import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    show GeoTileSource, TileFetchResult, TileUrlBuilder;

/// Backwards-compatible name for [GeoTileSource].
typedef GlobeRasterSource = GeoTileSource;

/// WMTS / XYZ over HTTP.
///
/// URL building (templates, TMS flip, quadkey, bbox, subdomains, ratio) is
/// delegated to the pure [TileUrlBuilder] in core, so it is unit-tested there.
/// This class only owns transport: one shared [HttpClient], timeouts, and the
/// 404-vs-network failure split.
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

  /// One shared client for the whole source.
  ///
  /// The old implementation created a fresh `HttpClient` per tile, which meant
  /// a fresh TCP connection *and* a fresh TLS handshake for every tile — at
  /// z12 that is hundreds of handshakes and a very visible stall.
  HttpClient? _client;

  HttpClient get _sharedClient => _client ??= HttpClient()
    ..connectionTimeout =
        const Duration(milliseconds: GeoEngineTuning.requestTimeoutMs)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = GeoEngineTuning.maxParallelRequests;

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
    final client = _sharedClient;
    try {
      final request = await client.getUrl(Uri.parse(urlFor(z, x, y)));
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
            const Duration(milliseconds: GeoEngineTuning.bodyTimeoutMs),
          );
      lastStatusCode = response.statusCode;
      if (response.statusCode != 200) {
        lastError = 'HTTP ${response.statusCode}';
        // 404 / 410: the tile genuinely does not exist. MapLibre does **not**
        // blacklist those — it keeps falling back to parent/child tiles.
        if (response.statusCode == 404 || response.statusCode == 410) {
          return const TileFetchResult.failed(TileFailureKind.notFound);
        }
        return const TileFetchResult.failed(TileFailureKind.network);
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty) {
        return const TileFetchResult.failed(TileFailureKind.empty);
      }
      lastError = null;
      return TileFetchResult.ok(bytes);
    } catch (e) {
      lastError = '$e';
      return const TileFetchResult.failed(TileFailureKind.network);
    }
  }

  static Future<Uint8List> consolidateHttpClientResponseBytes(
    HttpClientResponse response,
  ) async {
    final chunks = <List<int>>[];
    await for (final chunk in response) {
      chunks.add(chunk);
    }
    return Uint8List.fromList(
      chunks.expand((chunk) => chunk).toList(growable: false),
    );
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

  @override
  void dispose() {
    _client?.close(force: true);
    _client = null;
  }
}
