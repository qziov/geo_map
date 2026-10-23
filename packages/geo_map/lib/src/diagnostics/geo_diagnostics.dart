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

  /// MapLibre TileManager 同款常量（tile_manager.ts L102-103）。
  static const int maxUnderzooming = 10;
  static const int maxOverzooming = 3;

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
