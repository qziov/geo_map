/// Raster cache policy: byte budget + "current render set is never evicted".
///
/// Replaces the old count-based LRU (384 images ≈ 96 MB) where a transient spike
/// could evict tiles that were still on screen, causing black flicker.
library;

import '../tuning/geo_engine_tuning.dart';

class TileCachePolicy<K> {
  TileCachePolicy({
    int budgetBytes = GeoEngineTuning.cacheBudgetBytes,
  }) : budgetBytes = budgetBytes;

  final int budgetBytes;

  final Map<K, int> _bytes = {};
  final Map<K, int> _lastUsedTick = {};
  final Map<K, int> _hotFrame = {};

  final Set<K> _previousRenderSet = {};
  final Set<K> _currentRenderSet = {};

  int _tick = 0;
  int _frame = 0;
  int _totalBytes = 0;

  int get bytes => _totalBytes;
  int get length => _bytes.length;
  bool contains(K key) => _bytes.containsKey(key);
  int bytesOf(K key) => _bytes[key] ?? 0;

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
}
