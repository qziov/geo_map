/// Flat (Mercator) infinite horizontal scroll.
///
/// The vendor CRS clamps longitude to ±180, which used to stop a pan dead at the
/// seam. `FlatProjectionDelegate.panCenter` now **wraps** it, so panning east or
/// west continues forever; the renderer repeats world copies (raster:
/// `AffineGeometry.worldCopies`, vectors: `visibleWorldCopies`) so the wrap is
/// seamless — MapLibre's `renderWorldCopies` behaviour.
library;

import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

void main() {
  group('FlatProjectionDelegate infinite pan', () {
    test('panning east past +180 wraps instead of sticking', () {
      final d = FlatProjectionDelegate()
        ..updateCamera(const LatLng(0, 179), 4, const Size(800, 600));
      // Finger moves left (delta.dx < 0) → centre moves east.
      final next = d.panCenter(const LatLng(0, 179), const Offset(-400, 0), 4);
      expect(next.longitude, isNot(equals(179)));
      expect(next.longitude, inInclusiveRange(-180, 180));
      expect(next.longitude, lessThan(0)); // wrapped onto the west side
    });

    test('panning west past -180 wraps instead of sticking', () {
      final d = FlatProjectionDelegate()
        ..updateCamera(const LatLng(0, -179), 4, const Size(800, 600));
      final next = d.panCenter(const LatLng(0, -179), const Offset(400, 0), 4);
      expect(next.longitude, isNot(equals(-179)));
      expect(next.longitude, inInclusiveRange(-180, 180));
      expect(next.longitude, greaterThan(0));
    });

    test('repeated panning keeps moving (no stuck edge)', () {
      final d = FlatProjectionDelegate();
      var center = const LatLng(0, 0);
      final lngs = <double>[];
      for (var i = 0; i < 5; i++) {
        center = d.panCenter(center, const Offset(-500, 0), 3);
        lngs.add(center.longitude);
      }
      for (var i = 1; i < lngs.length; i++) {
        expect(lngs[i], isNot(equals(lngs[i - 1])));
      }
      expect(lngs.every((l) => l >= -180 && l <= 180), isTrue);
    });

    test('latitude is still clamped at the mercator limit', () {
      final d = FlatProjectionDelegate();
      final next = d.panCenter(const LatLng(84, 0), const Offset(0, 100000), 4);
      expect(next.latitude, lessThanOrEqualTo(85.05112878 + 1e-9));
      expect(next.latitude, greaterThanOrEqualTo(-85.05112878 - 1e-9));
    });
  });
}
