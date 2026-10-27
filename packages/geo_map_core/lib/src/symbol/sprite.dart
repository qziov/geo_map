/// Sprite atlas index: the JSON that ships next to a `<sprite>.png`.
///
/// MapLibre's format (`style/style_image.ts:4-9`):
///
/// ```json
/// { "cafe-11": { "x": 0, "y": 0, "width": 32, "height": 32, "pixelRatio": 1 } }
/// ```
///
/// `pixelRatio` is not decoration: the drawn size is `width / pixelRatio`
/// (MapLibre divides by it when it turns sprite pixels into tile units,
/// `symbol/quads.ts:133-134`), so a `@2x` sprite draws at half its pixel size.
/// `sdf` marks an icon that can be recoloured/tinted by a shader; a Canvas
/// engine ignores it.
library;

/// One icon's rectangle inside the atlas.
class SpriteIcon {
  const SpriteIcon({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.pixelRatio = 1,
    this.sdf = false,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double pixelRatio;
  final bool sdf;

  /// Size on screen at `icon-size: 1`, i.e. sprite pixels divided by density.
  double get displayWidth => pixelRatio <= 0 ? width : width / pixelRatio;
  double get displayHeight => pixelRatio <= 0 ? height : height / pixelRatio;

  @override
  String toString() =>
      'SpriteIcon($x,$y ${width}x$height @${pixelRatio}x)';
}

/// Name → icon lookup for one sprite.
class SpriteIndex {
  const SpriteIndex(this.icons);

  final Map<String, SpriteIcon> icons;

  int get length => icons.length;

  SpriteIcon? operator [](String name) => icons[name];

  /// Parses the sprite JSON, skipping entries that are malformed.
  ///
  /// Tolerant on purpose: a sprite atlas is third-party data, and one broken
  /// entry should cost that icon, not the whole layer.
  factory SpriteIndex.parse(Object? json) {
    if (json is! Map) return const SpriteIndex({});
    final out = <String, SpriteIcon>{};
    json.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final x = _number(value['x']);
      final y = _number(value['y']);
      final w = _number(value['width']);
      final h = _number(value['height']);
      if (x == null || y == null || w == null || h == null) return;
      out[key] = SpriteIcon(
        x: x,
        y: y,
        width: w,
        height: h,
        pixelRatio: _number(value['pixelRatio']) ?? 1,
        sdf: value['sdf'] == true,
      );
    });
    return SpriteIndex(out);
  }

  static double? _number(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
