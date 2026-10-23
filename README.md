# geo_map

A self-contained 2D/3D Flutter map engine — **no flutter_map dependency**.

- `packages/geo_map_core` — pure Dart: projections, camera math, tile selection, mesh, cache policy. Runs under `dart test` (no `dart:ui`).
- `packages/geo_map` — Flutter shell: `GeoMap` widget, layers, gesture layer, tile sources.

## Why two packages

`flutter_tester` is unreliable in this environment, so every guarantee that can be
automated lives in the pure-Dart core. The Flutter shell only wires `dart:ui`
(Canvas / Vertices / ImageShader) to the core's geometry.

## Design contracts

| Contract | Where | Test |
| --- | --- | --- |
| Projector is stateless | `projection/geo_projector.dart` | `projection_test.dart` |
| 2D/3D differ only by projector | `projection/*.dart` | `projection_test.dart` (limit consistency) |
| Styles are screen-space | `tuning/geo_engine_tuning.dart` | `hud_and_tuning_test.dart` |
| Tile window is O(visible) | `tiles/tile_selector.dart` | `tile_selector_test.dart` |
| Cache is byte-budgeted and protects the render set | `tiles/tile_cache_policy.dart` | `cache_and_scheduler_test.dart` |
| Geometry is cached on the unit sphere | `tiles/tile_mesh.dart` | `tile_mesh_test.dart` |

## Development

```bash
cd packages/geo_map_core
dart pub get
dart analyze
dart test
```

Tags: `p0-core` (core + tests), `p1-render` (host + raster), `p2-style` (style
system + vector/symbol/image + hit testing).
