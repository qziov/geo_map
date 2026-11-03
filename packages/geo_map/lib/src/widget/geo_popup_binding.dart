import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../query/geo_query_hit.dart';

/// Popup anchor — the nine-grid position (MapLibre `PositionAnchor`).
///
/// Decides which edge/corner of the card sits against the anchor latitude/
/// longitude carried by [GeoMapPopupController]. Defaults to [bottom], which
/// keeps the existing "card floats above the anchor" behaviour.
enum PopupAnchor {
  center,
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// A binding that ties a layer (its `sourceId` in [GeoFeatureRegistry]) to the
/// card shown when that layer is tapped.
///
/// This is the SDK equivalent of MapLibre's `map.on('click', layerId, handler)`:
/// the "layer" in our model is a `sourceId`, and binding a popup to it is how a
/// business layer declares "when I'm hit, render this card". Hit-testing, anchor
/// projection, positioning and close are all handled by [GeoPopupController] —
/// the business side only supplies [builder] (the card) plus a little metadata.
class GeoPopupBinding {
  const GeoPopupBinding({
    this.priority = 0,
    required this.cardSize,
    this.anchor = PopupAnchor.bottom,
    this.anchorOf,
    required this.builder,
  });

  /// Arbitration priority when several layers are hit at once (e.g. a SIGMET
  /// polygon overlapping an airport). Higher wins; ties go to the first hit in
  /// the query result (already sorted by screen distance within a source).
  final int priority;

  /// The card's logical maximum size, used by the layout to clamp inside
  /// [GeoMapPopupHost.keepOut]. Pass the card's real maximum width/height.
  final Size cardSize;

  /// Which side of the card meets the anchor (nine-grid).
  final PopupAnchor anchor;

  /// Override the default anchor point. The default is the tap point (MapLibre
  /// `setLngLat(e.lngLat)` semantics); pass this to pin the bubble to the
  /// feature geometry instead (e.g. an airport icon's own coordinate).
  final LatLng? Function(GeoQueryHit hit)? anchorOf;

  /// The business card builder, invoked by the render host after a hit. Receive
  /// the [GeoQueryHit] to map its `feature.id` back to your domain object.
  final Widget Function(BuildContext context, GeoQueryHit hit) builder;
}
