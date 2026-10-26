/// Raster cache policy: byte budget + "current render set is never evicted".
///
/// Replaces the old count-based LRU (384 images ≈ 96 MB) where a transient spike
/// could evict tiles that were still on screen, causing black flicker.
library;

import '../tuning/geo_engine_tuning.dart';

/// Why a tile could not be produced.
///
/// The distinction matters: a missing tile (404) must **not** be blacklisted
/// (MapLibre `tile_manager.ts` `_loadTile` just calls `update()` again and
/// keeps falling back to parent/child tiles), while a network error is
/// transient and should be retried quickly.
enum TileFailureKind {
  /// The server answered, but there is no such tile (HTTP 404/410).
  notFound,

  /// Transport-level problem: DNS, TCP, timeout, 5xx.
  network,

  /// The payload arrived but could not be decoded.
  decode,

  /// HTTP 200 with an empty body.
  empty,
}

/// Failure bookkeeping + byte budget + "current render set is never evicted".
class TileCachePolicy<K> {
  TileCachePolicy({
    this.budgetBytes = GeoEngineTuning.cacheBudgetBytes,
    this.maxTrackedKeys = GeoEngineTuning.maxTrackedTileKeys,
    this.maxConcurrentRequests = GeoEngineTuning.maxParallelRequests,
  });

  final int budgetBytes;

  /// Upper bound on the number of keys kept in the failure/tracking tables.
  final int maxTrackedKeys;

  /// Upper bound on concurrent in-flight requests.
  final int maxConcurrentRequests;

  final Map<K, int> _bytes = {};
  final Map<K, int> _lastUsedTick = {};
  final Map<K, int> _hotFrame = {};

  final Set<K> _previousRenderSet = {};
  final Set<K> _currentRenderSet = {};

  /// Failure state per key, with the wall-clock millisecond at which it may be
  /// retried.
  final Map<K, _FailureRecord> _failures = {};

  /// Insertion order of tracked keys — the eviction order for the tables above.
  final List<K> _trackedOrder = [];

  int _tick = 0;
  int _frame = 0;
  int _totalBytes = 0;
  int _inFlight = 0;

  int get bytes => _totalBytes;
  int get length => _bytes.length;
  bool contains(K key) => _bytes.containsKey(key);
  int bytesOf(K key) => _bytes[key] ?? 0;

  /// Number of keys currently tracked for failure/retry bookkeeping.
  int get trackedKeys => _trackedOrder.length;

  /// Number of requests currently in flight.
  int get inFlight => _inFlight;

  Set<K> get currentRenderSet => Set.unmodifiable(_currentRenderSet);
  Set<K> get previousRenderSet => Set.unmodifiable(_previousRenderSet);

  void put(K key, int byteSize) {
    if (_bytes.containsKey(key)) {
      _totalBytes -= _bytes[key]!;
    }
    _bytes[key] = byteSize;
    _lastUsedTick[key] = ++_tick;
    _hotFrame[key] = _frame;
    _totalBytes += byteSize;
  }

  void touch(K key) {
    if (!_bytes.containsKey(key)) return;
    _lastUsedTick[key] = ++_tick;
    _hotFrame[key] = _frame;
  }

  void remove(K key) {
    final b = _bytes.remove(key);
    if (b != null) _totalBytes -= b;
    _lastUsedTick.remove(key);
    _hotFrame.remove(key);
  }

  // --- render-set state machine -------------------------------------------------

  /// Start a frame: clears only the *current* set; the previous set survives so
  /// that a zoom-level switch can keep painting the old tiles underneath.
  void beginFrame() => _currentRenderSet.clear();

  void addRenderTile(K key) => _currentRenderSet.add(key);

  /// Promote the current set to "previous" for the next frame.
  ///
  /// If the frame drew nothing (e.g. all requests still pending) the previous set
  /// is kept — otherwise the underlay would disappear mid-zoom.
  void commitFrame() {
    _frame++;
    if (_currentRenderSet.isEmpty) return;
    _previousRenderSet
      ..clear()
      ..addAll(_currentRenderSet);
  }

  bool isProtected(K key) =>
      _currentRenderSet.contains(key) || _previousRenderSet.contains(key);

  /// Keys that may be evicted, oldest first. Protected (on-screen) keys are never
  /// returned, even when over budget.
  List<K> evictionOrder() {
    final candidates = _bytes.keys.where((k) => !isProtected(k)).toList()
      ..sort((a, b) => (_lastUsedTick[a] ?? 0).compareTo(_lastUsedTick[b] ?? 0));
    return candidates;
  }

  /// Evict until `bytes <= budgetBytes`, preserving the render sets.
  List<K> trim() {
    final evicted = <K>[];
    if (_totalBytes <= budgetBytes) return evicted;
    for (final key in evictionOrder()) {
      if (_totalBytes <= budgetBytes) break;
      evicted.add(key);
      remove(key);
    }
    return evicted;
  }

  /// Frames since [key] was last part of a rendered set (for diagnostics).
  int idleFrames(K key) => _frame - (_hotFrame[key] ?? _frame);

  // --- failure bookkeeping -----------------------------------------------------

  /// Retry cooldown for a failure kind.
  ///
  /// `notFound` gets the longest TTL because the tile genuinely does not
  /// exist; a network error must be retried almost immediately.
  Duration ttlFor(TileFailureKind kind) {
    switch (kind) {
      case TileFailureKind.notFound:
        return const Duration(milliseconds: GeoEngineTuning.notFoundTtlMs);
      case TileFailureKind.network:
        return const Duration(milliseconds: GeoEngineTuning.networkFailureTtlMs);
      case TileFailureKind.decode:
        return const Duration(milliseconds: GeoEngineTuning.decodeFailureTtlMs);
      case TileFailureKind.empty:
        return const Duration(milliseconds: GeoEngineTuning.networkFailureTtlMs);
    }
  }

  /// Exponential backoff for the [attempt]-th consecutive failure of a tile
  /// (MapLibre `tile.ts`: `1000 * 2^(n-1)`).
  Duration backoffFor(TileFailureKind kind, int attempt) {
    final base = switch (kind) {
      TileFailureKind.notFound => GeoEngineTuning.notFoundTtlMs,
      TileFailureKind.decode => GeoEngineTuning.decodeFailureTtlMs,
      TileFailureKind.network ||
      TileFailureKind.empty =>
        GeoEngineTuning.networkFailureTtlMs,
    };
    if (attempt <= 1) return Duration(milliseconds: base);
    final factor = 1 << (attempt - 1).clamp(0, 20);
    final ms = (base * factor).clamp(0, GeoEngineTuning.failureBackoffMaxMs);
    return Duration(milliseconds: ms);
  }

  /// Record a failure for [key].
  ///
  /// [nowMs] is the current wall clock in milliseconds; the record expires
  /// after the backoff window. The failure is *advisory*: it only gates the
  /// retry rate, it never prevents a parent/child fallback from being drawn.
  void markFailure(
    K key,
    TileFailureKind kind, {
    int nowMs = 0,
    int? attempt,
  }) {
    final previous = _failures[key];
    final n = attempt ??
        (previous == null || previous.kind != kind ? 1 : previous.attempt + 1);
    final wait = backoffFor(kind, n);
    _failures[key] = _FailureRecord(kind, nowMs + wait.inMilliseconds, n);
    _track(key);
  }

  /// Failure kind recorded for [key], or `null` when there is none.
  TileFailureKind? failureKind(K key) => _failures[key]?.kind;

  /// Whether [key] is still inside its failure cooldown.
  ///
  /// A `notFound` failure is reported as *not* blocking: MapLibre keeps
  /// loading parent/child tiles for a 404 and never blacklists it, so the
  /// engine must stay free to fall back. Only the retry of the very same URL
  /// is delayed.
  bool isFailed(K key, {int nowMs = 0, bool treatNotFoundAsBlocking = false}) {
    final rec = _failures[key];
    if (rec == null) return false;
    if (!treatNotFoundAsBlocking && rec.kind == TileFailureKind.notFound) {
      return false;
    }
    return nowMs < rec.retryAfterMs;
  }

  /// The moment [key] may be retried (epoch milliseconds), or `null`.
  int? retryAfter(K key) => _failures[key]?.retryAfterMs;

  /// Clear the failure record for [key] (a successful load).
  void clearFailure(K key) => _failures.remove(key);

  /// Drop every failure record.
  void clearFailures() => _failures.clear();

  // --- concurrency gate --------------------------------------------------------

  /// Reserve one of the [maxConcurrentRequests] slots.
  bool tryAcquireSlot() {
    if (_inFlight >= maxConcurrentRequests) return false;
    _inFlight++;
    return true;
  }

  /// Release a slot previously taken by [tryAcquireSlot].
  void releaseSlot() {
    if (_inFlight > 0) _inFlight--;
  }

  // --- internals ---------------------------------------------------------------

  void _track(K key) {
    if (_trackedOrder.contains(key)) return;
    _trackedOrder.add(key);
    while (_trackedOrder.length > maxTrackedKeys) {
      final oldest = _trackedOrder.removeAt(0);
      // Never drop a failure record for a key that is still cached.
      if (_bytes.containsKey(oldest)) {
        _trackedOrder.add(oldest);
        if (_trackedOrder.length > maxTrackedKeys * 2) break;
        continue;
      }
      _failures.remove(oldest);
    }
  }
}

class _FailureRecord {
  const _FailureRecord(this.kind, this.retryAfterMs, this.attempt);

  final TileFailureKind kind;
  final int retryAfterMs;
  final int attempt;
}
