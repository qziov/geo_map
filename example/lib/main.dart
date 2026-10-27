/// geo_map example gallery.
///
/// Entry point for **web** (and desktop). Every page under `lib/demos/` is
/// browser-safe: no `dart:io`, no sqlite, and the only network use is
/// `demotiles.maplibre.org`, which serves CORS headers.
///
/// Demos that cannot run in a browser live in `lib/native/` with their own
/// `main()` (see the last card). They are never imported from here, so
/// `flutter build web` leaves them out of the bundle entirely.
library;

import 'package:flutter/material.dart';

import 'demos/demo_common.dart';
import 'demos/mvt_demo.dart';
import 'demos/overlay_demo.dart';
import 'demos/projection_demo.dart';
import 'demos/style_demo.dart';
import 'demos/symbol_demo.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'geo_map examples',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: kDemoBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7FDCA4),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(backgroundColor: kDemoBackground),
      ),
      // Named routes so every demo is a shareable URL (`/#/overlay`) — and so a
      // headless screenshot can reach one page without clicking.
      initialRoute: _GalleryPage.route,
      routes: {
        _GalleryPage.route: (_) => const _GalleryPage(),
        MvtDemoPage.route: (_) => const MvtDemoPage(),
        StyleDemoPage.route: (_) => const StyleDemoPage(),
        SymbolDemoPage.route: (_) => const SymbolDemoPage(),
        OverlayDemoPage.route: (_) => const OverlayDemoPage(),
        ProjectionDemoPage.route: (_) => const ProjectionDemoPage(),
      },
    );
  }
}

/// One entry in the gallery.
class _Demo {
  const _Demo({
    required this.title,
    required this.summary,
    required this.api,
    this.route,
    this.nativePath,
  });

  final String title;
  final String summary;

  /// The public API this demo is about.
  final String api;

  /// Route of the runnable page; `null` for native-only demos.
  final String? route;

  /// Where to read the native-only implementation.
  final String? nativePath;

  bool get isRunnable => route != null;
}

const List<_Demo> _demos = [
  _Demo(
    title: 'MVT 矢量瓦片',
    summary: 'fill / line / 虚线 / 数据驱动着色 / 世界副本 / 地平线裁剪',
    api: 'MvtVectorLayer · HttpTileSource · StyleSpec',
    route: "/mvt",
  ),
  _Demo(
    title: '样式图层',
    summary: '内联 GeoJSON + filter + 随 zoom 插值，零网络',
    api: 'StyleVectorLayer · parseGeoJsonFeatures',
    route: "/style",
  ),
  _Demo(
    title: '符号标注',
    summary: 'text-field / text-halo / 25px 碰撞网格 / allow-overlap / ignore-placement',
    api: 'symbol 图层 · buildMvtSymbolBucket · SymbolPlacer · SymbolPainter',
    route: "/symbol",
  ),
  _Demo(
    title: '球面叠加层',
    summary: '经纬网 / Tissot 指示圆 / 大圆航线 / 网格点',
    api: 'GlobeVectorLayer · buildGraticule · buildTissot · densifyPath',
    route: "/overlay",
  ),
  _Demo(
    title: '投影切换 · 瓦片摆放',
    summary: '2D Mercator ↔ 3D 球面，两种投影共用一份瓦片缓存',
    api: 'GeoMapOptions.useGlobe · DebugTilesSource',
    route: "/projection",
  ),
  _Demo(
    title: 'MBTiles 离线底图',
    summary: '需要 dart:io + sqlite3，浏览器里不可用 —— 只保留代码',
    api: 'MbtilesTileSource · GeoMapOptions',
    nativePath: 'lib/native/mbtiles_demo.dart',
  ),
];

class _GalleryPage extends StatelessWidget {
  const _GalleryPage();

  static const String route = '/';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('geo_map examples')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '标 web 的条目在浏览器里直接跑。标 native only 的依赖 dart:io，'
              '代码留在 lib/native/ 下，用 flutter run -t 运行。',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          for (final demo in _demos) _DemoCard(demo: demo),
        ],
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.demo});

  final _Demo demo;

  @override
  Widget build(BuildContext context) {
    final runnable = demo.isRunnable;
    return Card(
      color: kDemoPanel,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        title: Row(
          children: [
            Flexible(child: Text(demo.title)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: runnable
                    ? const Color(0x267FDCA4)
                    : const Color(0x26FF8A80),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                runnable ? 'web' : 'native only',
                style: TextStyle(
                  fontSize: 10,
                  color: runnable
                      ? const Color(0xFF7FDCA4)
                      : const Color(0xFFFF8A80),
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(demo.summary, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                demo.api,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Color(0xFF7FDCA4),
                ),
              ),
            ],
          ),
        ),
        trailing: Icon(runnable ? Icons.chevron_right : Icons.code,
            color: Colors.white38),
        onTap: () => _open(context),
      ),
    );
  }

  void _open(BuildContext context) {
    final route = demo.route;
    if (route != null) {
      Navigator.of(context).pushNamed(route);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kDemoPanel,
        title: const Text('native only'),
        content: Text(
          '${demo.title} 依赖 dart:io 与 sqlite3，浏览器里跑不了。\n\n'
          '实现在 ${demo.nativePath}，运行：\n'
          'flutter run -t ${demo.nativePath}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }
}
