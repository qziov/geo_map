/// The map host: vendored (fork) camera + lab-verified globe layers + gestures.
///
/// This is geo_map 1.0 — the rendering stack is the lab-proven one
/// (`globe_tile_layer` / `globe_vector_layer` / `globe_image_layer` on the
/// vendored `MapCamera` + `GlobeProjectionDelegate`). The self-built Vertices
/// pipeline lives in `experimental/` and is not exported.
library;

import 'package:flutter/widgets.dart';

import 'package:latlong2/latlong.dart';

import '../camera/geo_map_controller.dart';
import '../globe/flat_tile_layer.dart';
import '../globe/globe_tile_layer.dart';
import '../globe/tile_source.dart';
import '../gesture/globe_gesture_overlay.dart';
import '../vendor/flutter_map_camera/flutter_map_camera.dart';

class GeoMapOptions {
  const GeoMapOptions({
    this.initialCenter = const LatLng(30, 105),
    this.initialZoom = 4.2,
    this.minZoom = 1,
    this.maxZoom = 8,
    this.useGlobe = true,
    this.background = const Color(0xFF000000),
  });

  final LatLng initialCenter;
  final double initialZoom;
  final double minZoom;
  final double maxZoom;

  /// true = 正交球面（3D）；false = Web Mercator 平面（2D）。
  /// 切换时 center/zoom 连续（经 delegate 的 anchorCenter 各自实现）。
  final bool useGlobe;

  final Color background;
}

/// `GeoMap` — the host widget. Children stack on top of the raster layer.
class GeoMap extends StatefulWidget {
  const GeoMap({
    required this.options,
    required this.source,
    this.controller,
    this.children = const [],
    this.onTap,
    super.key,
  });

  final GeoMapOptions options;
  final GlobeRasterSource source;
  final GeoMapController? controller;
  final List<Widget> children;
  final void Function(LatLng latLng)? onTap;

  @override
  State<GeoMap> createState() => _GeoMapState();
}

class _GeoMapState extends State<GeoMap> {
  GeoMapController? _internal;
  bool _viewportScheduled = false;
  late bool _globe = widget.options.useGlobe;

  GeoMapController get _controller =>
      widget.controller ??
      (_internal ??= GeoMapController(
        useGlobe: widget.options.useGlobe,
        initialCenter: widget.options.initialCenter,
        initialZoom: widget.options.initialZoom,
        minZoom: widget.options.minZoom,
        maxZoom: widget.options.maxZoom,
      ));

  @override
  void didUpdateWidget(covariant GeoMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null &&
        (widget.options.minZoom != _controller.minZoom ||
            widget.options.maxZoom != _controller.maxZoom)) {
      _controller.applyConstraints(
        minZoom: widget.options.minZoom,
        maxZoom: widget.options.maxZoom,
      );
    }
    if (widget.options.useGlobe != _globe) {
      setState(() {
        _globe = widget.options.useGlobe;
        _controller.setMode(_globe);
      });
    }
  }

  @override
  void dispose() {
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (!_viewportScheduled) {
        _viewportScheduled = true;
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _viewportScheduled = false;
          if (mounted) _controller.setViewport(size);
        });
      }

      return ClipRect(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => MapInheritedModel(
            camera: _controller.camera,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: widget.options.background),
                if (_globe)
                  GlobeTileLayer(source: widget.source)
                else
                  FlatTileLayer(source: widget.source),
                ...widget.children,
                GlobeGestureOverlay(
                  controller: _controller,
                  onTap: widget.onTap,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Read-only camera access for children: `GeoMapScope.of(context).camera`.
class GeoMapScope extends StatelessWidget {
  const GeoMapScope({required this.controller, required this.child, super.key});

  final GeoMapController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => MapInheritedModel(
        camera: controller.camera,
        child: child,
      );
}
