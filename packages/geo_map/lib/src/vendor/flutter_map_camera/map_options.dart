/// Minimal re-implementation of the flutter_map `MapOptions` surface that the
/// vendored `MapCamera` actually reads (7 fields). Part of the vendored
/// flutter_map camera extraction — see PATCHES provenance in docs.
library;

import 'package:latlong2/latlong.dart';

import 'crs.dart';
import 'projection_delegate.dart';

/// Options subset consumed by `MapCamera.initialCamera` / `withOptions`.
class MapOptions {
  const MapOptions({
    this.crs = const Epsg3857(),
    this.projectionDelegate,
    this.minZoom = 0,
    this.maxZoom = double.infinity,
    this.initialCenter = const LatLng(50.5, 30.51),
    this.initialZoom = 13,
    this.initialRotation = 0,
  });

  final Crs crs;
  final MapProjectionDelegate? projectionDelegate;
  final double minZoom;
  final double maxZoom;
  final LatLng initialCenter;
  final double initialZoom;
  final double initialRotation;

  @override
  bool operator ==(Object other) =>
      other is MapOptions &&
      other.crs == crs &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.projectionDelegate == projectionDelegate;

  @override
  int get hashCode =>
      Object.hash(crs, minZoom, maxZoom, projectionDelegate);
}
