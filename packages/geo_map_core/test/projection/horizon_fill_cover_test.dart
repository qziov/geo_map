/// Regression tests for the two ways a globe frame can lose coverage.
///
/// 1. **Selection** — every pixel inside the globe disc must belong to a
///    selected tile. A missing tile there is a hole nothing can fill.
/// 2. **Painting** — a fill ring that crosses the horizon must be closed along
///    the limb. Closing the visible runs with a chord (the old behaviour) makes
///    `PathFillType.nonZero` cancel most of the polygon, which shows up as a
///    straight-edged bite in the fill near the limb.
library;

import 'dart:math' as math;

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

/// Nonzero-winding point test over a set of closed sub-paths.
bool _covers(List<List<Vec2>> subpaths, double x, double y) {
  var winding = 0;
  for (final pts in subpaths) {
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      if (a.y <= y) {
        if (b.y > y && _isLeft(a, b, x, y) > 0) winding++;
      } else {
        if (b.y <= y && _isLeft(a, b, x, y) < 0) winding--;
      }
    }
  }
  return winding != 0;
}

double _isLeft(Vec2 a, Vec2 b, double x, double y) =>
    (b.x - a.x) * (y - a.y) - (x - a.x) * (b.y - a.y);

/// What `_MvtPainter` used to do: drop hidden vertices, close each visible run.
List<List<Vec2>> _breakAndClose(List<Vec2?> projected) {
  final runs = <List<Vec2>>[];
  List<Vec2>? current;
  for (final p in projected) {
    if (p == null) {
      if (current != null && current.isNotEmpty) runs.add(current);
      current = null;
      continue;
    }
    (current ??= <Vec2>[]).add(p);
  }
  if (current != null && current.isNotEmpty) runs.add(current);
  return runs;
}

void main() {
  const projector = OrthographicProjector();
  final camera = CameraState(
    center: const LatLng(0, 0),
    zoom: 2,
    size: const ViewportSize(600, 420),
  );

  /// A rectangle that straddles the limb on the east side: everything past
  /// ~90° of longitude from the centre is behind the globe at this zoom.
  final straddling = subdivideSpherePolyline(
    const [
      LatLng(-30, 40),
      LatLng(30, 40),
      LatLng(30, 130),
      LatLng(-30, 130),
    ],
    closed: true,
  );

  group('fill coverage at the limb', () {
    int countCovered(List<List<Vec2>> paths) {
      var covered = 0;
      for (var y = 0.0; y < camera.size.height; y += 2) {
        for (var x = 0.0; x < camera.size.width; x += 2) {
          if (_covers(paths, x, y)) covered++;
        }
      }
      return covered;
    }

    test('closing runs with a chord throws away most of the polygon', () {
      final projected = [
        for (final ll in straddling) projector.project(ll, camera),
      ];
      final broken = _breakAndClose(projected);
      final clipped = clipRingToHorizon(straddling, camera)!;

      expect(broken, hasLength(2), reason: 'the ring is cut in half');

      final chordArea = countCovered(broken);
      final clippedArea = countCovered([clipped.fill]);

      // The two chord-closed halves wind opposite ways, so nonZero cancels the
      // overlap instead of filling it.
      expect(chordArea, greaterThan(0));
      expect(clippedArea, greaterThan(chordArea * 2),
          reason: 'clip $clippedArea px vs chord $chordArea px');
    });

    test('clipping never loses an area the chord version kept', () {
      final projected = [
        for (final ll in straddling) projector.project(ll, camera),
      ];
      final clipped = clipRingToHorizon(straddling, camera)!;
      final paths = [clipped.fill];

      var chordOnly = 0;
      for (var y = 0.0; y < camera.size.height; y += 2) {
        for (var x = 0.0; x < camera.size.width; x += 2) {
          if (_covers(_breakAndClose(projected), x, y) &&
              !_covers(paths, x, y)) {
            chordOnly++;
          }
        }
      }
      expect(chordOnly, 0);
    });

    test('the clipped fill stays on the silhouette', () {
      final clipped = clipRingToHorizon(straddling, camera)!;
      final c = camera.size.center;
      for (final p in clipped.fill) {
        final d = math.sqrt(
            (p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y));
        expect(d, lessThanOrEqualTo(camera.radiusPx + 1e-6));
      }
    });
  });

  group('tile selection covers the disc', () {
    test('every pixel inside the disc maps to a selected tile', () {
      for (final zoom in [1.0, 2.0, 3.0]) {
        final cam = CameraState(
          center: const LatLng(20, 100),
          zoom: zoom,
          size: const ViewportSize(400, 760),
        );
        final selection = TileSelector.select(
          projector: projector,
          camera: cam,
          desiredZ: TileSelector.coveringZoomLevel(cam),
          sourceMinZoom: 0,
          sourceMaxZoom: 14,
        );
        final selected = selection.tiles.toSet();
        final grid = TileGrid.of(TileSchemeKind.webMercator, selection.dataZoom);
        final c = cam.size.center;
        final r = cam.radiusPx;

        var uncovered = 0;
        for (var y = 2.0; y < cam.size.height; y += 6) {
          for (var x = 2.0; x < cam.size.width; x += 6) {
            final dx = x - c.x;
            final dy = y - c.y;
            if (dx * dx + dy * dy > r * r) continue;
            final ll = projector.unproject(Vec2(x, y), cam);
            if (ll == null) continue;
            final key = TileKey(
              grid.zoom,
              grid.xOf(ll.longitude),
              grid.yOf(ll.latitude),
            );
            if (!selected.contains(key)) uncovered++;
          }
        }
        expect(uncovered, 0, reason: 'zoom $zoom');
      }
    });
  });
}
