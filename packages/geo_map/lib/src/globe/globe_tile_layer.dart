/// 3D globe raster layer.
///
/// The globe differs from the 2D plane only in the projection
/// ([OrthographicProjector]) and the geometry backend ([SphericalGeometry]) —
/// selection, the request layer, the fallback chain and the polar cap are
/// literally the same code, and they live in [TileLayer].
///
/// The old implementation of this file kept its own tile cache, its own
/// selection scan (every row of the grid) and its own fallback rules. That is
/// exactly what made 2D and 3D drift apart, and it is where the high-latitude
/// black tiles came from: the old grid used **linear** latitudes for Web
/// Mercator, so the row a tile belonged to was wrong everywhere above ~60°.
///
/// Pass an [engine] to share the decoded tiles with the 2D layer — switching
/// between 2D and 3D then costs nothing. The engine is then owned by **the
/// caller**: this layer will never dispose it.
library;

import 'package:flutter/widgets.dart';

import '../engine/tile_engine.dart';
import '../engine/tile_layer.dart';
import 'tile_source.dart';

class GlobeTileLayer extends StatelessWidget {
  const GlobeTileLayer({
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
        mode: TileLayerMode.globe,
      );
}
