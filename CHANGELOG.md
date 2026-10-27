# Changelog

## 0.2.0 (2026-10-27)

### M1 — style spec + 表达式

- `StyleSpec` / `StyleLayer` / `StyleDocument`：v8 子集解析（paint/layout 默认值、
  `source` / `source-layer` / `filter` / min-max zoom / visibility）
- 表达式求值器：`get`/`has`/`zoom`/比较/`all|any|!`/`interpolate`/`step`/`case`/
  `coalesce`/`let|var`/`match`/`in`/`to-*`，以及算术 `+ - * / %`
- **filter 可以读 `["zoom"]`** —— MapLibre 用 `EvaluationParameters(zoom)` 求值
  （`data/feature_index.ts:235`）；此前恒按 z0 求值，zoom 相关过滤静默失效
- `StyleVectorLayer`：GeoJSON 要素 → 样式驱动的 fill/line；新增 `.ofSources`
  多源变体（一个图层只看自己 `source` 的要素，此前会串源画）

### M2 — MVT 矢量瓦片

- MVT 解码（protobuf/zlib）+ `classifyRings` 绕向分组 + tile 空间细分
  （粒度照 MapLibre：line 512 / fill 128·min 2）
- `MvtVectorLayer`：fill / line / 虚线（`line-dasharray`，相位锚定全局量）/ 世界副本 /
  数据驱动着色按颜色分组合批
- 球面填充沿剪影封口（`clipRingToHorizon`），修复跨地平线的环被 `close()` 弦抵消
- **`fill-outline-color` / `fill-antialias`**：未设置描边色时取 `fill-color`
  （MapLibre `properties.ts:616-620` + `fill_style_layer.ts:30-32`）；球面描边只走真实边，
  不描剪影弧

### M3 — 符号与标注

- `buildMvtSymbolBucket`：点要素 → 归一化锚点 + properties + 稳定 `tilePriority`
- `GridIndex` + `SymbolPlacer`：25px 碰撞网格（`collision_index.ts:87`）的移植，
  `text-allow-overlap` / `text-ignore-placement` / 同 `collisionGroup` 互不遮挡的语义与
  MapLibre 一致（放置期只查阻断网格，`collision_index.ts:173`）
- `SymbolPainter`：`TextPainter` 量盒 → 放置 → 绘制，halo 用描边实现；
  布局缓存按 **字体 epoch** 失效（`PaintingBinding.systemFonts`），否则 web 上
  CJK 回退字体到达前的豆腐块会被永久缓存
- **`icon-image`**：`SpriteIndex` + `SpriteAtlas`（`<sprite>.json` + `.png` 语义），
  绘制尺寸 = 像素 ÷ `pixelRatio`（`quads.ts:133-134`）；图标与文字作为一对参与碰撞
- **标注不参与地平线裁剪**：与 MapLibre 一致，按符号判遮挡（`collision_index.ts:166`），
  放下的标签整条画完，不会被剪影切半

### Web

- HTTP 传输拆成条件实现（io 共享 `HttpClient` / web XHR），三处调用点不再 import `dart:io`
- `MbtilesTileSource` 走条件导出 + web stub（浏览器里调用即抛），整包可在 web 编译

### Fixes

- `GeoMapController`：`_isGlobe` 由构造参数初始化（此前硬编码 true，2D 启动切 3D 会早退 →
  delegate 与瓦片几何不一致）；`applyConstraints` 自赋值导致缩放范围永远不生效
- `decodeMvtTileAsync`：web 无 isolate，改为内联解码（否则 HTTP 200 的瓦片全被记成失败）

### Tests

- `geo_map_core`：82 → **398** 项（MVT、style、表达式、过滤器、符号分桶/放置、sprite、投影）
- 新增 `example/` 画廊：4 个 web 可运行页面 + 1 个 native-only MBTiles 示例

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
