# geo_map 拖动掉帧：根因调研与优化方向

> 调研目的：解释"相机静止 60fps、拖动明显掉帧、生产环境 mbtile 矢量瓦片尤其严重"的现象，给出可落地的优化方向。
> 调研范围：本地 `geo_map` 真仓源码 + 本地 `maplibre-native`、`maplibre-gl-js-main` 标杆实现 + 公开移动端地图渲染性能方案。
> 结论先行：**拖动的卡顿不是"渲染不出来"，而是每帧把几何从头重算了一遍**；矢量瓦片比栅格瓦片重，是因为栅格走 GPU 纹理贴图（廉价），矢量却走 CPU 三角化 + Canvas Path（昂贵），且这套重算在拖动的每一帧都发生。

---

## 1. 现象与结论速览

| 现象 | 直接原因 | 根因归类 |
|---|---|---|
| 静止 60fps | 画面不变 → 几何已就绪，每帧只是重绘已缓存内容 | — |
| 拖动掉帧 | 每帧 `paint()` 重新投影全部可见瓦片顶点、重建 `Path` 并 `drawPath` | 无保留几何（retained geometry） |
| 矢量瓦片更糟 | 矢量需 CPU 三角化 + Canvas 光栅化；栅格只是 `ImageShader` 贴图 | 矢量几何在主线程重建 |
| mbtile 生产环境更突出 | 直读 sqlite 时 `GZipCodec().decode` 在主 isolate 同步解压 | mbtile 取瓦片路径的主线程 CPU 成本 |

一句话根因：**矢量图层在拖动的每一帧都在主线程重做"解码后几何 → 屏幕坐标 → Canvas Path → 光栅化"的全链路，而栅格图层早已用"保留纹理 + 变换矩阵"规避了这一点。** 这正好与 MapLibre-native 的"几何只解码一次、每帧只改 MVP 矩阵 uniform"相反。

---

## 2. 对标：MapLibre（native / gl-js）为什么拖动不卡

（源码：`C:/WorkSpace/Flutter/maplibre-native`，本地只读调研）

1. **几何只生成一次，驻留 GPU；平移只改矩阵。**
   - 瓦片几何在解析阶段由 `GeometryTileWorker::parse` → `bucket->addFeature` 一次性三角化（`src/mln/tile/geometry_tile_worker.cpp:419-542`）。
   - 每帧 `RenderTile::prepare` 只算瓦片模型矩阵并乘上投影矩阵（`src/mln/renderer/render_tile.cpp:112-142`）：`matrix::multiply(matrix, transform.projMatrix, matrix)`。**顶点永远在瓦片局部坐标系，平移/旋转/缩放只改这个矩阵 uniform，不碰顶点数据。**
   - GPU 上传只发生一次：`Bucket::needsUpload()` = `hasData() && !uploaded`（`bucket.hpp:60`）。

2. **解析 / 布局 / SDF 字形 / 图集上传全在 worker 线程池，主渲染线程每帧只做廉价工作。**
   - Actor + Mailbox + 共享 `ThreadPool`（`actor/scheduler.cpp`）；`GeometryTile` 的解析 worker 跑在后台（`tile/geometry_tile.cpp:196-210`）。
   - 主线程因此每帧只做：矩阵计算 + 已上传 buffer 的绘制 + uniform 更新。

3. **瓦片调度：理想集 + 父子占位 + 过期丢弃 + wrap 复用。**
   - `TilePyramid::update` 用 `tileCover` 算 `idealTiles`，连续模式额外预取 `panTiles`（`tile_pyramid.cpp:56-300`）；`updateRenderables` 先复用已加载的子/父瓦片作占位（`:19-160`）。
   - 快速移动时旧解析结果被整包丢弃：`GeometryTile::markObsolete` + worker 检查 `obsolete` 直接退出（`geometry_tile_worker.cpp:452-454`）。

4. **符号碰撞放置被节流，不是每帧做。**
   - `placementIsRecent()`：若距上次放置未超过 `updatePeriod` 就复用（`text/placement.cpp:160-168`）；纯平移时直接 `setPlacementStale()` 复用上次结果（`render_orchestrator.cpp:543-592`）。

5. **文本用 SDF 图集，GPU quad 绘制，无每帧光栅化。**
   - `GlyphManager::generateLocalSDF` 把字形光栅化为 SDF 一次并打包进图集（`text/glyph_manager.cpp:72-77`），跨瓦片/跨帧复用。

### 2.6 补充参考：华为 Map Kit CodeLab（`huaweicodelabs/MapKit`）

- **是什么**：华为 Map Kit 的官方 CodeLab 示例仓库，包含 **Android（Java/Kotlin）** 与 **HarmonyOS（ArkTS/ArkUI）** 两套消费级 Demo，最后更新于 2022 年，Apache 2.0。它封装的是华为 Map Kit SDK 的公开 API，是"如何消费一个成熟移动端地图 SDK"的范例，**不是渲染引擎底层实现**。
- **与本调研的相关性**：
  - **HarmonyOS 对标价值**：geo_map 工程自身带有 `ohos/` 平台目录，而本仓库的 `harmonyos/` 子工程正是 ArkTS/ArkUI 上集成华为 Map Kit 的形态——可作为"在鸿蒙上地图应如何被集成 / 成熟 SDK 在该平台上的渲染与交互封装"的参照。
  - **架构对照价值**：它代表的"托管式 GPU-native 地图 SDK"（渲染下沉到原生 GPU 层，业务只调 API）恰好反衬出 geo_map 当前"在 Dart/Canvas 层自研渲染"的取舍——也印证了本报告的核心判断：把几何/绘制尽量下沉到"保留几何 + 变换矩阵 + GPU/原生层"才是流畅的关键，而不是每帧在 UI 层重算。
- **局限性（避免误用）**：该仓库是 API 使用示例，**不暴露**瓦片调度、几何三角化、线程模型、符号碰撞等底层优化细节，因此无法像 `maplibre-native` 那样提供可直接对照的渲染管线实现。它在本次调研中仅作为"鸿蒙目标 + 成熟 SDK 形态"的旁证，不作为渲染优化方案的代码来源。

公开方案交叉验证（Web 搜索）也指向同一组结论：MapLibre 的"GPU 加速几何变换 + Web Worker 卸载布局 + 流水线缓存 + LOD/declutter"是移动端矢量瓦片流畅的核心；而 Flutter `CustomPainter` 掉帧的经典根因正是"在 `paint()` 里每帧 `new Path` + 重算几何 + 盲目 `shouldRepaint` 返回 true"，对应修复是"预存 Path / 录成 `ui.Picture` / 精准 `shouldRepaint` / `RepaintBoundary`"。实测数据：每帧 `new Path` 方案 60fps 达标率约 **21%**，改用 `PictureRecorder` 后约 **92%**。

---

## 3. geo_map 当前实现剖析（关键证据）

### 3.1 栅格路径（已经做对了）

- `TileEngine`（栅格）解码为 `ui.Image` + `ImageShader`，绘制是廉价贴图（`engine/tile_engine.dart:43-59`）。
- `TileMeshBuilder` 把顶点缓存在**单位球面**上，注释明确写道 *"vertices are cached on the unit sphere, so panning does NOT rebuild geometry — the layer can reuse `ui.Vertices` through `canvas.transform`"*（`geo_map_core/lib/src/tiles/tile_mesh.dart:1-5`）。
- 调度用 `TileScheduler`：**120ms 防抖 + 中心向外优先级队列 + 相机 generation 失效**（`engine/tile_scheduler.dart`，`geo_engine_tuning.dart:tileRequestDebounceMillis=120`）。
- 结论：栅格层是"保留几何 + 变换"的正确范式，所以它能稳住帧率。

### 3.2 矢量路径（问题所在）

`MvtVectorLayer`（`style/mvt_vector_layer.dart`）每帧都做重活：

- **`paint()` 每帧重建全部 Path**：`_paintFills` / `_paintLines` 遍历每个可见瓦片、每个要素，逐个顶点 `_mappingFor().project()` 后 `Path.moveTo/lineTo`，再 `canvas.drawPath`（`:644-724`、`:787-880`）。`shouldRepaint` 一遇 `camera` 变化就返回 true（`:1130-1135`），于是**拖动每一帧都重投影 + 重建 Path + 重光栅化**。
  - 在平面（mercator）模式，拖动是**整张世界图的纯平移**，瓦片内相对几何根本不变——这里重算完全是浪费，本应只做一次 `canvas.translate`。
- **`build()` 每帧做重活**：`_layerWith` 每次重建都跑 `TileSelector.select`、逐瓦片 `_ensureTile`、 `resolveVectorDrawTiles`、 `planAncestorRequests`（`:289-379`）。
- **符号碰撞每帧重排**：`_paintSymbols` 每帧对全部瓦片全部符号调 `resolveSymbols`，`collisionGroup` 递增（`:733-783`），而 MapLibre 只在视口/缩放/数据变化时重排。
- **几何"分桶/三角化"在主线程**：`decodeMvtTileAsync` 把 protobuf 解码放到了 isolate（`mvt/mvt_async.dart:31-33`），但分桶 `buildMvtFillBucket` / `buildMvtLineBucket`（含细分）发生在 `_DecodedTile` 构造函数里、在 isolate 返回后于 **UI isolate 同步执行**（`:212-214`、`_DecodedTile` 构造 `:420-437`）。新瓦片在拖动中到达时，主线程被阻塞去三角化——z0 世界瓦片约 3.4 万顶点，是可见卡顿。
- **矢量自己的请求闸门很弱**：`_maxConcurrent = 6` 硬编码（`:141`），**没有防抖、没有优先级、没有相机 generation 失效**，与栅格 `TileScheduler` 不一致。快速拖动时会为每一个新视口位置立刻发最大量请求，既与帧预算抢 CPU，又可能去拉已经划出屏幕的瓦片。

### 3.3 mbtile 矢量瓦片生产环境更突出的额外原因

`MbtilesTileSource.fetch`（`source/mbtiles_source.dart`）：

- **同步 gzip 解压在主 isolate**：tippecanoe 默认 gzip 压缩 MVT，`fetch` 内 `_maybeGunzip` 用 `GZipCodec().decode` **同步**解压整张瓦片（`:265-275`）。HTTP 路径由 `HttpClient` 自动解压（不占主线程），但直读 sqlite 拿到的是原始 gzip 字节，**解压落在主线程**。
- sqlite 查询本身是同步（`_db.select`，`:238`），单文件句柄、并发 4（理论上不重），但解压 + 解析的时间都挤在 UI isolate。
- 结果：生产环境 mbtile 矢量瓦片每到达一张，主线程就同步承担"解压 + 分桶三角化 + 下一帧重投影"三笔 CPU 开销，拖动时成批到达 → 帧率雪崩。

---

## 4. 拖动掉帧的根本原因（按影响排序）

1. **无保留几何（retained geometry）。** 矢量 `paint()` 每帧重投影 + 重建 `Path` + 重光栅化；栅格层早已规避。这是首要原因，且平面平移场景纯属浪费。
2. **几何分桶/三角化在主线程。** 新瓦片到达即阻塞主线程去三角化，拖动时频繁触发。
3. **符号碰撞每帧重排。** O(N 符号)/帧，无节流、无跨帧缓存。
4. **矢量请求调度缺防抖/优先级/失效。** 拖动时请求风暴 + 拉取已离开屏幕的瓦片，浪费带宽与解码预算。
5. **mbtile 直读路径同步解压。** 矢量生产环境主线程额外 CPU 成本。
6. **每帧大量分配**（`Path`/`Paint`/`ExpressionContext`/列表）诱发 GC 停顿，表现为偶发掉帧，瓦片越密越明显。

> 为什么是"矢量比栅格糟"：栅格 = 解码成图片 + `ImageShader` 贴图（GPU 廉价）；矢量 = CPU 三角化 + Canvas Path 光栅化，且每帧重算。拖动的额外成本几乎全部来自矢量这条 CPU 重路径。

---

## 5. 优化方案建议（按收益排序，含落地方式）

### ★ A. 保留几何 + 瓦片 `Picture` 缓存（收益最大，对标 MapLibre 的 retained buffer + 矩阵 uniform）
- **平面模式**：把每个已解码瓦片（或每个 style-layer 分组）在瓦片局部坐标里用 `PictureRecorder` 预录成 `ui.Picture` 一次。`paint()` 时只做 `canvas.save(); canvas.translate(dx, dy); canvas.drawPicture(pic);` 每个瓦片（含 world copy）。平移变成整数平移已缓存画面 → 每帧 CPU 趋近零。
- **球面模式**：瓦片内细分几何（已在解码时按 zoom 细分）可在瓦片局部空间缓存；每帧只做廉价矩阵重投影 + `drawPicture`，并用每瓦片切平面仿射近似（细分粒度 `subdivPx=20px` 足够小，视觉无损）套用 `canvas.transform`，从而复用缓存 Picture。
- 落地：新增"瓦片→`ui.Picture`"缓存层，key 含 `(z,x,y, styleHash)`；几何/样式变化时失效重录。配套 `RepaintBoundary` + `isComplex:true`。
- 风险/注意：内存随可见瓦片数增长，用 `maxCachedTiles` + LRU 控制；样式热更新需失效对应 Picture。

### ★ B. 把分桶/三角化搬进 worker isolate（对标 MapLibre 的 `GeometryTileWorker`）
- 扩展 `decodeMvtTileAsync`：让 isolate 在解码后**一并**跑 `buildMvtFillBucket` / `buildMvtLineBucket`（含细分）。返回给主线程的已是可绘几何（纯 Dart、可 send）。主线程不再因新瓦片到达而卡顿。
- 注意：符号字形/精灵图集仍可能需主线程 `sprite`，但几何可全在 isolate 产出。
- 收益：消除根因 #2 的主线程阻塞。

### ★ C. 符号碰撞放置节流 + 跨帧缓存（对标 `placementIsRecent`）
- 仅在"瓦片集合 / 缩放 / 视口边界"变化时才重排；纯平移时复用上次碰撞网格结果。
- 将碰撞网格（`grid_index`）与放置结果持久化到帧间，而不是每帧重建。
- 收益：消除根因 #3 的每帧 O(N) 重排。

### ★ D. 矢量路径复用栅格的 `TileScheduler`（防抖 + 优先级 + generation）
- 把 `MvtVectorLayer` 自带的弱闸门替换为复用 `TileScheduler`：120ms 拖动防抖、中心向外优先级、相机 generation 失效丢弃过期请求。
- mbtile 源按 `sqliteParallelRequests=4` 限并发（不要硬编码 6）。
- 收益：消除根因 #4 的请求风暴，把帧预算让给渲染。

### E. mbtile 直读路径异步解压
- `_maybeGunzip` 改为在 isolate / `compute` 中解压，避免主线程同步 `GZipCodec().decode`。sqlite 读取也可经 `compute` 移出主线程。
- 收益：消除根因 #5，专治"生产 mbtile 更糟"。

### F. 零分配 / 复用绘制对象
- `Paint` 预存为字段，避免每帧 `new Paint()`；`Path` 用对象池 `reset()` 复用；`ExpressionContext` 不要逐要素 new。
- 配合 A 的 Picture 缓存，绝大部分分配可消除。收益：缓解根因 #6 的 GC 抖动。

### G. LOD / 抽稀（辅助）
- 低 zoom 或对 overzoom 瓦片降低细分粒度（`mvtSubdivisionGranularity`），减少顶点数；数据侧用 tippecanoe 在切片阶段按 zoom 简化、砍属性、brotli 压缩。

---

## 6. 验证与度量建议

- **对比实验**：在 `MvtVectorLayer` 加开关，A 方案前后用 DevTools Performance 录"拖动 1s"的 UI/Raster 线程耗时与 GC 频率，目标把每帧 `paint` 耗时从"重投影全量几何"降到"若干 `drawPicture`"。
- **指标**：拖动帧率（目标回到 ~60fps）、每帧 `paint()` 耗时、GC 次数/s、新瓦片到达时的主线程长任务（Long Task）。
- **诊断 HUD**：`MvtDiagnostics` 已有 `readyCount/tileCount/failedCount`；建议加"每帧 paint 耗时"与"主线程 decode/三角化耗时"埋点，定位是否在拖动用掉了帧预算。
- **可参考的标杆**：`tile_mesh.dart` 已是"保留几何 + canvas.transform"的正确样板，矢量层应向它看齐，而不是各自为政。

---

## 7. 参考

- 本地源码：`geo_map`（`packages/geo_map`, `packages/geo_map_core`）、`maplibre-native`（`src/mln/renderer`, `src/mln/tile`, `src/mln/text`, `src/mln/actor`），`maplibre-gl-js-main`（`src/render`, `src/tile`, `src/symbol`）。
- 公开方案：MapLibre 官方性能文档、`CustomPainter` jank 修复范式（`ui.Picture` 缓存 / `shouldRepaint` / `RepaintBoundary`）、移动端矢量瓦片优化（GPU 卸载 / LOD / declutter）。
- 标杆 SDK 对照：[`huaweicodelabs/MapKit`](https://github.com/huaweicodelabs/MapKit)（华为 Map Kit CodeLab：Android Java/Kotlin + HarmonyOS/ArkTS，2022，Apache 2.0）——作为"成熟托管式 GPU-native 地图 SDK 的消费级形态 + 鸿蒙集成"旁证；详情见 §2.6，注意其不提供渲染底层实现。
