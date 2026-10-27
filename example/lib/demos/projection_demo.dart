/// Projection switch and tile-placement debug: 2D Mercator vs 3D globe over the
/// offline `labeled` debug tiles, which print their own `z/x/y`.
///
/// The point is what *does not* change: one `TileEngine` serves both modes, so
/// switching reuses the decoded tiles instead of downloading them again.
library;

import 'package:flutter/material.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

import 'demo_common.dart';

class ProjectionDemoPage extends StatefulWidget {
  static const String route = "/projection";

  const ProjectionDemoPage({super.key});

  @override
  State<ProjectionDemoPage> createState() => _ProjectionDemoPageState();
}

class _ProjectionDemoPageState extends State<ProjectionDemoPage> {
  late final DebugTilesSource _source = DebugTilesSource.labeled(maxZoom: 6);
  bool _globe = true;
  bool _crosshair = true;

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: '投影切换 · 瓦片摆放',
      hint: '整级编号瓦片裁成 z/x/y 子块。切换 2D/3D 时视口中心与 zoom 保持连续，'
          '同一份瓦片缓存被两种投影复用。',
      detail: '瓦片图案上的数字 = 该级 zoom；拼缝对齐说明摆放正确',
      controls: [
        DemoChip(
          label: '3D 球面',
          selected: _globe,
          onChanged: (v) => setState(() => _globe = v),
        ),
        DemoChip(
          label: '中心点',
          selected: _crosshair,
          onChanged: (v) => setState(() => _crosshair = v),
        ),
      ],
      child: GeoMap(
        options: GeoMapOptions(
          initialCenter: const LatLng(30, 105),
          initialZoom: 2.0,
          minZoom: 0,
          maxZoom: 6,
          useGlobe: _globe,
          background: kDemoBackground,
        ),
        source: _source,
        children: [
          if (_crosshair)
            const GlobeVectorLayer(
              lines: [],
              dots: [LatLng(30, 105)],
              dotRadius: 4,
              dotColor: Color(0xFFFF5252),
            ),
        ],
      ),
    );
  }
}
