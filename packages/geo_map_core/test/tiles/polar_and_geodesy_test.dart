import 'dart:math' as math;

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  group('polar cap geometry', () {
    final grid = TileGrid.of(TileSchemeKind.webMercator, 4);

    test('runs from the mercator limit to the pole', () {
      final cap = PolarCapBuilder.build(grid: grid, x: 3, north: true);
      expect(cap.latDegrees.first, closeTo(mercatorMaxLatitude, 1e-9));
      expect(cap.latDegrees.last, closeTo(90, 1e-9));
    });

    test('south cap mirrors the north cap', () {
      final cap = PolarCapBuilder.build(grid: grid, x: 3, north: false);
      expect(cap.latDegrees.first, closeTo(-mercatorMaxLatitude, 1e-9));
      expect(cap.latDegrees.last, closeTo(-90, 1e-9));
    });

    test('all meridian vertices converge at the pole', () {
      final cap = PolarCapBuilder.build(grid: grid, x: 5, north: true);
      final n = (math.sqrt(cap.vertexCount) - 1).round();
      final lastRow = n * (n + 1);
      var maxGap = 0.0;
      for (var i = 1; i <= n; i++) {
        final ax = cap.unit[lastRow * 3];
        final ay = cap.unit[lastRow * 3 + 1];
        final az = cap.unit[lastRow * 3 + 2];
        final bx = cap.unit[(lastRow + i) * 3];
        final by = cap.unit[(lastRow + i) * 3 + 1];
        final bz = cap.unit[(lastRow + i) * 3 + 2];
        final d = math.sqrt(math.pow(ax - bx, 2) +
            math.pow(ay - by, 2) +
            math.pow(az - bz, 2));
        maxGap = math.max(maxGap, d);
      }
      expect(maxGap, lessThan(1e-9));
    });

    test('column spans the tile width', () {
      final cap = PolarCapBuilder.build(grid: grid, x: 2, north: true);
      // First row, first and last vertex longitudes differ by the tile width.
      final n = (math.sqrt(cap.vertexCount) - 1).round();
      final a = _lng(cap.unit[0], cap.unit[1]);
      final b = _lng(cap.unit[n * 3], cap.unit[n * 3 + 1]);
      expect((b - a).abs(), closeTo(grid.tileWidthDeg, 0.5));
    });

    test('visibility follows the camera hemisphere', () {
      CameraState c(double lat) => CameraState(
            center: LatLng(lat, 0),
            zoom: 3,
            size: const ViewportSize(800, 600),
          );
      expect(PolarCapBuilder.isVisible(camera: c(60), north: true), isTrue);
      expect(PolarCapBuilder.isVisible(camera: c(60), north: false), isFalse);
      expect(PolarCapBuilder.isVisible(camera: c(-60), north: true), isFalse);
      expect(PolarCapBuilder.isVisible(camera: c(-60), north: false), isTrue);
    });

    test('edge band picks the correct image row', () {
      final north = PolarCapBuilder.edgeBand(north: true, imageHeightPx: 256);
      final south = PolarCapBuilder.edgeBand(north: false, imageHeightPx: 256);
      expect(north.v0, 0);
      expect(south.v0, 255);
      expect(north.height, 1);
      expect(south.height, 1);
    });

    test('the edge band follows the wire row order', () {
      // In XYZ the northern edge is the image's first row; in TMS it is the
      // last one.
      final xyzNorth = PolarCapBuilder.edgeBand(
        north: true,
        imageHeightPx: 256,
        rowOrder: TileRowOrder.xyzTopDown,
      );
      final tmsNorth = PolarCapBuilder.edgeBand(
        north: true,
        imageHeightPx: 256,
        rowOrder: TileRowOrder.tmsBottomUp,
      );
      final xyzSouth = PolarCapBuilder.edgeBand(
        north: false,
        imageHeightPx: 256,
        rowOrder: TileRowOrder.xyzTopDown,
      );
      final tmsSouth = PolarCapBuilder.edgeBand(
        north: false,
        imageHeightPx: 256,
        rowOrder: TileRowOrder.tmsBottomUp,
      );
      expect(xyzNorth.v0, 0);
      expect(tmsNorth.v0, 255);
      expect(xyzSouth.v0, 255);
      expect(tmsSouth.v0, 0);
    });
  });

  group('polar cap column clipping', () {
    CameraState c(double lat, double zoom, {double lng = 0}) => CameraState(
          center: LatLng(lat, lng),
          zoom: zoom,
          size: const ViewportSize(800, 600),
          minZoom: 0,
          maxZoom: 22,
        );

    test('the opposite hemisphere has no cap columns', () {
      // The camera sits in the southern hemisphere: the north cap is beyond
      // the horizon, the south cap is in front of it.
      final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
      expect(
        PolarCapBuilder.visibleColumns(
            grid: grid, camera: c(-20, 3), north: true),
        isEmpty,
      );
      expect(
        PolarCapBuilder.visibleColumns(
            grid: grid, camera: c(-20, 3), north: false),
        isNotEmpty,
      );
    });

    test('near the pole at low zoom the cap is on screen', () {
      // At z3 the whole globe is smaller than the viewport, so the polar cap
      // is visible — but only a handful of columns can matter.
      final grid = TileGrid.of(TileSchemeKind.webMercator, 3);
      final cols = PolarCapBuilder.visibleColumns(
        grid: grid,
        camera: c(88, 3),
        north: true,
      );
      expect(cols, isNotEmpty);
      expect(cols.length, lessThanOrEqualTo(GeoEngineTuning.maxPolarCapColumns));
    });

    test('z12 still sees the cap, and draws it as one strip', () {
      // The old sampler stepped 8 latitudes across the 4.95° band — 0.6° apart
      // — while the whole viewport is 0.2° tall at z12. The cap was silently
      // dropped (black pole). The analytic span cannot alias, and 4096 columns
      // of wedges are out of the question, so this must take the single-strip
      // path.
      final grid = TileGrid.of(TileSchemeKind.webMercator, 12);
      final camera = c(88, 12);
      final span = PolarCapBuilder.visibleSpan(camera: camera, north: true);
      expect(span, isNotNull, reason: 'the cap must not be dropped at z12');
      expect(span!.startLng, lessThanOrEqualTo(0));
      expect(span.endLng, greaterThanOrEqualTo(0));
      expect(
        PolarCapBuilder.columnCountFor(grid, span),
        greaterThan(GeoEngineTuning.maxPolarCapColumns),
        reason: 'the renderer must take the single-strip path here',
      );
      final cols = PolarCapBuilder.visibleColumns(
        grid: grid,
        camera: camera,
        north: true,
      );
      expect(cols.length,
          lessThanOrEqualTo(GeoEngineTuning.maxPolarCapColumns),
          reason: 'got ${cols.length} of ${grid.cols} columns');
    });

    test('the columns are centred on the camera meridian', () {
      final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
      final cols = PolarCapBuilder.visibleColumns(
        grid: grid,
        camera: c(88, 3, lng: 30),
        north: true,
      );
      expect(cols, isNotEmpty);
      expect(cols.contains(grid.xOf(30)), isTrue);
    });

    test('the cost does not grow with the zoom level', () {
      // Whatever the zoom, the number of cap columns stays bounded: the cap
      // is a tiny disk around the pole and cannot resolve more columns than
      // that. The bound is the grid size (the cap can wrap all the way round
      // the pole when the camera is inside it), so it must not grow
      // *exponentially* with the zoom — the cap leaves the viewport again at
      // high zoom.
      for (final zoom in [3, 6, 9, 12, 15]) {
        final grid = TileGrid.of(TileSchemeKind.webMercator, zoom);
        final cols = PolarCapBuilder.visibleColumns(
          grid: grid,
          camera: c(88, zoom.toDouble()),
          north: true,
        );
        expect(cols.length, lessThanOrEqualTo(GeoEngineTuning.maxPolarCapColumns),
            reason: 'zoom $zoom produced ${cols.length} columns');
        expect(cols.length, lessThanOrEqualTo(grid.cols),
            reason: 'zoom $zoom produced ${cols.length} of ${grid.cols}');
      }
    });

    test('a camera inside the cap still sees the cap', () {
      // The camera is above 85.0511°, i.e. inside the polar cap itself. The
      // cap's boundary circle is entirely off screen here — only the wedge
      // between the boundary and the pole is visible. Sampling the boundary
      // circle alone would drop the cap and leave black pixels at the pole.
      final grid = TileGrid.of(TileSchemeKind.webMercator, 6);
      final cols = PolarCapBuilder.visibleColumns(
        grid: grid,
        camera: c(88, 6),
        north: true,
      );
      expect(cols, isNotEmpty);
      expect(cols.contains(grid.xOf(0)), isTrue);
    });
  });

  group('polar cap span', () {
    CameraState c(double lat, double zoom, {double lng = 0}) => CameraState(
          center: LatLng(lat, lng),
          zoom: zoom,
          size: const ViewportSize(800, 600),
          minZoom: 0,
          maxZoom: 22,
        );

    test('a wide span is one rectangular mesh, not many wedges', () {
      // The smeared regime must be a *single* strip: `lngSteps` columns by
      // `latSteps` rows, with the longitudes placed exactly on the interval.
      final mesh = PolarCapBuilder.buildSpan(
        startLng: 10,
        spanLng: 40,
        north: true,
        lngSteps: 4,
        latSteps: 2,
      );
      expect(mesh.cols, 4);
      expect(mesh.rows, 2);
      expect(mesh.vertexCount, 15);
      for (var i = 0; i <= 4; i++) {
        final lng = _lng(mesh.unit[i * 3], mesh.unit[i * 3 + 1]);
        expect(lng, closeTo(10 + 10.0 * i, 1e-4));
      }
      // The boundary row is the mercator limit, the last row the pole.
      expect(mesh.latDegrees.first, closeTo(mercatorMaxLatitude, 1e-6));
      expect(mesh.latDegrees.last, closeTo(90, 1e-6));
    });

    test('a span crossing the antimeridian stays contiguous', () {
      final mesh = PolarCapBuilder.buildSpan(
        startLng: 170,
        spanLng: 40,
        north: false,
        lngSteps: 4,
        latSteps: 1,
      );
      final at190 = _lng(mesh.unit[2 * 3], mesh.unit[2 * 3 + 1]);
      expect(at190, closeTo(-170, 1e-6));
      // The south cap runs from -85.05 down to -90.
      expect(mesh.latDegrees.first, closeTo(-mercatorMaxLatitude, 1e-6));
      expect(mesh.latDegrees.last, closeTo(-90, 1e-6));
    });

    test('a wrapping span is reported as a closed arc', () {
      final grid = TileGrid.of(TileSchemeKind.webMercator, 6);
      final span = PolarCapBuilder.visibleSpan(
        camera: c(88, 6),
        north: true,
      );
      expect(span, isNotNull);
      expect(span!.wrapsAround, isTrue);
      expect(span.spanLng, closeTo(360, 1e-6));
      expect(PolarCapBuilder.columnCountFor(grid, span), grid.cols);
    });

    test('a span is mapped onto the columns it really covers', () {
      // z4: 16 columns of 22.5°. A 40° arc from 170° covers 170…210, i.e.
      // columns 15, 0 and 1 — the wrap must not collapse into one window.
      final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
      final cols = PolarCapBuilder.columnsForSpan(
        grid: grid,
        span: const PolarCapSpan(170, 40),
      );
      expect(cols, [15, 0, 1]);
    });

    test('an over-wide span is windowed around the camera meridian', () {
      final grid = TileGrid.of(TileSchemeKind.webMercator, 6);
      final cols = PolarCapBuilder.columnsForSpan(
        grid: grid,
        span: const PolarCapSpan(-180, 360),
        nearLng: 90,
        maxColumns: 8,
      );
      expect(cols.length, 8);
      expect(cols.contains(grid.xOf(90)), isTrue);
    });

    test('the wedge regime is taken while a column is still resolvable', () {
      // At z5 the cap needs 32 columns — still one wedge each.
      final grid = TileGrid.of(TileSchemeKind.webMercator, 5);
      final span = PolarCapBuilder.visibleSpan(
        camera: c(88, 5),
        north: true,
      );
      expect(span, isNotNull);
      expect(
        PolarCapBuilder.columnCountFor(grid, span!),
        lessThanOrEqualTo(GeoEngineTuning.maxPolarCapColumns),
      );
      expect(span.wrapsAround, isTrue);
    });

    test('the analytic span agrees with a far denser sampler', () {
      // Cross-check the closed form against brute force at a resolution fine
      // enough for the viewport (this is the check the old sampler failed).
      // Every case below has the cap genuinely on screen, so the reference is
      // never `null`.
      const cases = <(double, double)>[
        (88.0, 4.0),
        (88.0, 6.0),
        (89.5, 9.0),
        // The first two do not wrap: they exercise the bisection.
        (88.0, 9.0),
        (88.0, 12.0),
      ];
      for (final (lat, zoom) in cases) {
        final camera = c(lat, zoom);
        final span = PolarCapBuilder.visibleSpan(camera: camera, north: true);
        final brute = _bruteForceSpan(camera, 2048, 64);
        expect(brute, isNotNull, reason: 'reference: lat $lat z$zoom');
        expect(span, isNotNull, reason: 'analytic: lat $lat z$zoom');
        // The analytic version uses the circumscribed circle, so it is a
        // superset: it may cover a little more, never less.
        const slack = 1.0;
        expect(span!.startLng, lessThanOrEqualTo(brute!.startLng + slack),
            reason: 'west edge: lat $lat z$zoom');
        expect(span.endLng, greaterThanOrEqualTo(brute.endLng - slack),
            reason: 'east edge: lat $lat z$zoom');
        expect(span.spanLng, lessThanOrEqualTo(360.0));
      }
    });
  });

  group('geodesy', () {
    test('slerp midpoint sits on the great circle', () {
      final a = Vec3.of(const LatLng(0, 0));
      final b = Vec3.of(const LatLng(0, 90));
      final mid = slerp(a, b, 0.5).toLatLng();
      expect(mid.latitude, closeTo(0, 1e-9));
      expect(mid.longitude, closeTo(45, 1e-9));
    });

    test('slerp endpoints are exact', () {
      final a = Vec3.of(const LatLng(10, 20));
      final b = Vec3.of(const LatLng(-30, 160));
      expect(slerp(a, b, 0).toLatLng().latitude, closeTo(10, 1e-9));
      expect(slerp(a, b, 1).toLatLng().longitude, closeTo(160, 1e-9));
    });

    test('densify keeps the chord error under the tuned budget', () {
      const radius = 1200.0;
      final step = densifyStepForPixelError(radius, 0.5);
      final err = radius * (1 - math.cos(step / 2));
      expect(err, lessThanOrEqualTo(0.5 * 1.001));
    });

    test('densify adds intermediate points and preserves endpoints', () {
      final line = densifyGreatCircle(
        const [LatLng(0, 0), LatLng(0, 90)],
        stepRad: 0.1,
      );
      expect(line.length, greaterThan(10));
      expect(line.first.longitude, closeTo(0, 1e-9));
      expect(line.last.longitude, closeTo(90, 1e-9));
    });

    test('densify handles the antimeridian without jumps', () {
      final line = densifyGreatCircle(
        const [LatLng(10, 179), LatLng(10, -179)],
        stepRad: 0.05,
      );
      for (final p in line) {
        expect(p.longitude.abs(), lessThanOrEqualTo(180.0));
      }
      final total = angleBetween(line.first, line.last);
      expect(total, lessThan(0.1));
    });

    test('closed rings close back onto the first point', () {
      final ring = densifyGreatCircle(
        const [LatLng(0, 0), LatLng(0, 10), LatLng(10, 10), LatLng(10, 0)],
        stepRad: 0.5,
        closed: true,
      );
      expect(angleBetween(ring.first, ring.last), lessThan(0.6));
    });

    test('haversine matches a known distance', () {
      final d = haversine(const LatLng(0, 0), const LatLng(0, 1));
      expect(d, closeTo(111195, 500));
    });

    test('destinationPoint: north/east bearings land on the axes', () {
      final north = destinationPoint(const LatLng(0, 0), 0, rad(1));
      expect(north.latitude, closeTo(1, 1e-9));
      expect(north.longitude, closeTo(0, 1e-9));
      final east = destinationPoint(const LatLng(0, 0), math.pi / 2, rad(1));
      expect(east.latitude, closeTo(0, 1e-9));
      expect(east.longitude, closeTo(1, 1e-9));
    });

    test('destinationPoint at lat 60 keeps geodesic distance', () {
      final d = destinationPoint(const LatLng(60, 0), 0, rad(5));
      expect(angleBetween(const LatLng(60, 0), d) * 180 / math.pi,
          closeTo(5, 1e-9));
    });

    test('centroid of a small ring is inside the ring', () {
      final c = sphericalCentroid(const [
        LatLng(0, 0),
        LatLng(0, 10),
        LatLng(10, 10),
        LatLng(10, 0),
      ]);
      expect(c.latitude, inInclusiveRange(0, 10));
      expect(c.longitude, inInclusiveRange(0, 10));
    });
  });
}

double _lng(double x, double y) => math.atan2(y, x) * 180 / math.pi;

/// Dense-sampling reference implementation of the visible cap arc.
///
/// Uses the **rectangle** (the real viewport), so it is a subset of what
/// [PolarCapBuilder.visibleSpan] produces with its circumscribed circle.
PolarCapSpan? _bruteForceSpan(
  CameraState camera,
  int lngSamples,
  int latSteps,
) {
  const ortho = OrthographicProjector();
  final hits = <double>[];
  for (var i = 0; i < lngSamples; i++) {
    final lng = -180 + 360 * i / lngSamples;
    for (var j = 0; j <= latSteps; j++) {
      final lat =
          mercatorMaxLatitude + (90 - mercatorMaxLatitude) * j / latSteps;
      final p = ortho.project(LatLng(lat, lng), camera);
      if (p == null) continue;
      if (p.x < 0 ||
          p.y < 0 ||
          p.x > camera.size.width ||
          p.y > camera.size.height) {
        continue;
      }
      hits.add(lng);
      break;
    }
  }
  if (hits.isEmpty) return null;
  hits.sort();
  var widestGap = hits.first + 360 - hits.last;
  var gapEnd = hits.last;
  for (var i = 0; i + 1 < hits.length; i++) {
    final gap = hits[i + 1] - hits[i];
    if (gap > widestGap) {
      widestGap = gap;
      gapEnd = hits[i];
    }
  }
  // The arc starts right after the widest gap — which wraps past 180°.
  var start = hits.first;
  for (final h in hits) {
    if (h > gapEnd) {
      start = h;
      break;
    }
  }
  final span = math.max(360 - widestGap, 360 / lngSamples);
  if (span >= 360 - 360 / lngSamples) return const PolarCapSpan(-180, 360);
  return PolarCapSpan(start, span);
}
