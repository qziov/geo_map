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
| `renderWorldCopies`（GeoJSON 直绘路径） | `StyleVectorLayer._drawWithCopies` + `visibleWorldCopies` | 平面每要素按可见世界副本平移重绘；此前只有 MVT 路径有 |
| 反子午线（geojson-vt 在 ±180° 切片） | `unwrapLongitudes` + `_projectContinuous`（core `antimeridian.dart`） | 逐顶点 wrap 会把环撕成两半；解缠后得连续 x，跨 ±180° 不再横跨整屏 |
| `fill` 绕向（外环 / 洞） | `_normalizeRings` | 外环保持、洞反向，`nonzero` 才正确挖洞 |

## M2（MVT + bucket）✅

| MapLibre | geo_map 对应 | 备注 |
| --- | --- | --- |
| protobuf 解码 / `classifyRings` 绕向分组 | `decodeMvtTile` + `classifyMvtPolygonRings`（core） | v1 polygon 不做 wagyu fixup（同 native） |
| tile 空间细分（`subdivision.ts`，line 512 / fill 128·min 2） | `subdivideTilePolyline` | 只在源空间加顶点，不沿大圆插值 |
| 桶按颜色分组批渲染（`fill_bucket` 的 program 变体） | 每图层一个 `Path` + 一次 `drawPath`，按 (fill, outline) 颜色分组合批 | Canvas 后端 |
| `renderWorldCopies` | `MvtVectorLayer.renderWorldCopies` | 2D 生效 |
| 球面裁剪（`_projection_globe` 的 clip/discard） | `clipRingToHorizon`（CPU） | Canvas 没有 depth/clipAntimeridian |

> **平面无限滚动（`worldCopyJump`）**：`FlatProjectionDelegate.panCenter` / `anchorCenter`
> 把相机经度 **wrap**（不 clamp 到 ±180），东西方向可无限平移；渲染侧栅格
> （`AffineGeometry.worldCopies`）与矢量（`visibleWorldCopies`）都按世界副本重复，接缝无缝。

## M3（symbol 避让）✅

| MapLibre | geo_map 对应 | 备注 |
| --- | --- | --- |
| `symbol_layout` 的锚点 + `image_positions` 查表 | `buildMvtSymbolBucket` + `resolveSymbols` | 文字**不**在桶里解析（桶跨样式复用） |
| `CollisionIndex` + `GridIndex`（25px cell） | `SymbolPlacer` + `GridIndex`（core） | 放置两颗网格 + 只查阻断网格（`collision_index.ts:173`） |
| `overlapAllowed`（always / cooperative / never） | `allowOverlap` / `ignorePlacement` / `collisionGroup` | 图标与文字同 group，可互相压 |
| `symbol_sort_key` 决定占位优先级 | `symbol-sort-key` + 稳定的 feature 序 | 没有稳定 tie-break 会逐帧互换 |
| 标签不随剪影裁剪（`isOccluded` 判定） | 锚点投影为 null 即丢，其余整条绘制 | `collision_index.ts:166` |
| sprite：`<url>.json` + `<url>.png`，尺寸 ÷ pixelRatio | `SpriteIndex` + `SpriteAtlas` | `quads.ts:133-134` |

**M3 已全部对齐**（此前这里列的四项"未对齐"经源码核对其实都已实现，文档当时没跟上）：

| MapLibre | geo_map 对应 | 实现位置 |
| --- | --- | --- |
| `symbol-placement: line`（沿线标注） | 沿线段角度旋转标签 | `mvt_vector_layer.dart:689`（读属性）/ `:715`（算角度）+ core `buildMvtLineSymbolBucket` |
| `text-anchor` / `text-offset` / `icon-anchor` / `icon-offset` | 九宫格锚点 + 偏移 | `style_properties.dart`（属性定义）+ `symbol_style.dart`（解析）+ `symbol_painter.dart:34` `anchorBoxOffset` |
| 图标 SDF 着色 | `icon-color` 对 SDF 图集染色 | `symbol_style.dart`（取色）+ `symbol_painter.dart:175`（`srcIn` 滤镜） |
| 跨 tile 去重（`cross_tile_symbol_index`） | `crossTileKey` 跨瓦片合并 | core `symbol_placement.dart` + `mvt_vector_layer.dart:718` |

## 要素查询 ✅

| MapLibre | geo_map 对应 | 备注 |
| --- | --- | --- |
| `queryRenderedFeatures`（屏幕 bbox 查询） | `GeoFeatureRegistry.queryFeatures` | 本 SDK **按几何类型分派**：点 = 屏幕半径（24px）、面 = 地理空间 point-in-polygon |
| `feature_filter` / `layer` 过滤 | `sourceIds` / `geometries` / `visible` | v1 不按 `layer` 过滤（一个 source 对应一个业务图层） |
| 跨 ±180° 的面要素 | `pointInPolygon`（even-odd + 窗口内唯一副本锚定） | 查询经度取**落在环解缠窗口内的唯一副本**，不是"挪到与首点同副本" —— 后者在宽环上会漏命中 |
| 拾取投影 | `projectForPick` | 平面折到最近世界副本（`project` 不 wrap，会把要素放到一整个世界之外）；球面识别 `(-1e6,-1e6)` 背面哨兵 |
| `setFeatureState` / 选中高亮 | — | **v1 不做**（含 MVT 瓦片要素查询） |

## M4（可选）

- 自定义 shader / heatmap / 3D 地形
