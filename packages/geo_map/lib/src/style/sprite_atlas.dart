/// Sprite atlas: the PNG behind `icon-image`, plus the index that locates icons
/// inside it.
///
/// MapLibre loads a sprite as two requests — `<url>.json` and `<url>.png`
/// (`style/load_sprite.ts:39-53`) — and looks up icons by name when laying out a
/// symbol (`symbol/symbol_layout.ts`, `image.pixelRatio` guards a mixed-density
/// atlas at `:240`). This file is the decoded form of that pair: one `ui.Image`
/// and the `SpriteIndex`.
///
/// The atlas is *not* split into per-icon images: drawing is a single
/// `drawImageRect` per icon against the atlas, which is also how MapLibre keeps
/// it to one texture per sprite.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:geo_map_core/geo_map_core.dart';

class SpriteAtlas {
  SpriteAtlas({required this.image, required this.index});

  /// The decoded atlas.
  final ui.Image image;

  /// Where each icon lives inside [image].
  final SpriteIndex index;

  SpriteIcon? operator [](String name) => index[name];

  int get length => index.length;

  /// Rectangular region of [image] occupied by [icon].
  Rect sourceRect(SpriteIcon icon) =>
      Rect.fromLTWH(icon.x, icon.y, icon.width, icon.height);

  /// Decodes a sprite from its JSON text and PNG bytes.
  ///
  /// Returns `null` when the image cannot be decoded — the caller keeps drawing
  /// labels and simply drops the icons, which is better than losing the layer.
  static Future<SpriteAtlas?> decode({
    required String json,
    required List<int> imageBytes,
  }) async {
    if (imageBytes.isEmpty) return null;
    SpriteIndex index;
    try {
      index = SpriteIndex.parse(jsonDecode(json));
    } catch (_) {
      index = const SpriteIndex({});
    }
    try {
      final codec = await ui.instantiateImageCodec(
        imageBytes is Uint8List ? imageBytes : Uint8List.fromList(imageBytes),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return SpriteAtlas(image: frame.image, index: index);
    } catch (_) {
      return null;
    }
  }

  void dispose() => image.dispose();
}
