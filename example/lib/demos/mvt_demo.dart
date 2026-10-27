/// MVT vector tiles on the globe: fill + outline + dashed `geolines`.
///
/// Everything here works in a browser: the tiles come from
/// `demotiles.maplibre.org`, which serves CORS headers. The base map is the
/// offline `DebugTilesSource.labeled`, so tile boundaries and the vector
/// geometry are visible in the same frame — if they disagree, placement is
/// wrong.
library;

import 'package:flutter/material.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

import 'demo_common.dart';

const String _tileUrl = 'https://demotiles.maplibre.org/tiles/{z}/{x}/{y}.pbf';

/// Same style as MapLibre's demo: countries coloured by `CONTINENT`, white
/// outlines, dashed `geolines`. Data-driven paint is the point of the `match`
/// expression — it exercises the per-colour batching path.
final Map<String, Object?> _styleJson = {
  'version': 8,
  'sources': {
    'demo': {
      'type': 'vector',
      'url': 'https://demotiles.maplibre.org/tiles/tiles.json',
    },
  },
  'layers': [
    {
      'id': 'countries-fill',
      'type': 'fill',
      'source': 'demo',
      'source-layer': 'countries',
      'paint': {
        'fill-color': [
          'match', ['get', 'CONTINENT'],
          'Asia', '#ff4081',
          'Europe', '#40c4ff',
          'Africa', '#ffab40',
          'North America', '#69f0ae',
          'South America', '#b388ff',
          'Oceania', '#ffd740',
          '#9e9e9e',
        ],
        'fill-opacity': 0.35,
      },
    },
    {
      'id': 'countries-outline',
      'type': 'line',
      'source': 'demo',
      'source-layer': 'countries',
      'paint': {
        'line-color': '#ffffff',
        'line-width': [
          'interpolate', ['linear'], ['zoom'], 0, 0.4, 6, 1.4,
        ],
        'line-opacity': 0.7,
      },
    },
    {
      'id': 'geolines',
      'type': 'line',
      'source': 'demo',
      'source-layer': 'geolines',
      'paint': {
        'line-color': '#ffd740',
        'line-width': 1.2,
        'line-dasharray': [4, 3],
        'line-opacity': 0.6,
      },
    },
  ],
};

class MvtDemoPage extends StatefulWidget {
  const MvtDemoPage({super.key});

  @override
  State<MvtDemoPage> createState() => _MvtDemoPageState();
}

class _MvtDemoPageState extends State<MvtDemoPage> {
  /// Demo tiles only exist up to z6; deeper zooms overzoom from there.
  late final HttpTileSource _vectorSource = HttpTileSource(
    urlTemplate: _tileUrl,
    scheme: TileSchemeKind.webMercator,
    minZoom: 0,
    maxZoom: 6,
    attribution: '© MapLibre demo tiles',
  );
  late final DebugTilesSource _base = DebugTilesSource.labeled(maxZoom: 8);

  late final StyleSpec _style = StyleSpec.parse(_styleJson);

  bool _globe = true;
  bool _copies = true;
  bool _graticule = false;
  MvtDiagnostics? _diag;

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'MVT 矢量瓦片',
      hint: 'countries 填充按 CONTINENT 上色 · 白描边 · geolines 虚线；'
          '底图是离线的 labeled 调试瓦片，可直接核对摆放。',
      detail: _diag == null
          ? '矢量: loading…'
          : '矢量: z${_diag!.dataZoom} · ${_diag!.readyCount}/${_diag!.tileCount} tiles'
              '${_diag!.failedCount > 0 ? ' · failed ${_diag!.failedCount}' : ''}'
              '${_diag!.firstFailed == null ? '' : ' (${_diag!.firstFailed})'}',
      controls: [
        DemoChip(
          label: '3D',
          selected: _globe,
          onChanged: (v) => setState(() => _globe = v),
        ),
        DemoChip(
          label: '重复世界',
          selected: _copies,
          onChanged: (v) => setState(() => _copies = v),
        ),
        DemoChip(
          label: '经纬网',
          selected: _graticule,
          onChanged: (v) => setState(() => _graticule = v),
        ),
      ],
      child: GeoMap(
        options: GeoMapOptions(
          initialCenter: const LatLng(25, 100),
          initialZoom: 2.2,
          minZoom: 0,
          maxZoom: 8,
          useGlobe: _globe,
          background: kDemoBackground,
        ),
        source: _base,
        children: [
          MvtVectorLayer(
            source: _vectorSource,
            style: _style,
            renderWorldCopies: _copies,
            onDiagnostics: (d) {
              if (!mounted) return;
              setState(() => _diag = d);
            },
          ),
          if (_graticule) GlobeVectorLayer(lines: _graticuleLines),
        ],
      ),
    );
  }
}

/// Built once: `buildGraticule` allocates ~35k points.
final List<GlobePolyline> _graticuleLines = buildGraticule();
