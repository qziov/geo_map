/// HUD value model: all formatting lives here so it can be asserted from pure
/// Dart tests (the widget layer just prints the strings).
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../math/projections.dart';
import '../tuning/geo_engine_tuning.dart';

class HudSnapshot {
  const HudSnapshot({
    required this.center,
    required this.zoom,
    required this.radiusPx,
    required this.projectorKind,
    required this.schemeName,
    this.visibleTiles,
    this.cameraSource = 'delegate',
    this.tap,
    this.fallbackLevel = 0,
    this.sourceReady = true,
  });

  final LatLng center;
  final double zoom;
  final double radiusPx;
  final String projectorKind; // 'mercator' | 'orthographic'
  final String schemeName; // 'webMercator' | 'epsg4326'

  /// `null` → the HUD omits the tile-count segment entirely.
  final int? visibleTiles;
  final String cameraSource;
  final LatLng? tap;
  final int fallbackLevel;
  final bool sourceReady;

  String get projectionTitle =>
      projectorKind == 'orthographic' ? '球面投影（正交）' : '平面投影（Web Mercator）';

  bool get polarWarning =>
      center.latitude.abs() > mercatorMaxLatitude && schemeName == 'webMercator';

  /// Lines rendered by the HUD overlay, in order.
  List<String> formatHud() {
    final lines = <String>[
      projectionTitle,
      'center ${center.latitude.toStringAsFixed(1)}, '
          '${center.longitude.toStringAsFixed(1)}   '
          'zoom ${zoom.toStringAsFixed(2)}   '
          'R ${radiusPx.round()}px',
      if (visibleTiles != null)
        '相机: $cameraSource · 网格: $schemeName · 可见瓦片 $visibleTiles'
      else
        '相机: $cameraSource · 网格: $schemeName',
    ];
    if (!sourceReady) {
      lines.add('底图源未就绪${fallbackLevel > 0 ? '（回退层级 $fallbackLevel）' : ''}');
    }
    if (polarWarning) {
      lines.add('极区无瓦片（mercator 数据止于 ±85.0511°）');
    }
    final t = tap;
    if (t != null) {
      lines.add(
          '点击 ${t.latitude.toStringAsFixed(2)}, ${t.longitude.toStringAsFixed(2)}');
    }
    return lines;
  }

  factory HudSnapshot.of({
    required LatLng center,
    required double zoom,
    required String projectorKind,
    required String schemeName,
    int? visibleTiles,
    String cameraSource = 'delegate',
    LatLng? tap,
    int fallbackLevel = 0,
    bool sourceReady = true,
  }) {
    final worldSize = GeoEngineTuning.tileSize * math.pow(2, zoom);
    return HudSnapshot(
      center: center,
      zoom: zoom,
      radiusPx: worldSize / (2 * math.pi),
      projectorKind: projectorKind,
      schemeName: schemeName,
      visibleTiles: visibleTiles,
      cameraSource: cameraSource,
      tap: tap,
      fallbackLevel: fallbackLevel,
      sourceReady: sourceReady,
    );
  }
}
