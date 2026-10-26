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
  PolarCapMesh(this.unit, this.indices, this.cols, this.rows, this.latDegrees);

  /// `x, y, z` per vertex, on the unit sphere.
  final Float32List unit;

  /// Triangle soup over the `(cols + 1) × (rows + 1)` vertex grid.
  final Uint16List indices;

  /// Longitude cells (meridian subdivision).
  final int cols;

  /// Latitude cells (cap boundary → pole).
  final int rows;

  /// Latitude of each vertex row (row 0 = cap boundary, last = pole).
  final List<double> latDegrees;

  int get vertexCount => (cols + 1) * (rows + 1);
}

/// The visible part of the polar cap, as a longitude interval.
///
/// [startLng] is deliberately **unwrapped**: an arc that crosses the
/// antimeridian keeps increasing past ±180°, so the interval stays contiguous
/// instead of being split into two windows.
class PolarCapSpan {
  const PolarCapSpan(this.startLng, this.spanLng);

  /// West edge of the interval (degrees; may lie outside `[-180, 180]`).
  final double startLng;

  /// Width of the interval (degrees). `360` means the arc closes on itself.
  final double spanLng;

  double get endLng => startLng + spanLng;

  /// Whether the arc wraps all the way around the pole.
  bool get wrapsAround => spanLng >= 360 - 1e-6;

  @override
  String toString() => 'PolarCapSpan(${startLng.toStringAsFixed(4)}° '
      '+${spanLng.toStringAsFixed(4)}°)';
}

class PolarCapBuilder {
  const PolarCapBuilder._();

  /// Hard bound on the meridian subdivision (keeps the vertex count well
  /// inside `Uint16` indices for any latitude subdivision).
  static const int _maxLngSteps = 360;

  /// Build a cap strip for tile column [x] at [grid]'s zoom.
  static PolarCapMesh build({
    required TileGrid grid,
    required int x,
    required bool north,
    int subdiv = 8,
  }) {
    final n = subdiv.clamp(4, GeoEngineTuning.subdivMax);
    return buildSpan(
      startLng: grid.west(x),
      spanLng: grid.tileWidthDeg,
      north: north,
      lngSteps: n,
      latSteps: n,
    );
  }

  /// Build a cap strip covering an arbitrary longitude interval.
  ///
  /// The mesh is a `(lngSteps + 1) × (latSteps + 1)` vertex grid running from
  /// the mercator limit up to the pole. It is used for two very different
  /// things:
  ///
  /// * a **single column wedge** (`spanLng == grid.tileWidthDeg`, `lngSteps`
  ///   of 1–2) — the cap is textured with that column's own tile;
  /// * a **smeared span** (`spanLng` up to 360°, `lngSteps` of tens) — used
  ///   when the camera sits *inside* the cap and the visible part wraps all
  ///   the way around the pole. Drawing one textured wedge per column there
  ///   produced a sunburst of `2^zoom` different images across the viewport
  ///   (and `2^zoom` meshes per frame); one continuous strip cannot.
  static PolarCapMesh buildSpan({
    required double startLng,
    required double spanLng,
    required bool north,
    int lngSteps = 1,
    int latSteps = 8,
  }) {
    final nl = lngSteps.clamp(1, _maxLngSteps);
    final nr = latSteps.clamp(1, GeoEngineTuning.subdivMax);
    final count = (nl + 1) * (nr + 1);
    final unit = Float32List(count * 3);
    final capLat = rad(mercatorMaxLatitude);
    final poleLat = math.pi / 2;
    final latRows = <double>[];

    for (var j = 0; j <= nr; j++) {
      final t = j / nr;
      final latRad = capLat + (poleLat - capLat) * t;
      final lat = north ? latRad : -latRad;
      latRows.add(lat * rad2deg);
      final c = math.cos(lat);
      final z = math.sin(lat);
      for (var i = 0; i <= nl; i++) {
        final lng = rad(startLng + spanLng * (i / nl));
        final idx = j * (nl + 1) + i;
        unit[idx * 3] = c * math.cos(lng);
        unit[idx * 3 + 1] = c * math.sin(lng);
        unit[idx * 3 + 2] = z;
      }
    }
    return PolarCapMesh(unit, _indicesFor(nl, nr), nl, nr, latRows);
  }

  /// True when the cap is front-facing for this camera.
  static bool isVisible({required CameraState camera, required bool north}) {
    final sinLat = math.sin(rad(camera.clampedLatitude));
    return north
        ? sinLat > GeoEngineTuning.epsDepth
        : -sinLat > GeoEngineTuning.epsDepth;
  }

  /// The visible part of the cap as a **longitude interval**, or `null` when
  /// the cap does not reach the viewport at all.
  ///
  /// The cap is a spherical disk of angular radius `r_c = 90° − 85.0511°`
  /// around the pole, and every grid column owns one meridian wedge of it.
  ///
  /// This is solved **analytically**, not by sampling. The old sampler stepped
  /// 8 latitudes across the 4.95° band and 1° of longitude, which silently
  /// aliased as soon as one sampling cell grew larger than the viewport (at
  /// z12 the whole screen spans 0.2° of latitude): the cap was simply dropped
  /// and the pole went black. A sampler that survives that has to be finer
  /// than the screen, i.e. thousands of projections *per frame*.
  ///
  /// The camera sees the inside of a disk of angular radius `alpha` (the
  /// circumscribed circle of the viewport — a superset of the rectangle, which
  /// is the safe side: over-drawing is invisible, under-drawing leaves a black
  /// wedge). The visible longitudes are those whose meridian segment
  /// `[85.0511°, 90°]` comes within `alpha` of the camera centre, and the
  /// closest point of a meridian is found in closed form:
  ///
  /// * the perpendicular foot on the meridian, `tan φ* = tan φ_c / cos δ`,
  ///   which gives `cos d = √(sin²φ_c + cos²φ_c·cos²δ)` when it lands inside
  ///   the band;
  /// * otherwise one of the two ends of the band, `φ = 85.0511°` or the pole.
  ///
  /// Visibility is monotonic in `|δ|`, so the arc edge is a bisection away.
  static PolarCapSpan? visibleSpan({
    required CameraState camera,
    required bool north,
    double marginPx = 64,
  }) {
    final lat = camera.clampedLatitude;
    // The cap lies beyond the horizon as soon as the camera is on the other
    // side of the equator.
    if (north ? lat <= 0 : lat >= 0) return null;

    final radius = math.max(camera.radiusPx, 1.0);
    final halfDiag = camera.size.diagonal / 2 + marginPx;
    final alpha = math.asin(math.min(1.0, halfDiag / radius));
    final cosAlpha = math.cos(alpha);

    // Work in |latitude|: the north and south caps are mirror images, and the
    // longitude extent is the same for both.
    final phiC = rad(lat.abs());
    final phi0 = rad(mercatorMaxLatitude);
    final capRadius = math.pi / 2 - phi0;
    final poleDistance = math.pi / 2 - phiC;

    // The cap disk never reaches the viewport.
    if (poleDistance - alpha > capRadius) return null;
    // The pole itself is on screen, so every meridian wedge converges in view.
    if (poleDistance <= alpha) return const PolarCapSpan(-180, 360);

    final sinC = math.sin(phiC);
    final cosC = math.cos(phiC);
    final sin0 = math.sin(phi0);
    final cos0 = math.cos(phi0);

    /// `cos` of the angular distance from the camera centre to the closest
    /// point of the meridian at [delta] radians from the camera meridian.
    double closestCos(double delta) {
      final cd = math.cos(delta);
      // Foot of the perpendicular, `tan φ* = tan φ_c / cos δ`.
      final phiStar = math.atan(math.tan(phiC) / cd);
      if (phiStar >= phi0) {
        return math.sqrt(sinC * sinC + cosC * cosC * cd * cd);
      }
      // The foot is below the band: the closest point is one of its ends.
      final atBoundary = sin0 * sinC + cos0 * cosC * cd;
      return math.max(atBoundary, sinC);
    }

    if (closestCos(math.pi) >= cosAlpha) {
      return const PolarCapSpan(-180, 360);
    }
    var lo = 0.0; // visible
    var hi = math.pi; // not visible (checked above)
    for (var i = 0; i < 48; i++) {
      final mid = (lo + hi) / 2;
      if (closestCos(mid) >= cosAlpha) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final halfSpan = lo * rad2deg;
    final center = camera.center.longitude;
    return PolarCapSpan(center - halfSpan, halfSpan * 2);
  }

  /// How many grid columns the span covers.
  static int columnCountFor(TileGrid grid, PolarCapSpan span) {
    if (span.wrapsAround) return grid.cols;
    final count = (span.spanLng / grid.tileWidthDeg).ceil();
    return count.clamp(1, grid.cols);
  }

  /// The tile columns whose wedge lies inside [span].
  ///
  /// The list is bounded by [maxColumns]: keeping **every** column of a
  /// wrap-around arc meant 4096 meshes at z12, each textured with a different
  /// image, which is exactly the radial sunburst that filled the viewport.
  /// Callers that need the whole arc must draw a single
  /// [buildSpan] strip instead — see [columnCountFor] to decide.
  ///
  /// When the span is wider than the bound, the window closest to [nearLng]
  /// is kept.
  static List<int> columnsForSpan({
    required TileGrid grid,
    required PolarCapSpan span,
    double? nearLng,
    int maxColumns = GeoEngineTuning.maxPolarCapColumns,
  }) {
    final first = grid.rawXOf(span.startLng);
    var count = grid.rawXOf(span.endLng) - first + 1;
    if (span.wrapsAround || count > grid.cols) count = grid.cols;
    if (count <= maxColumns) {
      return [for (var i = 0; i < count; i++) grid.wrapX(first + i)];
    }

    // Too many columns for one wedge each: keep the window of the arc that
    // sits closest to the camera meridian.
    var near = nearLng ?? (span.startLng + span.spanLng / 2);
    while (near < span.startLng) {
      near += 360;
    }
    while (near > span.endLng) {
      near -= 360;
    }
    var start = grid.rawXOf(near) - maxColumns ~/ 2;
    if (start < first) start = first;
    if (start > first + count - maxColumns) start = first + count - maxColumns;
    return [for (var i = 0; i < maxColumns; i++) grid.wrapX(start + i)];
  }

  /// The tile columns whose polar cap can reach the viewport.
  ///
  /// Kept for diagnostics and tests; the renderer decides between per-column
  /// wedges and a single smeared strip from [columnCountFor].
  static List<int> visibleColumns({
    required TileGrid grid,
    required CameraState camera,
    required bool north,
    double marginPx = 64,
    int maxColumns = GeoEngineTuning.maxPolarCapColumns,
  }) {
    final span = visibleSpan(camera: camera, north: north, marginPx: marginPx);
    if (span == null) return const [];
    return columnsForSpan(
      grid: grid,
      span: span,
      nearLng: camera.center.longitude,
      maxColumns: maxColumns,
    );
  }

  /// Pixel V band (1 px) used to stretch the edge row.
  ///
  /// [rowOrder] tells whether the tile image rows are stored top-down (XYZ) or
  /// bottom-up (TMS). In XYZ the northern edge is the image's first row; in
  /// TMS the northern edge is the image's **last** row.
  static ({double v0, double height}) edgeBand({
    required bool north,
    required double imageHeightPx,
    TileRowOrder rowOrder = TileRowOrder.xyzTopDown,
  }) {
    final topDown = rowOrder == TileRowOrder.xyzTopDown;
    final useTop = north ? topDown : !topDown;
    return useTop
        ? (v0: 0.0, height: 1.0)
        : (v0: imageHeightPx - 1.0, height: 1.0);
  }

  static Uint16List _indicesFor(int cols, int rows) {
    final out = <int>[];
    final stride = cols + 1;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final i00 = j * stride + i;
        final i10 = i00 + 1;
        final i01 = i00 + stride;
        final i11 = i01 + 1;
        out.addAll([i00, i10, i11, i00, i11, i01]);
      }
    }
    return Uint16List.fromList(out);
  }
}
