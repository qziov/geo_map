/// Tile request scheduling: debounce during gestures + generation tokens so
/// in-flight requests from an older camera are discarded.
///
/// Pure Dart with an injected millisecond clock — fully unit testable.
library;

import '../tuning/geo_engine_tuning.dart';

class TileScheduler {
  TileScheduler({
    this.debounceMillis = GeoEngineTuning.tileRequestDebounceMillis,
  });

  final int debounceMillis;

  int _lastInteractionMs = -1 << 30;
  int _generation = 0;

  int get generation => _generation;

  /// Called on every camera change; `interacting` marks an active gesture.
  void noteCameraChange(int nowMs, {required bool interacting}) {
    if (interacting) _lastInteractionMs = nowMs;
  }

  /// May we issue new tile requests right now?
  bool canRequest(int nowMs) => nowMs - _lastInteractionMs >= debounceMillis;

  /// Called when the camera settles; invalidates in-flight requests so their
  /// results are dropped instead of polluting the cache.
  int invalidate() => ++_generation;

  bool isStale(int requestGeneration) => requestGeneration != _generation;

  void reset() {
    _lastInteractionMs = -1 << 30;
    _generation = 0;
  }
}
