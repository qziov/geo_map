/// Feature query demo: click the map, find out what you hit.
///
/// The map draws a handful of points and two **overlapping** areas. Tapping
/// runs `GeoFeatureRegistry.queryFeatures` and the panel lists what came back
/// — the point that was closest, and every area that contains the tap.
///
/// Three things to try:
/// * tap a city → one point hit, with its pixel distance;
/// * tap where the two areas overlap → **two** area hits (a query returns
///   every match, not just the closest one);
/// * switch to 3D → a point on the far side of the globe is no longer
///   pickable, even though it is still "visible" to `isVisible`.
///
/// The query runs on **both** the flat map and the globe, and the point
/// strategy is screen-space (a 24 px radius), so a city stays grabbable at
/// any zoom.
library;

import 'package:flutter/material.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

import 'demo_common.dart';
import 'grid_tile_source.dart';

/// The point features. Their ids are the city's name, so a hit can be read
/// straight off the query result.
final List<GeoJsonFeature> _pointFeatures = [
  for (final (name, lat, lng) in <(String, double, double)>[
    ('北京', 39.90, 116.41),
    ('上海', 31.23, 121.47),
    ('广州', 23.13, 113.26),
    ('成都', 30.66, 104.07),
    ('武汉', 30.59, 114.31),
    ('西安', 34.34, 108.94),
    ('拉萨', 29.65, 91.14),
    ('哈尔滨', 45.80, 126.53),
  ])
    GeoJsonFeature(
      id: name,
      geometry: PointGeometry(LatLng(lat, lng)),
      properties: <String, Object?>{'name': name},
    ),
];

final List<LatLng> _dots = [
  for (final f in _pointFeatures)
    (f.geometry as PointGeometry).point,
];

/// Two areas that **overlap** around central China, so a tap in the
/// overlap returns two hits.
final List<GeoJsonFeature> _areaFeatures = [
  GeoJsonFeature(
    id: 'area-west',
    geometry: PolygonGeometry(<List<LatLng>>[
      <LatLng>[
        const LatLng(26, 96),
        const LatLng(26, 110),
        const LatLng(38, 110),
        const LatLng(38, 96),
        const LatLng(26, 96),
      ],
    ]),
  ),
  GeoJsonFeature(
    id: 'area-east',
    geometry: PolygonGeometry(<List<LatLng>>[
      <LatLng>[
        const LatLng(26, 104),
        const LatLng(26, 122),
        const LatLng(38, 122),
        const LatLng(38, 104),
        const LatLng(26, 104),
      ],
    ]),
  ),
];

/// The areas are drawn with the ordinary style layer; the query does not
/// care how they are rendered.
final StyleSpec _areaStyle = StyleSpec.parse(<String, Object?>{
  'version': 8,
  'sources': {
    'areas': {'type': 'geojson'},
  },
  'layers': [
    {
      'id': 'area-fill',
      'type': 'fill',
      'source': 'areas',
      'paint': {
        'fill-color': '#3a7afe',
        'fill-opacity': 0.22,
      },
    },
    {
      'id': 'area-line',
      'type': 'line',
      'source': 'areas',
      'paint': {
        'line-color': '#7fb0ff',
        'line-width': 1.4,
        'line-opacity': 0.9,
      },
    },
  ],
});

class QueryDemoPage extends StatefulWidget {
  const QueryDemoPage({super.key});

  static const String route = '/query';

  @override
  State<QueryDemoPage> createState() => _QueryDemoPageState();
}

class _QueryDemoPageState extends State<QueryDemoPage> {
  final GridTileSource _base = GridTileSource();

  /// The camera the query projects against. Owned by the page, so the same
  /// instance must be handed to `GeoMap`.
  late final GeoMapController _controller = GeoMapController(
    useGlobe: false,
    initialCenter: const LatLng(34, 108),
    initialZoom: 3.6,
    minZoom: 1,
    maxZoom: 8,
  );

  /// The registry is a **snapshot**: the features never change here, so it is
  /// filled once. A real app rebuilds it when its data changes.
  final GeoFeatureRegistry _registry = GeoFeatureRegistry()
    ..setSource('cities', _pointFeatures)
    ..setSource('areas', _areaFeatures);

  bool _globe = false;
  bool _points = true;
  bool _areas = true;
  String? _tap;
  List<GeoQueryHit> _hits = const <GeoQueryHit>[];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Set<GeoGeometryKind> get _kinds => {
        if (_points) GeoGeometryKind.point,
        if (_areas) GeoGeometryKind.polygon,
      };

  void _onTap(LatLng latLng) {
    final hits = _registry.queryFeatures(
      latLng,
      controller: _controller,
      geometries: _kinds,
    );
    setState(() {
      _tap = '${latLng.latitude.toStringAsFixed(2)}, '
          '${latLng.longitude.toStringAsFixed(2)}';
      _hits = hits;
    });
  }

  String get _detail {
    if (_tap == null) return '点击地图查询命中的要素';
    if (_hits.isEmpty) return '点击 ($_tap) —— 没有命中任何要素';
    final lines = <String>['点击 ($_tap) —— 命中 ${_hits.length} 条'];
    for (final hit in _hits) {
      final distance = hit.distancePx;
      lines.add('  · ${hit.sourceId} / ${hit.feature.id}'
          '${distance == null ? '（面）' : '（${distance.toStringAsFixed(1)}px）'}');
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: '要素查询 · queryRenderedFeatures',
      hint: '点按地图：点要素按 24px 屏幕半径命中，面要素按地理空间判定。'
          '两个面故意重叠 —— 重叠处会一次返回两条。',
      detail: _detail,
      controls: [
        DemoChip(
          label: '3D',
          selected: _globe,
          onChanged: (v) => setState(() => _globe = v),
        ),
        DemoChip(
          label: '点',
          selected: _points,
          onChanged: (v) => setState(() => _points = v),
        ),
        DemoChip(
          label: '面',
          selected: _areas,
          onChanged: (v) => setState(() => _areas = v),
        ),
      ],
      child: GeoMap(
        options: GeoMapOptions(
          initialCenter: const LatLng(34, 108),
          initialZoom: 3.6,
          minZoom: 1,
          maxZoom: 8,
          useGlobe: _globe,
          background: kDemoBackground,
        ),
        source: _base,
        controller: _controller,
        onTap: _onTap,
        children: [
          StyleVectorLayer.ofSources(
            style: _areaStyle,
            sources: <String, List<GeoJsonFeature>>{'areas': _areaFeatures},
          ),
          GlobeVectorLayer(
            lines: const [],
            dots: _dots,
            dotRadius: 3,
            dotColor: const Color(0xFF7FDCA4),
          ),
        ],
      ),
    );
  }
}
