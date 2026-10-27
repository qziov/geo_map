# 架构

```
GeoMap (widget/geo_map.dart)          组装：InheritedModel(camera) + 图层 + 手势
  │
  ├─ vendor/flutter_map_camera/       ★ fork 提取的相机层（冻结快照）
  │    MapCamera · Crs(Epsg3857/4326) · MapProjectionDelegate（接口）
  │    GlobeProjectionDelegate（3D 正交）· FlatProjectionDelegate（2D 仿射）
  │
  ├─ engine/                          ★ 统一渲染栈（2D/3D 共用同一条管线）
  │    TileEngine      请求 / 解码缓存 / 失败分级 / 回退链 / 极帽
  │    TileGeometry    抽象：drawTile / drawCap
  │      SphericalGeometry  3D 球面网格（单位球 mesh + 地平线剔除）
  │      AffineGeometry     2D 仿射矩形（世界像素 + 世界副本）
  │    TileLayer       唯一图层：选片 → 请求 → 回退 → 绘制
  │
  ├─ globe/                           其他图层（矢量/影像）与数据源
  │    GlobeVectorLayer 矢量（线/面/点/标签）+ buildGraticule/buildTissot
  │    GlobeImageLayer  影像叠加
  │    tile_source      GlobeRasterSource 契约（TileFetchResult / TileSchemeKind）
  │
  ├─ style/                           ★ 样式驱动图层（M1/M2/M3）
  │    StyleVectorLayer  GeoJSON + style spec → fill/line/symbol
  │    MvtVectorLayer    MVT 瓦片 → 建桶 → 绘制（fill/line/symbol）
  │    symbol_style      要素 → 图标/文字对（读 icon-* / text-*）
  │    symbol_painter    量盒 → 放置 → 绘制 + 布局缓存（字体 epoch 失效）
  │    sprite_atlas      <sprite>.png + .json → ui.Image + 名字→矩形
  │
  ├─ gesture/globe_gesture_overlay    手势（pan/锚点捏合/双击/fling/tap/滚轮）
  ├─ source/mbtiles_source            MBTiles（WAL 自愈 + 真实层级探测）
  └─ camera/geo_map_controller        控制器（持 MapCamera + delegate）
```

`packages/geo_map_core/` 是纯 Dart 核心（无 `dart:ui`），负责投影、相机数学、
瓦片网格、选片、网格构建、极帽、请求计划、回退决策、URL 构建与缓存策略；
以及 MVT 解码/分桶、style spec + 表达式 + 过滤器、符号分桶与碰撞放置、sprite 索引 ——
**398 项 `dart test` 覆盖**。

> 凡是"该不该请求 / 该回退到哪一级"这类决策，一律下沉到 core 的纯函数
> （如 `planTileRequest`），因为引擎本身依赖 `dart:ui`、在 `dart test` 下跑不起来。
> 放在引擎里的决策不会被任何测试覆盖 —— 这正是"放大后一直停留在上一级"能上线的原因。

## 数据流

1. 手势 → `GeoMapController`（move/panBy/zoomAround）
2. 控制器同步 `MapCamera` 值对象 + `delegate.updateCamera(center, zoom, size)`
3. `notifyListeners` → `MapInheritedModel` 重建 → 图层 painter 取 `MapCamera.of(context)`
4. `TileLayer.paint`：
   - 相机 → core `CameraState`（中心 / 缩放 / 视口）
   - `TileSelector.coveringZoomLevel` → 数据层级（钳到源范围）与渲染层级分离
   - `TileSelector.visible` → 窗口式选片（再逐块做几何相交验证）
   - `TileEngine.drawsFor` → 每块理想瓦片的绘制指令（命中 / 子代 / 祖先回退）
   - `TileGeometry.drawTile` → 2D 仿射矩形 或 3D 球面网格
   - `TileEngine.capDraws` → 极区极帽（mercator 止于 ±85.05°）
   - `TileEngine.commitFrame` → 渲染集保护（当前 / 上一帧的瓦片不会被淘汰）
5. `MvtVectorLayer` / `StyleVectorLayer.paint`：
   - 相机 → core `CameraState`；投影委托（2D 仿射 / 3D 正交）给出屏幕点
   - 逐图层遍历（fill / line 先画；**symbol 延后到剪影裁剪之外**）
   - fill：环沿剪影封口后 `addPolygon`；描边单独一条 Path（`fill-outline-color`）
   - symbol：`buildMvtSymbolBucket`（点要素 → 归一化锚点）→ 每要素解析成图标+文字对
     → `SymbolPainter` 量盒 → `SymbolPlacer` 决策 → 绘制（halo 先、填充后）

## 关键机制

| 机制 | 说明 |
| --- | --- |
| 请求语义 | 理想瓦片**无条件请求**（MapLibre `_updateRetainedTiles` → `_addTile(idealID)`），祖先链只作加载期回退。反过来（"什么都没缓存才请求"）会让画面在每次放大后永久停在粗一级 |
| 数据层 / 渲染层分离 | 数据层级 = `clamp(desiredZ, source.minZoom, source.maxZoom)`；渲染层级 = `desiredZ`。放大倍数恰为 `2^(render − data)`（MapLibre `calculateTileMatrix` 语义），纹理整图放大、不切子区 |
| 父级回退 | 瓦片缺失沿祖先链回退：**footprint 用细瓦片、纹理用父图子矩形**（`parentUvRect`）。反过来会把父图的一角拉伸到整个 footprint，即"马赛克块" |
| 失败分级 | 404 / 网络 / 解码失败分别计时退避；**404 永不拉黑**（MapLibre 同款），只延后重试 |
| 并发闸门 | HTTP 16 / MBTiles 4，超出的请求延后到下一帧 |
| 字节预算缓存 | 按字节而非条数淘汰；当前与上一帧的渲染集受保护 |
| 极帽·可见区间 | 解析求解（闭式），不采样：视口 = 角半径 `α` 的圆盘，极帽 = 极半径 `4.95°` 的圆盘，逐经线的最近点由 `tan φ* = tan φ_c / cos δ` 闭式给出，弧边靠二分。采样版在 z12 会漏掉整个极冠（8 个纬度样本 0.6° 间距 vs 0.2° 高的视口）|
| 极帽·两种 regimes | 需要列数 ≤ 64：逐列楔形（各自贴图、清晰）；否则**一整条带、单张贴图**（相机在极冠内、弧绕极一圈时）。逐列楔形在这个区间意味着每帧 4096 个 mesh、4096 张不同图片拼在一起 —— 即"放射状铺满视口" |
| 日界线 | 墨卡托投影按**相机相对经度**计算，跨 ±180° 的瓦片不会被劈成两半 |
| 碰撞网格 | 25px 均匀网格（`CollisionIndex` 默认值）：插入写进所有相交 cell，查询先收候选再比矩形。放置期**只查阻断网格**，`text-ignore-placement` 的符号插进另一张网格（不挤别人，但仍会被挡住）|
| 面要裁、标注不裁 | fill/line 在 `clipCircle` 内绘制（面不能画到球背面）；symbol 在 `restore()` 之后绘制 —— MapLibre 从不裁标签，它按符号判锚点遮挡（`collision_index.ts:166`），放下的标签整条画完 |
| 标签布局缓存 | `TextPainter.layout` 比绘制贵得多，缓存按（文字, 字号, 颜色, halo）键控；**字体 epoch** 由 `PaintingBinding.systemFonts` 递增，否则 web 上 CJK 回退字体到达前量出的"缺字形"结果会被永久缓存 |
| 图标尺寸 | 绘制像素 = sprite 像素 ÷ `pixelRatio`（`quads.ts:133-134`）：@2x 图集按半尺寸画，否则高分屏大一倍 |
| 虚线相位 | 相位锚定全局量（flat: `world*worldSize`；globe: `R·Δφ` / `R·cosφ·Δλ`），相邻瓦片在同一点算出同值；MapLibre 是每 tile 归零 |
