/// MapLibre-shaped facade over the geo_map controllers.
///
/// One object owns the camera, one style document, the feature registry and
/// the popup arbiter. Business code should talk to this handle instead of
/// importing each controller separately. Method names mirror MapLibre's
/// `map.*` / `map.style.*`; `before` is equivalent to MapLibre's `beforeId`.
library;

import 'dart:ui' show Size;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:geo_map_core/geo_map_core.dart' show GeoGeometryKind;
import 'package:latlong2/latlong.dart';

import '../camera/camera_animation.dart'
    show cameraForBounds, flyZoomArc, flyZoomAt;
import '../camera/camera_animator.dart';
import '../camera/geo_map_controller.dart';
import '../query/geo_feature_registry.dart';
import '../style/style_controller.dart';
import '../vendor/flutter_map_camera/flutter_map_camera.dart' show LatLngBounds;
import 'geo_popup_binding.dart';
import 'geo_popup_controller.dart';

/// Reserved parameter slots (T5c).
///
/// MapLibre's `bearing` / `pitch` and the *camera's own* padding offset would
/// tilt/translate the viewport. This batch animates center / zoom / bounds only
/// (BASELINE §1.3), so these arguments are accepted for API compatibility but
/// intentionally have no effect. `fitBounds`' [EdgeInsets] is different: it is
/// the bounds inset and **is** applied (see [cameraForBounds]).
const _kEaseDuration = Duration(milliseconds: 500);
const _kFlyDuration = Duration(milliseconds: 900);
const _kFallbackViewport = Size(256, 256);

class MapHandle {
  MapHandle({
    required this.camera,
    required this.style,
    required this.features,
    this.popups,
  });

  /// Camera / projection mode / gestures.
  final GeoMapController camera;

  /// The single style document. `map.style.*` operations live here:
  /// `addLayer(layer, before:)`, `moveLayer(id, before:)`,
  /// `setPaintProperty`, `setFilter`, `setVisibility`, …
  final GeoStyleController style;

  /// Registered features for `queryRenderedFeatures`.
  final GeoFeatureRegistry features;

  /// Optional popup arbiter for `map.on('click', layerId, handler)`.
  final GeoPopupController? popups;

  late final CameraAnimator _animator = CameraAnimator(camera);

  // --- sources (MapLibre `map.addSource` / `removeSource`) ------------------

  void addSource(String id, Map<String, Object?> source) =>
      style.addSource(id, source);

  void removeSource(String id) => style.removeSource(id);

  // --- query (MapLibre `queryRenderedFeatures`) -----------------------------

  List<GeoQueryHit> queryRenderedFeatures(
    LatLng at, {
    double? pointRadiusPx,
    Set<String>? sourceIds,
    Set<GeoGeometryKind>? geometries,
    int? limit,
  }) =>
      features.queryFeatures(
        at,
        controller: camera,
        pointRadiusPx: pointRadiusPx,
        sourceIds: sourceIds,
        geometries: geometries,
        limit: limit,
      );

  // --- events (MapLibre `map.on('click', layerId, handler)`) ----------------

  void onTap(String sourceId, GeoPopupBinding binding) =>
      popups?.registerPopup(sourceId, binding);

  void offTap(String sourceId) => popups?.unregisterPopup(sourceId);

  // --- camera ---------------------------------------------------------------

  /// Immediate move. Cancels any running eased animation first.
  void jumpTo({LatLng? center, double? zoom}) {
    _animator.cancel();
    camera.move(center ?? camera.center, zoom ?? camera.zoom);
  }

  void setCenter(LatLng center) => jumpTo(center: center);

  void setZoom(double zoom) => jumpTo(zoom: zoom);

  /// MapLibre `easeTo`: a smooth center/zoom transition with an easing curve.
  ///
  /// Omitted fields keep their current value. [bearing], [pitch] and
  /// [padding] are reserved and ignored (see the library note above).
  /// The returned future completes when the animation ends **or** is replaced
  /// by a newer camera command, so awaiting it is always safe.
  Future<void> easeTo({
    LatLng? center,
    double? zoom,
    Duration duration = _kEaseDuration,
    Curve curve = Curves.easeInOut,
    double? bearing,
    double? pitch,
    EdgeInsets? padding,
  }) {
    final toCenter = center ?? camera.center;
    final toZoom = (zoom ?? camera.zoom).clamp(camera.minZoom, camera.maxZoom);
    return _animator.run(
      toCenter: toCenter,
      toZoom: toZoom,
      duration: duration,
      curve: curve,
    );
  }

  /// MapLibre `flyTo`: like [easeTo] but pulls the camera back in the middle
  /// of a long move ("zoom out, travel, zoom in"). The arch height is derived
  /// from the on-screen travel distance; the endpoint is exact.
  Future<void> flyTo({
    required LatLng center,
    double? zoom,
    Duration? duration,
    Curve curve = Curves.easeInOut,
    double? bearing,
    double? pitch,
    EdgeInsets? padding,
  }) {
    final fromZoom = camera.zoom;
    final toZoom = (zoom ?? fromZoom).clamp(camera.minZoom, camera.maxZoom);
    final viewport =
        camera.viewport.isEmpty ? _kFallbackViewport : camera.viewport;
    final arc = flyZoomArc(
      from: camera.center,
      to: center,
      startZoom: fromZoom,
      viewport: viewport,
    );
    return _animator.run(
      toCenter: center,
      toZoom: toZoom,
      duration: duration ?? _kFlyDuration,
      curve: curve,
      zoomOverride: (eased) => flyZoomAt(
        startZoom: fromZoom,
        targetZoom: toZoom,
        arc: arc,
        t: eased,
      ).clamp(camera.minZoom, camera.maxZoom),
    );
  }

  /// MapLibre `fitBounds`: compute the centre + zoom that fits [bounds] inside
  /// the viewport (minus [padding]) and ease there. [maxZoom] caps the result.
  Future<void> fitBounds(
    LatLngBounds bounds, {
    EdgeInsets padding = EdgeInsets.zero,
    Duration duration = _kEaseDuration,
    Curve curve = Curves.easeInOut,
    double? maxZoom,
    double? bearing,
    double? pitch,
  }) {
    final viewport =
        camera.viewport.isEmpty ? _kFallbackViewport : camera.viewport;
    final target = cameraForBounds(
      bounds,
      viewport: viewport,
      minZoom: camera.minZoom,
      maxZoom: camera.maxZoom,
      padding: padding,
      maxZoomCap: maxZoom,
    );
    return _animator.run(
      toCenter: target.center,
      toZoom: target.zoom,
      duration: duration,
      curve: curve,
    );
  }

  /// Cancel any running animation. Call from the owning provider's dispose.
  void dispose() => _animator.dispose();
}
