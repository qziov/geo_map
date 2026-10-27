/// Screen-space overlays drawn through the same projector as the tiles:
/// graticule, Tissot indicatrices, a great-circle route and point markers.
///
/// Offline. The Tissot circles are the projection's own test: on a correct
/// orthographic globe they stay circular at the centre of the disc and squash
/// into ellipses towards the limb.
library;

import 'package:flutter/material.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

import 'demo_common.dart';

final List<GlobePolyline> _graticule = buildGraticule();
final List<GlobePolyline> _tissot = buildTissot();

/// London → Sydney, densified along the great circle (this one *should* be a
/// geodesic: it is a route, not a parallel).
final List<GlobePolyline> _route = [
  GlobePolyline(
    points: densifyPath(const [LatLng(51.51, -0.13), LatLng(-33.87, 151.21)]),
    color: const Color(0xFFFF5252),
    strokeWidth: 2,
  ),
];

final List<LatLng> _gridDots = [
  for (var lat = -75; lat <= 75; lat += 15)
    for (var lng = -180; lng < 180; lng += 15) LatLng(lat.toDouble(), lng.toDouble()),
];

class OverlayDemoPage extends StatefulWidget {
  const OverlayDemoPage({super.key});

  @override
  State<OverlayDemoPage> createState() => _OverlayDemoPageState();
}

class _OverlayDemoPageState extends State<OverlayDemoPage> {
  final DebugTilesSource _base = DebugTilesSource.labeled(maxZoom: 8);
  bool _graticuleOn = true;
  bool _tissotOn = true;
  bool _routeOn = true;
  bool _dotsOn = false;

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: '球面叠加层',
      hint: '经纬网 / Tissot 指示圆 / 大圆航线 / 网格点。全部走同一个投影器，'
          '边缘处会被地平线裁掉。',
      detail: 'Tissot：中心是圆、边缘被压成椭圆 = 正交投影正确',
      controls: [
        DemoChip(
          label: '经纬网',
          selected: _graticuleOn,
          onChanged: (v) => setState(() => _graticuleOn = v),
        ),
        DemoChip(
          label: 'Tissot',
          selected: _tissotOn,
          onChanged: (v) => setState(() => _tissotOn = v),
        ),
        DemoChip(
          label: '大圆',
          selected: _routeOn,
          onChanged: (v) => setState(() => _routeOn = v),
        ),
        DemoChip(
          label: '点',
          selected: _dotsOn,
          onChanged: (v) => setState(() => _dotsOn = v),
        ),
      ],
      child: GeoMap(
        options: const GeoMapOptions(
          initialCenter: LatLng(20, 100),
          initialZoom: 1.7,
          minZoom: 0,
          maxZoom: 8,
          useGlobe: true,
          background: kDemoBackground,
        ),
        source: _base,
        children: [
          GlobeVectorLayer(
            lines: [
              if (_graticuleOn) ..._graticule,
              if (_tissotOn) ..._tissot,
              if (_routeOn) ..._route,
            ],
            dots: _dotsOn ? _gridDots : const [],
          ),
        ],
      ),
    );
  }
}
