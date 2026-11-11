/// Incremental updates for a GeoJSON source.
///
/// Mirrors `maplibre-gl-js/src/source/geojson_source_diff.ts`: operations are
/// applied in a fixed **remove -> add -> update** order so the result is
/// predictable regardless of how the caller ordered the fields.
///
/// Deliberate scope differences (geo_map has no worker / geojson-vt pipeline):
/// * `mergeSourceDiffs` and `UpdateQueue` are **not** ported. MapLibre needs
///   them because `setData`/`updateData` are async messages to a worker and
///   can be superseded while in flight. Here the update is synchronous, so
///   "last call wins" holds trivially and there is no stale-result path to
///   guard against.
/// * `affectedGeometries` (used by MapLibre to reload only the touched tiles)
///   is reported as an [affectedCount] instead: geo_map draws the whole
///   source in one `CustomPainter`, so there are no tiles to invalidate.
library;

import 'geojson.dart';

/// A change to one source's data.
class GeoSourceDiff {
  const GeoSourceDiff({
    this.removeAll = false,
    this.remove = const <String>[],
    this.add = const <GeoJsonFeature>[],
    this.update = const <GeoSourceUpdate>[],
  });

  /// Remove every feature before applying the rest of the diff.
  final bool removeAll;

  /// Ids to remove. Unknown ids are ignored (MapLibre: best-effort updates).
  final List<String> remove;

  /// Features to add / replace. A feature with the same id overwrites the
  /// existing one; a feature without an id is skipped, matching MapLibre's
  /// `getFeatureId(...) == null -> continue` rather than silently inventing
  /// an id.
  final List<GeoJsonFeature> add;

  /// Property / geometry updates, keyed by feature id.
  final List<GeoSourceUpdate> update;

  bool get isEmpty =>
      !removeAll && remove.isEmpty && add.isEmpty && update.isEmpty;
}

/// An update to one feature, following MapLibre's `GeoJSONFeatureDiff`:
/// new geometry, remove properties, add/update properties.
class GeoSourceUpdate {
  const GeoSourceUpdate({
    required this.id,
    this.newGeometry,
    this.removeAllProperties = false,
    this.removeProperties = const <String>[],
    this.addOrUpdateProperties = const <String, Object?>{},
  });

  final String id;
  final GeoJsonGeometry? newGeometry;
  final bool removeAllProperties;
  final List<String> removeProperties;
  final Map<String, Object?> addOrUpdateProperties;

  bool get isNoOp =>
      newGeometry == null &&
      !removeAllProperties &&
      removeProperties.isEmpty &&
      addOrUpdateProperties.isEmpty;
}

/// Index features by id, or return `null` when the source is **not
/// updateable**.
///
/// MapLibre's `toUpdateable` refuses a FeatureCollection unless every feature
/// has a unique id — otherwise an incremental update would silently drop
/// features. Two boundary rules are preserved here:
/// * `null` means "no id"; an **empty string is a valid id** (MapLibre calls
///   out that `0` is a valid id and must not be treated as falsy).
/// * duplicate ids make the whole source non-updateable.
Map<String, GeoJsonFeature>? indexFeaturesById(
    List<GeoJsonFeature> features) {
  // A plain Dart Map literal is a LinkedHashMap: insertion order is preserved,
  // so an unchanged feature keeps its position after an incremental update.
  final out = <String, GeoJsonFeature>{};
  for (final feature in features) {
    final id = feature.id;
    if (id == null) return null;
    if (out.containsKey(id)) return null;
    out[id] = feature;
  }
  return out;
}

/// Apply [diff] to [current] in remove -> add -> update order.
///
/// Returns the resulting list, whether anything actually changed, and how many
/// features were affected. When [current] is not updateable (missing or
/// duplicate ids) the diff is rejected with `changed: false` rather than
/// throwing — callers can fall back to a full `setData`.
({
  List<GeoJsonFeature> features,
  bool changed,
  int affectedCount,
}) applySourceDiff(List<GeoJsonFeature> current, GeoSourceDiff diff) {
  final indexed = indexFeaturesById(current);
  if (indexed == null) {
    return (features: current, changed: false, affectedCount: 0);
  }

  var changed = false;
  var affected = 0;

  if (diff.removeAll) {
    if (indexed.isNotEmpty) {
      affected = indexed.length;
      indexed.clear();
      changed = true;
    }
  } else {
    for (final id in diff.remove) {
      if (indexed.remove(id) != null) {
        affected++;
        changed = true;
      }
    }
  }

  for (final feature in diff.add) {
    final id = feature.id;
    if (id == null) continue;
    indexed[id] = feature;
    affected++;
    changed = true;
  }

  for (final update in diff.update) {
    if (update.isNoOp) continue;
    final existing = indexed[update.id];
    if (existing == null) continue;

    final props = <String, Object?>{};
    if (!update.removeAllProperties) props.addAll(existing.properties);
    for (final key in update.removeProperties) {
      props.remove(key);
    }
    props.addAll(update.addOrUpdateProperties);

    indexed[update.id] = GeoJsonFeature(
      id: existing.id,
      properties: Map<String, Object?>.unmodifiable(props),
      geometry: update.newGeometry ?? existing.geometry,
    );
    affected++;
    changed = true;
  }

  return (
    features: changed
        ? List<GeoJsonFeature>.unmodifiable(indexed.values)
        : current,
    changed: changed,
    affectedCount: affected,
  );
}
