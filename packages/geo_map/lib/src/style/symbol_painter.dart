/// Screen-space label painting: measure, place, draw.
///
/// The placement decision lives in core (`SymbolPlacer`, a port of MapLibre's
/// `CollisionIndex`); this file is the part that needs `dart:ui` — laying text
/// out with a `TextPainter` to get a box, and drawing the glyphs (with a halo)
/// once the placer says yes.
///
/// Two things matter for frame time:
///
/// * **Text layout is cached.** `TextPainter.layout` shapes the string every
///   call, which is far more expensive than drawing it; a label set is stable
///   across frames, so the painter is kept in a small LRU keyed by everything
///   that changes the layout (text, size, colour, halo).
/// * **One `SymbolPlacer` per layer per frame**, not per tile. A label from tile
///   A must be able to hide a label from tile B, which is the whole point of the
///   global grid.
library;

import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:geo_map_core/geo_map_core.dart';

/// One label to draw, already resolved against the style.
class LabelSpec {
  const LabelSpec({
    required this.anchor,
    required this.text,
    this.fontSize = 16,
    this.color = const Color(0xFF000000),
    this.haloColor = const Color(0x00000000),
    this.haloWidth = 0,
    this.allowOverlap = false,
    this.ignorePlacement = false,
    this.sortKey = 0,
    this.order = 0,
    this.collisionGroup = 0,
  });

  /// Screen position of the label's anchor (the text is centred on it).
  final Vec2 anchor;
  final String text;
  final double fontSize;
  final Color color;
  final Color haloColor;

  /// Halo width in logical pixels. MapLibre's `text-halo-width` is a radius; the
  /// stroke is twice as wide, which `_styleFor` applies.
  final double haloWidth;

  final bool allowOverlap;
  final bool ignorePlacement;
  final double sortKey;
  final int order;

  /// Symbols sharing a non-zero group may overlap each other (icon + text).
  final int collisionGroup;
}

/// Measures, places and draws [LabelSpec]s.
class SymbolPainter {
  SymbolPainter({
    required this.viewport,
    this.maxCachedLabels = 600,
  });

  /// Screen size of the painter; the label cache and the collision grid are per
  /// frame, so this only feeds the placer.
  final Size viewport;

  final int maxCachedLabels;

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

  /// Places [labels] and draws the winners.
  ///
  /// Returns how many were drawn, which the HUD uses to show "labels x/y".
  int paint(Canvas canvas, List<LabelSpec> labels) {
    if (labels.isEmpty) return 0;
    _listenForFonts();

    // Measure once per label: the box is what the placer needs, and the painter
    // is what the draw call needs.
    final prepared = <_PreparedLabel>[];
    for (final label in labels) {
      if (label.text.isEmpty) continue;
      final textPainter = _cache.painterFor(label);
      final haloPainter =
          label.haloWidth > 0 ? _cache.haloPainterFor(label) : null;
      final size = textPainter.size;
      final cx = label.anchor.x;
      final cy = label.anchor.y;
      prepared.add(_PreparedLabel(
        label,
        textPainter,
        haloPainter,
        SymbolCandidate(
          key: prepared.length,
          // Centred box. `text-anchor` variants (left/right/top/bottom) would
          // shift these corners, not the anchor.
          box: (
            cx - size.width / 2,
            cy - size.height / 2,
            cx + size.width / 2,
            cy + size.height / 2,
          ),
          anchorX: cx,
          anchorY: cy,
          sortKey: label.sortKey,
          order: label.order,
          allowOverlap: label.allowOverlap,
          ignorePlacement: label.ignorePlacement,
          collisionGroup: label.collisionGroup,
        ),
      ));
    }
    if (prepared.isEmpty) return 0;

    final placer = SymbolPlacer(
      width: viewport.width,
      height: viewport.height,
    );
    final decisions = placer.place([for (final p in prepared) p.candidate]);

    var drawn = 0;
    for (var i = 0; i < prepared.length; i++) {
      if (!decisions[i].isPlaced) continue;
      final item = prepared[i];
      final origin = Offset(
        item.label.anchor.x - item.textPainter.size.width / 2,
        item.label.anchor.y - item.textPainter.size.height / 2,
      );
      item.haloPainter?.paint(canvas, origin);
      item.textPainter.paint(canvas, origin);
      drawn++;
    }
    return drawn;
  }


}

class _PreparedLabel {
  _PreparedLabel(this.label, this.textPainter, this.haloPainter, this.candidate);

  final LabelSpec label;
  final TextPainter textPainter;
  final TextPainter? haloPainter;
  final SymbolCandidate candidate;
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
        style: _styleFor(label, halo: false),
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
        style: _styleFor(label, halo: true),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _insert(_haloPainters, key, painter);
    return painter;
  }

  void _insert(LinkedHashMap<String, TextPainter> map, String key, TextPainter painter) {
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
  TextStyle _styleFor(LabelSpec label, {required bool halo}) {
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

/// Draws the text of a label at [origin], exposed for tests that want to check
/// layout without a placer.
TextPainter layoutLabel(LabelSpec label) => TextPainter(
      text: TextSpan(
        text: label.text,
        style: TextStyle(fontSize: label.fontSize, color: label.color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
