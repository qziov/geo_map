import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import 'globe_vector_layer.dart';

/// Loads vector data for the debug overlay.
///
/// "Vector basemap" here means: fetch a GeoJSON `FeatureCollection` over HTTP
/// and feed its linework into [GlobeVectorLayer]. Vector **tiles** (MVT) would
/// need a full style/protobuf pipeline; GeoJSON is enough to eyeball whether
/// the projection is correct.
class GeoJsonVectorSource {
  const GeoJsonVectorSource(this.url);

  /// e.g. Natural Earth 110m coastline (public domain, no API key).
  static const coastlineUrl =
      'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_coastline.geojson';

  final String url;

  Future<List<GlobePolyline>> load({
    Color color = const Color(0xCCFFFFFF),
    double strokeWidth = 1.0,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'globe_lab/0.1');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for $url');
      }
      final body = await response.transform(utf8.decoder).join();
      return parse(body, color: color, strokeWidth: strokeWidth);
    } finally {
      client.close(force: true);
    }
  }

  /// Loads a GeoJSON file bundled as an asset (works offline).
  static Future<List<GlobePolyline>> loadAsset(
    String assetPath, {
    Color color = const Color(0xCCFFFFFF),
    double strokeWidth = 1.0,
  }) async {
    final body = await rootBundle.loadString(assetPath);
    return parse(body, color: color, strokeWidth: strokeWidth);
  }

  /// Parses `LineString`, `MultiLineString` and `Polygon` (outer rings only).
  static List<GlobePolyline> parse(
    String body, {
    Color color = const Color(0xCCFFFFFF),
    double strokeWidth = 1.0,
  }) {
    final decoded = json.decode(body);
    if (decoded is! Map<String, dynamic>) return const [];

    final features = decoded['features'];
    if (features is! List) return const [];

    final lines = <GlobePolyline>[];

    void addLine(List<dynamic> coords, {bool closed = false}) {
      if (coords.length < 2) return;
      final points = <LatLng>[];
      for (final c in coords) {
        if (c is! List || c.length < 2) continue;
        final lng = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        points.add(LatLng(lat, lng));
      }
      if (points.length >= 2) {
        lines.add(
          GlobePolyline(
            points: points,
            color: color,
            strokeWidth: strokeWidth,
            closed: closed,
          ),
        );
      }
    }

    for (final feature in features) {
      if (feature is! Map<String, dynamic>) continue;
      final geometry = feature['geometry'];
      if (geometry is! Map<String, dynamic>) continue;

      final type = geometry['type'];
      final coords = geometry['coordinates'];
      if (coords is! List) continue;

      switch (type) {
        case 'LineString':
          addLine(coords);
        case 'MultiLineString':
          for (final part in coords) {
            if (part is List) addLine(part);
          }
        case 'Polygon':
          // Only the outer ring; holes would need a real fill rule.
          if (coords.isNotEmpty && coords.first is List) {
            addLine(coords.first as List, closed: true);
          }
        case 'MultiPolygon':
          for (final polygon in coords) {
            if (polygon is List &&
                polygon.isNotEmpty &&
                polygon.first is List) {
              addLine(polygon.first as List, closed: true);
            }
          }
      }
    }

    return lines;
  }
}
