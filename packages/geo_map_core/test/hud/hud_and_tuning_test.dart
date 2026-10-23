import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  group('hud snapshot', () {
    test('formats centre, zoom and radius', () {
      final hud = HudSnapshot.of(
        center: const LatLng(54.234, 81.234),
        zoom: 4.93,
        projectorKind: 'orthographic',
        schemeName: 'webMercator',
        visibleTiles: 42,
      );
      final lines = hud.formatHud();
      expect(lines.first, contains('球面投影'));
      expect(lines[1], contains('54.2'));
      expect(lines[1], contains('81.2'));
      expect(lines[1], contains('zoom 4.93'));
      expect(lines[1], contains('R 1242px'));
      expect(lines[2], contains('可见瓦片 42'));
    });

    test('radius follows the shared zoom scale', () {
      final hud = HudSnapshot.of(
        center: const LatLng(0, 0),
        zoom: 5,
        projectorKind: 'mercator',
        schemeName: 'webMercator',
        visibleTiles: 1,
      );
      expect(hud.radiusPx, closeTo(256 * 32 / 6.283185307179586, 1e-6));
    });

    test('warns about the polar cap only for mercator data', () {
      final merc = HudSnapshot.of(
        center: const LatLng(88, 0),
        zoom: 3,
        projectorKind: 'orthographic',
        schemeName: 'webMercator',
        visibleTiles: 4,
      );
      expect(merc.polarWarning, isTrue);
      expect(merc.formatHud().any((l) => l.contains('极区无瓦片')), isTrue);

      final geo = HudSnapshot.of(
        center: const LatLng(88, 0),
        zoom: 3,
        projectorKind: 'orthographic',
        schemeName: 'epsg4326',
        visibleTiles: 4,
      );
      expect(geo.polarWarning, isFalse);
    });

    test('reports an unready source with the fallback level', () {
      final hud = HudSnapshot(
        center: const LatLng(0, 0),
        zoom: 3,
        radiusPx: 100,
        projectorKind: 'orthographic',
        schemeName: 'webMercator',
        visibleTiles: 0,
        sourceReady: false,
        fallbackLevel: 2,
      );
      expect(hud.formatHud().any((l) => l.contains('回退层级 2')), isTrue);
    });

    test('appends the tapped coordinate in 2 decimals', () {
      final hud = HudSnapshot.of(
        center: const LatLng(30, 100),
        zoom: 4,
        projectorKind: 'mercator',
        schemeName: 'webMercator',
        visibleTiles: 8,
        tap: const LatLng(39.9042, 116.4074),
      );
      final last = hud.formatHud().last;
      expect(last, contains('39.90'));
      expect(last, contains('116.41'));
    });

    test('flat projection title', () {
      final hud = HudSnapshot.of(
        center: const LatLng(0, 0),
        zoom: 2,
        projectorKind: 'mercator',
        schemeName: 'webMercator',
        visibleTiles: 2,
      );
      expect(hud.projectionTitle, contains('Web Mercator'));
    });
  });

  group('tuning contract', () {
    test('constants stay locked (change with intent only)', () {
      expect(GeoEngineTuning.epsDepth, 0.02);
      expect(GeoEngineTuning.maxCameraLatitude, 89.999);
      expect(GeoEngineTuning.pickZoomCosFloor, 0.2);
      expect(GeoEngineTuning.tileSize, 256);
      expect(GeoEngineTuning.densifyPixelError, 0.5);
      expect(GeoEngineTuning.selectMargin, 64);
      expect(GeoEngineTuning.subdivMin, 6);
      expect(GeoEngineTuning.subdivMax, 16);
      expect(GeoEngineTuning.subdivPx, 20);
      expect(GeoEngineTuning.cacheBudgetBytes, 96 << 20);
      expect(GeoEngineTuning.tapSlopPx, 12);
      expect(GeoEngineTuning.tileRequestDebounceMillis, 120);
    });

    test('tile size is the single source of truth for zoom scale', () {
      final c = CameraState(
        center: const LatLng(0, 0),
        zoom: 2,
        size: const ViewportSize(800, 600),
      );
      expect(c.worldSize, GeoEngineTuning.tileSize * 4);
    });
  });
}
