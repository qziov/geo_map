# M1 方案：Style Spec + 表达式求值器

导语：M1 要解决的问题是——让 geo_map 不再"只会贴图"，而是能读一份 MapLibre 风格的 style JSON，按图层的 paint / layout 属性（含表达式）把 fill / line 画出来。本文是方案、技术验证、源码对齐与渲染管线梳理，随后分步落地。

## 一、目标与范围

**做**：

- 读入 style JSON（v8 子集）：`sources` + `layers`。
- 支持 `fill` / `line` 两类图层。
- 支持属性值"常量或表达式"：`get`、比较、逻辑、`interpolate`、`step`、`case`、`coalesce` 等。
- 按 zoom 求值（camera 表达式每帧重算）。

**不做（留给后续）**：

- `symbol` / 文本 / 图标 / 碰撞（M3）。
- MVT 矢量瓦片解码（M2）。
- 完整的 spec 校验、legacy function、`within` / `distance`、`*-pattern` 等。

## 二、技术验证（已跑通）

在 `packages/geo_map_core/lib/src/style/` 落地了一个可运行的 spike，纯 Dart、无 `dart:ui`：

- `style_color.dart` —— `StyleColor`（`#rgb`/`#rrggbb`/`#rrggbbaa`/`rgb()/rgba()`/命名色），`lerp`、`toCss`。
- `expression.dart` —— `Expr` 节点 + `parseExpression` + `ExpressionContext{zoom, properties}`。
  支持：`literal` `get` `has` `zoom`、`== != > < >= <=`、`all any !`、`interpolate`（linear / exponential）、`step`、`case`、`coalesce`、`to-number/to-string/to-color`。
  每个节点都能回答 `isFeatureConstant` / `isZoomConstant`（对齐 MapLibre 的常量分析）。
- `style_spec.dart` —— `StyleSpec` / `StyleLayer` / `PropertyValue`（常量或表达式，`evaluate(ctx)`）。
- 测试：`test/style/expression_test.dart`、`style_spec_test.dart`，**20 例**；core 全套 **209 例**全过。

验证到的事实：

1. 表达式"解析 + 求值 + 常量分析"完全能在纯 Dart 里做，且可测。
2. 颜色插值的坑：`interpolate` 的停靠点通常是字符串字面量，求值时需按颜色解析（已在 `_mix` 处理）；否则会"数值能插、颜色不能"。
3. `PropertyValue` 的"常量 vs 表达式"分叉点，正好对应 MapLibre 的 `PropertyValue` / `PossiblyEvaluatedPropertyValue`。

## 三、源码对齐（以源码为准）

**重要更正**：本机 `maplibre-gl-js-main` 里 **`src/style-spec/` 已不存在**——style spec 被抽成外部包
`@maplibre/maplibre-gl-style-spec`：

- 本仓依赖：`[REPO]\package.json:37` → `^26.4.4`；锁定 `26.4.4`（`package-lock.json:2254`）。
- 本仓没有 `node_modules`、也没有 vendored 副本；行号取自本机最接近的已安装副本 **v26.2.1**
  （`.../node_modules/@maplibre/maplibre-gl-style-spec/`，结构与 26.4.4 一致）。下文记作 `[SPEC]`；
  `[REPO]` 指 `C:\WorkSpace\Flutter\maplibre-gl-js-main\`。

**schema / 属性表**（`[SPEC]src/reference/v8.json`）：

- `layer` 定义 `:762`；`type` 枚举 `:767`（fill `:772`、line `:784`）。
- `paint_fill` `:6383`（`fill-color` `:6470`、`fill-opacity` `:6408`、`fill-antialias` `:6394`）。
- `paint_line` `:6896`（`line-color` `:6959`、`line-width` `:7062`）。
- 每个属性的关键字段：`type`、`default`、`property-type`（data-constant / data-driven / color-ramp / cross-faded）、`expression:{interpolated, parameters}`。

**表达式解析与求值**（`[SPEC]src/expression/`）：

- 解析入口：`parsing_context.ts:16`（类）/`:58`（`parse`）/`:73`（`_parse`：数组 vs 字面量）。
- 注册表：`definitions/index.ts:32`；内建 `get/has/zoom/all/any/!` 在 `compound_expression.ts`（`get:262`、`has:252`、`zoom:280`、`all:483`、`any:498`、`!:513`）。
- 比较：`definitions/comparison.ts:84`（`makeComparison`）。
- `interpolate`：`definitions/interpolate.ts:58`（类）/`:95`（parse）/`:214`（evaluate）/`:76`（插值因子）。
- `step`：`definitions/step.ts:11`；`case`：`case.ts:10`；`coalesce`：`coalesce.ts:9`；`let/var`：`let.ts:6`/`var.ts:6`。
- 顶层编译：`index.ts:665`（`normalizePropertyExpression`）/`:499`（`createPropertyExpression`）/`:721`（`findZoomCurve`）。
- 求值上下文：`evaluation_context.ts:8`（globals / feature / featureState …）。

**本仓消费侧**（`[REPO]src/style/` + `src/webgl/` + `src/data/`）：

- 属性对象：`properties.ts:73-105`（`PropertyValue`）、`:469-500`（`PossiblyEvaluatedPropertyValue`）、`:547-574`（`DataConstantProperty`）、`:582-656`（`DataDrivenProperty`）。
- 每帧重算：`style.ts:774-793`（`recalculate`）→ `style_layer.ts:344-354`。
- 绘制：`webgl/draw/draw_fill.ts:22-26`（取 `fill-color`/`fill-opacity`）。
- 数据驱动绑顶点：`data/program_configuration.ts:504-537`（constant/source/composite 三种 binder）。

**我们据此对齐的四个语义**：

1. 表达式有四种 `kind`：`constant` / `source`（按 feature）/ `camera`（按 zoom）/ `composite`（两者）。
2. `zoom` **只能**出现在顶层 `step` / `interpolate` 的输入端（`findZoomCurve`，`index.ts:721`）；嵌套或出现多条是编译错误。
3. `camera` 属性**每帧**按新 zoom 重算成常量；`composite` 则把 `zoom` 与 `zoom+1` 两个值存进顶点，绘制时只更新插值因子。
4. 颜色属于可插值类型；停靠点要按属性类型解析。

## 四、渲染管线理清（现状 + 接入点）

### 现状一帧

```
GeoMap
  └─ MapInheritedModel(camera)          // 只比 camera
       └─ Stack[ 背景, TileLayer, ...children, 手势 ]
            └─ TileLayer → CustomPaint(_TilePainter)
                 ├─ CameraState(center, zoom, size)
                 ├─ coveringZoomLevel → dataZoom = clamp(...)
                 ├─ TileSelector.select(...)          // 选片（中心向外）
                 ├─ TileEngine.drawsFor(key, dataZoom) // exact / 子 / 父
                 └─ TileGeometry.drawTile(canvas, draw, opacity)  // 2D 仿射 / 3D 球面
```

关键事实：

- 2D / 3D 共用 `TileLayer`，只换 `projector` + `geometry`。
- **render zoom / data zoom 已存在**：`desiredZ` 用相机 zoom，`dataZoom` 夹到源的 min/max；矢量层可直接复用这个惯例。
- **完全没有 style / expression / 矢量瓦片**：唯一的矢量入口 `geojson_vector_source.dart` 是一次性全量、且只产出折线。

### 三个候选接入点

- **A（先做）`StyleVectorLayer` 放进 `GeoMap.children`**：零侵入现有光栅管线，2D/3D 靠 `camera.projectionDelegate` 分支；缺点是永远压在底图之上、拿不到引擎缓存。
- **C `FeatureGeometry` 与 `TileGeometry` 并列**：复用 `GeoProjector` / `TileMeshBuilder` / `CircleClip` / `cameraBasis`，最贴近 MapLibre 的 render pass；需轻微重构 `_TilePainter`。
- **B 一等图层 + 多 source**：最完整（z-order 在底图与覆盖物之间），但要改 `GeoMap` 的"单 source + 单引擎"模型，改动最大。

### 推荐路径

**A → C → B**。先用 A 把 style 语义与表达式跑通（不碰易碎的引擎所有权）；再把"逐要素投影/裁剪"抽成 C，替掉 `GlobeVectorLayer` 里手写的投影数学；最后 B 让 `GeoMap` 支持图层列表与多个 source。

## 五、分阶段（每阶段可交付、可验证）

- **M1.0（本轮）** 方案 + 技术验证 + 源码对齐 + 管线梳理。
  验收：`docs/M1_STYLE_SPEC_PLAN.md`；`core/src/style/*` 存在且 `dart test` 全过。
- **M1.1** style model + JSON 解析（补齐默认值、`source-layer`、`filter` 结构、图层类型校验）。
  验收：能解析一份真实 style JSON 的 fill/line 图层，未知字段容错；测试覆盖。
- **M1.2** 表达式求值器扩充（`let/var`、`match`、`in`、`to-boolean`、字符串比较；编译期拒绝非法 `zoom` 位置）。
  验收：常量分析四类正确；错误用例抛 `FormatException`。
- **M1.3** 接线渲染：`StyleVectorLayer`（A）读 style + GeoJSON 源，按 `PropertyValue` 求值绘制 fill/line；出示例（读一份 style JSON 渲染）。
  验收：示例可运行；同一份 style 在 2D/3D 都能画；补一份技术总结。

## 六、风险与未决

- **表达式语义坑**：`zoom` 只能顶层、`camera` 每帧重算、颜色停靠点解析——三条都已踩过/对齐。
- **投影数学**：新矢量层必须复用 core `GeoProjector`，不要重演 `GlobeVectorLayer` 手写 `_view` 的老路。
- **性能**：逐要素求值 + 逐帧 `Path` 重建；M1 先接受，LOD/缓存留到 M2。
- **spec 版本漂移**：对齐的是 v26（外部包）；升级时要重新核对 `v8.json` 与 `expression/`。
- **数据源缺口**：M1 先用 GeoJSON（一次性全量）；真正的 MVT 在 M2。

## 七、小结

- M1 的本质是"把样式求值从绘制里拆出来"：`PropertyValue`（常量/表达式）→ 每次绘制用 `ExpressionContext` 求值。
- 技术验证已完成：纯 Dart 的解析 + 求值 + 常量分析可跑、可测（20 例）。
- 渲染先挂 `children`（A），再抽 `FeatureGeometry`（C），最后升一等图层（B）。
- 下一步是 M1.1：把 style model 补成能解析真实 style JSON 的程度。
