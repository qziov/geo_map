// T5d contract: the shared helper must be *exactly* equivalent to the
// scattered `is FlatProjectionDelegate` checks it replaces.
//
// If this ever fails, the flat/globe decision diverged between the two
// projection backends — which would move borders, images and popups.
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const viewport = Size(800, 600);
  const center = LatLng(30, 105);
  const samples = <LatLng>[
    LatLng(0, 0),
    LatLng(30, 105),
    LatLng(39.9, 116.4),
    LatLng(-33.9, 151.2),
    LatLng(60, -179),
    LatLng(-60, 179),
  ];

  MapProjectionDelegate flat() => FlatProjectionDelegate()
    ..updateCamera(center, 4.2, viewport);

  MapProjectionDelegate globe() => GlobeProjectionDelegate()
    ..updateCamera(center, 4.2, viewport);

  test('isFlatProjection matches the raw type test for flat / globe / null', () {
    final delegates = <MapProjectionDelegate?>[flat(), globe(), null];
    for (final d in delegates) {
      expect(
        isFlatProjection(d),
        d is FlatProjectionDelegate,
        reason: 'helper diverged for ${d.runtimeType}',
      );
    }
    expect(isFlatProjection(flat()), isTrue);
    expect(isFlatProjection(globe()), isFalse);
    expect(isFlatProjection(null), isFalse);
  });

  test('projectMapPoint keeps the original flat branch (projectForVector)', () {
    final d = flat();
    for (final p in samples) {
      expect(
        projectMapPoint(d, p),
        d.projectForVector(p),
        reason: 'flat must keep the antimeridian-aware projection at $p',
      );
    }
  });

  test('projectMapPoint keeps the original globe branch (project)', () {
    final d = globe();
    for (final p in samples) {
      expect(
        projectMapPoint(d, p),
        d.project(p),
        reason: 'globe must keep the sentinel-returning projection at $p',
      );
    }
  });

  test('flat and globe still choose different code paths', () {
    // Guards against a helper that collapsed both branches into one call.
    final f = flat();
    final g = globe();
    var differing = 0;
    for (final p in samples) {
      if (projectMapPoint(f, p) != projectMapPoint(g, p)) differing++;
    }
    expect(differing, greaterThan(0));
  });
}
