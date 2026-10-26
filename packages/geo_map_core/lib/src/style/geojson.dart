/// Minimal GeoJSON Feature/FeatureCollection parsing for the M1 vector layer.
///
/// Keeps feature **properties** (which the style filter and data-driven
/// expressions need) and the geometry in lat/lng rings. Only the geometry types
/// the M1 renderer understands are produced; others are skipped.
library;

import 'package:latlong2/latlong.dart';

sealed class GeoJsonGeometry {
  const GeoJsonGeometry();
}

class PointGeometry extends GeoJsonGeometry {
  const PointGeometry(this.point);
  final LatLng point;
}

class LineStringGeometry extends GeoJsonGeometry {
  const LineStringGeometry(this.points);
  final List<LatLng> points;
}

class PolygonGeometry extends GeoJsonGeometry {
  const PolygonGeometry(this.rings);
  final List<List<LatLng>> rings;
}

class MultiLineStringGeometry extends GeoJsonGeometry {
  const MultiLineStringGeometry(this.lines);
  final List<List<LatLng>> lines;
}

class MultiPolygonGeometry extends GeoJsonGeometry {
  const MultiPolygonGeometry(this.polygons);
  final List<List<List<LatLng>>> polygons;
}

class GeoJsonFeature {
  const GeoJsonFeature({
    this.id,
    this.properties = const {},
    required this.geometry,
  });

  final String? id;
  final Map<String, Object?> properties;
  final GeoJsonGeometry geometry;
}

/// Parse a GeoJSON `FeatureCollection` or a single `Feature`.
List<GeoJsonFeature> parseGeoJsonFeatures(Map<String, Object?> json) {
  final type = json['type'];
  if (type == 'FeatureCollection') {
    final feats = json['features'];
    if (feats is! List) return const [];
    final out = <GeoJsonFeature>[];
    for (final f in feats) {
      if (f is Map) {
        final parsed = _parseFeature(Map<String, Object?>.from(f));
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }
  if (type == 'Feature') {
    final parsed = _parseFeature(json);
    return parsed == null ? const [] : [parsed];
  }
  return const [];
}

GeoJsonFeature? _parseFeature(Map<String, Object?> f) {
  final rawGeometry = f['geometry'];
  if (rawGeometry is! Map) return null;
  final geometry = _parseGeometry(Map<String, Object?>.from(rawGeometry));
  if (geometry == null) return null;
  final rawProps = f['properties'];
  return GeoJsonFeature(
    id: f['id']?.toString(),
    properties:
        rawProps is Map ? Map<String, Object?>.from(rawProps) : const {},
    geometry: geometry,
  );
}

GeoJsonGeometry? _parseGeometry(Map<String, Object?> g) {
  final type = g['type'];
  final coords = g['coordinates'];
  if (coords is! List) return null;
  switch (type) {
    case 'Point':
      return PointGeometry(_point(coords));
    case 'LineString':
      return LineStringGeometry(_line(coords));
    case 'Polygon':
      return PolygonGeometry(_rings(coords));
    case 'MultiLineString':
      return MultiLineStringGeometry([for (final l in coords) _line(l)]);
    case 'MultiPolygon':
      return MultiPolygonGeometry([for (final p in coords) _rings(p)]);
    default:
      return null;
  }
}

LatLng _point(Object? c) {
  final list = c as List;
  return LatLng(
    (list[1] as num).toDouble(),
    (list[0] as num).toDouble(),
  );
}

List<LatLng> _line(Object? c) => [for (final p in c as List) _point(p)];

List<List<LatLng>> _rings(Object? c) => [for (final r in c as List) _line(r)];
