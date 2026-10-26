/// 2D (Web Mercator) raster layer.
///
/// The plane differs from the globe only in the projection
/// ([MercatorProjector]) and the geometry backend ([AffineGeometry]) —
/// selection, requests, the fallback chain and the cache are the same code
/// inside [TileLayer], so a fix in one mode cannot leave the other broken.
///
/// The old implementation of this file had its own cache with a
/// **2-strike blacklist**: a tile that failed twice was never requested
/// again, and the hole stayed black forever. MapLibre never blacklists a 404
/// — it keeps the tile in the ideal set and falls back to the parent. That
/// behaviour now lives in the shared engine.
///
/// Pass an [engine] to share the decoded tiles with the 3D layer. The engine
/// is then owned by **the caller**: this layer will never dispose it.
library;

import 'package:flutter/widgets.dart';

import '../engine/tile_engine.dart';
import '../engine/tile_layer.dart';
import 'tile_source.dart';

class FlatTileLayer extends StatelessWidget {
  const FlatTileLayer({
    required this.source,
    this.engine,
    super.key,
  });

  final GlobeRasterSource source;

  /// The shared engine. When `null` the layer creates one and owns it.
  final TileEngine? engine;

  @override
  Widget build(BuildContext context) => TileLayer(
        source: source,
        engine: engine,
        mode: TileLayerMode.mercator,
      );
}
