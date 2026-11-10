// T5c camera animation contract tests.
//
// Pure math is tested directly; the Ticker-driven facade is pumped with
// `testWidgets` so no real time passes (BASELINE §5.1 "easeTo 从 A 平滑落到 B").
//
// NOTE: a Flutter [Ticker] reports elapsed == 0 on its very first tick (that
// frame establishes `_startTime`). Every widget test therefore pumps one
// zero-duration frame first, then advances in steps.
import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

StyleSpec _empty() => StyleSpec.parse(const <String, Object?>{
      'version': 8,
      'sources': <String, Object?>{},
      'layers': <Object?>[],
    });

/// Pump a started animation past [total] so the ticker reaches t >= 1.
///
/// [onHalf] runs after ~half of the duration, for mid-flight assertions.
Future<void> pumpAnimation(
  WidgetTester tester,
  Duration total, {
  void Function()? onHalf,
}) async {
  await tester.pump(); // first tick: elapsed == 0
  const steps = 12;
  final step = Duration(microseconds: total.inMicroseconds ~/ 10);
  for (var i = 0; i < steps; i++) {
    await tester.pump(step);
    if (i == 4) onHalf?.call();
  }
}

void main() {
  group('pure camera math', () {
    test('shortestLongitudeDelta takes the antimeridian short way', () {
      expect(shortestLongitudeDelta(179, -179), 2);
      expect(shortestLongitudeDelta(-179, 179), -2);
      expect(shortestLongitudeDelta(0, 10), 10);
      expect(shortestLongitudeDelta(0, -10), -10);
      expect(shortestLongitudeDelta(-170, 170), -20);
    });

    test('flat interpolation keeps zoom-independent lat and wraps longitude', () {
      const from = LatLng(10, 179);
      const to = LatLng(20, -179);
      final mid = interpolateCenter(from, to, 0.5, sphere: false);
      expect(mid.latitude, closeTo(15, 1e-9));
      expect(mid.longitude.abs(), closeTo(180, 1e-9),
          reason: '179° → -179° must cross the date line, not Greenwich');
      expect(interpolateCenter(from, to, 0, sphere: false), from);
      expect(interpolateCenter(from, to, 1, sphere: false), to);
    });

    test('globe slerp stays on the great circle and hits both endpoints', () {
      const from = LatLng(0, 0);
      const to = LatLng(0, 90);
      final mid = interpolateCenter(from, to, 0.5, sphere: true);
      expect(mid.latitude, closeTo(0, 1e-6));
      expect(mid.longitude, closeTo(45, 1e-6));
      expect(interpolateCenter(from, to, 1, sphere: true), to);
      // Antipodal fallback must still produce finite coordinates.
      final anti = interpolateCenter(
          const LatLng(0, 0), const LatLng(0, 180), 0.5,
          sphere: true);
      expect(anti.latitude.isFinite, isTrue);
      expect(anti.longitude.isFinite, isTrue);
    });

    test('flyZoomAt dips in the middle but lands exactly on the target', () {
      expect(flyZoomAt(startZoom: 6, targetZoom: 6, arc: 1.5, t: 0), 6);
      expect(flyZoomAt(startZoom: 6, targetZoom: 6, arc: 1.5, t: 1),
          closeTo(6, 1e-9));
      expect(flyZoomAt(startZoom: 6, targetZoom: 6, arc: 1.5, t: 0.5),
          closeTo(4.5, 1e-9));
      expect(
          flyZoomArc(
              from: const LatLng(0, 0),
              to: const LatLng(0, 0),
              startZoom: 4,
              viewport: const Size(800, 600)),
          0);
      expect(
          flyZoomArc(
              from: const LatLng(0, 0),
              to: const LatLng(0, 120),
              startZoom: 8,
              viewport: const Size(800, 600)),
          greaterThan(0));
    });

    test('cameraForBounds fits both axes and honours padding / maxZoom', () {
      final bounds = LatLngBounds(
        const LatLng(20, 100),
        const LatLng(40, 120),
      );
      final fit = cameraForBounds(
        bounds,
        viewport: const Size(800, 600),
        minZoom: 1,
        maxZoom: 18,
      );
      expect(fit.center.longitude, closeTo(110, 1e-6));
      // Mercator-Y midpoint is not the arithmetic latitude mean (30°).
      expect(fit.center.latitude, greaterThan(30));
      expect(fit.zoom, greaterThanOrEqualTo(1));
      expect(fit.zoom, lessThanOrEqualTo(18));

      final padded = cameraForBounds(
        bounds,
        viewport: const Size(800, 600),
        minZoom: 1,
        maxZoom: 18,
        padding: const EdgeInsets.all(100),
      );
      expect(padded.zoom, lessThan(fit.zoom),
          reason: 'a smaller usable viewport needs a lower zoom');

      final capped = cameraForBounds(
        bounds,
        viewport: const Size(800, 600),
        minZoom: 1,
        maxZoom: 18,
        maxZoomCap: 2,
      );
      expect(capped.zoom, 2);

      final clamped = cameraForBounds(
        bounds,
        viewport: const Size(800, 600),
        minZoom: 18,
        maxZoom: 18,
      );
      expect(clamped.zoom, 18);
    });
  });

  group('MapHandle eased API (pumped Ticker)', () {
    testWidgets('easeTo converges to centre+zoom, keeps omitted fields',
        (tester) async {
      final camera = GeoMapController(useGlobe: false);
      camera.setViewport(const Size(800, 600));
      final style = GeoStyleController(_empty());
      final handle = MapHandle(
        camera: camera,
        style: style,
        features: GeoFeatureRegistry(),
      );
      addTearDown(() {
        handle.dispose();
        camera.dispose();
        style.dispose();
      });

      final future = handle.easeTo(
        center: const LatLng(40, 110),
        duration: const Duration(milliseconds: 500),
      );
      await pumpAnimation(
        tester,
        const Duration(milliseconds: 500),
        onHalf: () {
          expect(camera.center.latitude, greaterThan(30));
          expect(camera.center.latitude, lessThan(40));
        },
      );
      await future;
      expect(camera.center, const LatLng(40, 110));
      expect(camera.zoom, 4.2, reason: 'zoom omitted -> unchanged');
    });

    testWidgets('zoom-only easeTo clamps to camera constraints', (tester) async {
      final camera = GeoMapController(useGlobe: false, maxZoom: 7);
      camera.setViewport(const Size(800, 600));
      final style = GeoStyleController(_empty());
      final handle = MapHandle(
        camera: camera,
        style: style,
        features: GeoFeatureRegistry(),
      );
      addTearDown(() {
        handle.dispose();
        camera.dispose();
        style.dispose();
      });

      final future = handle.easeTo(
        zoom: 99,
        duration: const Duration(milliseconds: 200),
      );
      await pumpAnimation(tester, const Duration(milliseconds: 200));
      await future;
      expect(camera.zoom, 7);
    });

    testWidgets('flyTo zooms out mid-flight and lands exactly', (tester) async {
      final camera = GeoMapController(useGlobe: false);
      camera.setViewport(const Size(800, 600));
      final style = GeoStyleController(_empty());
      final handle = MapHandle(
        camera: camera,
        style: style,
        features: GeoFeatureRegistry(),
      );
      addTearDown(() {
        handle.dispose();
        camera.dispose();
        style.dispose();
      });

      final future = handle.flyTo(
        center: const LatLng(35, 120),
        zoom: 4.2,
        duration: const Duration(milliseconds: 600),
      );
      await pumpAnimation(
        tester,
        const Duration(milliseconds: 600),
        onHalf: () {
          expect(camera.zoom, lessThan(4.2), reason: 'pull back mid-flight');
        },
      );
      await future;
      expect(camera.center, const LatLng(35, 120));
      expect(camera.zoom, closeTo(4.2, 1e-9));
    });

    testWidgets('fitBounds eases to a zoom that contains the bounds',
        (tester) async {
      final camera = GeoMapController(useGlobe: false);
      camera.setViewport(const Size(800, 600));
      final style = GeoStyleController(_empty());
      final handle = MapHandle(
        camera: camera,
        style: style,
        features: GeoFeatureRegistry(),
      );
      addTearDown(() {
        handle.dispose();
        camera.dispose();
        style.dispose();
      });

      final bounds = LatLngBounds(
        const LatLng(20, 100),
        const LatLng(40, 120),
      );
      final expected = cameraForBounds(
        bounds,
        viewport: const Size(800, 600),
        minZoom: camera.minZoom,
        maxZoom: camera.maxZoom,
      );
      final future = handle.fitBounds(
        bounds,
        duration: const Duration(milliseconds: 400),
      );
      await pumpAnimation(tester, const Duration(milliseconds: 400));
      await future;
      expect(camera.center.latitude, closeTo(expected.center.latitude, 1e-6));
      expect(camera.center.longitude,
          closeTo(expected.center.longitude, 1e-6));
      expect(camera.zoom, closeTo(expected.zoom, 1e-6));
    });

    testWidgets('a newer command cancels the old animation without hanging',
        (tester) async {
      final camera = GeoMapController(useGlobe: false);
      camera.setViewport(const Size(800, 600));
      final style = GeoStyleController(_empty());
      final handle = MapHandle(
        camera: camera,
        style: style,
        features: GeoFeatureRegistry(),
      );
      addTearDown(() {
        handle.dispose();
        camera.dispose();
        style.dispose();
      });

      final first = handle.easeTo(
        center: const LatLng(50, 130),
        duration: const Duration(milliseconds: 800),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      handle.jumpTo(center: const LatLng(10, 10));
      await first; // must complete, not hang
      expect(camera.center, const LatLng(10, 10));
    });
  });
}
