/// Label placement: which candidates actually get drawn.
///
/// Port of MapLibre's two-step placement (`src/symbol/collision_index.ts:428-440`
/// for the insert half, `src/symbol/placement.ts` for the driving loop):
///
/// 1. **query** — `placeCollisionBox` asks the grid whether the box is free;
/// 2. **insert** — only then is the box written into the grid.
///
/// The two steps exist so a *paired* symbol (an icon and its text) can be checked
/// against the world and inserted together even though the two boxes overlap each
/// other. Our painter does not pair yet, but keeping the seam means adding
/// `icon-image` later does not turn this into a rewrite.
///
/// The two grids mirror `CollisionIndex.grid` / `ignoredGrid`:
///
/// * a normal symbol is inserted into `grid` and therefore **occludes** later
///   candidates;
/// * `text-ignore-placement` inserts into `ignoredGrid`, so it never pushes
///   anything aside — yet it is still **queried against `grid`**, so an already
///   placed label can hide it. The query deliberately skips `ignoredGrid`:
///   MapLibre's `placeCollisionBox` only calls `this.grid.hitTest(...)`
///   (`collision_index.ts:173`), and `ignoredGrid` shows up only in the click
///   hit-test path (`:387-388`), which is a different question.
///
/// Overlap allowance follows `overlapAllowed` (`src/symbol/grid_index.ts:36-49`):
/// a candidate marked `always` (MapLibre's `text-allow-overlap`) may overlap
/// anything, and a `never` candidate may overlap nothing — including a box that
/// was itself placed with `always`.
library;

import 'grid_index.dart';

/// What happened to one candidate.
enum SymbolPlacementResult {
  /// Visible; the box is now in the grid.
  placed,

  /// Hidden because something already occupies its box.
  collision,

  /// Hidden because it is entirely outside the padded viewport — MapLibre
  /// refuses those before the grid test, since a label no one can see must not
  /// occupy grid cells that visible labels need.
  offscreen,
}

/// A label box waiting for room.
///
/// Boxes are screen-space. [anchorX]/[anchorY] are carried through untouched so
/// the caller knows where to draw the glyphs if the box is accepted.
class SymbolCandidate {
  const SymbolCandidate({
    required this.key,
    required this.box,
    required this.anchorX,
    required this.anchorY,
    this.sortKey = 0,
    this.order = 0,
    this.allowOverlap = false,
    this.ignorePlacement = false,
    this.collisionGroup = 0,
  });

  /// Caller-defined identity, echoed back in the decision.
  final Object key;

  /// `(x1, y1, x2, y2)` in screen pixels, already ordered.
  final (double, double, double, double) box;

  final double anchorX;
  final double anchorY;

  /// `symbol-sort-key`; lower wins. Candidates are placed in this order.
  final double sortKey;

  /// Tie-breaker for equal [sortKey]: the decode order of the feature. Without
  /// it two equally-ranked labels that cannot both fit would swap every frame.
  final int order;

  /// `text-allow-overlap`: place even when the box is occupied.
  final bool allowOverlap;

  /// `text-ignore-placement`: do not reserve space for others.
  final bool ignorePlacement;

  /// MapLibre's `collisionGroupID`; symbols in the same group are allowed to
  /// overlap each other.
  final int collisionGroup;
}

/// The decision for one candidate.
class SymbolPlacement {
  const SymbolPlacement(this.candidate, this.result);

  final SymbolCandidate candidate;
  final SymbolPlacementResult result;

  bool get isPlaced => result == SymbolPlacementResult.placed;
}

/// Places candidates into the screen, one grid per frame.
class SymbolPlacer {
  SymbolPlacer({
    required double width,
    required double height,
    this.viewportPadding = 100,
    double cellSize = kCollisionCellSize,
  })  : _grid = GridIndex<SymbolCandidate>(width: width, height: height, cellSize: cellSize),
        _ignored = GridIndex<SymbolCandidate>(width: width, height: height, cellSize: cellSize),
        _width = width,
        _height = height;

  final double _width;
  final double _height;

  /// Same slack MapLibre keeps around the viewport
  /// (`collision_index.ts` `viewportPadding`): a label anchored just outside can
  /// still be partly visible.
  final double viewportPadding;

  final GridIndex<SymbolCandidate> _grid;
  final GridIndex<SymbolCandidate> _ignored;

  int get placedCount => _grid.length + _ignored.length;

  /// Places [candidates] in `(sortKey, order)` order.
  ///
  /// Returns one decision per candidate, in input order, so callers can keep
  /// their own list aligned with it.
  List<SymbolPlacement> place(List<SymbolCandidate> candidates) {
    final sorted = List<SymbolCandidate>.of(candidates)
      ..sort((a, b) {
        final byKey = a.sortKey.compareTo(b.sortKey);
        return byKey != 0 ? byKey : a.order.compareTo(b.order);
      });

    final result = <SymbolCandidate, SymbolPlacement>{};
    for (final candidate in sorted) {
      result[candidate] = SymbolPlacement(candidate, _placeOne(candidate));
    }
    return [for (final c in candidates) result[c]!];
  }

  SymbolPlacementResult _placeOne(SymbolCandidate candidate) {
    final (x1, y1, x2, y2) = candidate.box;

    // Off-screen: refuse before touching a cell.
    if (x2 < -viewportPadding ||
        y2 < -viewportPadding ||
        x1 > _width + viewportPadding ||
        y1 > _height + viewportPadding) {
      return SymbolPlacementResult.offscreen;
    }

    if (!candidate.allowOverlap) {
      final hit = _hitTest(x1, y1, x2, y2, candidate);
      if (hit) return SymbolPlacementResult.collision;
    }

    final grid = candidate.ignorePlacement ? _ignored : _grid;
    grid.insert(candidate, x1, y1, x2, y2);
    return SymbolPlacementResult.placed;
  }

  bool _hitTest(double x1, double y1, double x2, double y2, SymbolCandidate candidate) {
    bool blocks(SymbolCandidate other) {
      // Two symbols of the same collision group are a pair (icon + text) and are
      // allowed to overlap.
      if (other.collisionGroup == candidate.collisionGroup &&
          candidate.collisionGroup != 0) {
        return false;
      }
      // `overlapAllowed`: this candidate is `never` here (allowOverlap was false),
      // so it collides with everything except an `always` other — and an
      // `always` other still blocks a `never` candidate.
      return true;
    }

    // Only the blocking grid is queried — an ignore-placement symbol lives in
    // `_ignored` precisely so it does not block, so it must not be consulted
    // here either.
    return _grid.intersects(x1, y1, x2, y2, accept: blocks);
  }
}
