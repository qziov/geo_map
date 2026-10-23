/// The map host: camera + projector + layers + gestures.
library;

import 'package:flutter/widgets.dart';

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';

import '../camera/geo_map_controller.dart';
import '../gesture/map_gesture_layer.dart';
import '../layer/raster_tile_layer.dart';
import '../source/tile_source.dart';

class GeoMapOptions {
  const GeoMapOptions({
    this.initialCenter = const LatLng(30, 105),
    this.initialZoom = 4,
    this.minZoom = 0,
    this.maxZoom = 18,
    this.projector = const OrthographicProjector(),
    this.background = const Color(0xFF000000),
  });

  final LatLng initialCenter;
  final double initialZoom;
  final double minZoom;
  final double maxZoom;
  final GeoProjector projector;
  final Color background;
}

/// `GeoMap` — the host widget. Children stack on top of the raster layer.
///
/// ```dart
/// GeoMap(
///   options: GeoMapOptions(),
///   source: MbtilesTileSource(...),
///   children: [ /* any widgets; use GeoMapScope.of(context) for the camera */ ],
///   onTap: (latLng) { ... },
/// )
/// ```
class GeoMap extends StatefulWidget {
  const GeoMap({
    required this.options,
    required this.source,
    this.children = const [],
    this.onTap,
    this.rasterOpacity = 1.0,
    this.controller,
    super.key,
  });

  final GeoMapOptions options;
  final GeoTileSource source;
  final List<Widget> children;
  final void Function(LatLng latLng)? onTap;
  final double rasterOpacity;

  /// Optional external controller — pass one to read the camera from outside
  /// (HUD, buttons). If null, an internal controller is created.
  final GeoMapController? controller;

  @override
  State<GeoMap> createState() => _GeoMapState();
}

class _GeoMapState extends State<GeoMap> {
  GeoMapController? _internal;
  late GeoTileEngine _engine; // NOT final: rebuilt when the source changes
  bool _viewportScheduled = false;

  GeoMapController get _controller =>
      widget.controller ?? (_internal ??= _createController());

  GeoMapController _createController() {
    final c = GeoMapController(
      projector: widget.options.projector,
      initial: CameraState(
        center: widget.options.initialCenter,
        zoom: widget.options.initialZoom,
        size: const ViewportSize(1, 1),
        minZoom: widget.options.minZoom,
        maxZoom: widget.options.maxZoom,
      ),
    );
    return c;
  }

  @override
  void initState() {
    super.initState();
    _engine = GeoTileEngine(source: widget.source);
    _engine.onNeedsPaint = _controller.repaint;
  }

  @override
  void didUpdateWidget(covariant GeoMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source) {
      _engine.dispose();
      _engine = GeoTileEngine(source: widget.source);
      _engine.onNeedsPaint = _controller.repaint;
    }
    if (widget.options.projector.kind != _controller.projector.kind) {
      _controller.setProjector(widget.options.projector);
    }
  }

  @override
  void dispose() {
    _engine.dispose();
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = ViewportSize(
        constraints.maxWidth,
        constraints.maxHeight,
      );
      if (!_viewportScheduled) {
        _viewportScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _viewportScheduled = false;
          if (mounted) _controller.setViewport(size);
        });
      }

      return GeoMapScope(
        controller: _controller,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: widget.options.background),
              RasterTileLayer(
                controller: _controller,
                engine: _engine,
                opacity: widget.rasterOpacity,
              ),
              ...widget.children,
              MapGestureLayer(
                controller: _controller,
                onTap: widget.onTap,
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Read-only camera access for children: `GeoMapScope.of(context).value`.
class GeoMapScope extends InheritedNotifier<GeoMapController> {
  const GeoMapScope({
    required GeoMapController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static GeoMapController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GeoMapScope>();
    assert(scope != null, 'GeoMapScope not found — use it inside GeoMap');
    return scope!.notifier!;
  }
}
