/// Tests for the anchor-following popup widget and its pure layout helper.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

void main() {
  const viewport = Size(800, 600);
  const card = Size(200, 100);
  const noKeepOut = EdgeInsets.zero;

  group('layoutAnchoredPopup (pure)', () {
    test('hidden when viewport is empty', () {
      final r = layoutAnchoredPopup(
        anchor: const Offset(400, 300),
        viewport: Size.zero,
        card: card,
        keepOut: noKeepOut,
      );
      expect(r.visible, isFalse);
    });

    test('hidden when anchor is non-finite', () {
      final r = layoutAnchoredPopup(
        anchor: const Offset(double.nan, 300),
        viewport: viewport,
        card: card,
        keepOut: noKeepOut,
      );
      expect(r.visible, isFalse);
    });

    test('hidden on globe back-hemisphere sentinel (±1e6)', () {
      final r = layoutAnchoredPopup(
        anchor: const Offset(-1e6, -1e6),
        viewport: viewport,
        card: card,
        keepOut: noKeepOut,
      );
      expect(r.visible, isFalse);
    });

    test('hidden when anchor is just off-screen', () {
      final r = layoutAnchoredPopup(
        anchor: const Offset(900, 300), // beyond width + slop
        viewport: viewport,
        card: card,
        keepOut: noKeepOut,
      );
      expect(r.visible, isFalse);
    });

    test('positions card above the anchor, centered on x', () {
      final r = layoutAnchoredPopup(
        anchor: const Offset(400, 300),
        viewport: viewport,
        card: card,
        keepOut: noKeepOut,
      );
      expect(r.visible, isTrue);
      // bottom-mid of the card sits at the anchor (tail gap above it):
      // top = anchor.y - card.height - tail
      expect(r.top, closeTo(300 - 100 - 8, 1e-6));
      // left centers the card on the anchor
      expect(r.left, closeTo(400 - 100, 1e-6));
    });

    test('clamps into keepOut margins', () {
      final r = layoutAnchoredPopup(
        anchor: const Offset(20, 20),
        viewport: viewport,
        card: card,
        keepOut: const EdgeInsets.only(left: 50, top: 50),
      );
      expect(r.visible, isTrue);
      expect(r.left, greaterThanOrEqualTo(50));
      expect(r.top, greaterThanOrEqualTo(50));
    });
  });

  group('GeoAnchoredPopup (widget)', () {
    late GeoMapController controller;

    setUp(() {
      // Centre the camera on (0,0) so the anchor projects to screen (400,300).
      controller = GeoMapController(
        useGlobe: false,
        initialCenter: const LatLng(0, 0),
        initialZoom: 4,
      )..setViewport(viewport);
    });

    testWidgets('renders a Positioned at the projected anchor', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: Stack(
              children: [
                GeoAnchoredPopup(
                  controller: controller,
                  anchor: const LatLng(0, 0), // == centre → screen (400,300)
                  cardSize: card,
                  keepOut: noKeepOut,
                  child: const SizedBox(width: 200, height: 100),
                ),
              ],
            ),
          ),
        ),
      ));

      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.left, closeTo(400 - 100, 1e-6));
      expect(positioned.top, closeTo(300 - 100 - 8, 1e-6));
    });

    testWidgets('collapses to nothing when the anchor is off-screen',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: Stack(
              children: [
                GeoAnchoredPopup(
                  controller: controller,
                  anchor: const LatLng(0, 180), // far east → off-screen at z=4
                  cardSize: card,
                  keepOut: noKeepOut,
                  child: const SizedBox(width: 200, height: 100),
                ),
              ],
            ),
          ),
        ),
      ));

      expect(find.byType(Positioned), findsNothing);
      // The widget itself still mounts (no throw), just renders an empty box.
      expect(find.byType(GeoAnchoredPopup), findsOneWidget);
    });
  });

  group('GeoMapPopupController (state)', () {
    test('starts hidden', () {
      final c = GeoMapPopupController();
      expect(c.anchor, isNull);
      expect(c.isOpen, isFalse);
    });

    test('show opens at the anchor, hide closes', () {
      final c = GeoMapPopupController();
      c.show(const LatLng(1, 2));
      expect(c.isOpen, isTrue);
      expect(c.anchor, const LatLng(1, 2));
      c.hide();
      expect(c.isOpen, isFalse);
      expect(c.anchor, isNull);
    });

    test('re-showing the same anchor is idempotent (no extra notify)', () {
      var notifies = 0;
      final c = GeoMapPopupController()..addListener(() => notifies++);
      c.show(const LatLng(1, 2));
      c.show(const LatLng(1, 2)); // identical → no second notify
      expect(notifies, 1);
    });

    test('toggle flips open/closed', () {
      final c = GeoMapPopupController();
      c.toggle(const LatLng(0, 0));
      expect(c.isOpen, isTrue);
      c.toggle(const LatLng(0, 0));
      expect(c.isOpen, isFalse);
    });
  });

  group('GeoMapPopup (widget)', () {
    late GeoMapController controller;
    late GeoMapPopupController popup;

    setUp(() {
      controller = GeoMapController(
        useGlobe: false,
        initialCenter: const LatLng(0, 0),
        initialZoom: 4,
      )..setViewport(const Size(800, 600));
      popup = GeoMapPopupController();
    });

    Widget buildApp() => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: Stack(
                children: [
                  GeoMapPopup(
                    controller: controller,
                    popup: popup,
                    cardSize: card,
                    keepOut: noKeepOut,
                    builder: (context, anchor) =>
                        const SizedBox(width: 200, height: 100),
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('renders the card when open', (tester) async {
      popup.show(const LatLng(0, 0)); // == centre → on screen
      await tester.pumpWidget(buildApp());
      expect(find.byType(Positioned), findsOneWidget);
    });

    testWidgets('renders nothing when closed', (tester) async {
      await tester.pumpWidget(buildApp()); // popup starts hidden
      expect(find.byType(Positioned), findsNothing);
    });
  });
}
