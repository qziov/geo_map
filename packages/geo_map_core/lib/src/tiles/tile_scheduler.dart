/// Tile request scheduling: debounce during gestures + generation tokens so
/// in-flight requests from an older camera are discarded.
///
/// Pure Dart with an injected millisecond clock — fully unit testable.
library;

import '../tuning/geo_engine_tuning.dart';
import 'tile_scheme.dart';

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

  // --- request queue (priority + FIFO, with pending timeout) -------------------

  /// Waiting tiles, highest priority first. Within one priority it is FIFO.
  final List<_QueuedTile> _queue = [];

  /// Membership set so [enqueue] is idempotent without scanning [_queue].
  final Set<TileKey> _queuedKeys = {};

  int _sequence = 0;

  /// Queue [key] for a later slot. Returns `false` when it is already queued.
  ///
  /// [priority] is a higher-is-better score (e.g. proximity to the screen
  /// centre). Equal priorities keep insertion order, so a caller that enqueues
  /// in a centre-out selection order gets a centre-out queue for free.
  bool enqueue(TileKey key, int nowMs, {int priority = 0}) {
    if (!_queuedKeys.add(key)) return false;
    _queue.add(_QueuedTile(key, priority, _sequence++, nowMs));
    return true;
  }

  bool isQueued(TileKey key) => _queuedKeys.contains(key);

  /// How many tiles are waiting for a request slot.
  int get pendingCount => _queue.length;

  /// The next tile to dispatch (highest priority, FIFO within a priority), or
  /// `null` when the queue is empty.
  TileKey? takeNext() {
    if (_queue.isEmpty) return null;
    var best = 0;
    for (var i = 1; i < _queue.length; i++) {
      final a = _queue[i];
      final b = _queue[best];
      if (a.priority > b.priority ||
          (a.priority == b.priority && a.sequence < b.sequence)) {
        best = i;
      }
    }
    final chosen = _queue.removeAt(best);
    _queuedKeys.remove(chosen.key);
    return chosen.key;
  }

  /// Pull up to [max] tiles off the queue, in dispatch order.
  List<TileKey> take(int max) {
    final out = <TileKey>[];
    while (out.length < max) {
      final key = takeNext();
      if (key == null) break;
      out.add(key);
    }
    return out;
  }

  /// Remove [key] from the queue (e.g. it finished another way).
  bool remove(TileKey key) {
    if (!_queuedKeys.remove(key)) return false;
    _queue.removeWhere((e) => e.key == key);
    return true;
  }

  /// Drop every queued tile older than [timeoutMs] and return them.
  ///
  /// A stuck pending entry (e.g. a slot never freed) would otherwise occupy a
  /// queue slot forever; reclaiming lets the next selection re-request it.
  List<TileKey> reclaim(int nowMs, int timeoutMs) {
    final expired = <TileKey>[];
    _queue.removeWhere((e) {
      if (nowMs - e.enqueuedAtMs >= timeoutMs) {
        expired.add(e.key);
        return true;
      }
      return false;
    });
    for (final key in expired) {
      _queuedKeys.remove(key);
    }
    return expired;
  }

  /// Drop the whole queue.
  void clearQueue() {
    _queue.clear();
    _queuedKeys.clear();
  }

  void reset() {
    _lastInteractionMs = -1 << 30;
    _generation = 0;
    clearQueue();
    _sequence = 0;
  }
}

class _QueuedTile {
  _QueuedTile(this.key, this.priority, this.sequence, this.enqueuedAtMs);

  final TileKey key;
  final int priority;
  final int sequence;
  final int enqueuedAtMs;
}
