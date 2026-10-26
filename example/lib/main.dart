import 'package:flutter/material.dart';

import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final source = await MbtilesTileSource.open(
    id: 'base',
    // 把你的 MBTiles 放进 assets/tiles/base.mbtiles（真实层级自动探测）
    assetPath: '/assets/tiles/esri_satellite_z1-8.mbtiles',
  );
  runApp(GeoMapExampleApp(source: source));
}

class GeoMapExampleApp extends StatefulWidget {
  const GeoMapExampleApp({required this.source, super.key});

  final MbtilesTileSource source;

  @override
  State<GeoMapExampleApp> createState() => _GeoMapExampleAppState();
}

class _GeoMapExampleAppState extends State<GeoMapExampleApp> {
  late final GeoMapController _controller = GeoMapController(
    initialCenter: const LatLng(30, 105),
    initialZoom: 4.2,
    minZoom: widget.source.minZoom.toDouble(),
    maxZoom: widget.source.maxZoom.toDouble(),
  );
  bool _useGlobe = true;
  bool _graticule = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            GeoMap(
              controller: _controller,
              source: widget.source,
              options: GeoMapOptions(
                initialCenter: _controller.center,
                initialZoom: _controller.zoom,
                minZoom: widget.source.minZoom.toDouble(),
                maxZoom: widget.source.maxZoom.toDouble(),
                useGlobe: _useGlobe,
              ),
              children: [
                if (_graticule) GlobeVectorLayer(lines: buildGraticule()),
              ],
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilterChip(
                        label: const Text('3D'),
                        selected: _useGlobe,
                        onSelected: (v) => setState(() => _useGlobe = v),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('经纬网'),
                        selected: _graticule,
                        onSelected: (v) => setState(() => _graticule = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
