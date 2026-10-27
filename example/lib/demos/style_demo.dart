/// Style spec (M1) with inline GeoJSON: no network at all.
///
/// Exercises: `filter` (the water polygon is rejected by the fill layer),
/// `interpolate` by zoom (fill colour and line width both change as you zoom),
/// and data-driven grouping.
library;

import 'package:flutter/material.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

import 'demo_common.dart';
import 'grid_tile_source.dart';

final StyleSpec _style = StyleSpec.parse({
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
          2, '#1e6fd9',
          9, '#2fe39a',
        ],
        'fill-opacity': 0.45,
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
          2, 1.0,
          9, 5.0,
        ],
      },
    },
  ],
});

/// One feature list per style source — a `line` layer must not stroke the
/// polygons of a different source (that shows up as a stray orange outline).
final Map<String, List<GeoJsonFeature>> _sources = {
  'parcels': parseGeoJsonFeatures({
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
        // Filtered out by the fill layer (`use != park`): proves filters work.
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
    ],
  }),
  'roads': parseGeoJsonFeatures({
    'type': 'FeatureCollection',
    'features': [
      {
        // A long edge with only two vertices: on the globe it must be split in
        // Mercator space, otherwise it cuts through the sphere.
        'type': 'Feature',
        'properties': {'name': 'demo road'},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [90.0, 20.0], [120.0, 35.0],
          ],
        },
      },
      {
        'type': 'Feature',
        'properties': {'name': 'ring road'},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [105.0, 30.2], [106.4, 30.2], [106.4, 31.0], [105.0, 31.0],
            [105.0, 30.2],
          ],
        },
      },
    ],
  }),
};

class StyleDemoPage extends StatefulWidget {
  static const String route = "/style";

  const StyleDemoPage({super.key});

  @override
  State<StyleDemoPage> createState() => _StyleDemoPageState();
}

class _StyleDemoPageState extends State<StyleDemoPage> {
  final GridTileSource _base = GridTileSource();
  bool _globe = false;

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: '样式图层（style spec）',
      hint: '内联 GeoJSON + style JSON，零网络。park 面被 filter 接受、water 被拒绝；'
          '颜色与线宽随 zoom 插值。',
      detail: '填充 filter: ["==", "use", "park"] · 线长边两顶点（球面上靠细分贴球）',
      controls: [
        DemoChip(
          label: '3D',
          selected: _globe,
          onChanged: (v) => setState(() => _globe = v),
        ),
      ],
      child: GeoMap(
        options: GeoMapOptions(
          initialCenter: const LatLng(30.55, 105.2),
          initialZoom: 6.4,
          minZoom: 0,
          maxZoom: 8,
          useGlobe: _globe,
          background: kDemoBackground,
        ),
        source: _base,
        children: [
          StyleVectorLayer.ofSources(style: _style, sources: _sources),
        ],
      ),
    );
  }
}
