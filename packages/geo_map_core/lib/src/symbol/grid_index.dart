/// A uniform grid for 2D box hit-testing, ported from MapLibre.
///
/// Symbol placement asks "does this label's box overlap anything already
/// placed?" once per candidate, hundreds of times per frame, and a linear scan
/// over every placed box is the usual reason a map engine stutters when labels
/// appear. MapLibre splits the screen into cells and only compares boxes that
/// share a cell (`src/symbol/grid_index.ts:73-101`).
///
/// Two details are copied verbatim because they decide how much work each query
/// does:
///
/// * the cell size is **25 px** — `CollisionIndex`'s default
///   (`collision_index.ts:87`), chosen so that a small label fits one cell;
/// * a box is inserted into every cell its rect touches
///   (`grid_index.ts:109-116`), and a query collects candidates from the same
///   range and then compares full rectangles (`grid_index.ts:136-190`).
///
/// The grid is rebuilt every frame in MapLibre (a fresh `CollisionIndex` per
/// render); we do the same, so there is no remove operation here.
library;

import 'dart:math' as math;

/// Cell size in screen pixels. `CollisionIndex`'s default.
const double kCollisionCellSize = 25;

/// Grid of boxes keyed by an arbitrary payload.
///
/// Coordinates are screen-space and may be negative (a label anchored outside
/// the viewport still occupies cells that exist).
class GridIndex<T> {
  GridIndex({
    required this.width,
    required this.height,
    this.cellSize = kCollisionCellSize,
  })  : xCellCount = math.max(1, (width / cellSize).ceil()),
        yCellCount = math.max(1, (height / cellSize).ceil()) {
    _cells = List<List<int>>.generate(xCellCount * yCellCount, (_) => <int>[]);
  }

  final double width;
  final double height;
  final double cellSize;
  final int xCellCount;
  final int yCellCount;

  late final List<List<int>> _cells;

  /// Insertion order, so a query can return keys in placement order.
  final List<T> _keys = [];
  final List<double> _boxes = [];

  int get length => _keys.length;

  bool get isEmpty => _keys.isEmpty;

  /// Inserts the box `(x1,y1)-(x2,y2)`.
  ///
  /// Coordinates must be ordered; that is the caller's job (MapLibre normalises
  /// before inserting too).
  void insert(T key, double x1, double y1, double x2, double y2) {
    final uid = _keys.length;
    _keys.add(key);
    _boxes
      ..add(x1)
      ..add(y1)
      ..add(x2)
      ..add(y2);

    final minX = math.min(x1, x2);
    final maxX = math.max(x1, x2);
    final minY = math.min(y1, y2);
    final maxY = math.max(y1, y2);
    for (var cy = _cellY(minY); cy <= _cellY(maxY); cy++) {
      for (var cx = _cellX(minX); cx <= _cellX(maxX); cx++) {
        _cells[cy * xCellCount + cx].add(uid);
      }
    }
  }

  /// Keys whose box intersects `(x1,y1)-(x2,y2)`.
  ///
  /// [accept] filters candidates before the rectangle test, which is how
  /// placement skips keys it is allowed to overlap (MapLibre passes an
  /// `overlapAllowed` predicate, `grid_index.ts:150-186`).
  ///
  /// Returned keys are deduplicated and keep insertion order.
  List<T> hits(
    double x1,
    double y1,
    double x2,
    double y2, {
    bool Function(T key)? accept,
  }) {
    final out = <T>[];
    if (_keys.isEmpty) return out;
    final minX = math.min(x1, x2);
    final maxX = math.max(x1, x2);
    final minY = math.min(y1, y2);
    final maxY = math.max(y1, y2);

    final seen = <int>{};
    for (var cy = _cellY(minY); cy <= _cellY(maxY); cy++) {
      for (var cx = _cellX(minX); cx <= _cellX(maxX); cx++) {
        for (final uid in _cells[cy * xCellCount + cx]) {
          if (!seen.add(uid)) continue;
          final i = uid * 4;
          if (_boxes[i + 2] < minX ||
              _boxes[i] > maxX ||
              _boxes[i + 3] < minY ||
              _boxes[i + 1] > maxY) {
            continue;
          }
          final key = _keys[uid];
          if (accept != null && !accept(key)) continue;
          out.add(key);
        }
      }
    }
    return out;
  }

  /// True when any box intersects the rect.
  bool intersects(
    double x1,
    double y1,
    double x2,
    double y2, {
    bool Function(T key)? accept,
  }) =>
      hits(x1, y1, x2, y2, accept: accept).isNotEmpty;

  int _cellX(double x) =>
      (x / cellSize).floor().clamp(0, xCellCount - 1).toInt();

  int _cellY(double y) =>
      (y / cellSize).floor().clamp(0, yCellCount - 1).toInt();
}
