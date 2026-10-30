/// Screen projection for feature picking.
///
/// Picking needs a screen position, and the two projections disagree about
/// what to do with a point that is not on screen. This file is the single
/// place where those differences are reconciled.
///
/// * **Flat** → `projectForVector`, which folds the longitude onto the world
///   copy nearest the camera. Plain `project` does **not** wrap: with the
///   camera at −179° and a feature at +179°, the plain projection puts the
///   feature a whole world away, so the tap could never reach it.
/// * **Globe** → `project`, which throws the far side of the sphere far off
///   screen (`(-1e6, -1e6)`). `projectForVector` would instead clamp the
///   point onto the silhouette, letting a back-side feature falsely hit a
///   point near the limb.
///
/// `isVisible` is **not** a substitute for the sentinel check: the globe
/// delegate accepts points down to `z > -0.03` while `project` rejects
/// `z <= 0`, so the two disagree on a thin band near the horizon.
library;

import 'dart:ui' show Offset;

import 'package:geo_map_core/geo_map_core.dart' show GeoEngineTuning, Vec2;
import 'package:latlong2/latlong.dart';

import '../vendor/flutter_map_camera/flat_projection_delegate.dart'
    show FlatProjectionDelegate;
import '../vendor/flutter_map_camera/projection_delegate.dart'
    show MapProjectionDelegate;

/// The screen position of [point] for picking, or `null` when it cannot be
/// picked (the far side of the globe, or a non-finite coordinate).
Vec2? projectForPick(MapProjectionDelegate delegate, LatLng point) {
  final Offset offset = delegate is FlatProjectionDelegate
      ? delegate.projectForVector(point)
      : delegate.project(point);

  if (!offset.dx.isFinite || !offset.dy.isFinite) return null;

  // The globe's "not drawable" sentinel is a *finite* coordinate, so a naive
  // distance check would treat it as "very far away" instead of "not
  // pickable". Both end in a miss, but the sentinel has to be recognised.
  final sentinel = GeoEngineTuning.hiddenPointSentinelPx;
  if (offset.dx.abs() >= sentinel || offset.dy.abs() >= sentinel) return null;

  return Vec2(offset.dx, offset.dy);
}
