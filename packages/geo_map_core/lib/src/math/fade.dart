/// Time-based opacity helpers for tile fade-in and zoom cross-fade.
///
/// Kept free of `dart:ui` so they can be unit-tested under plain `dart test`
/// (the render stack that consumes them lives in the `geo_map` package, which
/// does import `dart:ui`).
library;

/// Linear self-fade opacity (0→1) for a tile decoded at [loadedAt] ms,
/// evaluated at wall-clock [now] ms over [durationMs].
///
/// A `null` [loadedAt] (pre-cached image) is always 1. Mirrors MapLibre's
/// raster self-fade (`getSelfFadeValues`): a freshly decoded tile rises from
/// transparent to opaque instead of popping in.
double selfFadeOpacity(int? loadedAt, int now, int durationMs) {
  if (loadedAt == null) return 1.0;
  final t = (now - loadedAt) / durationMs;
  if (t <= 0) return 0.0;
  if (t >= 1) return 1.0;
  return t;
}

/// Zoom cross-fade progress (0→1) for a transition that began at [startMs],
/// evaluated at [now] over [durationMs].
///
/// 0 means "show the old level only", 1 means "show the new level only" — the
/// two levels are blended in between. This is MapLibre's `u_fade_t` for the
/// parent↔child swap during a zoom step.
double crossFadeProgress(int startMs, int now, int durationMs) {
  if (durationMs <= 0) return 1.0;
  final t = (now - startMs) / durationMs;
  if (t <= 0) return 0.0;
  if (t >= 1) return 1.0;
  return t;
}

/// Whether a transition that began at [startMs] is still inside its
/// [durationMs] window at [now].
bool isWithinFade(int? startMs, int now, int durationMs) =>
    startMs != null && (now - startMs) < durationMs;
