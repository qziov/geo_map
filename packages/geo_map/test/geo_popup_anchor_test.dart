import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';

void main() {
  const card = Size(100, 80);
  const point = Offset(500, 400);

  group('anchorOffsetFor — nine-grid', () {
    test('bottom keeps the card above the anchor (default)', () {
      final o = anchorOffsetFor(PopupAnchor.bottom, point, card, 8);
      expect(o.dx, closeTo(450, 1e-6));
      expect(o.dy, closeTo(400 - 80 - 8, 1e-6));
    });
    test('top puts the card below the anchor', () {
      final o = anchorOffsetFor(PopupAnchor.top, point, card, 8);
      expect(o.dx, closeTo(450, 1e-6));
      expect(o.dy, closeTo(408, 1e-6));
    });
    test('left puts the card to the right of the anchor', () {
      final o = anchorOffsetFor(PopupAnchor.left, point, card, 8);
      expect(o.dx, closeTo(508, 1e-6));
      expect(o.dy, closeTo(360, 1e-6));
    });
    test('right puts the card to the left of the anchor', () {
      final o = anchorOffsetFor(PopupAnchor.right, point, card, 8);
      expect(o.dx, closeTo(500 - 100 - 8, 1e-6));
      expect(o.dy, closeTo(360, 1e-6));
    });
    test('center centers the card on the anchor', () {
      final o = anchorOffsetFor(PopupAnchor.center, point, card, 8);
      expect(o.dx, closeTo(450, 1e-6));
      expect(o.dy, closeTo(360, 1e-6));
    });
    test('corners offset by card size + tail', () {
      final tl = anchorOffsetFor(PopupAnchor.topLeft, point, card, 8);
      expect(tl, equals(const Offset(508, 408)));
      final br = anchorOffsetFor(PopupAnchor.bottomRight, point, card, 8);
      expect(br, equals(const Offset(500 - 100 - 8, 400 - 80 - 8)));
    });
  });

  group('layoutAnchoredPopup — visibility & clamp', () {
    test('hidden when the anchor is off-screen', () {
      final layout = layoutAnchoredPopup(
        anchor: const Offset(-100, 400),
        viewport: const Size(800, 600),
        card: card,
        keepOut: EdgeInsets.zero,
      );
      expect(layout.visible, isFalse);
    });
    test('clamps the left edge into keepOut', () {
      final layout = layoutAnchoredPopup(
        anchor: const Offset(10, 10),
        viewport: const Size(800, 600),
        card: card,
        keepOut: const EdgeInsets.only(left: 200),
        anchorSide: PopupAnchor.bottom,
      );
      // unclamped left = 10 - 50 = -40 → clamped to keepOut.left.
      expect(layout.left, equals(200));
      expect(layout.visible, isTrue);
    });
    test('keeps the default (bottom, card above) layout', () {
      final layout = layoutAnchoredPopup(
        anchor: const Offset(500, 400),
        viewport: const Size(800, 600),
        card: card,
        keepOut: EdgeInsets.zero,
      );
      expect(layout.left, closeTo(450, 1e-6));
      expect(layout.top, closeTo(400 - 80 - 8, 1e-6));
      expect(layout.visible, isTrue);
    });
  });
}
