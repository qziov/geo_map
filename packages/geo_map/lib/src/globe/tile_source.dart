import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:geo_map_core/geo_map_core.dart'
    show GeoEngineTuning, TileFailureKind, TileRowOrder, TileSchemeKind;

/// The outcome of a single tile fetch.
///
/// MapLibre draws a hard line between "the server says there is no such tile"
/// (404 — never blacklisted, the engine just keeps falling back to
/// parent/child tiles) and "the request broke" (network error — retried
/// quickly). Collapsing both into `null` is what made the old engine
/// blacklist tiles after two failures and leave black holes behind.
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
  String toString() =>
      isOk ? 'TileFetchResult.ok(${bytes?.length} bytes)' : 'TileFetchResult.failed($failure)';
}

/// A raster tile provider.
///
/// Async on purpose: WMTS/XYZ tiles come over HTTP, MBTiles is local. The
/// caller (the tile cache) is already async, so both fit the same shape.
abstract class GlobeRasterSource {
  int get minZoom;

  int get maxZoom;

  /// The tile grid geometry of this source.
  ///
  /// Uses the core enumeration so that the geometry (row latitudes, column
  /// counts, parent/child relations) has exactly **one** definition in the
  /// project — the old second definition used linear latitudes for Web
  /// Mercator, which is exactly why high-latitude tiles landed in the wrong
  /// row and the screen went black.
  TileSchemeKind get scheme;

  /// Row order used **on the wire** (TMS / MBTiles count rows from south).
  TileRowOrder get rowOrder => TileRowOrder.xyzTopDown;

  /// How many requests may be in flight at the same time.
  ///
  /// A local sqlite file gains nothing from parallel reads, so MBTiles
  /// overrides this with a much smaller number.
  int get maxConcurrentRequests => GeoEngineTuning.maxParallelRequests;

  /// Fetch one tile.
  ///
  /// [x] / [y] are always in **canonical XYZ** orientation (row 0 = northern
  /// edge); the source converts to its own wire order internally.
  Future<TileFetchResult> fetch(int z, int x, int y);

  /// Attribution shown in debug UI.
  String get attribution;

  /// Release any resource held by the source (sqlite handle, http client).
  void dispose() {}
}

/// WMTS / XYZ over HTTP.
///
/// [urlTemplate] supports `{z}`, `{x}`, `{y}`, `{TileMatrix}`, `{TileRow}`,
/// `{TileCol}`. Both RESTful WMTS and plain XYZ templates work, e.g.:
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

  /// Last transport error, surfaced in the debug HUD (DNS failure, timeout…).
  String? lastError;

  /// Last HTTP status code that was **not** 200 (`null` after a success).
  int? lastStatusCode;

  /// One shared client for the whole source.
  ///
  /// The old implementation created a fresh `HttpClient` per tile, which
  /// meant a fresh TCP connection *and* a fresh TLS handshake for every tile
  /// — at z12 that is hundreds of handshakes and a very visible stall.
  HttpClient? _client;

  HttpClient get _sharedClient => _client ??= HttpClient()
    ..connectionTimeout =
        const Duration(milliseconds: GeoEngineTuning.requestTimeoutMs)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = GeoEngineTuning.maxParallelRequests;

  /// The row index to put into the URL.
  ///
  /// TMS-style services number rows from the south
  /// (`y = 2^z − 1 − y`, MapLibre `tile_id.ts` L48).
  int _wireRow(int z, int y) => switch (rowOrder) {
        TileRowOrder.xyzTopDown => y,
        TileRowOrder.tmsBottomUp => (1 << z) - 1 - y,
      };

  String urlFor(int z, int x, int y) {
    final row = _wireRow(z, y);
    return urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$row')
        .replaceAll('{TileMatrix}', '$z')
        .replaceAll('{TileRow}', '$row')
        .replaceAll('{TileCol}', '$x');
  }

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
