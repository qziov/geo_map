/// Resolves the **draw set** for a frame of vector tiles.
///
/// `planTileResolution` already decides, for one ideal tile, whether to use the
/// tile itself, a complete generation of children, or a loaded ancestor. This
/// file turns those per-tile decisions into the three lists the painter needs:
///
/// * [VectorDrawTiles.placeholders] — ancestors drawn **first**, as stand-ins
///   while their descendants are in flight;
/// * [VectorDrawTiles.ready] — exact tiles and loaded children, drawn over the
///   placeholders;
/// * [VectorDrawTiles.missing] — nothing loaded yet (nothing to draw).
///
/// Key order matters: placeholders come first so a loaded tile always wins over
/// a coarse stand-in. Both lists are deduplicated — four ideals under one
/// ancestor must draw that ancestor once, not four times.
library;

import '../tiles/tile_fallback.dart';
import '../tiles/tile_scheme.dart';

class VectorDrawTiles {
  const VectorDrawTiles({
    required this.placeholders,
    required this.ready,
    required this.missing,
  });

  /// Ancestor tiles to draw before the exact ones (deduplicated, order kept).
  final List<TileKey> placeholders;

  /// Exact tiles or complete child generations (deduplicated, order kept).
  final List<TileKey> ready;

  /// Ideals with nothing drawable yet.
  final List<TileKey> missing;

  /// Placeholders followed by ready tiles — the painter's draw order.
  List<TileKey> get drawOrder => [...placeholders, ...ready];

  @override
  String toString() => 'VectorDrawTiles(placeholders: ${placeholders.length}, '
      'ready: ${ready.length}, missing: ${missing.length})';
}

/// Resolves [visible] ideals against the decoded cache.
VectorDrawTiles resolveVectorDrawTiles({
  required List<TileKey> visible,
  required bool Function(TileKey key) isLoaded,
  required int sourceMinZoom,
  required int sourceMaxZoom,
  required TileSchemeKind scheme,
}) {
  final placeholders = <TileKey>[];
  final ready = <TileKey>[];
  final missing = <TileKey>[];
  final seenPlaceholder = <TileKey>{};
  final seenReady = <TileKey>{};

  for (final ideal in visible) {
    final decision = planTileResolution(
      ideal: ideal,
      sourceMinZoom: sourceMinZoom,
      sourceMaxZoom: sourceMaxZoom,
      scheme: scheme,
      isLoaded: isLoaded,
    );
    switch (decision.kind) {
      case TileFallbackKind.exact:
        if (seenReady.add(ideal)) ready.add(ideal);
      case TileFallbackKind.descendants:
        for (final child in decision.children) {
          if (seenReady.add(child)) ready.add(child);
        }
      case TileFallbackKind.ancestor:
        final ancestor = decision.ancestor!;
        if (seenPlaceholder.add(ancestor)) placeholders.add(ancestor);
      case TileFallbackKind.none:
        missing.add(ideal);
    }
  }

  return VectorDrawTiles(
    placeholders: placeholders,
    ready: ready,
    missing: missing,
  );
}
