/// Diagnostics switches shared by the tile layers.
///
/// debug 构建默认开启；帧摘要 500ms 限速，miss 明细 2s 限速——足够定位
/// 黑瓦（缺失/回退断链/选片偏移）又不至于在 587MB 包上刷屏。
library;

import 'package:flutter/foundation.dart';

class GeoDiagnostics {
  GeoDiagnostics._();

  /// 总开关（debug 构建默认 true；release 恒关）。
  static bool enabled = true;

  static int frameIntervalMs = 500;
  static int missDetailIntervalMs = 2000;

  /// 逐瓦片 trace（key + 屏幕位置）。定位选片洞/覆盖缺口时打开；
  /// 每帧限量 + 500ms 限速，避免刷屏。
  static bool trace = false;
  static int tracePerFrame = 40;
  static int _lastTrace = 0;

  static bool get traceOn => enabled && kDebugMode && trace;

  static void traceLine(String message) {
    if (!traceOn) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTrace < frameIntervalMs) return;
    _lastTrace = now;
    debugPrint(message);
  }

  static int _lastFrame = 0;
  static int _lastMiss = 0;

  static bool get _on => enabled && kDebugMode;

  static void frame(String message) {
    if (!_on) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrame < frameIntervalMs) return;
    _lastFrame = now;
    debugPrint(message);
  }

  static void missDetail(String message) {
    if (!_on) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMiss < missDetailIntervalMs) return;
    _lastMiss = now;
    debugPrint(message);
  }
}

/// Per-frame paint timing for the vector layer, surfaced through the HUD.
///
/// Used to quantify the drag/pan optimisation: with retained geometry the
/// per-frame `paint` cost should collapse, and `avgPaintMs` drops accordingly.
/// Replaced the old full rebuild path when `enableRetainedGeometry` is off, so
/// the same HUD number can A/B the two implementations on-device.
class MvtPaintMetrics {
  MvtPaintMetrics._();

  static final Stopwatch _sw = Stopwatch();
  static int lastPaintMs = 0;
  static int maxPaintMs = 0;
  static int frames = 0;
  static int retainedHits = 0;
  static int retainedMisses = 0;

  static final List<int> _history = [];
  static const int _historyCap = 60;

  static void beginFrame() {
    _sw
      ..reset()
      ..start();
  }

  static void endFrame() {
    _sw.stop();
    lastPaintMs = (_sw.elapsedMicroseconds / 1000).round();
    if (lastPaintMs > maxPaintMs) maxPaintMs = lastPaintMs;
    frames++;
    _history.add(lastPaintMs);
    if (_history.length > _historyCap) _history.removeAt(0);
  }

  static double get avgPaintMs => _history.isEmpty
      ? 0
      : _history.fold(0, (a, b) => a + b) / _history.length;

  /// Call when a tile's cached `Picture` is reused this frame.
  static void recordRetainedHit() => retainedHits++;

  /// Call when a tile falls back to the old per-vertex path this frame.
  static void recordRetainedMiss() => retainedMisses++;

  static void reset() {
    lastPaintMs = 0;
    maxPaintMs = 0;
    frames = 0;
    retainedHits = 0;
    retainedMisses = 0;
    _history.clear();
  }
}
