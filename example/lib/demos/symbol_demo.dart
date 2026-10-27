/// Symbol layer demo: labels with collision avoidance.
///
/// The interesting part is not that text appears — it is what happens when it
/// does **not**. Every city below is a candidate; the placer (core
/// `SymbolPlacer`, a port of MapLibre's `CollisionIndex`) decides which ones are
/// drawn, so labels thin out as you zoom out instead of piling into a smear.
///
/// Three things to try:
/// * zoom in and out — `rank` gates density through a `filter`, the way real
///   styles do it (`["<=", ["get", "rank"], ["+", ["zoom"], 1]]`);
/// * **允许重叠** → `text-allow-overlap`, every label is drawn regardless of
///   overlaps;
/// * **不占位** → `text-ignore-placement`, a label stops pushing others aside
///   (but it can still be hidden by one that is already placed — that asymmetry
///   is exactly MapLibre's).
library;

import 'package:flutter/material.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

import 'demo_common.dart';
import 'grid_tile_source.dart';

/// `(name, nameEn, lat, lng, rank)` — rank 1 is always shown, 2/3/4 need more
/// zoom. Both names travel as properties so the demo can switch `text-field`.
const List<(String, String, double, double, int)> _cities = [
  ('北京', 'Beijing', 39.90, 116.41, 1),
  ('上海', 'Shanghai', 31.23, 121.47, 1),
  ('广州', 'Guangzhou', 23.13, 113.26, 1),
  ('成都', 'Chengdu', 30.66, 104.07, 1),
  ('重庆', 'Chongqing', 29.56, 106.55, 1),
  ('武汉', 'Wuhan', 30.59, 114.31, 1),
  ('西安', 'Xian', 34.34, 108.94, 2),
  ('沈阳', 'Shenyang', 41.80, 123.43, 2),
  ('昆明', 'Kunming', 25.04, 102.72, 2),
  ('乌鲁木齐', 'Urumqi', 43.83, 87.62, 2),
  ('哈尔滨', 'Harbin', 45.80, 126.53, 2),
  ('青岛', 'Qingdao', 36.07, 120.38, 2),
  ('郑州', 'Zhengzhou', 34.75, 113.63, 2),
  ('长沙', 'Changsha', 28.23, 112.94, 2),
  ('南京', 'Nanjing', 32.06, 118.80, 2),
  ('杭州', 'Hangzhou', 30.27, 120.16, 2),
  ('天津', 'Tianjin', 39.08, 117.20, 2),
  ('拉萨', 'Lhasa', 29.65, 91.14, 3),
  ('福州', 'Fuzhou', 26.07, 119.30, 3),
  ('南宁', 'Nanning', 22.82, 108.32, 3),
  ('兰州', 'Lanzhou', 36.06, 103.83, 3),
  ('呼和浩特', 'Hohhot', 40.84, 111.75, 3),
  ('银川', 'Yinchuan', 38.49, 106.23, 3),
  ('西宁', 'Xining', 36.62, 101.78, 3),
  ('贵阳', 'Guiyang', 26.65, 106.63, 3),
  ('南昌', 'Nanchang', 28.68, 115.86, 3),
  ('太原', 'Taiyuan', 37.87, 112.55, 3),
  ('石家庄', 'Shijiazhuang', 38.04, 114.51, 3),
  ('合肥', 'Hefei', 31.82, 117.23, 3),
  ('台北', 'Taipei', 25.03, 121.57, 3),
  ('海口', 'Haikou', 20.04, 110.32, 4),
  ('三亚', 'Sanya', 18.25, 109.51, 4),
];

final Map<String, List<GeoJsonFeature>> _sources = {
  'cities': [
    for (final (name, nameEn, lat, lng, rank) in _cities)
      GeoJsonFeature(
        geometry: PointGeometry(LatLng(lat, lng)),
        properties: {'name': name, 'name_en': nameEn, 'rank': rank},
      ),
  ],
};

final List<LatLng> _dots = [
  for (final (_, _, lat, lng, _) in _cities) LatLng(lat, lng),
];

/// The style as JSON so a toggle can splice a layout flag in without rebuilding
/// the expression tree by hand.
Map<String, Object?> _styleJson({
  bool allowOverlap = false,
  bool ignorePlacement = false,
  bool english = false,
}) =>
    {
      'version': 8,
      'sources': {
        'cities': {'type': 'geojson'},
      },
      'layers': [
        {
          'id': 'city-label',
          'type': 'symbol',
          'source': 'cities',
          // Zoom-dependent density: a higher zoom admits higher ranks.
          'filter': [
            '<=', ['get', 'rank'], ['+', ['zoom'], 1]
          ],
          'layout': {
            // `text-field` is just an expression, so switching language is one
            // property change. (On web, CJK glyphs need Flutter's Noto fallback,
            // which is downloaded at runtime — a headless browser without that
            // download shows tofu boxes, Latin does not.)
            'text-field': ['get', english ? 'name_en' : 'name'],
            'text-size': [
              'interpolate', ['linear'], ['zoom'],
              2, 11,
              5, 14,
              8, 18,
            ],
            // Lower rank wins the space when two labels collide.
            'symbol-sort-key': ['get', 'rank'],
            if (allowOverlap) 'text-allow-overlap': true,
            if (ignorePlacement) 'text-ignore-placement': true,
          },
          'paint': {
            'text-color': '#ffffff',
            'text-halo-color': '#0b1a2a',
            'text-halo-width': 1.6,
          },
        },
      ],
    };

class SymbolDemoPage extends StatefulWidget {
  const SymbolDemoPage({super.key});

  static const String route = '/symbol';

  @override
  State<SymbolDemoPage> createState() => _SymbolDemoPageState();
}

class _SymbolDemoPageState extends State<SymbolDemoPage> {
  final GridTileSource _base = GridTileSource();
  bool _globe = false;
  bool _allowOverlap = false;
  bool _ignorePlacement = false;
  bool _dotsOn = true;
  bool _english = false;

  StyleSpec get _style => StyleSpec.parse(_styleJson(
        allowOverlap: _allowOverlap,
        ignorePlacement: _ignorePlacement,
        english: _english,
      ));

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: '符号标注 · 碰撞避让',
      hint: '32 个候选标注，缩放时按 rank 与 25px 碰撞网格决定谁可见。'
          '「允许重叠」看全部；「不占位」看标注不再互相挤开。',
      detail: _allowOverlap
          ? 'text-allow-overlap: 全部绘制，盒子不参与碰撞'
          : _ignorePlacement
              ? 'text-ignore-placement: 不挤别人，但仍会被已放置的挡住'
              : '默认: 先到先得（rank 小的先占位），放不下的直接丢弃',
      controls: [
        DemoChip(
          label: '3D',
          selected: _globe,
          onChanged: (v) => setState(() => _globe = v),
        ),
        DemoChip(
          label: '允许重叠',
          selected: _allowOverlap,
          onChanged: (v) => setState(() => _allowOverlap = v),
        ),
        DemoChip(
          label: '不占位',
          selected: _ignorePlacement,
          onChanged: (v) => setState(() => _ignorePlacement = v),
        ),
        DemoChip(
          label: '英文',
          selected: _english,
          onChanged: (v) => setState(() => _english = v),
        ),
        DemoChip(
          label: '锚点',
          selected: _dotsOn,
          onChanged: (v) => setState(() => _dotsOn = v),
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
        children: [
          StyleVectorLayer.ofSources(style: _style, sources: _sources),
          if (_dotsOn)
            GlobeVectorLayer(
              lines: const [],
              dots: _dots,
              dotRadius: 2.4,
              dotColor: const Color(0xFF7FDCA4),
            ),
        ],
      ),
    );
  }
}
