/// Polar cap fill: Web Mercator stops at ±85.0511°, so the cap up to the pole has
/// no tiles. Stretch the edge pixel row of the first/last tile row onto the pole.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../camera/camera_state.dart';
import '../math/geodesy.dart';
import '../math/projections.dart';
import '../tuning/geo_engine_tuning.dart';
import 'tile_scheme.dart';

class PolarCapMesh {
  PolarCapMesh(this.unit, this.indices, this.vertexCount, this.latDegrees);

  final Float32List unit; // x,y,z
  final Uint16List indices;
  final int vertexCount;

  /// Latitude of each vertex row (row 0 = cap boundary, last = pole).
  final List<double> latDegrees;
}

class PolarCapBuilder {
  const PolarCapBuilder._();

  /// Build a cap strip for tile column [x] at [grid]'s zoom.
  static PolarCapMesh build({
    required TileGrid grid,
    required int x,
    required bool north,
    int subdiv = 8,
  }) {
    final n = subdiv.clamp(4, GeoEngineTuning.subdivMax);
    final count = (n + 1) * (n + 1);
    final unit = Float32List(count * 3);
    final west = grid.west(x);
    final east = grid.east(x);
    final capLat = rad(mercatorMaxLatitude);
    final poleLat = math.pi / 2;
    final latRows = <double>[];

    for (var j = 0; j <= n; j++) {
      final t = j / n;
      final latRad = capLat + (poleLat - capLat) * t;
      final lat = north ? latRad : -latRad;
      latRows.add(lat * rad2deg);
      for (var i = 0; i <= n; i++) {
        final lng = rad(west + (east - west) * (i / n));
        final c = math.cos(lat);
        final idx = j * (n + 1) + i;
        unit[idx * 3] = c * math.cos(lng);
        unit[idx * 3 + 1] = c * math.sin(lng);
        unit[idx * 3 + 2] = math.sin(lat);
      }
    }
    return PolarCapMesh(unit, _indices(n), count, latRows);
  }

  /// True when the cap is front-facing for this camera.
  static bool isVisible({required CameraState camera, required bool north}) {
    final sinLat = math.sin(rad(camera.clampedLatitude));
    return north
        ? sinLat > GeoEngineTuning.epsDepth
        : -sinLat > GeoEngineTuning.epsDepth;
  }

  /// Pixel V band (1 px) used to stretch the edge row.
  static ({double v0, double height}) edgeBand({
    required bool north,
    required double imageHeightPx,
  }) =>
      north
          ? (v0: 0.0, height: 1.0)
          : (v0: imageHeightPx - 1.0, height: 1.0);

  static Uint16List _indices(int n) {
    final out = <int>[];
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final i00 = j * (n + 1) + i;
        final i10 = i00 + 1;
        final i01 = i00 + n + 1;
        final i11 = i01 + 1;
        out.addAll([i00, i10, i11, i00, i11, i01]);
      }
    }
    return Uint16List.fromList(out);
  }
}
