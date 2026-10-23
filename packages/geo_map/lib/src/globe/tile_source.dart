import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// How a tile pyramid is laid out on the sphere.
enum TileScheme {
  /// Web Mercator (XYZ): 2^z × 2^z tiles, latitude follows the mercator
  /// spacing. What MBTiles/OSM use.
  webMercator,

  /// OGC "GoogleMapsCompatible"-style geodetic grid: 2^(z+1) × 2^z tiles,
  /// latitude linear in degrees. What most WMTS `EPSG:4326` matrix sets use
  /// (e.g. NASA GIBS).
  geodetic,
}

/// Tile grid geometry for a scheme at a given zoom.
class TileGrid {
  const TileGrid({required this.cols, required this.rows});

  factory TileGrid.of(TileScheme scheme, int z) {
    switch (scheme) {
      case TileScheme.webMercator:
        final n = 1 << z;
        return TileGrid(cols: n, rows: n);
      case TileScheme.geodetic:
        return TileGrid(cols: 2 << z, rows: 1 << z);
    }
  }

  final int cols;
  final int rows;

  double west(int x) => x / cols * 360 - 180;

  double east(int x) => (x + 1) / cols * 360 - 180;

  double north(int y) => 90 - y / rows * 180;

  double south(int y) => 90 - (y + 1) / rows * 180;
}

/// A raster tile provider for the globe.
///
/// Async on purpose: WMTS/XYZ tiles come over HTTP, MBTiles is local. The
/// caller (the tile cache) is already async, so both fit the same shape.
abstract class GlobeRasterSource {
  int get minZoom;

  int get maxZoom;

  TileScheme get scheme;

  /// [x]/[y] are in **XYZ** orientation (y from the top).
  Future<Uint8List?> fetch(int z, int x, int y);

  /// Attribution shown in debug UI.
  String get attribution;
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
  });

  final String urlTemplate;

  @override
  final TileScheme scheme;

  @override
  final int minZoom;

  @override
  final int maxZoom;

  @override
  final String attribution;

  final Map<String, String> headers;

  /// Last transport error, surfaced in the debug HUD (DNS failure, timeout…).
  String? lastError;

  String urlFor(int z, int x, int y) => urlTemplate
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y')
      .replaceAll('{TileMatrix}', '$z')
      .replaceAll('{TileRow}', '$y')
      .replaceAll('{TileCol}', '$x');

  @override
  Future<Uint8List?> fetch(int z, int x, int y) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(urlFor(z, x, y)));
      request.headers.set(HttpHeaders.userAgentHeader, 'globe_lab/0.1');
      headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode != 200) {
        lastError = 'HTTP ${response.statusCode}';
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      return bytes.isEmpty ? null : bytes;
    } catch (e) {
      lastError = '$e';
      return null;
    } finally {
      client.close(force: true);
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
  /// Good demo for the geodetic scheme: coastlines must line up with the
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
      scheme: TileScheme.geodetic,
      minZoom: 0,
      maxZoom: 7,
      attribution: 'NASA GIBS / MODIS',
    );
  }

  /// Plain XYZ raster (OSM). Only for smoke tests — respect the tile policy.
  factory HttpTileSource.osm() => HttpTileSource(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    scheme: TileScheme.webMercator,
    minZoom: 0,
    maxZoom: 18,
    attribution: '© OpenStreetMap contributors',
  );

  static Uint8List? decodeBase64(String value) => base64Decode(value);
}
