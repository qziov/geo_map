/// Immutable camera value object shared by both projections.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../math/geo_geometry.dart';
import '../tuning/geo_engine_tuning.dart';

class CameraState {
  CameraState({
    required this.center,
    required this.zoom,
    required this.size,
    this.minZoom = 0,
    this.maxZoom = 22,
  });

  final LatLng center;
  final double zoom;
  final ViewportSize size;
  final double minZoom;
  final double maxZoom;

  /// Mercator world width in pixels (and the globe circumference in pixels),
  /// so both projections share one zoom scale.
  double get worldSize => GeoEngineTuning.tileSize * math.pow(2, zoom).toDouble();

  /// Globe radius in pixels — identical scale to [worldSize] / 2π.
  double get radiusPx => worldSize / (2 * math.pi);

  double get clampedLatitude => center.latitude.abs() > GeoEngineTuning.maxCameraLatitude
      ? (center.latitude.isNegative ? -GeoEngineTuning.maxCameraLatitude : GeoEngineTuning.maxCameraLatitude)
      : center.latitude;

  CameraState copyWith({
    LatLng? center,
    double? zoom,
    ViewportSize? size,
    double? minZoom,
    double? maxZoom,
  }) =>
      CameraState(
        center: center ?? this.center,
        zoom: zoom ?? this.zoom,
        size: size ?? this.size,
        minZoom: minZoom ?? this.minZoom,
        maxZoom: maxZoom ?? this.maxZoom,
      );

  /// Equality is used to decide "camera unchanged → reuse last Picture".
  @override
  bool operator ==(Object other) =>
      other is CameraState &&
      other.center.latitude == center.latitude &&
      other.center.longitude == center.longitude &&
      other.zoom == zoom &&
      other.size.width == size.width &&
      other.size.height == size.height &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom;

  @override
  int get hashCode => Object.hash(center.latitude, center.longitude, zoom,
      size.width, size.height, minZoom, maxZoom);

  @override
  String toString() => 'CameraState(${center.latitude.toStringAsFixed(4)}, '
      '${center.longitude.toStringAsFixed(4)} z${zoom.toStringAsFixed(2)})';
}
