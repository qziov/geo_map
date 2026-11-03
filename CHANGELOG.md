# Changelog

## 0.2.1 (unreleased)

### Added — 要素查询（对标 `queryRenderedFeatures`）

- core 新增 `lib/src/math/point_in_polygon.dart`：`pointInRing` / `pointInPolygon` /
  `pointInMultiPolygon`（**even-odd** 规则，绕向无关；跨 ±180° 用"落在环解缠窗口内的
  **唯一副本**"锚定查询经度，而非"挪到与首点同一副本" —— 后者在经度跨度 > 180° 的宽环上
  会漏命中）、`ringSignedArea` / `normalizeRingWinding`（绕向归一化从 `StyleVectorLayer`
  下沉到 core，渲染与查询从此共用同一套绕向语义）。
  边界语义：外环边界算命中、**洞的边界不算**（洞优先）；零面积的退化环永不命中。
- core 新增 `lib/src/query/feature_query.dart`：`planFeatureQuery` —— 纯规划器
  （可见性 / source / 几何类型过滤 → 按几何类型分派 → 排序 → limit）。
  排序契约：来源分组（注册序）→ 点要素按屏幕距离升序且**等距"上层优先"**（后注册者在前，
  与绘制顺序一致）→ 面要素按原序。**线要素 v1 不命中**（明确文档化）。
- 引擎新增 `lib/src/query/`：`GeoFeatureRegistry`（注册 + `queryFeatures`）、`GeoQueryHit`
  （原样带回 `GeoJsonFeature` 的 id 与 properties、像素距离）、
  `projectForPick`（平面折到最近世界副本；球面识别 `(-1e6,-1e6)` 背面哨兵）。
  注册表是**快照而非 observable**，由宿主在数据变化时重建。
- `geo_map` barrel 追加 re-export：`GeoGeometryKind` 与上述地理工具
  （`unwrapLongitudes` / `splitRingAtSeam` 此前需直接 import core）。
- `GeoMap.onTap` 签名与 `GeoMap` / `GeoMapController` 公开 API **零改动**。

### Fixes — 平面模式

- **GeoJSON 多边形填充横跨整屏**：`StyleVectorLayer` 平面分支此前逐顶点投影
  （`MercatorProjector` 逐点 `wrapLongitude`），跨“相机经度 + 180°”剪切线的环被拉出
  满屏长弦、`nonZero` 填成横带。现在先 `unwrapLongitudes` 解缠得到**连续 x**（锚定最近
  世界副本），再按 `visibleWorldCopies` **平移重绘世界副本**，并对多环做绕向归一化
  （`_normalizeRings`）。等价 MapLibre `getVisibleUnwrappedCoordinates`。
- **平面无限水平平移**：`FlatProjectionDelegate.panCenter` / `anchorCenter` 把经度
  **wrap**（此前被 `_inclusiveLng` clamp 到 ±180，平移到边界即卡死）。栅格/矢量的
  世界副本保证接缝无缝。

### Added — 反子午线工具

- `packages/geo_map_core/lib/src/math/antimeridian.dart`：`unwrapLongitudes`（顺序解缠）、
  `splitRingAtSeam`（Sutherland–Hodgman 拆环），由 `geo_map_core.dart` 导出。

### Added — 跟随视角的气泡

- 新增 `GeoAnchoredPopup`（`src/widget/geo_anchored_popup.dart`，由 `geo_map.dart` 导出）：
  锚定一个 `LatLng`、在每次相机变化（平移/缩放/2D↔3D）时重新投影并重定位的纯展示浮层，
  对标 MapLibre `new Popup().setLngLat()`。配套导出 `AnchoredPopupLayout` 与
  `layoutAnchoredPopup`（纯布局：卡片底边中点对准锚点、夹入 `keepOut`、出屏/背半球哨兵判
  `visible:false`）。平面用 `projectForVector`（折回最近世界副本），球面用 `project`（背半球
  哨兵）→ 跨日界线/球面都准。
- 在 `GeoAnchoredPopup` 之上再封一层通用状态 + 接口，进一步解耦业务：
  - `GeoMapPopupController`（`ChangeNotifier`）：只持有**锚点**，`show/hide/toggle/isOpen`，
    对标 MapLibre `Popup` 的 open/close。状态与内容分离，SIGMET / 机场 / POI 等任意图层共用。
  - `GeoMapPopup`：自监听 `GeoMapPopupController`、自动在 `anchor==null` 时折叠，业务内容经
    `builder(context, anchor)` 注入（保留给宿主的"接口"）。
  - 复用时宿主只需：提供 `builder` 卡片、`keepOut`、点空白调 `hide()`、卡片关闭按钮调
    `hide()`；无需自己维护 `ValueNotifier<LatLng?>` 与 `if (anchor!=null) …` 样板。

### Added — 弹窗绑定层（`map.on('click', layerId, handler)` 的等价物）

把"哪个图层被点中、弹哪张卡、多个命中谁优先"从业务代码里收进 SDK：

- 新增 `GeoPopupBinding`（`src/widget/geo_popup_binding.dart`）：**声明式**绑定
  （`priority` / `cardSize` / `anchor` / `anchorOf` / `builder`）。通过
  `GeoFeatureRegistry.setSource(..., popup: binding)` 挂在要素源上，绑定与要素同生命周期，
  源重建/关闭时不会留下悬空绑定；读取用 `registry.popupOf(sourceId)`。
- 新增 `PopupAnchor` 九宫格枚举（`center` / `top` / `bottom` / `left` / `right` / 四角），
  对齐 MapLibre `PositionAnchor`。`layoutAnchoredPopup` 与 `GeoAnchoredPopup` /
  `GeoMapPopup` 均新增可选 `anchorSide`（默认 `bottom`，**旧行为不变**），并抽出纯函数
  `anchorOffsetFor(anchorSide, point, card, tail)` 便于单独断言。
- 新增 `GeoPopupController`（`src/widget/geo_popup_controller.dart`，`ChangeNotifier`）：
  `handleTap(tap, controller:, registry:, hits?, pointRadiusPx?)` 一条链路完成
  查询 → 过滤出注册了弹窗的源 → 按 `priority` 仲裁 → `show/close`（closeOnClick 语义）。
  另有 `registerPopup` / `unregisterPopup`（运行时挂载）与 `close()`。
  **不持有注册表**（每次由宿主传入），因此不会读到旧快照，也不会与宿主的
  Riverpod provider 形成循环依赖。`hits` 参数允许复用宿主已查过的结果，避免二次查询。
- 新增 `GeoMapPopupHost`：渲染侧唯一挂载点，把 `activeBuilder` / `activeCardSize` /
  `activeAnchor` 喂给底层 `GeoMapPopup`，业务层不必再手写 `GeoMapPopup(builder: ...)`。
- `GeoQueryHit` 抽到叶子文件 `src/query/geo_query_hit.dart`（仍由 `geo_feature_registry.dart`
  re-export），解除 `registry ↔ binding` 的循环导入。

### Fixes — 弹窗 dispose 安全

- `GeoPopupController` / `GeoMapPopupController` 现在 **dispose 后安全**：新增
  `isDisposed`，`dispose()` 置位后 `handleTap` / `close` / `show` / `hide` / `toggle`
  一律安静返回，`notifyListeners` 走内部 `_safeNotify()`。
  起因是一个真实崩溃：hot reload 改到 provider 源码时，Riverpod 的
  `ProviderElementBase.invalidateSelf()` 会**先 `runOnDispose()`（即 `notifier.dispose()`）
  再在下一帧重建**，这段"僵尸期"内点地图仍会把事件送到旧实例，`notifyListeners()`
  直接抛 `A GeoPopupController was used after being disposed` 打断整条手势链路。
  同样覆盖业务侧 `ref.invalidate(xxxPopupControllerProvider)` 的场景。
- 回归测试：`geo_popup_controller_test.dart` 新增 disposed-safety 组（2 例）。

### Fixes — 球面面要素封口走向（整球被涂满）

- **回归修复**：`db6d631` 把 limb 封口弧从"永远短弧"改成"按隐藏顶点的角度均值
  在长短弧之间选"。隐藏顶点在正交投影下落在**圆盘内部**，其角度与 limb 方位无关，
  一旦均值落到短弧区间之外就会选成长弧 —— 而"可见段 + 长弧"围出的正是
  *整个圆盘减去这块区域*，表现为 3D 球面被某块 SIGMET 颜色涂满。
  实测：10° 小矩形、相机 (30°, -12°)、z4 时填充覆盖 **99%** 圆盘（真值 <1%）。
- 改为**恒走短弧**：简单环的可见部分永远不会超过半个 limb，长弧没有正确场景。
  `clipRingToHorizon` 与 `GlobeVectorLayer._polygonPaths` 两处同步修正。
- 顺带补上"无旋转"带来的另一个缺口：可见段跨数组首尾时（首、末顶点都可见），
  原先被切成两个 run、中间被补一条 limb 弧。现在先合并成一段再封口 ——
  实测多个机位的 run 数从 2 降到 1，填充与真值一致。
- 新增 `core/test/projection/horizon_clip_cover_test.dart`：用"圆盘采样 + 球面
  point-in-ring"做**独立真值**，断言填充覆盖率与真值偏差 < max(5%, 30%)，
  并锁定"整球被填"的具体机位（覆盖率必须 < 10%）。原有 flicker 测试（连续性）
  全部保留且通过。

### Tests

- 新增 `geo_map_core/test/math/antimeridian_test.dart`、`geo_map/test/flat_infinite_pan_test.dart`
- 新增 `geo_map/test/geo_anchored_popup_test.dart`：`layoutAnchoredPopup` 纯函数 6 例 +
  `GeoAnchoredPopup` 控件 2 例 + `GeoMapPopupController` 4 例 + `GeoMapPopup` 控件 2 例
- 修正 `style_vector_layer_test.dart`：2D 组此前 `projectionDelegate` 为 null（实际跑的是
  球面投影），现显式 `FlatProjectionDelegate`；新增跨缝回归（跨 ±180° 的环不再填满屏幕中心、
  左右两侧各一段）
- 新增 `geo_map_core/test/math/point_in_polygon_test.dart`（几何判定：日界线、宽环、洞、
  边界、退化环、绕向）与 `geo_map_core/test/query/feature_query_test.dart`（规划器：半径
  闭区间、平局上层优先、过滤、排序契约、limit）——共 45 例
- 新增 `geo_map/test/geo_feature_registry_test.dart`（17 例：点命中、**球面背面哨兵**、
  **平面跨缝命中**、面命中、过滤、要素 id/properties 回传）
- 新增 `geo_map/test/geo_popup_anchor_test.dart`（九宫格九档未夹取偏移、`tail` 只作用于
  四边、出屏/非有限/背半球哨兵判 `visible:false`、`keepOut` 夹取）
- 新增 `geo_map/test/geo_popup_controller_test.dart`（命中开、无命中关=closeOnClick、
  `priority` 仲裁、`anchorOf` 覆盖锚点 / 默认用点击点、未绑定弹窗的源不触发、
  `registerPopup` 命令式绑定与 `unregisterPopup` 关闭当前卡片）
- `geo_map_core` 398 → **460**；`geo_map` 27 → **41** 项（本轮另新增引擎测试 17 例，
  需在可运行 `flutter test` 的环境执行；上述弹窗测试已实跑通过，见 0.2.1 弹窗绑定层）

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

### M3 — 符号收尾（标注几何与着色）

- **`symbol-placement: line`**：线要素逐段取中点、`atan2` 求段方向，标注沿线旋转
  （`buildMvtLineSymbolBucket`）；MVT 路径完整可用，`symbol-spacing` 仅预留参数
- **`text-anchor` / `icon-anchor` 九宫格** + **`text-offset` / `icon-offset`**：
  由 `anchorBoxOffset` 解出盒子相对锚点的位移；`text-offset` 单位是 **em**（乘
  `text-size`），`icon-offset` 是**像素** —— 同名不同义
- **`icon-color` 染 SDF 图标**：仅对 `sdf: true` 的精灵生效，走
  `ColorFilter.mode(color, BlendMode.srcIn)`；普通图标保持原样（对齐 MapLibre）
- **跨瓦片去重**：世界经纬度键（量化 1e-5°≈1m，`mvtTilePointToLatLng` 口径），同键只保留
  先放置者、其余标记 `SymbolPlacementResult.duplicate` 且**不占**碰撞网格
- **`text-rotate` / `icon-rotate`**：度 → 弧度，叠加在线段方向之上；旋转后的碰撞盒取
  轴对齐外接矩形（AABB），与 MapLibre 同一近似
- **`text-opacity`**：同时乘进文字填充与 halo 的 alpha，并参与布局缓存 key

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
