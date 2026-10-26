# 瓦片管线：从"视口要什么"到"屏幕画什么"

导语：一块瓦片要经过选片、请求、缓存、回退、绘制、淡入六道关才上屏。任何一道错了，用户看到的就是黑屏、闪烁或卡顿。本文把 geo_map 的管事代码和 MapLibre GL JS 的对应模块摆在一起，说明每一段在做什么、为什么这么分。

## 一、问题从哪来

渲染一帧地图，先要回答一个问题：**当前视口该显示哪些瓦片？**

这听着简单，但每一块瓦片都有三种状态：还没请求、正在下载、已经解码。

三种状态混在一起，就会出现三类事故：

- 该请求的不请求，屏幕上留个洞 → **黑块（black tile）**。
- 请求了不该请求的，一屏发上千个请求 → **请求风暴（request storm）**。
- 已经画出来的被新帧覆盖掉，中间空一帧 → **闪烁（flicker）**。

MapLibre 的解法不是一个大函数，而是把管线**切成独立的段**，每段只做一件事。geo_map 照搬了这个切法。

```
视口 ──▶ 选片 ──▶ 请求 ──▶ 缓存/淘汰 ──▶ 回退 ──▶ 绘制 ──▶ 淡入 ──▶ 屏幕
        select    fetch      cache        resolve   draw     fade
```

分段的好处：一段出错，不会污染另一段。2D 和 3D 也能共用前五段，只在"绘制"这一步分叉。

## 二、原理：六段各做什么

### 1. 选片（selection）

目标：用尽量少的候选瓦片，覆盖整个视口。

不用"扫全表"，而是先算一个**可见包围盒**，再在这个窗口里逐片验证。

```
可见包围盒 ──▶ 窗口(x0..x1, y0..y1) ──▶ 逐片投影验证 ──▶ 候选列表
```

关键点：窗口必须是"真可见集合"的**超集**。宁可多选一片再否掉，也不能漏一片。漏一片就是黑块。

### 2. 请求（request）

目标：该要的都要，但别一次要一堆。

两条铁律：

- **理想瓦片无条件请求**。哪怕屏幕上已经有一张粗瓦片顶着，细瓦片也必须去下载，否则永远停在粗层级。
- **祖先链逐级升级**。只有下一级确认真失败，才去够上一级。一次把整座金字塔全请求，就是请求风暴的源头。

并发要设上限，手势期间要能防抖和作废在途请求。

### 3. 缓存 / 淘汰（cache）

目标：内存有上限，但当前帧用到的不能删。

用**字节预算**而不是"片数"做上限。淘汰按最近最少使用（LRU），但**渲染集里的瓦片受保护**——这一帧画过的，哪怕超预算也先留着。

### 4. 回退（fallback）

目标：理想瓦片没到时，屏幕上别留洞。

优先级：**精确 → 已加载的子瓦片 → 已加载的祖先**。

- 有子：一块大瓦片的足迹，交给四块小的拼。
- 有父：拿粗瓦片的**一小块纹理**拉到细瓦片的足迹上。

这里最容易错的是 UV：足迹（画在哪）和纹理区（取哪块图）是两回事。搞反了，就变成"把父瓦片的四分之一拉到整块足迹"——经典的"马赛克块"。

### 5. 绘制（draw）

目标：把每条绘制指令变成屏幕像素。

2D（Web Mercator）用仿射矩形 `drawImageRect`；3D（正交地球）用球面网格 `drawVertices`。

两者吃的是**同一份**指令列表，所以 bug 不会"2D 修好了 3D 还坏着"。

### 6. 淡入（fade）

目标：新瓦片别"啪"地硬弹出来。

每块瓦片解码时打时间戳，之后按经过时间从透明升到不透明。缩放跨层级时，旧层级（父）与新层级（子）再交叉混合。细节见 `docs/TILE_FADE.md`。

## 三、geo_map 与 MapLibre 的分段对应

```
段          geo_map 管事代码                          MapLibre 对应（源码位置）
────────    ─────────────────────────────────────    ──────────────────────────────────
选片        TileSelector.select / visible            coveringTiles (geo/projection/covering_tiles.ts:286)
            (core/src/tiles/tile_selector.dart)      coveringZoomLevel (:171) / isTileVisible (:90)
请求        planTileRequest (tile_request_plan.dart) _updateRetainedTiles (tile/tile_manager.ts:682)
            TileEngine.request + TileScheduler       _addTile / cancelPendingTileRequestsWhileZooming (:720)
缓存        TileCachePolicy (tile_cache_policy.dart)字节预算 LRU + 渲染集保护（MapLibre 的 retain/out-of-view 缓存）
回退        TileEngine.resolve + parentUvRect        parent/child retain（tile_manager.ts）
绘制        TileGeometry.drawTile / drawCap          draw_raster.ts + raster.vertex/fragment.glsl
            (AffineGeometry / SphericalGeometry)
淡入        fadeOpacity / crossFadeProgress          tile.ts timeAdded/fadeOpacity → draw_raster.ts
            (core/src/math/fade.dart)                getSelfFadeValues/getCrossFadeValues
```

一句话读法：**选片决定"要哪些"，请求决定"去拿哪些"，缓存决定"留哪些"，回退决定"没到时拿什么顶"，绘制决定"怎么画"，淡入决定"画出来怎么出现"。**

geo_map 把这些段都收在一个 `TileEngine` 里，2D/3D 只换投影和几何后端——这是它能"一处修、两处好"的原因。

## 四、关键代码（点到为止）

选片窗口。窗口必须覆盖"像素 margin 膨胀后的视口"，否则高纬会被投影压缩骗过去：

```dart
// core/src/tiles/tile_selector.dart
final bounds = projector.approximateVisibleBounds(camera, m); // m = 像素 margin
// ...
final extra = projector.windowPadTiles; // 球=1，平面=0，补采样误差
```

请求决策。理想瓦片和祖先链分开，逻辑下沉成纯函数才能单测：

```dart
// core/src/tiles/tile_request_plan.dart
if (isLoaded(ideal)) return const TileRequestPlan();
// 祖先只在"下一级确已失败"时才升级
if (failureOf(child) == null) break;
```

回退的 UV。足迹用细瓦片，纹理用父瓦片的子矩形：

```dart
// packages/geo_map/lib/src/engine/tile_engine.dart
final rect = parentUvRect(
  childX: key.x, childY: key.y, dz: dz,
  parentWidth: iw, parentHeight: ih,
); // geoKey = 细足迹，u0/v0/spanU/spanV = 父的子矩形
```

绘制。2D/3D 共用 `TileDraw`，只换后端：

```dart
// packages/geo_map/lib/src/engine/tile_layer.dart
geometry.drawTile(canvas, draw, camera: state, opacity: opacity);
```

## 五、未来可以怎么优化

调度器优先级队列与 pending 超时 —— 已实现（`TileScheduler.enqueue/take/reclaim`，同级 FIFO、超时回收）。**仍差一步**：引擎请求路径还没接这个队列（仍是立即 fetch + slot gate），队列目前未被消费；接线后优先级才真正生效。

URL 构建下沉到 core —— 已实现（core `TileUrlBuilder`：`{prefix}{ratio}{quadkey}{bbox}{bbox-epsg-3857}`、TMS 翻转、多模板轮询；`HttpTileSource` 已委托，`GeoTileSource` 契约也在 core）。

回退的 children/none 判定纯化 —— 已实现（`planTileResolution`：exact/children/ancestor/none，引擎 `resolve` 直接消费）。

验证 —— 淡入和交叉淡入是逐帧动画，`flutter test` 本机被拦截，只能在真机/模拟器肉眼确认。选片、缓存、请求这些纯逻辑都有 `dart test`。

## 六、小结

- 瓦片管线切成六段：选片 / 请求 / 缓存 / 回退 / 绘制 / 淡入。
- 每段只做一件事，一段出错不污染另一段；2D/3D 共用前五段。
- 选片要"超集"；请求要"理想必请求 + 祖先逐级"；缓存要"字节预算 + 渲染集保护"；回退要"足迹与纹理分开"。
- geo_map 把段收进一个 `TileEngine`，投影和几何后端是可替换的两处。
