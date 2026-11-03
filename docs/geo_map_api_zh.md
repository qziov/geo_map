# geo_map API 参考（中文版）

> 本文件由源码自动提取生成，等价于 dartdoc 在线参考（https://qziov.github.io/geo_map/api/geo_map/），但**只保留定义**：类 / 接口 / 枚举 / 类型定义 / 函数 / 常量及其签名，不含使用示例。

> 各符号下方的说明为源码 `///` 文档的**中文译注**；成员级说明保留原文（简洁且引用参数名，便于对照）。

---

## 库 `package:geo_map`

### 类（Classes）

`AffineGeometry`, `AnchoredPopupLayout`, `CapDraw`, `DebugTilesSource`, `FlatTileLayer`, `GeoAnchoredPopup`, `GeoDiagnostics`, `GeoFeatureRegistry`, `GeoJsonVectorSource`, `GeoMap`, `GeoMapController`, `GeoMapOptions`, `GeoMapPopup`, `GeoMapPopupController`, `GeoMapPopupHost`, `GeoMapScope`, `GeoPopupBinding`, `GeoPopupCard`, `GeoPopupController`, `GeoStyleController`, `GeoTileDefaults`, `GlobeGestureOverlay`, `GlobeImageLayer`, `GlobeLabel`, `GlobePolygonShape`, `GlobePolyline`, `GlobeProjectionDelegate`, `GlobeTileLayer`, `GlobeVectorLayer`, `HttpTileSource`, `LatLngBounds`, `MbtilesTileSource`, `MvtDiagnostics`, `MvtVectorLayer`, `SphericalGeometry`, `SpriteAtlas`, `StyleVectorLayer`, `TileDraw`, `TileEngine`, `TileGeometry`, `TileImage`, `TileLayer`, `TileResolution`

#### `AffineGeometry` （类）

```dart
class AffineGeometry extends TileGeometry
```

Web Mercator（2D）几何：世界像素矩形。


**成员**


##### 构造

- `const AffineGeometry({required this.scheme})`

##### 方法

- `void drawTile(
Canvas canvas,
TileDraw draw, {
required CameraState camera,
required double opacity,
})`
- `void drawCap(
Canvas canvas,
CapDraw cap, {
required CameraState camera,
required double opacity,
})`

##### 字段

- `final TileSchemeKind scheme`
- `static const int worldCopies = 1` — How many world copies are drawn around the camera longitude.


---

#### `AnchoredPopupLayout` （类）

```dart
class AnchoredPopupLayout
```

纯布局结果（`left/top` 为逻辑像素）。


**成员**


##### 构造

- `const AnchoredPopupLayout({
required this.left,
required this.top,
required this.visible,
})`

##### 字段

- `final double left` — 卡片左上角相对视口的偏移。
- `final double top` — 卡片左上角相对视口的偏移。
- `final bool visible` — 是否应显示（锚点出屏/非有限/被遮挡时为 false）。


---

#### `CapDraw` （类）

```dart
class CapDraw
```

极冠绘制指令（仅 Web Mercator）。

一条极冠指令覆盖一个**经度区间**，而非单一列，因此两种情形形状一致：

* 单列宽（`spanLng == grid.tileWidthDeg`）— 一条清晰的楔形，用该列自身瓦片贴图；
* 最宽至 `360°` — 一条被涂抹的条带，用单张图像贴图，用于相机身处极冠内部时。


**成员**


##### 构造

- `const CapDraw({
required this.zoom,
required this.north,
required this.startLng,
required this.spanLng,
required this.sourceKey,
required this.image,
required this.u0,
required this.spanU,
required this.v0,
required this.vSpan,
})`

##### 字段

- `final int zoom` — The data-zoom level the cap belongs to.
- `final bool north` — Northern or southern cap.
- `final double startLng` — West edge of the interval (degrees, unwrapped).
- `final double spanLng` — Width of the interval (degrees).
- `final TileKey sourceKey` — The tile the [image] was decoded from (for eviction protection).
- `final TileImage image`
- `final double u0` — Texture region (image pixels).
- `final double spanU` — Texture extent (image pixels).
- `final double v0` — Texture origin (image pixels).
- `final double vSpan` — Texture extent (image pixels).


---

#### `DebugTilesSource` （类）

```dart
class DebugTilesSource implements GlobeRasterSource
```


**成员**


##### 构造

- `DebugTilesSource.maplibreNumber({this.maxZoom = 22})
: mode = DebugTilesMode.maplibreNumber,
minZoom = 0`
- `DebugTilesSource.labeled({this.maxZoom = 8})
: mode = DebugTilesMode.labeled,
minZoom = 0`

##### 方法

- `Future<TileFetchResult> fetch(int z, int x, int y) async`
- `void dispose()`

##### 取值

- `TileSchemeKind get scheme => TileSchemeKind.webMercator`
- `TileRowOrder get rowOrder => TileRowOrder.xyzTopDown`
- `int get maxConcurrentRequests => GeoEngineTuning.maxParallelRequests`
- `String get attribution =>
mode == DebugTilesMode.maplibreNumber
? '© MapLibre debug tiles'
: 'generated debug tiles'`

##### 字段

- `final DebugTilesMode mode`
- `final int minZoom`
- `final int maxZoom`


---

#### `FlatTileLayer` （类）

```dart
class FlatTileLayer extends StatelessWidget
```


**成员**


##### 构造

- `const FlatTileLayer({
required this.source,
this.engine,
super.key,
})`

##### 方法

- `Widget build(BuildContext context) => TileLayer(
source: source,
engine: engine,
mode: TileLayerMode.mercator,
)`

##### 字段

- `final GlobeRasterSource source`
- `final TileEngine? engine` — The shared engine. When `null` the layer creates one and owns it.


---

#### `GeoAnchoredPopup` （类）

```dart
class GeoAnchoredPopup extends StatelessWidget
```

跟随地图的浮层：每次相机变化重新投影 [anchor] 并重定位 [child]。

纯展示容器——宿主自行决定 [anchor]（如点击命中的地理点）与 [child]（业务卡片）。


**成员**


##### 构造

- `const GeoAnchoredPopup({
super.key,
required this.controller,
required this.anchor,
required this.child,
required this.keepOut,
required this.cardSize,
this.anchorSide = PopupAnchor.bottom,
})`

##### 方法

- `Widget build(BuildContext context)`

##### 字段

- `final GeoMapController controller`
- `final LatLng anchor`
- `final Widget child`
- `final EdgeInsets keepOut`
- `final Size cardSize` — 用于夹取的卡片逻辑尺寸（实际卡片可更小）。
- `final PopupAnchor anchorSide` — 卡片贴锚点的哪一侧（九宫格）。默认 [PopupAnchor.bottom]（卡片在锚点上方）。


---

#### `GeoDiagnostics` （类）

```dart
class GeoDiagnostics
```


**成员**


##### 构造

- `GeoDiagnostics._()`

##### 方法

- `static void traceLine(String message)`
- `static void frame(String message)`
- `static void missDetail(String message)`

##### 取值

- `static bool get traceOn => enabled && kDebugMode && trace`

##### 字段

- `static bool enabled = true` — 总开关（debug 构建默认 true；release 恒关）。
- `static int frameIntervalMs = 500`
- `static int missDetailIntervalMs = 2000`
- `static bool trace = false` — 逐瓦片 trace（key + 屏幕位置）。定位选片洞/覆盖缺口时打开；
每帧限量 + 500ms 限速，避免刷屏。
- `static int tracePerFrame = 40`


---

#### `GeoFeatureRegistry` （类）

```dart
class GeoFeatureRegistry
```

可查询要素的注册表。


**成员**


##### 方法

- `void setSource(
String sourceId,
List<GeoJsonFeature> features, {
bool visible = true,
String? layerId,
double? pointRadiusPx,
GeoPopupBinding? popup,
})` — Register (or replace) the features of one source.

[visible] hides the whole source without removing it — a layer that is
switched off must not be pickable. [pointRadiusPx] overrides the query's
default pick radius for this source, and [layerId] records which layer
it came from.

[popup] optionally binds a popup card to this source (the SDK equivalent of
MapLibre `map.on('click', layerId, handler)`); see [GeoPopupBinding]. A
source without a popup is still pickable — it just won't open a card via
[GeoPopupController] (the host may drive a SnackBar or selection instead).
- `void removeSource(String sourceId) => _sources.remove(sourceId)` — Drop a source. Its features are no longer pickable.
- `void clear() => _sources.clear()` — Drop every source.
- `bool containsSource(String sourceId) => _sources.containsKey(sourceId)`
- `GeoPopupBinding? popupOf(String sourceId) => _sources[sourceId]?.popup` — The popup binding registered for [sourceId], or `null` if that source has
no popup card (e.g. it only drives a SnackBar or a selection state).
- `List<GeoQueryHit> queryFeatures(
LatLng tap, {
required GeoMapController controller,
double? pointRadiusPx,
Set<String>? sourceIds,
Set<GeoGeometryKind>? geometries,
int? limit,
})` — The features under [tap].

Point features are matched in **screen space** (within [pointRadiusPx]);
area features in **geographic space** (point-in-polygon). The two are
dispatched per feature by its geometry type — see
`planFeatureQuery` in `geo_map_core` for the full contract.

[sourceIds] and [geometries] narrow the query; [limit] truncates the
result after sorting.

##### 取值

- `Iterable<String> get sourceIds => _sources.keys` — The registered source ids, in registration order.
- `int get length => _sources.length`


---

#### `GeoJsonVectorSource` （类）

```dart
class GeoJsonVectorSource
```

为调试叠加层加载矢量数据。

此处的“矢量底图”指：通过 HTTP 拉取一个 GeoJSON `FeatureCollection`，把其中的线稿喂给 [GlobeVectorLayer]。矢量**瓦片**（MVT）需要完整的样式 / protobuf 管线；GeoJSON 已足以肉眼验证投影是否正确。


**成员**


##### 构造

- `const GeoJsonVectorSource(this.url)`

##### 方法

- `Future<List<GlobePolyline>> load({
Color color = const Color(0xCCFFFFFF),
double strokeWidth = 1.0,
}) async`
- `static Future<List<GlobePolyline>> loadAsset(
String assetPath, {
Color color = const Color(0xCCFFFFFF),
double strokeWidth = 1.0,
}) async` — Loads a GeoJSON file bundled as an asset (works offline).
- `static List<GlobePolyline> parse(
String body, {
Color color = const Color(0xCCFFFFFF),
double strokeWidth = 1.0,
})` — Parses `LineString`, `MultiLineString` and `Polygon` (outer rings only).

##### 字段

- `final String url`


---

#### `GeoMap` （类）

```dart
class GeoMap extends StatefulWidget
```

`GeoMap`——宿主控件。子控件堆叠在栅格图层之上。


**成员**


##### 构造

- `const GeoMap({
required this.options,
required this.source,
this.controller,
this.children = const [],
this.onTap,
super.key,
})`

##### 方法

- `final void Function(LatLng latLng)? onTap`
- `State<GeoMap> createState() => _GeoMapState()`

##### 字段

- `final GeoMapOptions options`
- `final GlobeRasterSource source`
- `final GeoMapController? controller`
- `final List<Widget> children`


---

#### `GeoMapController` （类）

```dart
class GeoMapController extends ChangeNotifier
```


**成员**


##### 构造

- `GeoMapController({
bool useGlobe = true,
GlobeProjectionDelegate? projectionDelegate,
LatLng initialCenter = const LatLng(30, 105),
double initialZoom = 4.2,
this.minZoom = 1,
this.maxZoom = 8,
})  : _isGlobe = useGlobe,
delegate = projectionDelegate ??
(useGlobe
? GlobeProjectionDelegate()
: FlatProjectionDelegate())`

##### 方法

- `void applyConstraints({required double minZoom, required double maxZoom})` — 外部宿主同步缩放约束（防 options 与 controller 脱节）。
- `void setMode(bool globe)` — 2D/3D 切换：替换投影 delegate 并重建 vendored camera（center/zoom 连续）。
- `void move(LatLng center, double zoom)` — Move the camera; syncs the projection delegate and notifies listeners.
- `void panBy(Offset pixelDelta) =>
move(delegate.panBy(pixelDelta), _zoom)` — Content follows the finger: delegate handles the 1/cos(lat) compensation.
- `void zoomBy(double factor, Offset anchor)` — Pinch: multiply zoom by [factor], keeping [anchor] (screen px) fixed.
- `void zoomAround(Offset focal, double newZoom)` — Lab-verified anchor zoom (`_zoomAround` + `_anchorCenter`): first-order
correction for the radius change, then `panCenter` with the view direction.
- `void recenter(LatLng target) => move(target, _zoom)`
- `void setViewport(Size size)` — Viewport size changed (layout pass).

##### 取值

- `bool get isGlobe => _isGlobe`
- `MapCamera get camera => _camera`
- `LatLng get center => _center`
- `double get zoom => _zoom`
- `Size get viewport => Size(_camera.size.x, _camera.size.y)`

##### 字段

- `MapProjectionDelegate delegate`
- `double minZoom`
- `double maxZoom`


---

#### `GeoMapOptions` （类）

```dart
class GeoMapOptions
```


**成员**


##### 构造

- `const GeoMapOptions({
this.initialCenter = const LatLng(30, 105),
this.initialZoom = 4.2,
this.minZoom = 1,
this.maxZoom = 8,
this.useGlobe = true,
this.background = const Color(0xFF000000),
})`

##### 字段

- `final LatLng initialCenter`
- `final double initialZoom`
- `final double minZoom`
- `final double maxZoom`
- `final bool useGlobe` — true = 正交球面（3D）；false = Web Mercator 平面（2D）。
切换时 center/zoom 连续（经 delegate 的 anchorCenter 各自实现）。
- `final Color background`


---

#### `GeoMapPopup` （类）

```dart
class GeoMapPopup extends StatelessWidget
```

把 [GeoMapPopupController] 的显隐状态接到 [GeoAnchoredPopup] 上。

自监听 [popup]：调用 `popup.show/hide` 即自动重绘，宿主无需在父级 `watch`。业务内容通过 [builder]（入参含锚点）注入——这就是留给宿主的“接口”：在此返回自己的卡片（含关闭按钮，关闭按钮调用 [GeoMapPopupController.hide]）。


**成员**


##### 构造

- `const GeoMapPopup({
super.key,
required this.controller,
required this.popup,
required this.builder,
required this.keepOut,
required this.cardSize,
this.anchorSide = PopupAnchor.bottom,
})`

##### 方法

- `final Widget Function(BuildContext context, LatLng anchor) builder` — 业务内容构造器：给定锚点，返回卡片。
- `Widget build(BuildContext context)`

##### 字段

- `final GeoMapController controller` — 地图相机（用于每帧重投影锚点）。
- `final GeoMapPopupController popup` — 浮层显隐状态。
- `final EdgeInsets keepOut` — 留白区（顶栏 / 侧栏 / 底栏尺寸），浮层不会盖进去。
- `final Size cardSize` — 用于夹取的卡片逻辑尺寸（实际卡片可更小）。
- `final PopupAnchor anchorSide` — 卡片贴锚点的哪一侧（九宫格）。默认 [PopupAnchor.bottom]（卡片在锚点上方）。


---

#### `GeoMapPopupController` （类）

```dart
class GeoMapPopupController extends ChangeNotifier
```

跟随地图的浮层显隐状态（对标 MapLibre `Popup` 的 open/close）。

只持有**锚点**：内容由宿主通过 [GeoMapPopup.builder] 注入。状态因此与业务完全解耦，SIGMET / 机场 / POI 等任意图层共用同一套“显示—关闭”逻辑。


**成员**


##### 方法

- `void dispose()`
- `void show(LatLng anchor)` — 在 [anchor] 处打开（覆盖式：重复 open 同一锚点幂等）。
- `void hide()` — 关闭浮层（锚点置空）。
- `void toggle(LatLng anchor) => isOpen ? hide() : show(anchor)` — 点同一锚点切换开/关（MapLibre `togglePopup` 语义）。

##### 取值

- `bool get isDisposed => _disposed` — 是否已 dispose（语义同 `GeoPopupController.isDisposed`：Riverpod 的
`invalidateSelf()` —— hot reload 改到 provider 源码时的常规路径 —— 会
先 dispose 再重建，这段窗口内的 `show/hide` 必须安静丢弃）。
- `LatLng? get anchor => _anchor` — 当前锚点；`null` 表示浮层隐藏。
- `bool get isOpen => _anchor != null` — 是否处于打开状态。


---

#### `GeoMapPopupHost` （类）

```dart
class GeoMapPopupHost extends StatelessWidget
```

弹窗控制层的渲染宿主。

在 `GeoMap` 之外、作为外层 `Stack` 的**直接子级**恰好挂载一个（与 [GeoMapPopup]同一约束：必须是外层 `Stack` 的直接子级，绝不可位于 `GeoMap.children` 之内）。它从 [popup] 读取已打开的绑定并渲染对应卡片，每次相机移动时由底层 [GeoMapPopup] 重新定位。


**成员**


##### 构造

- `const GeoMapPopupHost({
super.key,
required this.controller,
required this.popup,
required this.keepOut,
})`

##### 方法

- `Widget build(BuildContext context)`

##### 字段

- `final GeoMapController controller` — Map camera (re-projects the anchor each frame).
- `final GeoPopupController popup` — The popup control layer that decides what to show.
- `final EdgeInsets keepOut` — Insets the card never covers (top bar / side bar / bottom bar).


---

#### `GeoMapScope` （类）

```dart
class GeoMapScope extends StatelessWidget
```

供子控件只读访问相机的入口：`GeoMapScope.of(context).camera`。


**成员**


##### 构造

- `const GeoMapScope({required this.controller, required this.child, super.key})`

##### 方法

- `Widget build(BuildContext context) => MapInheritedModel(
camera: controller.camera,
child: child,
)`

##### 字段

- `final GeoMapController controller`
- `final Widget child`


---

#### `GeoPopupBinding` （类）

```dart
class GeoPopupBinding
```

把一个图层（其在 [GeoFeatureRegistry] 中的 `sourceId`）与点击该图层时弹出的卡片绑定起来。

这是 MapLibre `map.on('click', layerId, handler)` 的 SDK 等价物：在我们的模型里“图层”就是一个 `sourceId`，把弹窗绑定到它就是业务图层声明“我被命中时渲染这张卡片”。命中测试、锚点投影、定位与关闭全部由 [GeoPopupController] 处理——业务侧只需提供 [builder]（卡片）及少量元数据。


**成员**


##### 构造

- `const GeoPopupBinding({
this.priority = 0,
required this.cardSize,
this.anchor = PopupAnchor.bottom,
this.anchorOf,
required this.builder,
})`

##### 方法

- `final LatLng? Function(GeoQueryHit hit)? anchorOf` — Override the default anchor point. The default is the tap point (MapLibre
`setLngLat(e.lngLat)` semantics); pass this to pin the bubble to the
feature geometry instead (e.g. an airport icon's own coordinate).
- `final Widget Function(BuildContext context, GeoQueryHit hit) builder` — The business card builder, invoked by the render host after a hit. Receive
the [GeoQueryHit] to map its `feature.id` back to your domain object.

##### 字段

- `final int priority` — Arbitration priority when several layers are hit at once (e.g. a SIGMET
polygon overlapping an airport). Higher wins; ties go to the first hit in
the query result (already sorted by screen distance within a source).
- `final Size cardSize` — The card's logical maximum size, used by the layout to clamp inside
[GeoMapPopupHost.keepOut]. Pass the card's real maximum width/height.
- `final PopupAnchor anchor` — Which side of the card meets the anchor (nine-grid).


---

#### `GeoPopupCard` （类）

```dart
class GeoPopupCard extends StatelessWidget
```

统一的弹窗卡片外壳。

结构：
- 最外层 [GestureDetector]（`behavior: opaque`）吞掉卡片内的空白点击，避免漏给下面的地图（等价于 MapLibre Popup 作为独立 DOM 覆盖层的事件隔离）。
- [header] 右侧可带一个 SDK 关闭按钮（[onClose] 非空时渲染），命中区 ≥32px。


**成员**


##### 构造

- `const GeoPopupCard({
super.key,
required this.child,
this.header,
this.onClose,
this.width = 280,
this.padding = const EdgeInsets.all(12),
this.decoration,
})`

##### 方法

- `Widget build(BuildContext context)`

##### 字段

- `final Widget child` — 卡片内容。
- `final Widget? header` — 标题区（业务排版）。为 null 时不渲染标题行。
- `final VoidCallback? onClose` — 关闭回调；非空时在标题行右侧渲染关闭按钮。
- `final double width` — 卡片宽度（逻辑像素）。
- `final EdgeInsets padding` — 内容内边距。
- `final BoxDecoration? decoration` — 卡片背景/边框/阴影；为 null 时使用主题色的默认外观。


---

#### `GeoPopupController` （类）

```dart
class GeoPopupController extends ChangeNotifier
```

[GeoFeatureRegistry] 与共享的 [GeoMapPopupController] 之间的粘合层。

使用流程见库级文档注释。宿主应用持有一个实例（通常通过把底层弹窗控制器接入的 Riverpod provider）。


**成员**


##### 构造

- `GeoPopupController(this.geoPopup)` — [geoPopup] is the shared show/hide/anchor state, owned by the host. The
feature registry is passed to [handleTap] per tap so the controller never
holds a stale snapshot.

##### 方法

- `void dispose()`
- `void registerPopup(String sourceId, GeoPopupBinding binding)` — Bind a popup to [sourceId] imperatively. Call from a layer's setup and pair
it with [unregisterPopup] on teardown so stale bindings never fire.
- `void unregisterPopup(String sourceId)` — Drop an imperative binding. If it is the one currently shown, the popup
closes.
- `Widget? Function(BuildContext context, LatLng anchor)? get activeBuilder =>
_active == null
? null
: (context, anchor) => _active!.binding.builder(context, _active!.hit)` — The card builder for the open popup, or `null` when nothing is open. The
render host calls this with the projected anchor.
- `List<GeoQueryHit> handleTap(
LatLng tap, {
required GeoMapController controller,
required GeoFeatureRegistry registry,
double? pointRadiusPx,
List<GeoQueryHit>? hits,
})` — The single entry point for a map tap.

Queries [registry], filters to sources that registered a popup, and opens
the highest-priority one. No hit, or a hit on a source without a popup
(e.g. an airport that only fires a SnackBar), closes any open popup.

Pass [hits] when the host already ran the query (it usually needs the same
results for its own business reactions) — this avoids querying twice.

Disposed controller (see [isDisposed]) → no-op: the popup it owned no longer
exists, and the freshly created replacement will handle the next tap.

Returns the query result so the host can reuse it for its own reactions
(SnackBar / selection) without querying a second time.
- `void close()` — Close the popup (anchor cleared, active binding dropped).

##### 取值

- `bool get isDisposed => _disposed` — Whether [dispose] has run.

宿主可能在这个窗口里仍然调到本实例：Riverpod 的 `invalidateSelf()`
（hot reload 改到 provider 源码时的常规路径，或业务主动 `ref.invalidate`）
会**先 `runOnDispose()` 再重建**，也就是说 notify 监听方的 dispose 先发生、
新实例下一帧才出现。旧实例这段"僵尸期"内收到的点击必须安静地丢弃，
而不是让 `notifyListeners()` 抛 assert 打断整条手势链路。
- `Size get activeCardSize => _active?.binding.cardSize ?? const Size(280, 240)` — The open card's maximum size, for keepOut clamping.
- `PopupAnchor get activeAnchor => _active?.binding.anchor ?? PopupAnchor.bottom` — The open card's anchor side (nine-grid).

##### 字段

- `final GeoMapPopupController geoPopup`


---

#### `GeoStyleController` （类）

```dart
class GeoStyleController extends ChangeNotifier
```


**成员**


##### 构造

- `GeoStyleController(StyleSpec spec) : _document = StyleDocument.fromSpec(spec)`
- `GeoStyleController.document(StyleDocument document)
: _document = document`

##### 方法

- `void addSource(String id, Map<String, Object?> source) =>
_set(_document.addSource(id, source))`
- `void removeSource(String id) => _set(_document.removeSource(id))`
- `void addLayer(StyleLayer layer, {String? before}) =>
_set(_document.addLayer(layer, before: before))`
- `void removeLayer(String id) => _set(_document.removeLayer(id))`
- `void moveLayer(String id, {String? before}) =>
_set(_document.moveLayer(id, before: before))`
- `void setPaintProperty(String id, String name, Object? value) =>
_set(_document.setPaintProperty(id, name, value))`
- `void setLayoutProperty(String id, String name, Object? value) =>
_set(_document.setLayoutProperty(id, name, value))`
- `void setFilter(String id, Object? filter) =>
_set(_document.setFilter(id, filter))`
- `void setLayerZoomRange(String id, num min, num max) =>
_set(_document.setLayerZoomRange(id, min, max))`
- `void setVisibility(String id, String visibility) =>
_set(_document.setVisibility(id, visibility))`

##### 取值

- `StyleDocument get document => _document`
- `int get revision => _revision` — Monotonic revision; changes only when the document actually changed.


---

#### `GeoTileDefaults` （类）

```dart
abstract class GeoTileDefaults
```


**成员**


##### 字段

- `static const int maxZoom = 18`


---

#### `GlobeGestureOverlay` （类）

```dart
class GlobeGestureOverlay extends StatefulWidget
```


**成员**


##### 构造

- `const GlobeGestureOverlay({
required this.controller,
this.onTap,
this.minZoom,
this.maxZoom,
super.key,
})`

##### 方法

- `final void Function(LatLng latLng)? onTap`
- `State<GlobeGestureOverlay> createState() => _GlobeGestureOverlayState()`

##### 字段

- `final GeoMapController controller`
- `final double? minZoom` — Zoom clamps for wheel/double-tap; null = controller's own range.
- `final double? maxZoom`


---

#### `GlobeImageLayer` （类）

```dart
class GlobeImageLayer extends StatefulWidget
```

绘制在地球表面的图像叠加层（气象雷达、卫星条带等）。

flutter_map 的 `OverlayImageLayer` 把图像映射到四角构成的四边形上，在球面上看起来像一张平铺的纸：没有曲率、没有地平线裁剪。本图层把 bounds细分为网格并对每个顶点做投影，于是叠加层贴合地表并会在其背后消失。


**成员**


##### 构造

- `const GlobeImageLayer({
super.key,
required this.image,
required this.bounds,
this.opacity = 0.85,
this.subdivisions = 24,
})`

##### 方法

- `State<GlobeImageLayer> createState() => _GlobeImageLayerState()`

##### 字段

- `final ImageProvider image`
- `final LatLngBounds bounds`
- `final double opacity`
- `final int subdivisions`


---

#### `GlobeLabel` （类）

```dart
class GlobeLabel
```

锚定在地理坐标点上的文本标签。


**成员**


##### 构造

- `const GlobeLabel({
required this.point,
required this.text,
this.style = const TextStyle(color: Colors.white, fontSize: 11),
this.offset = const Offset(0, -16),
this.background = const Color(0xCC0F2440),
})`

##### 字段

- `final LatLng point`
- `final String text`
- `final TextStyle style`
- `final Offset offset`
- `final Color background`


---

#### `GlobePolygonShape` （类）

```dart
class GlobePolygonShape
```

球面上的填充多边形（填充 + 描边），用于地球模式以取代 flutter_map 的`PolygonLayer`——后者的绘制器无法裁剪到地平线。


**成员**


##### 构造

- `const GlobePolygonShape({
required this.points,
required this.fill,
required this.stroke,
this.strokeWidth = 2,
this.label,
this.labelStyle = const TextStyle(color: Colors.white, fontSize: 12),
})`

##### 字段

- `final List<LatLng> points`
- `final Color fill`
- `final Color stroke`
- `final double strokeWidth`
- `final String? label` — Optional text drawn at the ring's centroid (3D counterpart of
`Polygon.label`, which only the native painter handles).
- `final TextStyle labelStyle`


---

#### `GlobePolyline` （类）

```dart
class GlobePolyline
```

绘制在屏幕空间中的球面上的折线。


**成员**


##### 构造

- `const GlobePolyline({
required this.points,
required this.color,
this.strokeWidth = 1.2,
this.closed = false,
this.dashPattern,
})`

##### 字段

- `final List<LatLng> points`
- `final Color color`
- `final double strokeWidth`
- `final bool closed`
- `final List<double>? dashPattern` — 屏幕像素的虚线样式：`[2, 2]` 表示实 2px / 空 2px 交替。null 为实线。


---

#### `GlobeProjectionDelegate` （类）

```dart
class GlobeProjectionDelegate implements MapProjectionDelegate
```

通过（仅 fork 版）`MapProjectionDelegate` 钩子接入 flutter_map 的正交地球投影。

屏幕空间取代世界空间：
* `project()` 返回**屏幕像素**（或远侧点的远端坐标，交给 flutter_map 自带的剔除移除）；
* `pixelOrigin` 被 fork 版 `MapCamera` 强制为零；
* `pixelBounds` 即视口。


**成员**


##### 构造

- `GlobeProjectionDelegate({this.tileSize = 256})`

##### 方法

- `void updateCamera(LatLng center, double zoom, Size size)`
- `Offset project(LatLng point)`
- `Offset projectForVector(LatLng point)`
- `bool isVisible(LatLng point) => _toView(point).$3 > -0.03`
- `LatLng? unproject(Offset local)`
- `LatLng panBy(Offset pixelDelta) => panCenter(_center, pixelDelta, _zoom)`
- `LatLng anchorCenter(
LatLng center, LatLng anchor, double fromZoom, double toZoom)`
- `LatLng panCenter(LatLng from, Offset delta, double zoom)`

##### 取值

- `LatLng get center => _center`
- `double get zoom => _zoom`
- `double get radius => tileSize * math.pow(2, _zoom) / (2 * math.pi)` — Disc radius in logical pixels — a function of zoom only.

Multiplying by `1/cos(lat)` (mercator's trick) would make the globe grow
as you drag towards the poles; on a sphere the apparent size is fixed.

##### 字段

- `final double tileSize`
- `static const double maxCameraLatitude = 89.999` — The camera may look straight at a pole. 85.0511° is a **tile data** limit
(Web Mercator), not a projection limit — clamping the camera there makes
the globe feel truncated, so only stop just short of the degenerate pole.


---

#### `GlobeTileLayer` （类）

```dart
class GlobeTileLayer extends StatelessWidget
```


**成员**


##### 构造

- `const GlobeTileLayer({
required this.source,
this.engine,
super.key,
})`

##### 方法

- `Widget build(BuildContext context) => TileLayer(
source: source,
engine: engine,
mode: TileLayerMode.globe,
)`

##### 字段

- `final GlobeRasterSource source`
- `final TileEngine? engine` — The shared engine. When `null` the layer creates one and owns it.


---

#### `GlobeVectorLayer` （类）

```dart
class GlobeVectorLayer extends StatelessWidget
```

地球的矢量调试图层。

刻意**不**使用 flutter_map 的 `PolylineLayer`/`PolygonLayer`：那些图层在`camera.project` 之后用 `crs.transform` 再次投影，一旦启用了投影代理就错了。此处每个顶点都经过 `camera.project`（即代理）与大圆加密，因此本图层也充当那些图层日后所需实现的参考。


**成员**


##### 构造

- `const GlobeVectorLayer({
super.key,
required this.lines,
this.polygons = const [],
this.dots = const [],
this.dotColors,
this.labels = const [],
this.dotRadius = 1.6,
this.dotColor = const Color(0x803DDC97),
this.opacity = 1,
})`

##### 方法

- `Widget build(BuildContext context)`

##### 字段

- `final List<GlobePolyline> lines`
- `final List<GlobePolygonShape> polygons`
- `final List<LatLng> dots` — Points (e.g. graticule intersections) drawn in the same projection as the
lines — avoids the mismatch you get from mixing in a separate layer.
- `final List<Color>? dotColors` — Per-dot override colors. Length must match [dots] or be null (all use
[dotColor]). Entries can be [dotColor] for individual dots to fall back.
- `final List<GlobeLabel> labels`
- `final double dotRadius`
- `final Color dotColor`
- `final double opacity`


---

#### `HttpTileSource` （类）

```dart
class HttpTileSource implements GlobeRasterSource
```

基于 HTTP 的 WMTS / XYZ。

URL 构建（模板、TMS 翻转、quadkey、bbox、子域、ratio）委托给 core 中的纯 [TileUrlBuilder]，因此在那里有单元测试。本类只负责 404 与网络故障的区分；套接字本身是 `platform/http_get.dart` 中的共享传输，它有浏览器实现，故本文件可编译到 web。

`urlTemplate` 支持 `{z}`、`{x}`、`{y}`、`{TileMatrix}`、`{TileRow}`、`{TileCol}`、`{prefix}`、`{ratio}`、`{quadkey}`、`{bbox}`、`{bbox-epsg-3857}`。RESTful WMTS 与纯 XYZ 模板均可用。


**成员**


##### 构造

- `HttpTileSource({
required this.urlTemplate,
required this.scheme,
required this.maxZoom,
this.minZoom = 0,
this.attribution = '',
this.headers = const {},
this.rowOrder = TileRowOrder.xyzTopDown,
this.userAgent = 'geo_map/0.1',
this.subdomains = const [],
this.tileRatio = 1,
})`
- `factory HttpTileSource.gibsTrueColor({DateTime? date})` — NASA GIBS daily true-colour mosaic (no API key, EPSG:4326 WMTS).

Good demo for the 2:1 matrix set: coastlines must line up with the
bundled MBTiles basemap when both are visible.
- `factory HttpTileSource.osm() => HttpTileSource(
urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
scheme: TileSchemeKind.webMercator,
minZoom: 0,
maxZoom: 18,
attribution: '© OpenStreetMap contributors',
)` — Plain XYZ raster (OSM). Only for smoke tests — respect the tile policy.

##### 方法

- `String urlFor(int z, int x, int y) => _urls.urlFor(z, x, y)`
- `Future<TileFetchResult> fetch(int z, int x, int y) async`
- `static Uint8List? decodeBase64(String value) => base64Decode(value)`
- `void dispose()`

##### 取值

- `int get maxConcurrentRequests => GeoEngineTuning.maxParallelRequests`

##### 字段

- `final String urlTemplate`
- `final TileSchemeKind scheme`
- `final TileRowOrder rowOrder`
- `final int minZoom`
- `final int maxZoom`
- `final String attribution`
- `final Map<String, String> headers`
- `final String userAgent`
- `final List<String> subdomains` — Subdomains spread by `{prefix}` (empty disables it).
- `final int tileRatio` — Pixel ratio rendered by `{ratio}` (`> 1` → `@Nx`).
- `String? lastError` — Last transport error, surfaced in the debug HUD (DNS failure, timeout…).
- `int? lastStatusCode` — Last HTTP status code that was **not** 200 (`null` after a success).


---

#### `LatLngBounds` （类）

```dart
class LatLngBounds
```

由西北角与东南角约束而成的矩形包围盒数据结构。


**成员**


##### 构造

- `factory LatLngBounds(LatLng corner1, LatLng corner2)` — Create new [LatLngBounds] by providing two corners. Both corners have to
be on opposite sites but it doesn't matter which opposite corners or in
what order the corners are provided.

If you want to create [LatLngBounds] with raw values, use the
[LatLngBounds.unsafe] constructor instead.
- `LatLngBounds.unsafe({
required this.north,
required this.south,
required this.east,
required this.west,
})  : assert(north <= maxLatitude,
"The north latitude can't be bigger than $maxLatitude: $north"),
assert(north >= minLatitude,
"The north latitude can't be smaller than $minLatitude: $north"),
assert(south <= maxLatitude,
"The south latitude can't be bigger than $maxLatitude: $south"),
assert(south >= minLatitude,
"The south latitude can't be smaller than $minLatitude: $south"),
assert(east <= maxLongitude,
"The east longitude can't be bigger than $maxLongitude: $east"),
assert(east >= minLongitude,
"The east longitude can't be smaller than $minLongitude: $east"),
assert(west <= maxLongitude,
"The west longitude can't be bigger than $maxLongitude: $west"),
assert(west >= minLongitude,
"The west longitude can't be smaller than $minLongitude: $west"),
assert(
north >= south,
"The north latitude ($north) can't be smaller than the "
'south latitude ($south)',
),
assert(
east >= west,
"The west longitude ($west) can't be smaller than the "
'east longitude ($east)',
)` — Create a [LatLngBounds] instance from raw edge values.

Potentially throws assertion errors if the coordinates exceed their max
or min values or if coordinates are meant to be smaller / bigger
but aren't.
- `factory LatLngBounds.fromPoints(List<LatLng> points)` — Create a new [LatLngBounds] from a list of [LatLng] points. This
calculates the bounding box of the provided points.

##### 方法

- `void extend(LatLng latLng)` — Expands bounding box by [latLng] coordinate point. This method mutates
the bounds object on which it is called.
- `void extendBounds(LatLngBounds bounds)` — Expands bounding box by other [bounds] object. If provided [bounds] object
is smaller than current one, it is not shrunk. This method mutates
the bounds object on which it is called.
- `bool contains(LatLng point) =>
point.longitude >= west &&
point.longitude <= east &&
point.latitude >= south &&
point.latitude <= north` — Checks whether [point] is inside bounds
- `bool containsBounds(LatLngBounds other) =>
other.south >= south &&
other.north <= north &&
other.west >= west &&
other.east <= east` — Checks whether the [other] bounding box is contained inside bounds.
- `bool isOverlapping(LatLngBounds other) => !(south > other.north ||
north < other.south ||
east < other.west ||
west > other.east)` — Checks whether at least one edge of the [other] bounding box  is
overlapping with this bounding box.

Bounding boxes that touch each other but don't overlap are counted as
not overlapping.
- `bool operator ==(Object other) =>
identical(this, other) ||
(other is LatLngBounds &&
other.north == north &&
other.south == south &&
other.east == east &&
other.west == west)`
- `String toString() =>
'LatLngBounds(north: $north, south: $south, east: $east, west: $west)'`

##### 取值

- `LatLng get southWest => LatLng(south, west)` — Obtain coordinates of southwest corner of the bounds.

Instead of using latitude or longitude of the corner, use [south] or
[west] instead!
- `LatLng get northEast => LatLng(north, east)` — Obtain coordinates of northeast corner of the bounds.

Instead of using latitude or longitude of the corner, use [north] or
[east] instead!
- `LatLng get northWest => LatLng(north, west)` — Obtain coordinates of northwest corner of the bounds.

Instead of using latitude or longitude of the corner, use [north] or
[west] instead!
- `LatLng get southEast => LatLng(south, east)` — Obtain coordinates of southeast corner of the bounds.

Instead of using latitude or longitude of the corner, use [south] or
[east] instead!
- `LatLng get center` — Obtain coordinates of the bounds center
- `LatLng get simpleCenter => LatLng((south + north) / 2, (east + west) / 2)` — Obtain simple coordinates of the bounds center
- `int get hashCode => Object.hash(south, north, east, west)`

##### 字段

- `static const double minLatitude = -90` — minimum latitude value, south
- `static const double maxLatitude = 90` — maximum latitude value, north
- `static const double minLongitude = -180` — minimum longitude value, west
- `static const double maxLongitude = 180` — maximum longitude value, east
- `double north` — The latitude north edge of the bounds
- `double south` — The latitude south edge of the bounds
- `double east` — The longitude east edge of the bounds
- `double west` — The longitude west edge of the bounds


---

#### `MbtilesTileSource` （类）

```dart
class MbtilesTileSource implements GlobeRasterSource
```


**成员**


##### 构造

- `MbtilesTileSource._(this.id, this._db, this.minZoom, this.maxZoom)`

##### 方法

- `static Future<MbtilesTileSource> open({
required String id,
required String assetPath,
}) async` — Open (and lazily copy) an MBTiles asset.
- `Future<TileFetchResult> fetch(int z, int x, int y) async`
- `void dispose() => _db.dispose()`

##### 取值

- `TileSchemeKind get scheme => TileSchemeKind.webMercator`
- `TileRowOrder get rowOrder => TileRowOrder.tmsBottomUp`
- `int get maxConcurrentRequests => GeoEngineTuning.sqliteParallelRequests`
- `String get attribution => 'MBTiles: $id'`

##### 字段

- `final String id`
- `final int minZoom`
- `final int maxZoom`


---

#### `MvtDiagnostics` （类）

```dart
class MvtDiagnostics
```

图层当前正在做什么，供调试 HUD 使用。

`dataZoom` 是瓦片被请求的层级（0..source.maxZoom），即 `round(camera zoom)`——并非 HUD 通常显示的连续相机缩放。`readyCount` / `tileCount` 说明已解码的可见瓦片数量，`lastStatusCode` 在源为 HTTP 时透出传输状态。

`firstFailed` 标出 `failedCount` 背后那块瓦片（`z/x/y · status`）。没有它，“一块瓦片失败”的报告无法诊断——关键在于它告诉你那是边界瓦片、越界坐标还是限流。


**成员**


##### 构造

- `const MvtDiagnostics({
required this.dataZoom,
required this.tileCount,
required this.readyCount,
required this.failedCount,
this.lastStatusCode,
this.firstFailed,
})`

##### 方法

- `bool operator ==(Object other) =>
other is MvtDiagnostics &&
other.dataZoom == dataZoom &&
other.tileCount == tileCount &&
other.readyCount == readyCount &&
other.failedCount == failedCount &&
other.lastStatusCode == lastStatusCode &&
other.firstFailed == firstFailed`
- `String toString() => 'MvtDiagnostics(z$dataZoom, $readyCount/$tileCount, '
'failed $failedCount${firstFailed == null ? '' : ' ($firstFailed)'}, '
'http $lastStatusCode)';`

##### 取值

- `int get hashCode => Object.hash(dataZoom, tileCount, readyCount, failedCount,
lastStatusCode, firstFailed)`

##### 字段

- `final int dataZoom`
- `final int tileCount`
- `final int readyCount`
- `final int failedCount`
- `final int? lastStatusCode`
- `final String? firstFailed`


---

#### `MvtVectorLayer` （类）

```dart
class MvtVectorLayer extends StatefulWidget
```

通过 [StyleSpec] 渲染的矢量瓦片。

传输以 [GeoTileSource] 注入，因此同一图层可配合 HTTP、MBTiles 或测试桩工作。


**成员**


##### 构造

- `const MvtVectorLayer({
super.key,
required this.source,
this.style,
this.controller,
this.opacity = 1.0,
this.maxCachedTiles = 160,
this.renderWorldCopies = true,
this.sprite,
this.onDiagnostics,
}) : assert(style != null || controller != null,
'provide either style or controller')`

##### 方法

- `State<MvtVectorLayer> createState() => _MvtVectorLayerState()`

##### 字段

- `final GeoTileSource source`
- `final StyleSpec? style` — A static style. Ignored when [controller] is provided.
- `final GeoStyleController? controller` — A runtime style controller (M1.4); the layer rebuilds on notify.
- `final double opacity`
- `final int maxCachedTiles`
- `final bool renderWorldCopies` — Draw the world once per visible copy when panning past ±180°.

Defaults to `true` (MapLibre's `renderWorldCopies`). Set `false` for a
fixed single-world view: off-screen data is clipped instead of repeated.
- `final SpriteAtlas? sprite` — Icons for `icon-image`; without one the labels are still drawn.
- `final ValueChanged<MvtDiagnostics>? onDiagnostics` — Called after a frame when the diagnostics change (for a debug HUD).


---

#### `SphericalGeometry` （类）

```dart
class SphericalGeometry extends TileGeometry
```

正交（3D 地球）几何。


**成员**


##### 构造

- `const SphericalGeometry({
required this.projector,
required this.scheme,
this.meshBuilder,
})`

##### 方法

- `void drawTile(
Canvas canvas,
TileDraw draw, {
required CameraState camera,
required double opacity,
})`
- `void drawCap(
Canvas canvas,
CapDraw cap, {
required CameraState camera,
required double opacity,
})`

##### 字段

- `final GeoProjector projector`
- `final TileSchemeKind scheme`
- `final TileMeshBuilder? meshBuilder` — Shared mesh cache — the unit meshes are projection independent, so they
survive panning and zoom changes.


---

#### `SpriteAtlas` （类）

```dart
class SpriteAtlas
```


**成员**


##### 构造

- `SpriteAtlas({required this.image, required this.index})`

##### 方法

- `Rect sourceRect(SpriteIcon icon) =>
Rect.fromLTWH(icon.x, icon.y, icon.width, icon.height)` — Rectangular region of [image] occupied by [icon].
- `static Future<SpriteAtlas?> decode({
required String json,
required List<int> imageBytes,
}) async` — Decodes a sprite from its JSON text and PNG bytes.

Returns `null` when the image cannot be decoded — the caller keeps drawing
labels and simply drops the icons, which is better than losing the layer.
- `void dispose() => image.dispose()`

##### 取值

- `int get length => index.length`

##### 字段

- `final ui.Image image` — The decoded atlas.
- `final SpriteIndex index` — Where each icon lives inside [image].


---

#### `StyleVectorLayer` （类）

```dart
class StyleVectorLayer extends StatelessWidget
```


**成员**


##### 构造

- `const StyleVectorLayer({
super.key,
this.style,
this.controller,
required this.features,
this.opacity = 1.0,
this.sprite,
})  : sources = null,
assert(style != null || controller != null,
'provide either style or controller')`
- `const StyleVectorLayer.ofSources({
super.key,
this.style,
this.controller,
required Map<String, List<GeoJsonFeature>> this.sources,
this.opacity = 1.0,
this.sprite,
})  : features = const [],
assert(style != null || controller != null,
'provide either style or controller')` — Multi-source variant: each style layer draws only `sources[layer.source]`.

Without this, a style with two sources draws every feature twice — a
`line` layer would happily stroke the polygons that belong to a different
source, which reads as a stray outline in the wrong colour.

##### 方法

- `Widget build(BuildContext context)`

##### 字段

- `final StyleSpec? style` — A static style. Ignored when [controller] is provided.
- `final GeoStyleController? controller` — A runtime style controller (M1.4); the layer rebuilds on notify.
- `final List<GeoJsonFeature> features`
- `final Map<String, List<GeoJsonFeature>>? sources` — Features keyed by style source id (see [StyleVectorLayer.ofSources]).
- `final double opacity`
- `final SpriteAtlas? sprite` — Icons for `icon-image`; without one the labels are still drawn.


---

#### `TileDraw` （类）

```dart
class TileDraw
```

屏幕瓦片的一条绘制指令。

`geoKey` 是**足迹**（覆盖世界的哪一块），UV 值是 `image` 内部的**纹理区域**（以图像像素计）。


**成员**


##### 构造

- `const TileDraw({
required this.geoKey,
required this.sourceKey,
required this.image,
required this.u0,
required this.v0,
required this.spanU,
required this.spanV,
})`

##### 取值

- `ui.Rect get sourceRect => ui.Rect.fromLTWH(u0, v0, spanU, spanV)` — The source rect inside the image.

##### 字段

- `final TileKey geoKey` — The tile whose geographic footprint is drawn.
- `final TileKey sourceKey` — The tile the [image] was decoded from (an ancestor when falling back).
- `final TileImage image`
- `final double u0` — Texture origin (image pixels).
- `final double v0` — Texture origin (image pixels).
- `final double spanU` — Texture extent (image pixels).
- `final double spanV` — Texture extent (image pixels).


---

#### `TileEngine` （类）

```dart
class TileEngine extends ChangeNotifier
```

瓦片引擎：选择、请求、缓存、回退。


**成员**


##### 构造

- `TileEngine({required this.source})
: _policy = TileCachePolicy(
maxConcurrentRequests: source.maxConcurrentRequests,
)`

##### 方法

- `static String keyOf(TileKey key) => '${key.z}/${key.x}/${key.y}'`
- `TileImage? imageOf(TileKey key) => _images[keyOf(key)]` — The decoded image of a tile, or `null`.
- `bool wasRequested(TileKey key) => _requested.contains(keyOf(key))` — Whether a tile was ever requested (MapLibre `wasRequested`).
- `bool isLive(TileDraw draw) => _images[keyOf(draw.sourceKey)] == draw.image` — Whether the image behind a draw command is still cached.
- `void request(TileKey key)` — Request a tile (idempotent; failures are graded, never blacklisted).

The tile is **enqueued** on the [TileScheduler] priority queue and a pump
dispatches as many as the concurrency gate allows. A tile that finds every
slot busy is no longer silently dropped (and re-requested next frame) — it
waits its turn and is dispatched the moment a slot frees.
- `TileResolution resolve(TileKey key, int dataZoom)` — Resolve one ideal tile: exact → descendants → ancestors.

The **ideal** tile is always requested (MapLibre `_updateRetainedTiles`
→ `_addTile(idealID)`), *even when a fallback is already drawable*. This
is not an optimisation detail: requesting only when nothing at all is
cached means that the moment a coarse tile is in the cache — which is
true after **every** zoom-in — the finer tile is never fetched and the
view stays pinned to the coarse level forever.

The **ancestor chain** is different: it escalates one level per round and
only after the level below has actually failed (MapLibre
`parentWasRequested`). Requesting the whole pyramid at once is what
produced request storms (and the black holes that followed).
- `List<TileDraw> drawsFor(TileKey key, int dataZoom)` — The drawing commands for one ideal tile.

* exact hit → one command (whole texture);
* loaded descendants → one command per child (they tile the footprint);
* loaded ancestor → one command: the *fine* footprint with the
ancestor's sub-rectangle as texture region.

An empty list means "nothing available yet" — the caller keeps the
previous frame underneath so the screen never flashes black.
- `List<CapDraw> capDraws({
required CameraState camera,
required int dataZoom,
})` — The polar caps that should be drawn for the current camera.

Only mercator has a blind spot (|lat| > 85.05°); the cap stretches the
edge pixel row of the first / last tile row onto the pole.

Two regimes, chosen by [PolarCapBuilder.columnCountFor]:

* **wedge** — the span is a handful of columns wide: each column is drawn
as its own strip, textured with its own tile. Crisp, and the request
count is proportional to the visible cap.
* **smeared** — the span needs more columns than
[GeoEngineTuning.maxPolarCapColumns] allows (the camera is inside the
cap, so the arc wraps the pole): **one** strip, one image. Drawing a
wedge per column there meant 4096 meshes per frame, each with a
different picture, i.e. a sunburst across the whole viewport.
- `double fadeOpacity(TileImage image, int now) =>
selfFadeOpacity(image.loadedAt, now, fadeDurationMs)` — Linear self-fade opacity (0→1) for [image] at wall-clock [now].

A `null` [TileImage.loadedAt] (e.g. a pre-cached image) is always 1. This
is the raster-only "load fade" of MapLibre — a tile is blended in from
transparent to opaque instead of popping in (see `draw_raster.ts`
`getSelfFadeValues`). The math lives in `geo_map_core` so it is
unit-testable without `dart:ui`.
- `bool hasFadingTiles([int? now])` — Whether any cached tile is still inside its fade window at [now].

Drives the per-frame repaint loop: while this is true the layer keeps
redrawing so the fade actually animates (MapLibre keeps `triggerRepaint`
alive while `hasRasterTransition`).
- `bool noteDataZoom(int dataZoom, int now)` — Record the data level of this frame. When it differs from the previous
frame a cross-fade begins; returns true on the first frame of a transition.
- `double crossFadeProgressAt(int now)` — Cross-fade progress (0→1) at [now]; 1 means the transition is complete.
- `bool isCrossFading(int now) =>
_crossFadeFrom != null &&
isWithinFade(_crossFadeStartMs, now, crossFadeDurationMs)` — Whether a zoom cross-fade is still animating at [now].
- `void noteRenderZoom(double zoom, int now)` — Record the render zoom of this frame. Any change of zoom marks the camera
as zooming until [zoomSettleMs] after the last change.
- `void beginFrame()` — Start a frame: the *previous* render set stays protected, the current one
is rebuilt. Also reclaims stuck queue entries and pumps the queue once.
- `void markRendered(TileKey key) => _policy.addRenderTile(keyOf(key))` — Mark a tile as drawn this frame (protects it from eviction).
- `void commitFrame(List<TileDraw> draws)` — Promote the current frame's draws to the "previous" underlay.
- `void noteCameraChange({required bool interacting})` — Note a camera interaction (used for the request debounce).
- `void invalidate()` — Drop in-flight results of an older camera generation, and clear queued
requests that belong to the old view.
- `void dispose()`

##### 取值

- `TileCachePolicy<String> get policy => _policy` — Failure / retry bookkeeping (exposed for the diagnostics HUD).
- `TileScheduler get scheduler => _scheduler` — Scheduler (exposed so the host can flag camera gestures).
- `int get imageCount => _images.length`
- `int get pendingCount => _pending.length`
- `int get inFlight => _policy.inFlight`
- `int get queuedCount => _scheduler.pendingCount`
- `int get requestedCount => _requested.length`
- `int get previousDrawCount => _previousDraws.length`
- `int? get crossFadeFromZoom => _crossFadeFrom` — The level currently being faded *from*, or null when not cross-fading.
- `bool get isZooming => _nowMs < _zoomingUntilMs` — Whether the camera is currently zooming (within [zoomSettleMs] of the last
zoom change). Drives [planTileRequest]'s `suspendAncestors`.
- `List<TileDraw> get previousDraws =>
_previousDraws.where(isLive).toList(growable: false)` — The draw commands of the previous frame (still cached ones only).

##### 字段

- `final GlobeRasterSource source`
- `static const int fadeDurationMs = 300` — Self-fade window for a freshly decoded raster tile (ms). Mirrors
MapLibre's `fadeDuration` (default 300).
- `static const int crossFadeDurationMs = 300` — Duration of a zoom-level cross-fade (ms). Mirrors MapLibre's
`fadeDuration`-based zoom transition between a parent and its child.
- `VoidCallback? onCrossFadeStart` — Notifies the host when a new zoom transition starts, so it can begin the
per-frame repaint loop even while the camera is otherwise stationary.
- `static const int zoomSettleMs = 250` — How long after the last zoom change the camera is still treated as
"zooming" (ms). Long enough to cover a continuous pinch, short enough to
resume parent requests promptly after the finger lifts.


---

#### `TileGeometry` （类）

```dart
abstract class TileGeometry
```

负责绘制一帧瓦片指令。


**成员**


##### 构造

- `const TileGeometry()`

##### 方法

- `void drawTile(
Canvas canvas,
TileDraw draw, {
required CameraState camera,
required double opacity,
})` — Draw one tile command.
- `void drawCap(
Canvas canvas,
CapDraw cap, {
required CameraState camera,
required double opacity,
})` — Draw one polar cap command.


---

#### `TileImage` （类）

```dart
class TileImage
```

一张已解码的瓦片图像及其着色器。


**成员**


##### 构造

- `TileImage(this.image, this.shader, {this.loadedAt})`

##### 方法

- `void dispose()`

##### 取值

- `int get bytes => image.width * image.height * 4`

##### 字段

- `final ui.Image image`
- `final ui.ImageShader shader`
- `final int? loadedAt` — Wall-clock time (ms) the image finished decoding, used for the self
fade-in (MapLibre `fadeDuration`). `null` marks a pre-settled image that
always draws at full opacity.


---

#### `TileLayer` （类）

```dart
class TileLayer extends StatefulWidget
```

同时服务于 2D 与 3D 的栅格瓦片图层。

### 引擎归属

图层接受一个可选的 `engine`。一旦注入，**它归宿主所有**，图层绝不得释放它：共享引擎的全部意义在于 2D 与 3D 图层能互换而不丢失缓存，而正在卸载的图层并不知道是否有兄弟图层即将以同一引擎挂载。

若此处搞反，后果并不 subtle——释放被注入的引擎会杀死所有在途解码（`_decode` 在 `_disposed` 时丢弃该帧），下一次构建即断言`A TileEngine was used after being disposed`，表现为“地球底图永远加载不出来”。


**成员**


##### 构造

- `const TileLayer({
required this.source,
required this.mode,
this.engine,
super.key,
})`

##### 方法

- `State<TileLayer> createState() => _TileLayerState()`

##### 字段

- `final GlobeRasterSource source`
- `final TileEngine? engine` — The shared engine. When `null` the layer creates one and owns it.
- `final TileLayerMode mode`


---

#### `TileResolution` （类）

```dart
class TileResolution
```

一块屏幕瓦片将如何被填充。

* `exact`（精确）— 请求的瓦片本身可用。
* `ancestor`（祖先）— 用更粗的一层瓦片拉伸覆盖请求的足迹；`ancestorDz` 说明它上溯了几级（UV 为子矩形）。
* `descendants`（后代）— 更细的瓦片已加载并覆盖请求的足迹（对应 MapLibre 的 `_retainLoadedChildren`）。


**成员**


##### 构造

- `const TileResolution.exact(this.image)
: ancestor = null,
ancestorDz = 0,
descendants = const [],
descendantImages = const []`
- `const TileResolution.ancestor(this.image, this.ancestorDz)
: ancestor = image,
descendants = const [],
descendantImages = const []`
- `const TileResolution.descendants(this.descendants, this.descendantImages)
: image = null,
ancestor = null,
ancestorDz = 0`

##### 取值

- `bool get isEmpty => image == null && ancestor == null && descendants.isEmpty`

##### 字段

- `final TileImage? image` — The exact tile (if any).
- `final TileImage? ancestor` — The ancestor used as a fallback (if any).
- `final int ancestorDz` — How many zoom levels up [ancestor] is.
- `final List<TileKey> descendants` — Loaded descendants covering the footprint.
- `final List<TileImage> descendantImages` — The images of [descendants] (same order).


---

### 枚举（Enums）

`DebugTilesMode`, `PopupAnchor`, `TileLayerMode`

#### `DebugTilesMode` （枚举）

```dart
enum DebugTilesMode
```


---

#### `PopupAnchor` （枚举）

```dart
enum PopupAnchor
```

浮层锚点——九宫格位置（MapLibre `PositionAnchor`）。

决定卡片的哪条边 / 角贴住由 [GeoMapPopupController] 携带的锚点经纬度。默认 [bottom]，即保持现有的“卡片浮在锚点上方”行为。


**成员**


##### 枚举值

- `center`
- `top`
- `bottom`
- `left`
- `right`
- `topLeft`
- `topRight`
- `bottomLeft`
- `bottomRight`


---

#### `TileLayerMode` （枚举）

```dart
enum TileLayerMode
```

该图层以哪种投影渲染。


**成员**


##### 枚举值

- `mercator`
- `globe`


---

### 类型定义（Typedefs）

`GlobeRasterSource`

#### `GlobeRasterSource` （类型定义）

```dart
typedef GlobeRasterSource = GeoTileSource
```

为 [GeoTileSource] 保留的向后兼容别名。


---

### 函数（Functions）

`anchorOffsetFor`, `buildGraticule`, `buildGreatCircle`, `buildTissot`, `densifyPath`, `layoutAnchoredPopup`, `projectForPick`

#### `anchorOffsetFor` （函数）

```dart
Offset anchorOffsetFor(PopupAnchor side, Offset point, Size card, double tail)
```

卡片左上角的「未夹取」位置（九宫格）。

给定投影后的锚点 [point] 与卡片尺寸 [card]，返回卡片左上角应处的逻辑像素，
再交由 [layoutAnchoredPopup] 夹进 [EdgeInsets]。[tail] 是卡片朝向锚点那一侧
留出的小尖角间距（仅 top/bottom/left/right 用；四角忽略）。

纯函数，可纯 Dart 断言测试。


---

#### `buildGraticule` （函数）

```dart
List<GlobePolyline> buildGraticule({
double latStep = 15,
double lngStep = 15,
double maxLat = 80,
Color color = const Color(0x553DDC97),
})
```

Meridians every [lngStep]° and parallels every [latStep]°.

Parallels are sampled densely so they visibly curve — that curvature is the
first thing to check when the projection is off.


---

#### `buildGreatCircle` （函数）

```dart
GlobePolyline buildGreatCircle(
LatLng from,
LatLng to, {
Color color = const Color(0xCCFF1744),
double strokeWidth = 2,
}) => GlobePolyline(points: [from, to], color: color, strokeWidth: strokeWidth)
```

Great-circle segment between two points (for checking long distances).


---

#### `buildTissot` （函数）

```dart
List<GlobePolyline> buildTissot({
double latStep = 30,
double lngStep = 30,
double radiusDeg = 9,
int segments = 48,
Color color = const Color(0x88FFC107),
})
```

Tissot indicatrices: small equal-radius circles on the sphere.

On a correct orthographic projection they stay circular at the disc centre
and squash into ellipses towards the limb — an instant visual check for
distortion and for wrong great-circle interpolation.


---

#### `densifyPath` （函数）

```dart
List<LatLng> densifyPath(List<LatLng> points, {double stepDeg = 2})
```

Densifies a path along great circles.

flutter_map's polygon/polyline painters connect projected points with
straight screen lines, so data fed to them must already be densified for the
edges to follow the sphere.


---

#### `layoutAnchoredPopup` （函数）

```dart
AnchoredPopupLayout layoutAnchoredPopup({
required Offset anchor,
required Size viewport,
required Size card,
required EdgeInsets keepOut,
PopupAnchor anchorSide = PopupAnchor.bottom,
double tail = 8,
double slop = 32,
})
```

计算卡片左上角：按 [anchorSide] 九宫格把卡片某一侧对准 [anchor]，再夹进 [keepOut]。

[anchor] / [viewport] / [card] 都是逻辑像素。锚点出屏、非有限、或球面背半球
哨兵（`±1e6`）时返回 `visible:false`。宿主据此决定是否渲染卡片。

[anchorSide] 默认 [PopupAnchor.bottom]，与旧行为（底边中点对准锚点）一致；
其余八档见 [PopupAnchor]。


---

#### `projectForPick` （函数）

```dart
Vec2? projectForPick(MapProjectionDelegate delegate, LatLng point)
```

The screen position of [point] for picking, or `null` when it cannot be
picked (the far side of the globe, or a non-finite coordinate).


---

## 库 `package:geo_map_core`（再导出部分）

### 类（Classes）

`Expr`, `ExpressionContext`, `GeoEngineTuning`, `GeoJsonFeature`, `GeoJsonGeometry`, `GeoTileSource`, `LineStringGeometry`, `MultiLineStringGeometry`, `MultiPolygonGeometry`, `PointGeometry`, `PolygonGeometry`, `PropertyValue`, `SpriteIcon`, `SpriteIndex`, `StyleColor`, `StyleDocument`, `StyleLayer`, `StyleSpec`, `TileFetchResult`

#### `Expr` （类）

```dart
abstract class Expr
```

一个已解析的表达式节点。


**成员**


##### 构造

- `const Expr()`

##### 方法

- `Object? evaluate(ExpressionContext ctx)`

##### 取值

- `bool get isFeatureConstant` — True when the value does **not** depend on feature properties.
- `bool get isZoomConstant` — True when the value does **not** depend on the zoom.
- `bool get isConstant => isFeatureConstant && isZoomConstant` — True when this is a compile-time constant.


---

#### `ExpressionContext` （类）

```dart
class ExpressionContext
```

表达式的求值输入。

对应 MapLibre 的 `EvaluationParameters` / `EvaluationContext`：`zoom` 是 spike 阶段唯一需要的全局量；`properties` 替代要素的属性表（这正是 `get`/`has` 让表达式依赖要素的原因）。


**成员**


##### 构造

- `const ExpressionContext({
required this.zoom,
this.properties = const {},
this.variables = const {},
})`

##### 字段

- `final double zoom`
- `final Map<String, Object?> properties`
- `final Map<String, Object?> variables` — Bindings introduced by [`let`] expressions.


---

#### `GeoEngineTuning` （类）

```dart
class GeoEngineTuning
```


**成员**


##### 构造

- `const GeoEngineTuning._()`

##### 字段

- `static const double epsDepth = 0.02` — Depth below which a vertex counts as "behind the horizon".
- `static const double maxCameraLatitude = 89.999` — Camera latitude clamp — keeps the orthographic camera out of the exact pole
(avoids NaN in `1/cos(lat)` compensation and degenerate tangents).
- `static const double pickZoomCosFloor = 0.2` — Floor for `cos(lat)` when picking a tile zoom near the poles.
- `static const int tileSize = 256` — Raster tile edge in pixels. Single source of truth.
- `static const double tileSizeD = tileSize * 1.0` — [tileSize] as a double (const-usable default parameter).
- `static const double densifyPixelError = 0.5` — Maximum chord error allowed when densifying great circles (screen px).
- `static const double selectMargin = 64` — Extra margin (px) used when testing whether a tile touches the viewport.
- `static const int subdivMin = 6` — Mesh subdivision bounds per tile / image quad.
- `static const int subdivMax = 16`
- `static const double subdivPx = 20` — Target number of screen pixels per subdivision cell.
- `static const int cacheBudgetBytes = 96 << 20` — Raster cache budget (bytes) — replaces the old "384 images" count cap.
- `static const int defaultTileBytes = 256 * 1024` — Default estimated bytes per decoded tile, used before a real measurement.
- `static const double tapSlopPx = 12` — Tap slop and fling thresholds for the gesture layer.
- `static const int tapMaxMillis = 400`
- `static const int doubleTapMaxMillis = 320`
- `static const double flingMinVelocityPxPerSec = 600`
- `static const int tileRequestDebounceMillis = 120` — Debounce before issuing new tile requests while the camera is moving.
- `static const int maxUnderzooming = 10` — How many zoom levels up the ancestor chain may be used as a fallback.

MapLibre: `maxUnderzooming` (default 10). The chain stops at
`source.minzoom`.
- `static const int maxOverzooming = 3` — How many zoom levels down the descendant chain may be used as a fallback.

MapLibre: `maxOverzooming` (default 3). The whole generation must be
present before it is drawn.
- `static const int tileCacheZoomLevels = 5` — Zoom levels kept in the cache (MapLibre `MAX_TILE_CACHE_ZOOM_LEVELS`).
- `static const int maxParallelRequests = 16` — Maximum concurrent raster tile requests (MapLibre
`MAX_PARALLEL_IMAGE_REQUESTS`).
- `static const int sqliteParallelRequests = 4` — Concurrent requests for a sqlite-backed source — a single file handle
does not benefit from more.
- `static const int requestTimeoutMs = 15000` — TCP connect timeout for tile requests.
- `static const int bodyTimeoutMs = 30000` — Timeout for reading the response body of a tile request.
- `static const int pendingTimeoutMs = 45000` — A pending request that never completed within this window is reclaimed.
- `static const int maxTrackedTileKeys = 4096` — Upper bound on the number of tracked request/failure keys.
- `static const int networkFailureTtlMs = 3000` — Network / timeout failures are transient — retry quickly.
- `static const int notFoundTtlMs = 30000` — A missing tile (HTTP 404) stays missing for longer: MapLibre does not
blacklist it, it just falls back to parent/child tiles.
- `static const int decodeFailureTtlMs = 8000` — Decode failures (corrupt payload) — retry, but not immediately.
- `static const int failureBackoffBaseMs = 1000` — Exponential backoff base for repeated failures of the same tile
(MapLibre `tile.ts`: `1000 * 2^(n-1)`).
- `static const int failureBackoffMaxMs = 30000` — Cap for the exponential backoff.
- `static const int maxPolarCapColumns = 64` — Upper bound on the number of **separate meshes** used to draw one polar
cap.

Two regimes exist and this constant is the switch between them:

* **wedge regime** (`columns ≤ maxPolarCapColumns`) — every visible grid
column gets its own strip textured with that column's own tile. This is
the crisp path and it is what a cap seen from *outside* looks like.
* **smeared regime** (`columns > maxPolarCapColumns`) — the whole visible
arc is drawn as **one** strip with a single texture. The camera is
inside the cap here, the arc wraps all the way around the pole, and a
per-column wedge would mean thousands of meshes each sampling a
different image: that is precisely the radial sunburst that used to
fill the viewport.

The bound therefore has to stay small enough that the wedge regime stays
cheap, and the smeared regime is only reached where the cap is a
featureless blob anyway.
- `static const double featurePickRadiusPx = 24` — Default screen-space pick radius (px) for point features.

24 px is roughly twice the on-screen diameter of a 12 px symbol, so a
dot is grabbable without demanding pixel accuracy. Hosts may override it
per query or per feature.
- `static const double hiddenPointSentinelPx = 1e6` — Magnitude at which a projected screen coordinate is treated as the
"not drawable" sentinel.

The globe projector returns `(-1e6, -1e6)` for the far side of the
sphere. Such a coordinate is finite, so a naive distance check would
treat it as "very far away" rather than "not pickable" — both are
rejected, but the sentinel must be detected explicitly.
- `static const double featureBoundaryEpsilonDeg = 1e-7` — Tolerance (degrees) for "the tap is exactly on the ring boundary".

1e-7° is about a centimetre — it only absorbs floating-point noise, it
does not widen the shape.


---

#### `GeoJsonFeature` （类）

```dart
class GeoJsonFeature
```


**成员**


##### 构造

- `const GeoJsonFeature({
this.id,
this.properties = const {},
required this.geometry,
})`

##### 字段

- `final String? id`
- `final Map<String, Object?> properties`
- `final GeoJsonGeometry geometry`


---

#### `GeoJsonGeometry` （类）

```dart
sealed class GeoJsonGeometry
```


**成员**


##### 构造

- `const GeoJsonGeometry()`


---

#### `GeoTileSource` （类）

```dart
abstract class GeoTileSource
```

栅格瓦片提供者（HTTP、MBTiles 等）。


**成员**


##### 方法

- `Future<TileFetchResult> fetch(int z, int x, int y)` — Fetch one tile. [x] / [y] are canonical XYZ (row 0 = north); the source
converts to its own wire order internally.
- `void dispose()` — Release any resource held by the source (sqlite handle, http client).

##### 取值

- `int get minZoom`
- `int get maxZoom`
- `TileSchemeKind get scheme` — The tile grid geometry of this source.
- `TileRowOrder get rowOrder => TileRowOrder.xyzTopDown` — Row order used **on the wire** (TMS / MBTiles count rows from south).
- `int get maxConcurrentRequests => GeoEngineTuning.maxParallelRequests` — How many requests may be in flight at the same time. A local sqlite file
gains nothing from parallel reads, so MBTiles overrides this with a much
smaller number.
- `String get attribution` — Attribution shown in debug UI.


---

#### `LineStringGeometry` （类）

```dart
class LineStringGeometry extends GeoJsonGeometry
```


**成员**


##### 构造

- `const LineStringGeometry(this.points)`

##### 字段

- `final List<LatLng> points`


---

#### `MultiLineStringGeometry` （类）

```dart
class MultiLineStringGeometry extends GeoJsonGeometry
```


**成员**


##### 构造

- `const MultiLineStringGeometry(this.lines)`

##### 字段

- `final List<List<LatLng>> lines`


---

#### `MultiPolygonGeometry` （类）

```dart
class MultiPolygonGeometry extends GeoJsonGeometry
```


**成员**


##### 构造

- `const MultiPolygonGeometry(this.polygons)`

##### 字段

- `final List<List<List<LatLng>>> polygons`


---

#### `PointGeometry` （类）

```dart
class PointGeometry extends GeoJsonGeometry
```


**成员**


##### 构造

- `const PointGeometry(this.point)`

##### 字段

- `final LatLng point`


---

#### `PolygonGeometry` （类）

```dart
class PolygonGeometry extends GeoJsonGeometry
```


**成员**


##### 构造

- `const PolygonGeometry(this.rings)`

##### 字段

- `final List<List<LatLng>> rings`


---

#### `PropertyValue` （类）

```dart
class PropertyValue
```

一个绘制 / 布局值：常量，或每次绘制时求值的表达式。


**成员**


##### 构造

- `PropertyValue._(this._constant, this._expr, this.isColor)`
- `factory PropertyValue.fromJson(Object? json, {bool isColor = false})`

##### 方法

- `Object? evaluate(ExpressionContext ctx)`

##### 取值

- `bool get isExpression => _expr != null`
- `bool get isFeatureConstant => _expr?.isFeatureConstant ?? true` — True when the value does not depend on feature properties.
- `bool get isZoomConstant => _expr?.isZoomConstant ?? true` — True when the value does not depend on zoom.

##### 字段

- `final bool isColor`


---

#### `SpriteIcon` （类）

```dart
class SpriteIcon
```

图集中某个图标的矩形区域。


**成员**


##### 构造

- `const SpriteIcon({
required this.x,
required this.y,
required this.width,
required this.height,
this.pixelRatio = 1,
this.sdf = false,
})`

##### 方法

- `String toString() =>
'SpriteIcon($x,$y ${width}x$height @${pixelRatio}x)'`

##### 取值

- `double get displayWidth => pixelRatio <= 0 ? width : width / pixelRatio` — Size on screen at `icon-size: 1`, i.e. sprite pixels divided by density.
- `double get displayHeight => pixelRatio <= 0 ? height : height / pixelRatio`

##### 字段

- `final double x`
- `final double y`
- `final double width`
- `final double height`
- `final double pixelRatio`
- `final bool sdf`


---

#### `SpriteIndex` （类）

```dart
class SpriteIndex
```

单个精灵的 名称 → 图标 查找表。


**成员**


##### 构造

- `const SpriteIndex(this.icons)`
- `factory SpriteIndex.parse(Object? json)` — Parses the sprite JSON, skipping entries that are malformed.

Tolerant on purpose: a sprite atlas is third-party data, and one broken
entry should cost that icon, not the whole layer.

##### 取值

- `int get length => icons.length`

##### 字段

- `final Map<String, SpriteIcon> icons`


---

#### `StyleColor` （类）

```dart
class StyleColor
```


**成员**


##### 构造

- `const StyleColor(this.r, this.g, this.b, [this.a = 255])`

##### 方法

- `static StyleColor parse(Object? value)` — Parse a CSS color: `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, a
few named colors, an `0xAARRGGBB` int, or an existing [StyleColor].
- `static StyleColor lerp(StyleColor x, StyleColor y, double t) => StyleColor(
(x.r + (y.r - x.r) * t).round(),
(x.g + (y.g - x.g) * t).round(),
(x.b + (y.b - x.b) * t).round(),
(x.a + (y.a - x.a) * t).round(),
)`
- `String toCss()`
- `bool operator ==(Object other) =>
other is StyleColor &&
other.r == r &&
other.g == g &&
other.b == b &&
other.a == a`
- `String toString() => 'StyleColor(${toCss()})'`

##### 取值

- `int get hashCode => Object.hash(r, g, b, a)`

##### 字段

- `final int r`
- `final int g`
- `final int b`
- `final int a`


---

#### `StyleDocument` （类）

```dart
class StyleDocument
```


**成员**


##### 构造

- `StyleDocument({
this.version = 8,
Map<String, Map<String, Object?>> sources = const {},
List<StyleLayer> layers = const [],
})  : sources = Map.unmodifiable(sources),
layers = List.unmodifiable(layers)`
- `factory StyleDocument.fromSpec(StyleSpec spec) => StyleDocument(
version: spec.version,
sources: spec.sources,
layers: spec.layers,
)`

##### 方法

- `StyleSpec toSpec() =>
StyleSpec(version: version, sources: sources, layers: layers)`
- `StyleLayer? layer(String id)`
- `StyleDocument addSource(String id, Map<String, Object?> source)`
- `StyleDocument removeSource(String id)`
- `StyleDocument addLayer(StyleLayer layer, {String? before})`
- `StyleDocument removeLayer(String id)`
- `StyleDocument moveLayer(String id, {String? before})`
- `StyleDocument setPaintProperty(String id, String name, Object? value) =>
_updateLayer(id, (l) {
final def = layerPaintDefs[l.type]?[name];
return l.copyWith(paint: {
...l.paint,
name: PropertyValue.fromJson(
value,
isColor: def?.type == StylePropertyType.color,
),
});
})`
- `StyleDocument setLayoutProperty(String id, String name, Object? value) =>
_updateLayer(id, (l) {
final def = layerLayoutDefs[l.type]?[name];
return l.copyWith(layout: {
...l.layout,
name: PropertyValue.fromJson(
value,
isColor: def?.type == StylePropertyType.color,
),
});
})`
- `StyleDocument setFilter(String id, Object? filter) =>
_updateLayer(id, (l) => l.copyWith(filter: compileFilter(filter)))`
- `StyleDocument setLayerZoomRange(String id, num min, num max) =>
_updateLayer(id, (l) => l.copyWith(minZoom: min, maxZoom: max))`
- `StyleDocument setVisibility(String id, String visibility) =>
setLayoutProperty(id, 'visibility', visibility)`

##### 字段

- `final int version`
- `final Map<String, Map<String, Object?>> sources`
- `final List<StyleLayer> layers`


---

#### `StyleLayer` （类）

```dart
class StyleLayer
```


**成员**


##### 构造

- `StyleLayer({
required this.id,
required this.type,
this.source,
this.sourceLayer,
this.minZoom,
this.maxZoom,
this.paint = const {},
this.layout = const {},
this.filter = matchAllFeatures,
})`

##### 方法

- `bool matches(Map<String, Object?> properties, double zoom) =>
filter(properties, zoom)` — Whether this layer wants [properties] at [zoom].

The zoom argument exists because MapLibre lets a filter reference
`["zoom"]`; see `style_filter.dart`.
- `static StyleLayer parse(Map<String, Object?> json)`
- `Object? valueOf(String name, ExpressionContext ctx)` — Evaluate any paint or layout property (paint first, then layout).
- `double? number(String name, ExpressionContext ctx)`
- `StyleColor? color(String name, ExpressionContext ctx)`
- `String? string(String name, ExpressionContext ctx) =>
valueOf(name, ctx)?.toString()`
- `bool? boolean(String name, ExpressionContext ctx)`
- `bool isVisibleAt(double zoom)` — MapLibre visibility: `minzoom <= zoom < maxzoom` and `visibility != none`.
- `StyleLayer copyWith({
Map<String, PropertyValue>? paint,
Map<String, PropertyValue>? layout,
num? minZoom,
num? maxZoom,
FeaturePredicate? filter,
}) =>
StyleLayer(
id: id,
type: type,
source: source,
sourceLayer: sourceLayer,
minZoom: minZoom ?? this.minZoom,
maxZoom: maxZoom ?? this.maxZoom,
paint: paint ?? this.paint,
layout: layout ?? this.layout,
filter: filter ?? this.filter,
)`

##### 取值

- `bool get isSupported => type == 'fill' || type == 'line' || type == 'symbol'` — Whether the M1 renderer can draw this layer type.

##### 字段

- `final String id`
- `final String type` — `fill` or `line` in the M1 subset (other types parse but are not drawn).
- `final String? source`
- `final String? sourceLayer`
- `final num? minZoom`
- `final num? maxZoom`
- `final Map<String, PropertyValue> paint`
- `final Map<String, PropertyValue> layout`
- `final FeaturePredicate filter` — Compiled filter over feature properties (always-true when absent).

Call it through [matches], which supplies the zoom.


---

#### `StyleSpec` （类）

```dart
class StyleSpec
```


**成员**


##### 构造

- `StyleSpec({
required this.version,
required this.sources,
required this.layers,
})`

##### 方法

- `static StyleSpec parse(Map<String, Object?> json)`

##### 字段

- `final int version`
- `final Map<String, Map<String, Object?>> sources`
- `final List<StyleLayer> layers`


---

#### `TileFetchResult` （类）

```dart
class TileFetchResult
```

单次瓦片请求的结果。

MapLibre 在“服务器声明无此瓦片”（404——永不黑名单，引擎持续回退）与“请求中断”（网络错误——快速重试）之间划出硬界限。把两者都坍缩成 `null`正是旧引擎在两次失败后把瓦片拉黑的原因。


**成员**


##### 构造

- `const TileFetchResult.ok(this.bytes) : failure = null`
- `const TileFetchResult.failed(this.failure) : bytes = null`

##### 方法

- `String toString() => isOk
? 'TileFetchResult.ok(${bytes?.length} bytes)'
: 'TileFetchResult.failed($failure)'`

##### 取值

- `bool get isOk => failure == null && bytes != null`
- `bool get isNotFound => failure == TileFailureKind.notFound`

##### 字段

- `final Uint8List? bytes` — The decoded payload, or `null` when [failure] is set.
- `final TileFailureKind? failure` — Why the tile could not be produced (`null` on success).


---

### 枚举（Enums）

`GeoGeometryKind`, `TileFailureKind`, `TileRowOrder`, `TileSchemeKind`

#### `GeoGeometryKind` （枚举）

```dart
enum GeoGeometryKind
```

一次查询可考量的几何种类。


---

#### `TileFailureKind` （枚举）

```dart
enum TileFailureKind
```

一块瓦片为何无法生成。

区分很关键：缺失的瓦片（404）**不得**被黑名单（MapLibre `tile_manager.ts` 的 `_loadTile` 只是再次 `update()` 并持续回退到父 / 子瓦片），而网络错误是瞬时的，应快速重试。


**成员**


##### 枚举值

- `notFound`
- `network`
- `decode`
- `empty`


---

#### `TileRowOrder` （枚举）

```dart
enum TileRowOrder
```

**线上**使用的行序。

内部（规范）行序始终是 XYZ——第 0 行是网格的北缘。某些服务（TMS、MBTiles）从南边数行，因此在构建 URL 或从本地文件读取行时必须翻转行索引。

MapLibre 用一行实现：`tile_id.ts` L48 `y = scheme === 'tms' ? 2^z - y - 1 : y`。


**成员**


##### 枚举值

- `xyzTopDown`
- `tmsBottomUp`


---

#### `TileSchemeKind` （枚举）

```dart
enum TileSchemeKind
```


---

### 类型定义（Typedefs）

`FeaturePredicate`

#### `FeaturePredicate` （类型定义）

```dart
typedef FeaturePredicate = bool Function(
Map<String, Object?> properties, [
double? zoom,
])
```

在某一缩放层级上对单个要素的谓词。

zoom 可选，因此没有相机的调用方（测试、从不提及 `[\"zoom\"]` 的过滤器）仍可询问 `matches(props)`；此时含义为“zoom 0”。


---

### 函数（Functions）

`compileFilter`, `normalizeRingWinding`, `parseGeoJsonFeatures`, `pointInMultiPolygon`, `pointInPolygon`, `pointInRing`, `ringSignedArea`, `splitRingAtSeam`, `unwrapLongitudes`

#### `compileFilter` （函数）

```dart
FeaturePredicate compileFilter(Object? json)
```


---

#### `normalizeRingWinding` （函数）

```dart
List<List<LatLng>> normalizeRingWinding(List<List<LatLng>> rings)
```

把绕向与外环一致的环反转。

Canvas 用非零环绕规则填充，因此绕向与外环相同的洞**不会**穿透；将其反转即可恢复孔洞。外环保持朝向不变，单环多边形原样返回。


---

#### `parseGeoJsonFeatures` （函数）

```dart
List<GeoJsonFeature> parseGeoJsonFeatures(Map<String, Object?> json)
```

解析一个 GeoJSON `FeatureCollection` 或单个 `Feature`。


---

#### `pointInMultiPolygon` （函数）

```dart
bool pointInMultiPolygon(
List<List<List<LatLng>>> polygons,
LatLng point, {
bool includeBoundary = true,
})
```

[point] 是否落在 [polygons]（MultiPolygon）的任一子多边形内。

各子多边形独立求值（并集语义），与渲染器绘制方式一致——每个环一次 `addPolygon`。


---

#### `pointInPolygon` （函数）

```dart
bool pointInPolygon(
List<List<LatLng>> rings,
LatLng point, {
bool includeBoundary = true,
})
```

[point] 是否落在多边形 [rings] 内（首环 = 外环，其余 = 洞）。

内部为“外环减洞”（RFC 7946）。边界处理：落在**外环**边界上的点算内部；落在**洞**边界上的点算外部——洞优先。


---

#### `pointInRing` （函数）

```dart
bool pointInRing(
List<LatLng> ring,
LatLng point, {
bool includeBoundary = true,
})
```

[point] 是否落在闭合环 [ring] 内。

使用奇偶规则，因此环的绕向无关。`includeBoundary` 决定恰好落在边上的点是否算内部（默认：算）。顶点少于三个的环返回 `false`。


---

#### `ringSignedArea` （函数）

```dart
double ringSignedArea(List<LatLng> ring)
```

[ring] 的带符号面积，在**展开后**的经度上度量。

正值表示逆时针。展开很关键：靠近 ±180° 的环否则会翻转符号，悄然改变哪个环被当作外环。


---

#### `splitRingAtSeam` （函数）

```dart
List<List<LatLng>> splitRingAtSeam(List<LatLng> ring, double seamLng)
```

在经线 [seamLng] 处切分 [ring]，返回一个或两个闭合片段。

先展开环，因此 +179°/−179° 的边会被识别为跨越接缝。若环完全位于一侧，则原样返回 `[ring]`。顶点少于三个的片段被丢弃。

这对应 MapLibre 在切片时于 ±180° 切分 GeoJSON 的行为。渲染器自身只需要 [unwrapLongitudes] 加世界副本；此辅助函数让该行为可测试，并允许调用方显式裁剪。


---

#### `unwrapLongitudes` （函数）

```dart
List<double> unwrapLongitudes(List<double> lons)
```

顺序展开 [lons]，使每对相邻差值都落在 (-180, 180]。

`out[0] == lons[0]`；`out[i] = out[i-1] + wrapLongitude(lons[i] - lons[i-1])`。一条从 +179° “跳”到 −179° 的环会变成 +179° → +181°（2° 步长）而非 −358° 步长，从而可被连续投影。


---
