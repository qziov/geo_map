/// Integration tests for [SymbolPainter] — the M3 label/icon placement + draw
/// path.
///
/// These exercise the real `dart:ui` half: text layout, the shared
/// `SymbolPlacer` (a port of MapLibre's `CollisionIndex`), and the actual
/// draw calls onto a `Canvas`. The placement decisions mirror
/// `collision_index.ts` / `placement.ts` and the two-grid (`grid` vs
/// `ignoredGrid`) semantics; getting them wrong is the most likely M3 regression,
/// so they are pinned here.
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/src/style/symbol_painter.dart';
import 'package:geo_map_core/geo_map_core.dart';

import 'test_helpers.dart';

const Size _viewport = Size(800, 600);

LabelSpec _label(
  String text,
  Vec2 anchor, {
  bool allowOverlap = false,
  bool ignorePlacement = false,
  int collisionGroup = 0,
}) =>
    LabelSpec(
      anchor: anchor,
      text: text,
      fontSize: 16,
      allowOverlap: allowOverlap,
      ignorePlacement: ignorePlacement,
      collisionGroup: collisionGroup,
    );

void main() {
  group('SymbolPainter placement', () {
    testWidgets('overlapping labels without allowOverlap collapse to one',
        (tester) async {
      final painter = SymbolPainter(viewport: _viewport);
      final canvas = ui.Canvas(ui.PictureRecorder());
      // Three identical boxes on the same anchor: only the first fits.
      final drawn = painter.paint(canvas, [
        _label('A', const Vec2(400, 300)),
        _label('B', const Vec2(400, 300)),
        _label('C', const Vec2(400, 300)),
      ]);
      expect(drawn, 1);
    });

    testWidgets('allowOverlap places every overlapping label', (tester) async {
      final painter = SymbolPainter(viewport: _viewport);
      final canvas = ui.Canvas(ui.PictureRecorder());
      final drawn = painter.paint(canvas, [
        _label('A', const Vec2(400, 300), allowOverlap: true),
        _label('B', const Vec2(400, 300), allowOverlap: true),
        _label('C', const Vec2(400, 300), allowOverlap: true),
      ]);
      expect(drawn, 3);
    });

    testWidgets('paired symbols in the same collisionGroup overlap each other',
        (tester) async {
      // An icon + its label share a group and must be allowed to overlap.
      final painter = SymbolPainter(viewport: _viewport);
      final canvas = ui.Canvas(ui.PictureRecorder());
      final drawn = painter.paint(canvas, [
        _label('A', const Vec2(400, 300), collisionGroup: 1),
        _label('B', const Vec2(400, 300), collisionGroup: 1),
      ]);
      expect(drawn, 2);
    });

    testWidgets('ignorePlacement is occluded by a prior placed label',
        (tester) async {
      final painter = SymbolPainter(viewport: _viewport);
      final canvas = ui.Canvas(ui.PictureRecorder());
      // Normal label goes into `grid`; the ignore-placement one is queried
      // against `grid` and is hidden by it.
      final drawn = painter.paint(canvas, [
        _label('A', const Vec2(400, 300)),
        _label('B', const Vec2(400, 300), ignorePlacement: true),
      ]);
      expect(drawn, 1);
    });

    testWidgets('an ignore-placement label does not block a later one',
        (tester) async {
      final painter = SymbolPainter(viewport: _viewport);
      final canvas = ui.Canvas(ui.PictureRecorder());
      // The ignore-placement label lands in `ignoredGrid` (never occupies
      // `grid`), so the following normal label finds the grid empty.
      final drawn = painter.paint(canvas, [
        _label('A', const Vec2(400, 300), ignorePlacement: true),
        _label('B', const Vec2(400, 300)),
      ]);
      expect(drawn, 2);
    });

    testWidgets('off-screen symbols are rejected before the grid check',
        (tester) async {
      final painter = SymbolPainter(viewport: _viewport);
      final canvas = ui.Canvas(ui.PictureRecorder());
      // Anchor far outside the padded viewport.
      final drawn = painter.paint(
        canvas,
        [_label('X', const Vec2(5000, 5000))],
      );
      expect(drawn, 0);
    });
  });

  group('SymbolPainter draw', () {
    testWidgets('distinct labels are all placed and actually painted',
        (tester) async {
      final painter = SymbolPainter(viewport: _viewport);
      final symbols = [
        for (var i = 0; i < 5; i++)
          _label('L$i', Vec2(120.0 + i * 120, 300)),
      ];
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final drawn = painter.paint(canvas, symbols);
      final picture = recorder.endRecording();
      // Rasterization runs on the engine's raster thread. Inside the test's
      // fake-async zone that future never completes (the first run hung until
      // the 10-minute timeout), so step out with `runAsync`.
      var opaque = 0;
      await tester.runAsync(() async {
        final image = await picture.toImage(800, 600);
        opaque = await countOpaquePixels(image);
      });
      // All five fit (no overlaps)…
      expect(drawn, 5);
      // …and the rasterized picture is not blank.
      expect(opaque, greaterThan(0));
    });
  });
}
