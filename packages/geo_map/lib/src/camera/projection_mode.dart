/// The single place where "is this camera flat (2D) or a globe (3D)?" is
/// decided (T5d, interface-only convergence).
///
/// Two projection backends still exist — the vendored [MapProjectionDelegate]
/// / [FlatProjectionDelegate] used by `MapCamera`, and core's `GeoProjector`
/// (`MercatorProjector` / `OrthographicProjector`) used by the Canvas painters.
/// This batch deliberately does **not** merge them (BASELINE Q-T5-1); it only
/// funnels every scattered `is FlatProjectionDelegate` check through here so
/// the two backends can never disagree about which mode a frame is in.
///
/// Both functions are strict equivalents of the code they replace: the same
/// predicate, the same method call, therefore identical pixels.
library;

import 'dart:ui' show Offset;

import 'package:latlong2/latlong.dart';

import '../vendor/flutter_map_camera/flat_projection_delegate.dart'
    show FlatProjectionDelegate;
import '../vendor/flutter_map_camera/projection_delegate.dart'
    show MapProjectionDelegate;

/// `true` for the 2D Web-Mercator delegate, `false` for globe or `null`.
///
/// Exactly equivalent to `delegate is FlatProjectionDelegate`, including the
/// `null → false` case (a camera without a delegate is treated as non-flat).
bool isFlatProjection(MapProjectionDelegate? delegate) =>
    delegate is FlatProjectionDelegate;

/// Project a point for an overlay / hit-test, choosing the flat vs globe path.
///
/// Flat uses `projectForVector` (wraps longitude to the world copy nearest the
/// camera, which is what the antimeridian needs); globe uses `project` (the
/// back hemisphere returns a far-off-screen sentinel so the caller can hide).
/// Both methods are declared on [MapProjectionDelegate], so no cast/promotion
/// is required — this is why the branch can live in one place.
Offset projectMapPoint(MapProjectionDelegate delegate, LatLng point) =>
    isFlatProjection(delegate)
        ? delegate.projectForVector(point)
        : delegate.project(point);
