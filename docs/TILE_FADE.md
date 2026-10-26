# 瓦片加载淡入与拖动刷新：MapLibre 的过渡机制与 geo_map 移植

导语：缩放地图时，瓦片常常"啪"地一下出现，整片闪烁甚至黑屏。MapLibre GL JS 用两套机制消除这种硬切换：瓦片淡入（fade）和拖动缩放结束自动刷新。本文讲清原理，并说明 geo_map 如何移植其中的"淡入"。

## 一、问题从哪来

地图是瓦片（tile）拼出来的。每一块瓦片是一张图片，需要先下载。

用户缩放时，视口想要的是"理想瓦片（ideal tile）"——当前缩放级别下正好盖住屏幕的瓦片。

理想瓦片往往还没下载完。此时屏幕上只有两样东西：空白，或一张更粗的父瓦片被拉伸顶替。

如果下载完就立刻替换，用户会看到一次"硬弹出（hard pop）"：画面突跳、闪烁。

```
时间 ──────────────────────────────▶

缩放开始
  │
  ▼
理想瓦片缺失 ──▶ 空白 / 粗父瓦片(拉伸)
  │
  ▼  (几百毫秒后)
理想瓦片到达
  │
  ├─ 硬替换：瞬间切换  → 闪烁 / 黑屏
  └─ 淡入：  渐显叠加  → 平滑
```

问题本质：下载是异步的，渲染是同步的，两者需要一座桥。

## 二、原理：它到底在做什么

MapLibre 用两条独立的桥。

### 1. 瓦片淡入（fade / cross-fade）

只对栅格瓦片（raster tile）生效。矢量瓦片不走这条路径。

每块瓦片解码完成时打一个时间戳 `timeAdded`。之后每一帧，按经过的时间算一个透明度：

```
opacity = (now - timeAdded) / fadeDuration     // 0 → 1 线性
```

两种淡入：

- 自身淡入（self-fade）：新瓦片从透明渐变到不透明，盖在下面已有的内容上。
- 交叉淡入（cross-fade）：缩放时细瓦片还没到，先用粗父瓦片拉伸占位；细瓦片到达后，两者用 `mix(color0, color1, u_fade_t)` 混合，父淡出、子淡入。

```
缩放过渡期

  子瓦片(细, 新)   ▓▓▓▓▓   opacity: 0 → 1
  父瓦片(粗, 旧)   ░░░░░   opacity: 1 → 0
                    │
              screen = mix(父, 子, t)
```

淡入期间，引擎每帧都重绘自己（`triggerRepaint`），直到所有瓦片都过了 `fadeDuration`。

### 2. 拖动缩放结束自动刷新

这不是一个专门的"结束"函数，而是"每帧都重算"。

每一帧渲染时，引擎都重新算一次理想覆盖（`coveringTiles`）。移动过程中，理想瓦片没到就用已加载的子瓦片或父瓦片顶替；手指抬起、视口稳定后，理想瓦片就自然补齐。

```
每帧:
  render → updateSources → TileManager.update
        → coveringTiles  (重算理想覆盖)
        → 理想瓦片在途? 用子/父占位
        → 理想瓦片到达? 替换占位
```

节流也很关键：缩放途中暂停请求"无数据且未请求过的父瓦片"，滑出视口的瓦片中止在途请求，滑回时从缓存复用。这样不会狂发请求，也不留空洞。

## 三、几种做法对比

geo_map 之前只有"占位防黑屏"，没有"淡入"。

```
做法              缩放瞬换   占位防黑屏   自身淡入       交叉淡入
──────────────────────────────────────────────────────────
geo_map 旧版      有          有           无             无
MapLibre         已消除      有           有             有
geo_map 新版     无(已消除)  有           有(已移植)     有(已移植)
```

一句话：占位解决"黑屏"，自身淡入解决"新瓦片硬弹出"，交叉淡入解决"缩放跨层级瞬换"。三者互补，不冲突。geo_map 新版已无缩放瞬换。

geo_map 的占位已经很强——上一帧作为底图（underlay）一直画在下面，缩放不会黑。缺的只是"新瓦片从透明浮上来"那一下。

## 四、关键代码（点到为止）

MapLibre 源码位置（已逐行核对；该版本已重构，旧路径 `SourceCache` / `render/draw_raster.ts` 等已不存在）：

- 时间戳与状态：`src/tile/tile.ts` 的 `timeAdded` / `fadeEndTime` / `fadeOpacity` / `setCrossFadeLogic` / `setSelfFadeLogic`。
- 解码打时间戳：`src/tile/tile_manager.ts:309-317`（`_tileLoaded` → `timeAdded = now()`）。
- 自身淡入取值：`src/webgl/draw/draw_raster.ts:211-222`（`getSelfFadeValues`），结果乘进片元 alpha：`src/shaders/glsl/raster.fragment.glsl:28`。
- 交叉淡入取值：`src/webgl/draw/draw_raster.ts:150-206`（`getFadeProperties` / `getCrossFadeValues`），混合在 `raster.fragment.glsl:27` 的 `mix(color0, color1, u_fade_t)`。
- 每帧重算：`src/ui/map.ts:4438` → `src/style/style.ts:1903` → `src/tile/tile_manager.ts:540` → `src/geo/projection/covering_tiles.ts:286`。
- 占位与节流：`src/tile/tile_manager.ts:682`（`_updateRetainedTiles`）、`720`（`cancelPendingTileRequestsWhileZooming`）、`824`（`_removeTile` / `abortTile`）、`85,123`（`_outOfViewCache`）。

geo_map 移植（自身淡入，本次新增）：

- 时间戳：`packages/geo_map/lib/src/engine/tile_engine.dart` 的 `TileImage.loadedAt`，在 `_decode` 解码成功时写入。
- 透明度过场：`tile_engine.dart` 的 `fadeDurationMs`（300ms）、`fadeOpacity(image, now)`、`hasFadingTiles()`。
- 逐帧驱动：`packages/geo_map/lib/src/engine/tile_layer.dart` 的 `_TilePainter.fadeClock` 与 `_TileLayerState` 的 `_fadeTicker` / `_onFadeTick` / `_onEngineChanged`。
- 交叉淡入（本次新增）：`tile_engine.dart` 的 `noteDataZoom` / `crossFadeFromZoom` / `crossFadeProgressAt` / `isCrossFading` / `onCrossFadeStart`；`tile_layer.dart` 的 `paint` 在过渡期先画旧层级（from，opacity 1）再画新层级（to，opacity = selfFade × t）。
- 纯函数（可单测）：`geo_map_core/src/math/fade.dart` 的 `selfFadeOpacity` / `crossFadeProgress` / `isWithinFade`，已有 `geo_map_core/test/math/fade_test.dart`（5 例全过）。
- 透传钩子（早已存在）：`tile_geometry.dart` 的 `drawTile` / `drawCap` 本来就收 `opacity` 参数，本次只是从上层传入随时间变化的值。

最小片段——geo_map 如何算透明度：

```dart
// tile_engine.dart：刚解码完的瓦片，按经过时间线性淡入
double fadeOpacity(TileImage image, int now) {
  final loadedAt = image.loadedAt;
  if (loadedAt == null) return 1.0;          // 预缓存的，直接满不透明
  final t = (now - loadedAt) / fadeDurationMs;
  if (t <= 0) return 0.0;
  if (t >= 1) return 1.0;
  return t;
}
```

逐帧驱动的关键——淡入期间必须一直重绘，否则透明度卡在 0：

```dart
// tile_layer.dart：只要还有瓦片在淡入窗口内，就开着 ticker 重绘
void _onEngineChanged() {
  if (!_fadeActive && _engine.hasFadingTiles()) {
    _fadeActive = true;
    _fadeTicker.start();
  }
}
```

## 五、未来可以怎么优化

交叉淡入已落地（本轮实现）—— 过渡期同时绘制旧层级（from，opacity 1）与新层级（to，opacity = selfFade × t），t 由 `crossFadeProgress` 从 0 升到 1。仍可精进：现在 from 层是按"旧层级 + 当前相机"每帧重新选片，若缩放很快、层级连跳，会反复重建 from 层。可改为缓存上一帧的 draw 命令直接复用，省一次选片，代价是要处理缓存淘汰与相机差异。

缩放途中暂停父请求 —— 现在 geo_map 已用"理想瓦片无条件请求、祖先链只作加载期回退"的思路节流，但没在缩放中显式挂起"无数据父瓦片"的请求。补上能进一步压低请求风暴，代价是缩放中边缘可能更久用占位。

验证手段 —— `flutter test` 在本机被安全策略拦截，纯逻辑要用 `dart test`。淡入是逐帧时间动画，无法在纯逻辑层断言，只能在真机或模拟器肉眼确认。本次改动**未做端到端动眼验证**，仅通过 `dart analyze`。

## 六、小结

- 瓦片异步下载与同步渲染之间，需要"过渡"这座桥。
- 淡入（fade）解决新瓦片"硬弹出"，每瓦片一个时间戳加线性透明度即可。
- 拖动刷新靠"每帧重算理想覆盖"，不是靠专门的结束事件。
- geo_map 已移植自身淡入：时间戳 + `fadeOpacity` + 淡入期逐帧重绘。
- geo_map 已移植交叉淡入：旧层级（from，opacity 1）+ 新层级（to，selfFade × t），t 从 0 升到 1。
- 缩放期父请求挂起仍待做，是下一步。
