import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../vendor/flutter_map_camera/flutter_map_camera.dart';

/// Image overlay (weather radar, satellite swath, …) drawn on the globe.
///
/// flutter_map's `OverlayImageLayer` maps the image onto a quad from four
/// corners, which on a sphere looks like a flat sheet: no curvature, no horizon
/// clipping. This layer tessellates the bounds into a mesh and projects every
/// vertex, so the overlay follows the surface and disappears behind it.
class GlobeImageLayer extends StatefulWidget {
  const GlobeImageLayer({
    super.key,
    required this.image,
    required this.bounds,
    this.opacity = 0.85,
    this.subdivisions = 24,
  });

  final ImageProvider image;
  final LatLngBounds bounds;
  final double opacity;
  final int subdivisions;

  @override
  State<GlobeImageLayer> createState() => _GlobeImageLayerState();
}

class _GlobeImageLayerState extends State<GlobeImageLayer> {
  ui.Image? _image;
  ImageStreamListener? _listener;
  ImageStream? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(GlobeImageLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (identical(stream, _stream)) return;
    _detach();
    _stream = stream;
    _listener = ImageStreamListener((info, _) {
      if (!mounted) {
        info.dispose();
        return;
      }
      setState(() => _image = info.image);
    }, onError: (_, e2) {});
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final image = _image;
    if (image == null) return const SizedBox.shrink();

    return RepaintBoundary(
      child: CustomPaint(
        size: Size(camera.size.x, camera.size.y),
        painter: _ImagePainter(
          camera: camera,
          image: image,
          bounds: widget.bounds,
          opacity: widget.opacity,
          subdivisions: widget.subdivisions,
        ),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter({
    required this.camera,
    required this.image,
    required this.bounds,
    required this.opacity,
    required this.subdivisions,
  });

  final MapCamera camera;
  final ui.Image image;
  final LatLngBounds bounds;
  final double opacity;
  final int subdivisions;

  static const double _eps = 0.01;
  static const double _cutoff = -0.12;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final lat0 = camera.center.latitude * math.pi / 180;
    final lng0 = camera.center.longitude * math.pi / 180;
    final radius = 256 * math.pow(2, camera.zoom) / (2 * math.pi);
    if (radius <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final n = subdivisions.clamp(4, 64);
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

    var allFront = true;
    var anyFront = false;

    for (var j = 0; j <= n; j++) {
      final fy = j / n;
      final lat = north + (south - north) * fy;
      for (var i = 0; i <= n; i++) {
        final fx = i / n;
        final lng = west + (east - west) * fx;
        final v = _view(lng * math.pi / 180, lat * math.pi / 180, lat0, lng0);
        final index = j * (n + 1) + i;

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

    final paint = Paint()
      ..isAntiAlias = true
      ..shader = ui.ImageShader(
        image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        _identity(),
        filterQuality: ui.FilterQuality.low,
      );

    // Opacity via a layer so it applies to the whole mesh uniformly.
    canvas.save();
    canvas.clipPath(
      ui.Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
    if (opacity < 1) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    if (opacity < 1) canvas.restore();
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

  static final Map<int, Uint16List> _indexCache = {};

  static Uint16List _staticIndices(int n) => _indexCache.putIfAbsent(n, () {
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

  static Uint16List _culledIndices(int n, Float32List depths) {
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

        if (z00 <= _eps && z10 <= _eps && z01 <= _eps && z11 <= _eps) {
          continue;
        }
        if (z00 < _cutoff || z10 < _cutoff || z01 < _cutoff || z11 < _cutoff) {
          continue;
        }
        out.addAll([i00, i10, i11, i00, i11, i01]);
      }
    }
    return Uint16List.fromList(out);
  }

  static Float64List _identity() {
    final m = Float64List(16);
    m[0] = 1;
    m[5] = 1;
    m[10] = 1;
    m[15] = 1;
    return m;
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.image != image ||
      oldDelegate.bounds != bounds ||
      oldDelegate.opacity != opacity ||
      oldDelegate.subdivisions != subdivisions;
}
