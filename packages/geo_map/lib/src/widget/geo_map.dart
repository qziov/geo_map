/// The map host: vendored (fork) camera + the shared tile engine + gestures.
///
/// The rendering stack is the lab-proven one: a single [TileLayer] driven by
/// a [TileEngine]; 2D and 3D differ only in the projection and the geometry
/// backend, so both modes share one tile cache.
library;

import 'package:flutter/widgets.dart';

import 'package:latlong2/latlong.dart';

import '../camera/geo_map_controller.dart';
import '../engine/tile_engine.dart';
import '../engine/tile_layer.dart';
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

  /// One engine for both modes: switching between 2D and 3D then reuses the
  /// decoded tiles instead of downloading them again.
  ///
  /// This state owns it, and only this state disposes it. The tile layers are
  /// told to *borrow* it — a layer that disposed it while being unmounted for
  /// the 2D/3D switch would kill every in-flight decode.
  late TileEngine _engine;

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
  void initState() {
    super.initState();
    _engine = TileEngine(source: widget.source);
  }

  @override
  void didUpdateWidget(covariant GeoMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      // A different source cannot share the cache: retire the old engine after
      // the frame (it may still be listened to while the tree rebuilds).
      final old = _engine;
      _engine = TileEngine(source: widget.source);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
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
    _engine.dispose();
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
                // One widget type for both modes: switching 2D/3D then updates
                // this element instead of unmounting it, so the mesh cache and
                // the decoded tiles survive the switch.
                TileLayer(
                  source: widget.source,
                  engine: _engine,
                  mode: _globe
                      ? TileLayerMode.globe
                      : TileLayerMode.mercator,
                ),
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
