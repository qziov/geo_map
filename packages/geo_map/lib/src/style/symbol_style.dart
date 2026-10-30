/// Turns one feature into the symbols it contributes: an icon, a label, or both.
///
/// This is the shared half of the two painters (`MvtVectorLayer` and
/// `StyleVectorLayer`) — the part that reads style properties and needs no
/// geometry. MapLibre does the same work in `symbol_layout.ts` (`addFeature` →
/// icon quad + text quads), with one difference: it looks icons up in a sprite
/// atlas through `imagePositions`, which is what [sprite] is here.
///
/// The icon and its label are returned as a **pair**: same `collisionGroup`, so
/// `SymbolPlacer` lets them overlap each other but not the world
/// (`CollisionIndex`'s group predicate). `text-anchor` / `icon-anchor` +
/// `text-offset` / `icon-offset` position each box relative to the anchor; when an
/// icon is present the label keeps a small downward bias so the pair reads as one
/// marker unless the style overrides it.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:geo_map_core/geo_map_core.dart';

import 'sprite_atlas.dart';
import 'symbol_painter.dart';

/// Resolves the symbols for a feature at [anchor].
///
/// [order] must be unique per feature and increasing along the draw order; the
/// pair uses `order` for the icon and `order + 1` for the text so the placer sees
/// them adjacently. Returns an empty list when the feature contributes nothing.
///
/// [lineAngle] is the local segment angle (radians) for `symbol-placement: line`;
/// it is 0 for point placement and is added to `text-rotate` / `icon-rotate`.
/// [baseKey] is the feature's stable identity (world coordinate for MVT, feature
/// id/properties for GeoJSON); it seeds [SymbolSpec.crossTileKey] so the same
/// logical label drawn from two tiles collapses to one. [sourceLayer] namespaces
/// that key.
List<SymbolSpec> resolveSymbols({
  required StyleLayer layer,
  required ExpressionContext ctx,
  required Vec2 anchor,
  required SpriteAtlas? sprite,
  required int order,
  required int collisionGroup,
  double lineAngle = 0,
  String? baseKey,
  required String sourceLayer,
}) {
  final out = <SymbolSpec>[];
  final sortKey = layer.number('symbol-sort-key', ctx) ?? 0;

  final textAnchor = layer.string('text-anchor', ctx) ?? 'center';
  final iconAnchor = layer.string('icon-anchor', ctx) ?? 'center';
  final textRotate = (layer.number('text-rotate', ctx) ?? 0) * (math.pi / 180);
  final iconRotate = (layer.number('icon-rotate', ctx) ?? 0) * (math.pi / 180);
  final textOffset = _offsetVec(layer.valueOf('text-offset', ctx));
  final iconOffset = _offsetVec(layer.valueOf('icon-offset', ctx));

  IconSpec? icon;
  final imageName = _string(layer.valueOf('icon-image', ctx));
  final iconRef = imageName == null ? null : sprite?[imageName];
  if (imageName != null && iconRef != null && sprite != null) {
    final iconSize = layer.number('icon-size', ctx) ?? 1;
    final size = Size(
      iconRef.displayWidth * iconSize,
      iconRef.displayHeight * iconSize,
    );
    if (size.width > 0 && size.height > 0) {
      // Only SDF sprites are tinted; `icon-color` recolours a monochrome icon.
      final tint = iconRef.sdf
          ? _color(layer.color('icon-color', ctx), const Color(0xFF000000))
          : null;
      icon = IconSpec(
        anchor: anchor,
        image: sprite.image,
        source: sprite.sourceRect(iconRef),
        size: size,
        sdf: iconRef.sdf,
        tint: tint,
        offset: iconOffset,
        rotation: lineAngle + iconRotate,
        anchorName: iconAnchor,
        crossTileKey: _instanceKey(baseKey, sourceLayer, imageName, 'i'),
        allowOverlap: layer.valueOf('icon-allow-overlap', ctx) == true,
        ignorePlacement: layer.valueOf('icon-ignore-placement', ctx) == true,
        sortKey: sortKey,
        order: order,
        collisionGroup: collisionGroup,
      );
      out.add(icon);
    }
  }

  final text = _string(layer.valueOf('text-field', ctx));
  if (text != null && text.isNotEmpty) {
    final fontSize = layer.number('text-size', ctx) ?? 16;
    final opacity = layer.number('text-opacity', ctx) ?? 1;
    // Keep the label below an icon unless the style positions it otherwise.
    final dy = icon == null ? 0.0 : icon.size.height / 2 + fontSize * 0.55;
    final labelOffset = Vec2(textOffset.x * fontSize, textOffset.y * fontSize + dy);
    out.add(LabelSpec(
      anchor: anchor,
      text: text,
      fontSize: fontSize,
      color: _color(layer.color('text-color', ctx), const Color(0xFF000000)),
      haloColor: _color(layer.color('text-halo-color', ctx), const Color(0x00000000)),
      haloWidth: layer.number('text-halo-width', ctx) ?? 0,
      opacity: opacity,
      offset: labelOffset,
      rotation: lineAngle + textRotate,
      anchorName: textAnchor,
      crossTileKey: _instanceKey(baseKey, sourceLayer, text, 't'),
      allowOverlap: layer.valueOf('text-allow-overlap', ctx) == true,
      ignorePlacement: layer.valueOf('text-ignore-placement', ctx) == true,
      sortKey: sortKey,
      order: order + 1,
      collisionGroup: collisionGroup,
    ));
  }
  return out;
}

/// Style expressions may yield numbers or strings for a text field.
String? _string(Object? value) {
  if (value == null) return null;
  final text = '$value';
  return text.isEmpty ? null : text;
}

/// `text-offset` / `icon-offset` come in as a `[x, y]` array (style default
/// `[0, 0]`). Returns it in doubles; the caller scales `text-offset` by font size
/// (ems) but uses `icon-offset` as-is (pixels).
Vec2 _offsetVec(Object? value) {
  if (value is! List || value.length < 2) return const Vec2(0, 0);
  final x = (value[0] as num?)?.toDouble() ?? 0;
  final y = (value[1] as num?)?.toDouble() ?? 0;
  return Vec2(x, y);
}

/// Builds a per-symbol cross-tile key. `null` [baseKey] disables deduplication;
/// the `i`/`t` suffix keeps an icon and its label from deduplicating each other
/// within one feature (they are separate instances, like MapLibre's crossTileID).
String? _instanceKey(
  String? baseKey,
  String sourceLayer,
  String? tag,
  String suffix,
) {
  if (baseKey == null) return null;
  return '$baseKey:$sourceLayer:${tag ?? ''}:$suffix';
}

Color _color(StyleColor? color, Color fallback) => color == null
    ? fallback
    : Color.fromARGB(color.a, color.r, color.g, color.b);
