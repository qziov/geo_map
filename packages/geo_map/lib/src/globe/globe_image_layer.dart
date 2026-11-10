/// Image overlay (weather radar, satellite swath, …) drawn on the globe.
///
/// flutter_map's `OverlayImageLayer` maps the image onto a quad from four
/// corners, which on a sphere looks like a flat sheet: no curvature, no horizon
/// clipping. This layer tessellates the bounds into a mesh and projects every
/// vertex, so the overlay follows the surface and disappears behind it.
///
/// The actual drawing lives in `image_overlay.dart` (`paintImageOverlay`) so the
/// style raster layer renders exactly the same pixels.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../vendor/flutter_map_camera/flutter_map_camera.dart'
    show LatLngBounds, MapCamera;
import 'image_overlay.dart' show paintImageOverlay;

class GlobeImageLayer extends StatefulWidget {
  const GlobeImageLayer({
    super.key,
    required this.image,
    required this.bounds,
    this.opacity = 0.85,
    this.subdivisions = 24,
    /// 当图片本身是 **Web Mercator** 投影渲染时（如 WAFS 全球 PNG），
    /// 把网格也按 Mercator y 均匀细分、UV v 用同一 Mercator v 值，
    /// 让几何和 UV 采样共用同一个空间，避免平面模式下的拉伸和条纹。
    ///
    /// 等经纬度 / Plate-Carrée 投影的图层（卫星图、雷达拼图）不要开，
    /// 保持默认的线性纬度采样。
    this.mercatorSampling = false,
  });

  final ImageProvider image;
  final LatLngBounds bounds;
  final double opacity;
  final int subdivisions;
  final bool mercatorSampling;

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
          mercatorSampling: widget.mercatorSampling,
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
    required this.mercatorSampling,
  });

  final MapCamera camera;
  final ui.Image image;
  final LatLngBounds bounds;
  final double opacity;
  final int subdivisions;
  final bool mercatorSampling;

  @override
  void paint(Canvas canvas, Size size) => paintImageOverlay(
        canvas,
        size,
        camera: camera,
        image: image,
        bounds: bounds,
        opacity: opacity,
        mercatorSampling: mercatorSampling,
        subdivisions: subdivisions,
      );

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.image != image ||
      oldDelegate.bounds != bounds ||
      oldDelegate.opacity != opacity ||
      oldDelegate.subdivisions != subdivisions ||
      oldDelegate.mercatorSampling != mercatorSampling;
}
