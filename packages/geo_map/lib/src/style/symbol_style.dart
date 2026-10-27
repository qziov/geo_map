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
/// (`CollisionIndex`'s group predicate). The label is pushed below the icon —
/// MapLibre instead stacks them by `text-anchor`/`icon-anchor`, which this engine
/// does not implement yet, so the pair layout is fixed rather than style-driven.
library;

import 'package:flutter/painting.dart';
import 'package:geo_map_core/geo_map_core.dart';

import 'sprite_atlas.dart';
import 'symbol_painter.dart';

/// Resolves the symbols for a feature at [anchor].
///
/// [order] must be unique per feature and increasing along the draw order; the
/// pair uses `order` for the icon and `order + 1` for the text so the placer sees
/// them adjacently. Returns an empty list when the feature contributes nothing.
List<SymbolSpec> resolveSymbols({
  required StyleLayer layer,
  required ExpressionContext ctx,
  required Vec2 anchor,
  required SpriteAtlas? sprite,
  required int order,
  required int collisionGroup,
}) {
  final out = <SymbolSpec>[];
  final sortKey = layer.number('symbol-sort-key', ctx) ?? 0;

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
      icon = IconSpec(
        anchor: anchor,
        image: sprite.image,
        source: sprite.sourceRect(iconRef),
        size: size,
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
    // Push the label below the icon so the pair reads as one marker. Without an
    // icon the label stays centred on the anchor.
    final dy = icon == null ? 0.0 : icon.size.height / 2 + fontSize * 0.55;
    out.add(LabelSpec(
      anchor: anchor,
      text: text,
      fontSize: fontSize,
      color: _color(layer.color('text-color', ctx), const Color(0xFF000000)),
      haloColor: _color(layer.color('text-halo-color', ctx), const Color(0x00000000)),
      haloWidth: layer.number('text-halo-width', ctx) ?? 0,
      offset: Vec2(0, dy),
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

Color _color(StyleColor? color, Color fallback) => color == null
    ? fallback
    : Color.fromARGB(color.a, color.r, color.g, color.b);
