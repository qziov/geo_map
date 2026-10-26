// A minimal style-spec demo (M1):
//
//   flutter run -t lib/style_demo.dart
//
// OSM raster base + one style JSON with a fill layer (filtered to parks,
// zoom-interpolated color) and a line layer (zoom-interpolated width).
import 'package:flutter/material.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(const StyleDemoApp());

class StyleDemoApp extends StatelessWidget {
  const StyleDemoApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: StyleDemoPage(),
      );
}

class StyleDemoPage extends StatelessWidget {
  const StyleDemoPage({super.key});

  static final StyleSpec _style = StyleSpec.parse({
    'version': 8,
    'sources': {
      'parcels': {'type': 'geojson'},
      'roads': {'type': 'geojson'},
    },
    'layers': [
      {
        'id': 'parcels-fill',
        'type': 'fill',
        'source': 'parcels',
        'filter': ['==', 'use', 'park'],
        'paint': {
          'fill-color': [
            'interpolate', ['linear'], ['zoom'],
            8, '#cfe8ff',
            16, '#1e6fd9',
          ],
          'fill-opacity': 0.55,
        },
      },
      {
        'id': 'roads-line',
        'type': 'line',
        'source': 'roads',
        'paint': {
          'line-color': '#ff7a00',
          'line-width': [
            'interpolate', ['linear'], ['zoom'],
            8, 1.5,
            16, 8,
          ],
        },
      },
    ],
  });

  static final List<GeoJsonFeature> _features = parseGeoJsonFeatures({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {'use': 'park'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [104.8, 30.4], [105.4, 30.4], [105.4, 30.9],
              [104.8, 30.9], [104.8, 30.4],
            ],
          ],
        },
      },
      {
        // Filtered out by the fill layer (`use != park`); proves filters work.
        'type': 'Feature',
        'properties': {'use': 'water'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [105.6, 30.2], [106.1, 30.2], [106.1, 30.6],
              [105.6, 30.6], [105.6, 30.2],
            ],
          ],
        },
      },
      {
        'type': 'Feature',
        'properties': {'name': 'demo road'},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [104.6, 30.1], [105.1, 30.6], [105.8, 30.7], [106.3, 30.3],
          ],
        },
      },
    ],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GeoMap(
        options: const GeoMapOptions(
          initialCenter: LatLng(30.55, 105.45),
          initialZoom: 8.6,
          minZoom: 2,
          maxZoom: 18,
          useGlobe: false,
        ),
        source: HttpTileSource.osm(),
        children: [
          StyleVectorLayer(style: _style, features: _features),
        ],
      ),
    );
  }
}
