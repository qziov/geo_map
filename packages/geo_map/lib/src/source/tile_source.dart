/// Raster tile source contract + HTTP implementation.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../../geo_map.dart';

/// Where raster tiles come from. The engine only knows this contract.
abstract class GeoTileSource {
  String get id;

  TileSchemeKind get scheme;

  int get minZoom;

  int get maxZoom;

  Future<Uint8List?> fetch(int z, int x, int y);

  /// Called when the last consumer goes away.
  void dispose() {}
}

class HttpTileSource implements GeoTileSource {
  HttpTileSource({
    required this.id,
    required this.scheme,
    required this.minZoom,
    required this.maxZoom,
    required this.urlTemplate,
    this.headers = const {},
  });

  @override
  final String id;

  @override
  final TileSchemeKind scheme;

  @override
  final int minZoom;

  @override
  final int maxZoom;

  final String urlTemplate;
  final Map<String, String> headers;

  HttpClient? _client;

  @override
  Future<Uint8List?> fetch(int z, int x, int y) async {
    final url = urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
    try {
      _client ??= HttpClient();
      final request = await _client!.getUrl(Uri.parse(url));
      headers.forEach((name, value) => request.headers.add(name, value));
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final bytes = await response.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _client?.close(force: true);
    _client = null;
  }
}

/// Convenience: bounds → [LatLng] list (used by overlays).
List<LatLng> boundsCorners(double south, double west, double north, double east) =>
    [
      LatLng(north, west),
      LatLng(north, east),
      LatLng(south, east),
      LatLng(south, west),
    ];
