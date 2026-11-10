/// Shared image-overlay rendering for `GlobeImageLayer` and the style-layer
/// renderers (`StyleVectorLayer` / `MvtVectorLayer`).
///
/// The 2D fast path draws an axis-aligned `drawImageRect` quad; the 3D path
/// tessellates the geographic bounds and projects every vertex onto the
/// orthographic sphere. Keeping both here means the widget and the style
/// raster layer paint exactly the same pixels.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:latlong2/latlong.dart';

import '../camera/projection_mode.dart' show isFlatProjection;
import '../vendor/flutter_map_camera/flutter_map_camera.dart'
    show LatLngBounds, MapCamera;

/// Runtime image data behind a `raster` style layer.
///
/// Style documents are pure Dart / JSON-like, so they only carry a source id;
/// the actual `ui.Image` lives in `GeoStyleController`'s image registry and is
/// looked up by `layer.source` at paint time.
class ImageSource {
  const ImageSource({
    required this.image,
    required this.bounds,
    this.subdivisions = 24,
  });

  final ui.Image image;

  /// Geographic coverage: south-west / north-east corners.
  final LatLngBounds bounds;

  /// Mesh resolution for the 3D spherical path.
  final int subdivisions;
}

const double _eps = 0.01;
const double _cutoff = -0.12;

/// Draws [image] over [bounds] on [canvas], in the current style-layer order.
void paintImageOverlay(
  ui.Canvas canvas,
  ui.Size size, {
  required MapCamera camera,
  required ui.Image image,
  required LatLngBounds bounds,
  required double opacity,
  required bool mercatorSampling,
  required int subdivisions,
}) {
  if (size.isEmpty) return;

  final flat = isFlatProjection(camera.projectionDelegate);
  final lat0 = camera.center.latitude * math.pi / 180;
  final lng0 = camera.center.longitude * math.pi / 180;
  final radius = 256 * math.pow(2, camera.zoom) / (2 * math.pi);
  if (!flat && radius <= 0) return;

  // Plane + Mercator-rendered image: the bounds corners project to an
  // axis-aligned rect, so a single affine blit is exact. Use `project()`
  // (not `projectClamped`): the latter unwraps longitudes and collapses a
  // global -180..180 rect to zero width.
  if (flat && mercatorSampling) {
    final tl = camera.project(LatLng(bounds.north, bounds.west));
    final br = camera.project(LatLng(bounds.south, bounds.east));
    final dst = ui.Rect.fromPoints(
      ui.Offset(tl.x, tl.y),
      ui.Offset(br.x, br.y),
    );
    final src = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      ui.Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..color = ui.Color.fromRGBO(255, 255, 255, opacity),
    );
    return;
  }

  final center = ui.Offset(size.width / 2, size.height / 2);
  final n = subdivisions.clamp(4, 256);
  final vertexCount = (n + 1) * (n + 1);
  final positions = Float32List(vertexCount * 2);
  final uvs = Float32List(vertexCount * 2);
  final depths = Float32List(vertexCount);

  final west = bounds.west;
  final east = bounds.east;
  final north = bounds.north;
  final south = bounds.south;
  final imageWidth = image.width.toDouble();
  final imageHeight = image.height.toDouble();

  final double northMerc;
  final double mercSpan;
  if (mercatorSampling) {
    northMerc = _mercY(north);
    final southMerc = _mercY(south);
    mercSpan = southMerc - northMerc;
  } else {
    northMerc = 0;
    mercSpan = 0;
  }

  var allFront = true;
  var anyFront = false;

  for (var j = 0; j <= n; j++) {
    final fy = j / n;
    final lat = mercatorSampling
        ? _inverseMercY(northMerc + mercSpan * fy)
        : north + (south - north) * fy;
    for (var i = 0; i <= n; i++) {
      final fx = i / n;
      final lng = west + (east - west) * fx;
      final index = j * (n + 1) + i;

      final v = _view(lng * math.pi / 180, lat * math.pi / 180, lat0, lng0);
      depths[index] = v.$3;
      var vx = v.$1;
      var vy = v.$2;
      if (v.$3 <= _eps) {
        allFront = false;
        final len = math.sqrt(vx * vx + vy * vy);
        if (len < 1e-6) {
          vx = 0;
          vy = 0;
        } else {
          vx /= len;
          vy /= len;
        }
      } else {
        anyFront = true;
      }
      positions[index * 2] = center.dx + vx * radius;
      positions[index * 2 + 1] = center.dy - vy * radius;
      uvs[index * 2] = fx * imageWidth;
      uvs[index * 2 + 1] = fy * imageHeight;
    }
  }

  if (!anyFront) return;

  final indices = allFront ? _staticIndices(n) : _culledIndices(n, depths);
  final vertices = ui.Vertices.raw(
    ui.VertexMode.triangles,
    positions,
    textureCoordinates: uvs,
    indices: indices,
  );

  final paint = ui.Paint()
    ..isAntiAlias = true
    ..color = ui.Color.fromRGBO(255, 255, 255, opacity)
    ..shader = ui.ImageShader(
      image,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      _identity(),
      filterQuality: ui.FilterQuality.medium,
    );

  canvas.save();
  canvas.clipPath(
    ui.Path()..addOval(ui.Rect.fromCircle(center: center, radius: radius)),
  );
  canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
  canvas.restore();

  vertices.dispose();
}

(double, double, double) _view(
  double lng,
  double lat,
  double lat0,
  double lng0,
) {
  final dLng = lng - lng0;
  final cosLat = math.cos(lat);
  return (
    cosLat * math.sin(dLng),
    math.cos(lat0) * math.sin(lat) - math.sin(lat0) * cosLat * math.cos(dLng),
    math.sin(lat0) * math.sin(lat) + math.cos(lat0) * cosLat * math.cos(dLng),
  );
}

final Map<int, Uint16List> _indexCache = <int, Uint16List>{};

Uint16List _staticIndices(int n) => _indexCache.putIfAbsent(n, () {
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
    });

Uint16List _culledIndices(int n, Float32List depths) {
  final out = <int>[];
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      final i00 = j * (n + 1) + i;
      final i10 = i00 + 1;
      final i01 = i00 + n + 1;
      final i11 = i01 + 1;

      final z00 = depths[i00];
      final z10 = depths[i10];
      final z01 = depths[i01];
      final z11 = depths[i11];

      if (z00 <= _eps && z10 <= _eps && z01 <= _eps && z11 <= _eps) continue;
      if (z00 < _cutoff || z10 < _cutoff || z01 < _cutoff || z11 < _cutoff) {
        continue;
      }
      out.addAll([i00, i10, i11, i00, i11, i01]);
    }
  }
  return Uint16List.fromList(out);
}

Float64List _identity() {
  final m = Float64List(16);
  m[0] = 1;
  m[5] = 1;
  m[10] = 1;
  m[15] = 1;
  return m;
}

double _mercY(double latDeg) {
  final latRad = latDeg * math.pi / 180;
  return math.log(math.tan(math.pi / 4 + latRad / 2));
}

double _inverseMercY(double mercY) {
  final latRad = 2 * math.atan(math.exp(mercY)) - math.pi / 2;
  return latRad * 180 / math.pi;
}
