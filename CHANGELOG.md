# Changelog

## 0.1.0 (2026-10-23)

- Initial release: 2D (Web Mercator) / 3D (orthographic globe) map engine
- Vendored flutter_map camera layer (12-patch fork extraction), zero
  flutter_map / proj4dart dependency
- Lab-proven globe layers: tiles (over/under-zoom, parent-tile fallback,
  polar caps, render-set underlay), vectors, images
- MapProjectionDelegate: pluggable projections behind one interface
- MBTiles raster source (WAL self-heal, real zoom-level detection)
- Gestures: pan / anchor pinch / double-tap / fling / wheel zoom
- `geo_map_core`: pure-Dart math + 82 tests
