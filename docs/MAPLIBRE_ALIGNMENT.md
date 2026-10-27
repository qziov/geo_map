# MapLibre 对齐

> 策略：**先对齐接口形状**（命名/分层），渲染实现保持 Canvas/Vertices；
> 完整 MapLibre 能力分阶段（M1-M4），每阶段产出对照表并更新本文档。
> 参照：maplibre-gl-js（style spec / 表达式）+ maplibre-native（渲染管线）。

## 已对齐（P1.8/P1.9）

| MapLibre 概念 | geo_map 对应 |
| --- | --- |
| Transform（相机状态） | vendored `MapCamera` + `MapProjectionDelegate` |
| overscaledZ（over-zoom 钳 maxzoom 放大绘制） | `_pickZoom().clamp(trueMinZoom, trueMaxZoom)` + mesh/贴图按 cameraZoom 缩放 |
| 父代回退（`max(zoom−maxUnderzooming, source.minzoom)`） | `lookupWithFallback` 祖先链 + UV 子矩形（`scaledTo` 等价） |
| 渲染集保留（`_retainLoadedChildren` 廉价版） | previousRenderSet 垫底（`addRenderTile` 在命中判定后） |
| source/layer 解耦 | `GlobeRasterSource` / 图层 widget 分离 |

## M1（style spec + 表达式）✅

| MapLibre | geo_map 对应 | 备注 |
| --- | --- | --- |
| `$root` / `layer` 解析与 paint/layout 默认值 | `StyleSpec` / `StyleLayer`（`layerPaintDefs` / `layerLayoutDefs`） | 默认值照 `v8.json` |
| `expression` 求值（`get`/`zoom`/`interpolate`/`match`/`case`/`let`…） | `Expr` 树 + `ExpressionContext` | 另补算术 `+ - * / %`（n 元、左折叠、除零返回 null） |
| `feature_filter`（可读 `["zoom"]`，`data/feature_index.ts:235`） | `compileFilter` → `FeaturePredicate(props, zoom)` | 此前恒按 z0 求值（bug，已修） |
| `fill_outline` 程序（1px 抗锯齿带，`fill_outline.fragment.glsl`） | 同环 1px `stroke`，独立 Path | 未设 `fill-outline-color` 时取 `fill-color`（`fill_style_layer.ts:30-32`）；球面只描真实边 |
| `fill-antialias` | 关闭时跳过描边 | — |

## M2（MVT + bucket）✅

| MapLibre | geo_map 对应 | 备注 |
| --- | --- | --- |
| protobuf 解码 / `classifyRings` 绕向分组 | `decodeMvtTile` + `classifyMvtPolygonRings`（core） | v1 polygon 不做 wagyu fixup（同 native） |
| tile 空间细分（`subdivision.ts`，line 512 / fill 128·min 2） | `subdivideTilePolyline` | 只在源空间加顶点，不沿大圆插值 |
| 桶按颜色分组批渲染（`fill_bucket` 的 program 变体） | 每图层一个 `Path` + 一次 `drawPath`，按 (fill, outline) 颜色分组合批 | Canvas 后端 |
| `renderWorldCopies` | `MvtVectorLayer.renderWorldCopies` | 2D 生效 |
| 球面裁剪（`_projection_globe` 的 clip/discard） | `clipRingToHorizon`（CPU） | Canvas 没有 depth/clipAntimeridian |

## M3（symbol 避让）✅

| MapLibre | geo_map 对应 | 备注 |
| --- | --- | --- |
| `symbol_layout` 的锚点 + `image_positions` 查表 | `buildMvtSymbolBucket` + `resolveSymbols` | 文字**不**在桶里解析（桶跨样式复用） |
| `CollisionIndex` + `GridIndex`（25px cell） | `SymbolPlacer` + `GridIndex`（core） | 放置两颗网格 + 只查阻断网格（`collision_index.ts:173`） |
| `overlapAllowed`（always / cooperative / never） | `allowOverlap` / `ignorePlacement` / `collisionGroup` | 图标与文字同 group，可互相压 |
| `symbol_sort_key` 决定占位优先级 | `symbol-sort-key` + 稳定的 feature 序 | 没有稳定 tie-break 会逐帧互换 |
| 标签不随剪影裁剪（`isOccluded` 判定） | 锚点投影为 null 即丢，其余整条绘制 | `collision_index.ts:166` |
| sprite：`<url>.json` + `<url>.png`，尺寸 ÷ pixelRatio | `SpriteIndex` + `SpriteAtlas` | `quads.ts:133-134` |

**M3 未对齐**：`symbol-placement: line`（沿线标注）、`text-anchor`/`text-offset`（当前图标上/文字下固定）、
图标 SDF 着色、跨 tile 去重（`cross_tile_symbol_index`）。

## M4（可选）

- 自定义 shader / heatmap / 3D 地形
