/// Screen-space symbol painting: measure, place, draw.
///
/// Two kinds of symbol share one placement pass, because MapLibre does too: a
/// text label and its icon are a **pair** — one `CollisionGroup`, checked against
/// the world once, allowed to overlap each other
/// (`symbol/placement.ts`, `collision_index.ts:428-440`).
///
/// The placement decision lives in core (`SymbolPlacer`, a port of MapLibre's
/// `CollisionIndex`); this file is the `dart:ui` half — laying text out to get a
/// box, taking an icon's rect out of the sprite atlas, and drawing the winners.
///
/// Two things matter for frame time:
///
/// * **Text layout is cached.** `TextPainter.layout` shapes the string every
///   call, which is far more expensive than drawing it; a label set is stable
///   across frames, so the painter is kept in a small LRU keyed by everything
///   that changes the layout (text, size, colour, halo). The cache is invalidated
///   when the platform reports a new font — see [_fontEpoch].
/// * **One `SymbolPlacer` per layer per frame**, not per tile. A label from tile
///   A must be able to hide a label from tile B, which is the whole point of the
///   global grid.
library;

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:geo_map_core/geo_map_core.dart';

/// A symbol that can be placed and drawn.
sealed class SymbolSpec {
  const SymbolSpec({
    required this.anchor,
    this.offset = const Vec2(0, 0),
    this.allowOverlap = false,
    this.ignorePlacement = false,
    this.sortKey = 0,
    this.order = 0,
    this.collisionGroup = 0,
  });

  /// Screen position of the symbol's anchor.
  final Vec2 anchor;

  /// Shift applied to both the drawn position and the collision box.
  ///
  /// MapLibre gets this from `text-offset` (em units) and from the icon/text
  /// pair layout; here the caller computes it in pixels.
  final Vec2 offset;

  final bool allowOverlap;
  final bool ignorePlacement;
  final double sortKey;
  final int order;

  /// Symbols sharing a non-zero group may overlap each other (icon + text).
  final int collisionGroup;
}

/// A text label.
class LabelSpec extends SymbolSpec {
  const LabelSpec({
    required super.anchor,
    required this.text,
    this.fontSize = 16,
    this.color = const Color(0xFF000000),
    this.haloColor = const Color(0x00000000),
    this.haloWidth = 0,
    super.offset,
    super.allowOverlap,
    super.ignorePlacement,
    super.sortKey,
    super.order,
    super.collisionGroup,
  });

  final String text;
  final double fontSize;
  final Color color;
  final Color haloColor;

  /// Halo width in logical pixels. MapLibre's `text-halo-width` is a radius; the
  /// stroke is twice as wide, which [_LabelCache.styleFor] applies.
  final double haloWidth;
}

/// An icon taken from a sprite atlas.
class IconSpec extends SymbolSpec {
  const IconSpec({
    required super.anchor,
    required this.image,
    required this.source,
    required this.size,
    super.offset,
    super.allowOverlap,
    super.ignorePlacement,
    super.sortKey,
    super.order,
    super.collisionGroup,
  });

  /// The atlas holding [source].
  final ui.Image image;

  /// Region of [image] to draw.
  final Rect source;

  /// On-screen size, i.e. sprite pixels divided by density and multiplied by
  /// `icon-size`.
  final Size size;
}

/// A prepared symbol: measured box plus everything needed to draw it.
class _Prepared {
  _Prepared.label(this.spec, TextPainter this.text, this.halo, this.box)
      : iconSource = null,
        iconImage = null,
        iconSize = null;

  _Prepared.icon(IconSpec this.spec, this.iconImage, this.iconSource,
      this.iconSize, this.box)
      : text = null,
        halo = null;

  final SymbolSpec spec;
  final TextPainter? text;
  final TextPainter? halo;
  final Rect box;
  final ui.Image? iconImage;
  final Rect? iconSource;
  final Size? iconSize;
}

/// Measures, places and draws [SymbolSpec]s.
class SymbolPainter {
  SymbolPainter({required this.viewport});

  /// Screen size of the painter; the collision grid is per frame, so this only
  /// feeds the placer.
  final Size viewport;

  /// Shared across frames on purpose: the custom painter that owns this object
  /// is rebuilt on every frame, so a per-instance cache would never survive to
  /// be useful. Layout keys contain the text, so sharing is safe.
  static final _LabelCache _cache = _LabelCache();

  /// Bumped whenever the platform reports a new font.
  ///
  /// A paragraph laid out before a fallback font has loaded keeps the "missing
  /// glyph" result forever — which is what made every CJK label render as tofu
  /// boxes on web, where the Noto fallback is fetched at runtime. Widgets fix
  /// this by re-laying out when `systemFonts` fires; a cache has to be told.
  static int _fontEpoch = 0;

  static bool _fontListenerAttached = false;

  static void _listenForFonts() {
    if (_fontListenerAttached) return;
    _fontListenerAttached = true;
    PaintingBinding.instance.systemFonts.addListener(() {
      _fontEpoch++;
      _cache.clear();
    });
  }

  /// Drops every cached layout (tests, or after a font-size change).
  static void clearCache() => _cache.clear();

  /// Places [symbols] and draws the winners.
  ///
  /// Returns how many were drawn, which a HUD can show as "labels x/y".
  int paint(Canvas canvas, List<SymbolSpec> symbols) {
    if (symbols.isEmpty) return 0;
    _listenForFonts();

    final prepared = <_Prepared>[];
    for (final spec in symbols) {
      final preparedSpec = _prepare(spec);
      if (preparedSpec != null) prepared.add(preparedSpec);
    }
    if (prepared.isEmpty) return 0;

    final placer = SymbolPlacer(
      width: viewport.width,
      height: viewport.height,
    );
    final decisions = placer.place([
      for (final p in prepared)
        SymbolCandidate(
          key: p,
          box: (p.box.left, p.box.top, p.box.right, p.box.bottom),
          anchorX: p.box.center.dx,
          anchorY: p.box.center.dy,
          sortKey: p.spec.sortKey,
          order: p.spec.order,
          allowOverlap: p.spec.allowOverlap,
          ignorePlacement: p.spec.ignorePlacement,
          collisionGroup: p.spec.collisionGroup,
        ),
    ]);

    var drawn = 0;
    for (var i = 0; i < prepared.length; i++) {
      if (!decisions[i].isPlaced) continue;
      _draw(canvas, prepared[i]);
      drawn++;
    }
    return drawn;
  }

  _Prepared? _prepare(SymbolSpec spec) {
    switch (spec) {
      case LabelSpec():
        if (spec.text.isEmpty) return null;
        final text = _cache.painterFor(spec);
        final halo = spec.haloWidth > 0 ? _cache.haloPainterFor(spec) : null;
        final size = text.size;
        final left = spec.anchor.x + spec.offset.x - size.width / 2;
        final top = spec.anchor.y + spec.offset.y - size.height / 2;
        return _Prepared.label(
          spec,
          text,
          halo,
          Rect.fromLTWH(left, top, size.width, size.height),
        );
      case IconSpec():
        return _Prepared.icon(
          spec,
          spec.image,
          spec.source,
          spec.size,
          Rect.fromCenter(
            center: Offset(
              spec.anchor.x + spec.offset.x,
              spec.anchor.y + spec.offset.y,
            ),
            width: spec.size.width,
            height: spec.size.height,
          ),
        );
    }
  }

  void _draw(Canvas canvas, _Prepared item) {
    switch (item.spec) {
      case LabelSpec():
        item.halo?.paint(canvas, item.box.topLeft);
        item.text?.paint(canvas, item.box.topLeft);
      case IconSpec():
        canvas.drawImageRect(
          item.iconImage!,
          item.iconSource!,
          item.box,
          Paint()..filterQuality = FilterQuality.medium,
        );
    }
  }
}

/// Layout cache keyed by everything that changes the shaped result.
///
/// Colours are part of the key: the halo is a *stroked* painter and the fill is a
/// solid one, so they are two entries per label — cheap, because layout is what
/// costs, and both are reused next frame.
class _LabelCache {
  final LinkedHashMap<String, TextPainter> _painters = LinkedHashMap();
  final LinkedHashMap<String, TextPainter> _haloPainters = LinkedHashMap();

  static const int _max = 600;

  TextPainter painterFor(LabelSpec label) {
    final key = '${SymbolPainter._fontEpoch}|${label.text}'
        '|${label.fontSize}|${label.color.value}';
    final hit = _painters[key];
    if (hit != null) return hit;
    final painter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: styleFor(label, halo: false),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _insert(_painters, key, painter);
    return painter;
  }

  TextPainter haloPainterFor(LabelSpec label) {
    final key = '${SymbolPainter._fontEpoch}|${label.text}'
        '|${label.fontSize}|${label.haloColor.value}|${label.haloWidth}';
    final hit = _haloPainters[key];
    if (hit != null) return hit;
    final painter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: styleFor(label, halo: true),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _insert(_haloPainters, key, painter);
    return painter;
  }

  void _insert(
    LinkedHashMap<String, TextPainter> map,
    String key,
    TextPainter painter,
  ) {
    map[key] = painter;
    while (map.length > _max) {
      final oldest = map.keys.first;
      map.remove(oldest)?.dispose();
    }
  }

  void clear() {
    for (final p in _painters.values) {
      p.dispose();
    }
    for (final p in _haloPainters.values) {
      p.dispose();
    }
    _painters.clear();
    _haloPainters.clear();
  }

  /// MapLibre draws the halo by stroking the glyph outline
  /// (`text-halo-width` is a radius, so the stroke is twice as wide) and then
  /// filling on top. Flutter exposes the same idea through `foreground`.
  static TextStyle styleFor(LabelSpec label, {required bool halo}) {
    if (!halo) {
      return TextStyle(
        fontSize: label.fontSize,
        color: label.color,
        height: 1.2,
      );
    }
    return TextStyle(
      fontSize: label.fontSize,
      height: 1.2,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = label.haloWidth * 2
        ..strokeJoin = StrokeJoin.round
        ..color = label.haloColor,
    );
  }
}
