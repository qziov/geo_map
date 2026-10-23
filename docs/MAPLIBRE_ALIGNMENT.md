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

## M1（style spec + 表达式）

- 审计：maplibre-gl-js `src/style-spec/*`、`src/expression/*`
- 产出：`GeoStyleSheet{version, sources, layers}` + `Expr` 求值器
- 命名映射：paint 属性 snake_case→camelCase（fill-color→fillColor）

## M2（MVT + bucket）

- 审计：maplibre-native `src/tile/vector_tile*`、bucket 分层
- 产出：MVT 解码（protobuf）+ fill/line bucket + `sourceLayer` 过滤

## M3（symbol 避让）

- 审计：gl-js `symbol/cross_tile_symbol_index` 与 placement
- 产出：碰撞检测 + 标注淡入淡出

## M4（可选）

- 自定义 shader / heatmap / 3D 地形
