# geo_map API 文档

> 风格参考 MapLibre GL JS 官方文档，面向 Dart / Flutter 开发者。
> 覆盖范围：包结构、快速开始、`GeoMapController`、栅格瓦片源、图层体系、**要素查询（queryRenderedFeatures）**、典型使用场景、样式系统（含 **symbol 符号与标注**全量属性）、约束与踩坑、与本项目（`app_client`）的落地对照。
>
> 对应版本 `0.2.1`（M1 style spec / M2 MVT / M3 符号与标注 / 要素查询 / **弹窗控制层** 均已落地）。

---

## 目录

- [0. 这是什么](#0-这是什么)
- [1. 快速开始](#1-快速开始)
- [2. GeoMapController](#2-geomapcontroller)
- [3. 栅格瓦片源](#3-栅格瓦片源)
- [4. 图层体系总览](#4-图层体系总览)
- [5. 要素查询（queryRenderedFeatures）](#5-要素查询queryrenderedfeatures)
- [6. 使用场景](#6-使用场景)
- [7. 样式系统](#7-样式系统)
  - [7.2 symbol 属性速查](#72-symbol-属性速查)
  - [7.3 锚点九宫格](#73-锚点九宫格)
  - [7.4 沿线标注](#74-沿线标注)
  - [7.5 SDF 图标着色](#75-sdf-图标着色)
  - [7.6 跨瓦片去重](#76-跨瓦片去重)
  - [7.7 旋转与透明度](#77-旋转与透明度)
  - [7.8 图标集 SpriteAtlas](#78-图标集-spriteatlas)
- [8. 约束与踩坑](#8-约束与踩坑)
  - [8.1 日界线与平面无限滚动](#81-日界线与平面无限滚动)
- [9. 与 app_client 的落地对照](#9-与-app_client-的落地对照)
- [10. 浮层 / 弹窗（Popup）](#10-浮层--弹窗popup)
  - [10.1 为什么不能放进 `GeoMap.children`](#101-为什么不能放进-geomapchildren)
  - [10.2 三层结构：状态 / 定位 / 绑定](#102-三层结构状态--定位--绑定)
  - [10.3 绑定式弹窗（推荐）](#103-绑定式弹窗推荐)
  - [10.4 九宫格锚点](#104-九宫格锚点)
  - [10.5 约束与踩坑](#105-约束与踩坑)

---

## 0. 这是什么

`geo_map` 是一个自研的 Flutter 地图渲染包，由两层构成：

- **`geo_map`**：面向开发者的上层 API —— `GeoMap` 控件、各类图层（`GlobeVectorLayer`、`GlobeImageLayer`、`StyleVectorLayer`、`MvtVectorLayer`）、经纬网/大圆工具、以及控制器 `GeoMapController`。
- **`geo_map_core`**：底层引擎。提供 2D Web Mercator 平面投影与 3D 正交球面投影，**两者共享同一套瓦片加载引擎与缓存**；并导出 `StyleSpec`、`GeoJson`、`GeoTileSource` 等基础类型。

`geo_map` 通过 `geo_map.dart` 统一 re-export `geo_map_core` 的基础类型，因此业务代码通常只需 `import 'package:geo_map/geo_map.dart';`。

### 2D / 3D 的真相

很多地图库用「模式切换」来切换平面/地球，但 `geo_map` 的 2D 与 3D 并非简单开关：

- 2D 使用 **Web Mercator 平面**；
- 3D 使用 **正交投影球面**；
- 二者复用同一套瓦片引擎与缓存，所以离线底图、HTTP 源在两种视图下都能直接复用。

**重要约束**：不要用 `GeoMapController.setMode()` 直接切换视图。正确的切换入口是状态层的 `mapUseGlobeProvider`（见 [第 9 章](#9-与-app_client-的落地对照)），由它驱动 delegate 替换。直接调 `setMode` 会绕过状态管理，导致 UI 与控制器状态不一致。

---

## 1. 快速开始

### 1.1 引入与最小示例

```dart
import 'package:flutter/material.dart';
import 'package:geo_map/geo_map.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GeoMap(
        options: GeoMapOptions(
          initialCenter: LatLng(30.0, 114.0), // 中国中部
          initialZoom: 4.0,
          minZoom: 2.0,
          maxZoom: 12.0,
          useGlobe: false,            // false = 2D 平面；true = 3D 地球
          background: Colors.black,
        ),
        source: myTileSource,         // GeoTileSource，见第 3 章
        children: const [
          // 图层、覆盖物放在这里，见第 4、6 章
        ],
      ),
    );
  }
}
```

### 1.2 `GeoMapOptions` 字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `initialCenter` | `LatLng` | 初始地图中心 |
| `initialZoom` | `double` | 初始缩放级别 |
| `minZoom` | `double` | 最小缩放 |
| `maxZoom` | `double` | 最大缩放 |
| `useGlobe` | `bool` | `false` 走 2D 平面，`true` 走 3D 球面 |
| `background` | `Color` | 画布背景色 |

### 1.3 `GeoMap` 构造参数

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `options` | `GeoMapOptions` | 地图配置 |
| `source` | `GeoTileSource` | 底图瓦片源 |
| `controller` | `GeoMapController?` | 可选，外部持有控制器 |
| `children` | `List<Widget>` | 图层与覆盖物 |
| `onTap` | `Function(LatLng)?` | 点击地图回调（经纬度） |

### 1.4 关于 `children` 的指针事件（务必注意）

`children` 被放置在 `GlobeGestureOverlay`（一个 **opaque** 手势层）**之下**。因此：

- **`children` 中的 Widget 收不到指针事件**（点击、拖动会被手势层吃掉）。
- 整棵 `children` 树被 `ListenableBuilder(controller)` 包裹 —— 任何平移都会重建全部 `children`。所以请勿在 `children` 里放重组件或依赖局部状态的控件，应把覆盖物写成由控制器状态驱动的纯绘制层。

> 如果你需要可交互的 UI（按钮、弹窗、图例），请放在 `GeoMap` **之外**的 Stack / Overlay 中，而不是 `children`。

---

## 2. GeoMapController

`GeoMapController` 用于以编程方式驱动相机（平移、缩放、重定位、约束、视图切换）。

### 2.1 创建与绑定

```dart
final controller = GeoMapController();

GeoMap(
  options: GeoMapOptions(initialCenter: LatLng(30, 114), initialZoom: 4),
  source: myTileSource,
  controller: controller,
  children: [
    ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // 根据 controller 状态绘制覆盖物
        return const SizedBox.shrink();
      },
    ),
  ],
);
```

### 2.2 方法一览

| 方法 | 签名（要点） | 说明 |
| --- | --- | --- |
| `move` | `move(LatLng center, double zoom)` | 直接跳到指定中心与缩放 |
| `panBy` | `panBy(Offset delta)` | 按像素偏移平移 |
| `zoomBy` | `zoomBy(double delta, [LatLng? around])` | 相对缩放，`around` 为锚点 |
| `zoomAround` | `zoomAround(LatLng point, double zoom)` | 以某地理点为锚缩放 |
| `recenter` | `recenter([LatLng? center])` | 回到初始/指定中心 |
| `setMode` | `setMode(MapMode mode)` | **内部用**：替换 2D/3D delegate |
| `setViewport` | `setViewport(...)` | 设置视口范围 |
| `applyConstraints` | `applyConstraints()` | 应用 min/max zoom 等约束 |
| `isGlobe` | `bool get isGlobe` | 当前是否为 3D 球面视图 |

> **再次强调**：业务层请通过 `mapUseGlobeProvider` 切换 2D/3D，不要直接调用 `setMode`。`setMode` 是引擎内部在 provider 变化时替换 delegate 用的。

### 2.3 示例：以机场为中心缩放

```dart
controller.zoomAround(LatLng(30.58, 114.30), 8.0); // 武汉天河机场
```

---

## 3. 栅格瓦片源

瓦片源是底图的来源，统一实现 `GeoTileSource` 接口（`GlobeRasterSource` 是 `GeoTileSource` 的别名）。

### 3.1 `MbtilesTileSource`（离线 MBTiles）

```dart
final source = await MbtilesTileSource.open(
  'basemap',                       // 唯一 id
  'assets/maps/basemap.mbtiles',   // 包内 asset 路径
);
```

`MbtilesTileSource.open(id, assetPath)` 的行为：

1. 将 asset 拷贝到应用文档目录（避免直接读包内路径）；
2. 将 WAL 日志模式切换为 DELETE（兼容只读/移动端）；
3. 读取真实的瓦片层级（zoom levels），供 `minZoom`/`maxZoom` 对齐；
4. 对损坏文件做自愈（重建索引/重新拷贝）。

> **Web 限制**：当前在 Web 平台下该方法为 stub，会直接抛出异常。Web 端请改用 `HttpTileSource` 或在线 XYZ 源。

### 3.2 `HttpTileSource`（在线 XYZ / WMTS）

支持占位符：`{z}` `{x}` `{y}` `{TileMatrix}` `{prefix}` `{quadkey}` `{bbox}`。

```dart
// 工厂：OpenStreetMap 标准 XYZ
final osm = HttpTileSource.osm();

// 工厂：NASA GIBS 真彩色（WMTS，含 TileMatrix）
final gibs = HttpTileSource.gibsTrueColor();

// 自定义 XYZ
final custom = HttpTileSource(
  urlTemplate: 'https://tile.example.com/{z}/{x}/{y}.png',
);
```

### 3.3 `DebugTilesSource`（调试）

绘制带坐标系的调试瓦片，用于核对瓦片编号与投影对齐：

```dart
final debug = DebugTilesSource();
```

### 3.4 自定义源

只要实现 `GeoTileSource`，即可接入任意来源（如自研瓦片服务、内存缓存源）。`app_client` 中的 `MbtilesRegistryTileSource` 就是一个「多包路由」的自定义实现范例（见 [第 9 章](#9-与-app_client-的落地对照)）。

---

## 4. 图层体系总览

| 图层 | 适用视图 | 关键能力 |
| --- | --- | --- |
| `GlobeImageLayer` | 3D | 在球面上叠加单张图像（`image`/`bounds`/`opacity`/`subdivisions`） |
| `GlobeVectorLayer` | 3D | 球面矢量：线/面/点/标签，含地平线裁剪与大圆致密化 |
| `StyleVectorLayer` | 2D/3D | MapLibre 式样式矢量，`.ofSources` 可聚合多源 |
| `MvtVectorLayer` | 2D/3D | MVT/PBF 矢量瓦片：解码→分桶→批绘，含回退与重试 |

辅助构造（来自 `geo_map_core` re-export）：

- `buildGraticule()`：经纬网
- `buildTissot()`：Tissot 指示圈（变形可视化）
- `buildGreatCircle()`：大圆路径
- `densifyPath()`：路径点加密（球面插值）
- `GlobePolyline` / `GlobePolygonShape` / `GlobeLabel`：球面几何与标注

---

## 5. 要素查询（queryRenderedFeatures）

把"点到了什么"交给 SDK：**注册你正在绘制的要素**，再用 `GeoFeatureRegistry` 查询。
对标 MapLibre 的 `queryRenderedFeatures`。

### 5.1 快速上手

```dart
// 注册表由宿主自己持有：它是**快照**而非 observable，数据变了就重建。
final registry = GeoFeatureRegistry()
  // 传与 StyleVectorLayer 用的**同一批** GeoJsonFeature
  ..setSource('airports', airportFeatures);

GeoMap(
  options: GeoMapOptions(initialCenter: const LatLng(35, 105), initialZoom: 4),
  source: tileSource,
  controller: controller,
  onTap: (latLng) {
    final hits = registry.queryFeatures(latLng, controller: controller);
    for (final hit in hits) {
      debugPrint('${hit.sourceId} / ${hit.feature.id}  ${hit.distancePx}px');
    }
  },
  children: const [],
);
```

### 5.2 API

| 成员 | 说明 |
| --- | --- |
| `GeoFeatureRegistry()` | 建一个注册表 |
| `setSource(sourceId, features, {visible, layerId, pointRadiusPx})` | 注册/替换某个来源的要素 |
| `removeSource(sourceId)` · `clear()` | 移除来源 / 清空 |
| `containsSource(id)` · `sourceIds` · `length` | 查看注册状态 |
| `queryFeatures(tap, {controller, pointRadiusPx, sourceIds, geometries, limit})` | 查询命中 |
| `GeoQueryHit.feature` | 命中的 `GeoJsonFeature`（含 id 与 properties，原样带回） |
| `GeoQueryHit.sourceId` | 命中的来源 id |
| `GeoQueryHit.distancePx` | 点要素的屏幕距离（px）；面要素为 `null` |

`visible: false` 的来源整体不可命中 —— 关掉的图层不该被点到。

### 5.3 两种命中策略（按几何类型自动分派）

| 几何 | 策略 | 半径/容差 | 为什么 |
| --- | --- | --- | --- |
| 点（`PointGeometry`） | **屏幕空间**：投影后比像素距离 | `pointRadiusPx`（默认 24px） | 判定与"眼睛看到的那个圆点"一致，缩放时手感不变 |
| 面（`PolygonGeometry` / `MultiPolygonGeometry`） | **地理空间**：经纬度平面 point-in-polygon | 边界容差 `1e-7°` | 与缩放/平移/世界副本/球面遮挡无关，跨 ±180° 也准 |
| 线（`LineStringGeometry` / `MultiLineStringGeometry`） | **v1 不命中** | — | 尚未实现；命中列表里不会出现线要素 |

### 5.4 命中顺序（可以依赖）

1. 按来源分组，来源顺序 = 注册顺序；
2. 同来源内**点要素在前**，按屏幕距离升序，**等距时后注册者在前**（"上层优先"，与绘制顺序一致 —— 点到的就是眼睛看到的那一个）；
3. 同来源内**面要素在后**，按注册顺序。

所以"取最近的一个点"就是取该来源的第一条命中；"取全部重叠的面"则是该来源的全部面命中。

### 5.5 边界、日界线与球面语义

- **外环边界算命中**；**洞的边界不算**（洞优先）。
- 判定用 **even-odd 规则**，环的绕向无关 —— 洞即使与外环同绕向也依然是洞。
- 跨 ±180° 的多边形：查询经度取**落在环解缠窗口内的唯一副本**，而不是"挪到与首点同一副本"。后者在经度跨度 > 180° 的宽环上会漏命中（旧的手写实现正是如此）。
- 平面模式下拾取用 `projectForVector`，把经度折到**最近的世界副本**：相机在 −179°、要素在 +179° 时也能点中（普通 `project` 不折，会把要素放到一整个世界之外）。
- 球面模式下**背面的要素不会被命中**（`project` 返回的 `(−1e6, −1e6)` 哨兵会被识别）。注意 `isVisible` 的阈值与 `project` 不一致，**不能拿它替代哨兵检查**。

### 5.6 与 MapLibre 的差异

| MapLibre | geo_map |
| --- | --- |
| `queryRenderedFeatures` 按屏幕 bbox 查询 | 按几何类型分派：点 = 屏幕半径，面 = 地理空间 |
| 结果是"渲染出的要素"（含 MVT 瓦片要素） | v1 只查**注册过的** GeoJSON 要素；MVT 瓦片要素查询尚未实现 |
| `setFeatureState` / 高亮 | v1 未实现（选中态由宿主自己管理） |
| 按 `layer` 过滤 | v1 支持 `sourceIds` 与 `geometries` 过滤 |

### 5.7 完整例子

```dart
class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  late final GeoMapController _controller = GeoMapController(useGlobe: false);
  final GeoFeatureRegistry _registry = GeoFeatureRegistry();

  @override
  Widget build(BuildContext context) {
    // 数据/可见性变了就重建注册表 —— 它是快照，永远与画面一致。
    _registry
      ..setSource('airports', ref.watch(airportFeaturesProvider))
      ..setSource('sigmet', ref.watch(sigmetFeaturesProvider));

    return GeoMap(
      options: GeoMapOptions(
        initialCenter: const LatLng(35, 105),
        initialZoom: 4,
      ),
      source: ref.watch(mapTileSourceProvider),
      controller: _controller,
      onTap: (latLng) {
        final hits = _registry.queryFeatures(latLng, controller: _controller);
        if (hits.isEmpty) return;

        // 点要素：取最近的一个（命中顺序保证第一条就是最近的）。
        final dots = hits.where((h) => h.distancePx != null).toList();
        if (dots.isNotEmpty) {
          showAirportSheet(dots.first.feature.id!);
        }
        // 面要素：可能多个（重叠的 SIGMET 区域）。
        final areas = hits.where((h) => h.distancePx == null).toList();
        if (areas.isNotEmpty) {
          showSigmetSheet(areas.map((h) => h.feature.id!).toList());
        }
      },
      children: const [],
    );
  }
}
```

---

## 6. 使用场景

下面给出 10 个典型场景，每个都附带可直接使用的 Dart 示例。

### A. 离线底图（MBTiles）

```dart
final source = await MbtilesTileSource.open('basemap', 'assets/maps/basemap.mbtiles');

GeoMap(
  options: GeoMapOptions(initialCenter: LatLng(30, 114), initialZoom: 4, useGlobe: false),
  source: source,
  children: const [],
);
```

### B. 在线 XYZ 底图

```dart
GeoMap(
  options: GeoMapOptions(initialCenter: LatLng(0, 0), initialZoom: 2, useGlobe: true),
  source: HttpTileSource.osm(),
  children: const [],
);
```

### C. 限制区（球面多边形，含地平线裁剪）

```dart
GlobeVectorLayer(
  polygons: [
    GlobePolygonShape(coordinates: [
      [LatLng(20, 100), LatLng(40, 100), LatLng(40, 130), LatLng(20, 130)],
    ]),
  ],
  fillColor: Colors.red.withOpacity(0.25),
  strokeColor: Colors.red,
);
```

### D. 经纬网 / 大圆

```dart
GlobeVectorLayer(
  lines: [buildGraticule(step: 15)],     // 每 15° 一条经纬线
);

// 或一条大圆航线
GlobeVectorLayer(
  lines: [buildGreatCircle(LatLng(30, 114), LatLng(35, 139))],
);
```

### E. 机场符号（点 + 标签）

```dart
GlobeVectorLayer(
  dots: [
    GlobeLabel(
      position: LatLng(30.58, 114.30),
      text: 'WUH',
      color: Colors.white,
    ),
  ],
);
```

### F. 雷达 / 卫星图像叠加（球面图像）

```dart
GlobeImageLayer(
  image: radarImageProvider,
  bounds: LatLngBounds(
    southwest: LatLng(20, 100),
    northeast: LatLng(40, 130),
  ),
  opacity: 0.6,
  subdivisions: 32, // 球面细分，越大越贴合曲面
);
```

### G. MVT 矢量瓦片

```dart
MvtVectorLayer(
  source: HttpTileSource(urlTemplate: 'https://tiles.example.com/{z}/{x}/{y}.pbf'),
  style: myVectorStyle, // GeoStyleController 或 StyleSpec
);
```

### H. 运行时改样式（MapLibre 式）

```dart
final style = GeoStyleController();

style.addLayer('roads', sourceId: 'basemap');
style.setPaintProperty('roads', 'line-color', '#ff8800');
style.setFilter('roads', ['==', 'class', 'motorway']);
style.setVisibility('roads', visible: true);
```

### I. 2D / 3D 切换

```dart
// 业务层：通过 Riverpod provider 切换，而非 controller.setMode
final isGlobe = ref.watch(mapUseGlobeProvider);
// 把 isGlobe 传给 GeoMapOptions.useGlobe，或在控制器初始化时决定
```

### J. 机场符号（图标 + 标签 + SDF 着色）

```dart
// 1) 先把雪碧图解成 SpriteAtlas（<name>.json + <name>.png）
final atlas = await SpriteAtlas.decode(
  json: await rootBundle.loadString('assets/sprite/sprite.json'),
  imageBytes: (await rootBundle.load('assets/sprite/sprite.png'))
      .buffer
      .asUint8List(),
);

// 2) 样式描述「图标在上、文字在下」
final style = StyleSpec.parse({
  'version': 8,
  'layers': [
    {
      'id': 'airports',
      'type': 'symbol',
      'source': 'poi',
      'source-layer': 'airport',
      'layout': {
        'icon-image': 'airport',
        'icon-size': 1.2,
        'icon-anchor': 'bottom',     // 图标盒挂到锚点上方
        'icon-offset': [0, -4],       // 像素
        'text-field': ['get', 'iata'],
        'text-size': 13,
        'text-anchor': 'top',         // 文字盒挂到锚点下方
        'text-offset': [0, 0.2],      // em（会乘 text-size）
      },
      'paint': {
        'text-color': '#ffffff',
        'text-halo-color': '#000000',
        'text-halo-width': 1.2,
        'icon-color': '#ffcc00',      // 仅 SDF 图标生效
      },
    },
  ],
});

StyleVectorLayer(
  style: style,
  features: airports,   // List<GeoJsonFeature>
  sprite: atlas,        // 没有它也能画，只是丢掉图标
);
```

> `rootBundle` 需要 `import 'package:flutter/services.dart';`。`SpriteAtlas.decode` 在图片解码失败时返回 `null` —— 此时图层照常绘制文字，仅丢掉图标，不会整层消失。

---

## 7. 样式系统

`StyleVectorLayer` 与 `MvtVectorLayer` 共享一套 MapLibre 风格的样式 API。静态声明走 `StyleSpec.parse(...)`，运行时改写走 `GeoStyleController` —— 二者等价，后者适合交互式图例/筛选。

### 7.1 `GeoStyleController`

```dart
final style = GeoStyleController(StyleSpec.parse({...}));
```

| 成员 | 说明 |
| --- | --- |
| `GeoStyleController(StyleSpec)` / `.document(StyleDocument)` | 构造 |
| `document` / `revision` | 当前文档；`revision` 只在文档真变化时递增 |
| `addSource(id, source)` / `removeSource(id)` | 增删数据源 |
| `addLayer(StyleLayer layer, {String? before})` | 新增图层；`before` 指定插入到某图层之前 |
| `removeLayer(id)` / `moveLayer(id, {before})` | 删除 / 调整层级顺序（数组顺序 = z-order） |
| `setPaintProperty(id, name, value)` | 改 paint 属性（颜色/宽度/透明度） |
| `setLayoutProperty(id, name, value)` | 改 layout 属性（锚点/偏移/旋转/可见性字段等） |
| `setFilter(id, filter)` | 设置过滤表达式 |
| `setLayerZoomRange(id, min, max)` | 限制图层生效的缩放区间 |
| `setVisibility(id, visibility)` | `'visible'` / `'none'` |

> 它是 `ChangeNotifier`，图层会自动监听重建。注意 `addLayer` 收的是 **`StyleLayer` 对象**，不是 `(id, sourceId)` 两个字符串。

### 7.2 symbol 属性速查

`type: 'symbol'` 图层即「图标 + 文字标注」。属性分 **layout**（放不放、放哪、多大）与 **paint**（什么颜色、多透明）两组，与 MapLibre v8 一致。下表是 `geo_map` **实际实现**的子集，默认值取自 `style_properties.dart`；表外属性不会被解析。

**layout**

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `text-field` | string（可 data-driven） | — | 标注文本，如 `['get', 'name']` |
| `text-size` | number | `16` | 字号（逻辑像素），可插值 |
| `text-anchor` | string | `'center'` | 文字盒挂在哪一侧，见 [6.3](#63-锚点九宫格) |
| `text-offset` | `[x, y]` | `[0, 0]` | 文字偏移，单位是 **em**（会乘 `text-size`） |
| `text-rotate` | number（度） | `0` | 文字旋转，叠加在线要素方向之上 |
| `text-allow-overlap` | bool | `false` | 允许压住已放置的标注 |
| `text-ignore-placement` | bool | `false` | 自己不占碰撞网格（但仍会被别人的盒子挡住） |
| `symbol-placement` | string | `'point'` | `'point'` 直立 / `'line'` 沿线，见 [6.4](#64-沿线标注) |
| `symbol-sort-key` | number（可 data-driven） | `0` | 越小越优先占位 |
| `icon-image` | string（可 data-driven） | — | 雪碧图名，取自 `SpriteAtlas` |
| `icon-size` | number | `1` | 图标缩放，可插值 |
| `icon-anchor` | string | `'center'` | 图标盒挂在哪一侧 |
| `icon-offset` | `[x, y]` | `[0, 0]` | 图标偏移，单位是 **像素** |
| `icon-rotate` | number（度） | `0` | 图标旋转 |
| `icon-allow-overlap` | bool | `false` | 同 `text-allow-overlap` |
| `icon-ignore-placement` | bool | `false` | 同 `text-ignore-placement` |
| `visibility` | string | `'visible'` | `'visible'` / `'none'` |

**paint**

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `text-color` | color | `#000000` | 文字颜色 |
| `text-opacity` | number | `1` | 透明度，同时乘进文字与 halo 的 alpha |
| `text-halo-color` | color | `rgba(0,0,0,0)` | 描边颜色 |
| `text-halo-width` | number | `0` | 描边**半径**；实际描边宽度是它的 2 倍 |
| `icon-color` | color | `#000000` | **仅对 SDF 图标生效**，见 [6.5](#65-sdf-图标着色) |

> **单位差异是高频坑**：`text-offset` 用 **em**（乘 `text-size`），`icon-offset` 用 **像素**（直用）。二者同名不同义。

### 7.3 锚点九宫格

`text-anchor` / `icon-anchor` 决定盒子从锚点往哪边展开。屏幕坐标 y 向下：

| 取值 | 盒子展开方向 | 中心相对锚点位移 |
| --- | --- | --- |
| `center` | 正中 | `(0, 0)` |
| `top` | 向下 | `(0, +h/2)` |
| `bottom` | 向上 | `(0, -h/2)` |
| `left` | 向右 | `(+w/2, 0)` |
| `right` | 向左 | `(-w/2, 0)` |
| `top-left` | 向右下 | `(+w/2, +h/2)` |
| `top-right` | 向左下 | `(-w/2, +h/2)` |
| `bottom-left` | 向右上 | `(+w/2, -h/2)` |
| `bottom-right` | 向左上 | `(-w/2, -h/2)` |

所以「图标在上、文字在下」是 `icon-anchor: 'bottom'` + `text-anchor: 'top'`（见场景 J）。

### 7.4 沿线标注

```json
{
  "id": "road-label",
  "type": "symbol",
  "source-layer": "roads",
  "layout": {
    "text-field": ["get", "name"],
    "symbol-placement": "line"
  }
}
```

设为 `'line'` 后不再按点取锚点，而是**逐线段取中点**，并把标注旋转到该段方向（`atan2`）。与 MapLibre 一致，当前是「一段一个标注」；`symbol-spacing` 仅预留参数，不做细分采样。

> 该能力在 **MVT**（`MvtVectorLayer`）路径上完整可用；GeoJSON（`StyleVectorLayer`）目前只处理点要素，沿线标注不会生效。

### 7.5 SDF 图标着色

`icon-color` 只对 **SDF** 雪碧图生效（`<sprite>.json` 中标记 `sdf: true` 的单通道图标），实现是把颜色以 `ColorFilter.mode(color, BlendMode.srcIn)` 叠到贴图通道上。

普通（非 SDF）图标即使设了 `icon-color` 也**保持原样** —— 与 MapLibre 一致，避免把彩色图标误染成纯色。

### 7.6 跨瓦片去重

同一个 POI 落在相邻瓦片的缓冲重叠区时会被解出两份。引擎用**世界经纬度**（量化到 1e-5°，约 1 米）作去重键：两份解出同一个键时只保留**先放置的那份**，另一份标记为 `duplicate` 且不占用碰撞网格。

这是自动行为，无需配置。沿线标注的中点同样会生成键，但不同瓦片对同一条线的采样相位不同、中点几乎不可能重合，因此不会误去重。

### 7.7 旋转与透明度

- `text-rotate` / `icon-rotate` 以**度**为单位（引擎内部转弧度），且**叠加**在 `symbol-placement: line` 的线段方向之上。
- 旋转后的碰撞盒取**轴对齐外接矩形（AABB）**。碰撞网格本身是轴对齐的，45° 时盒子会略微多占空间 —— 这是与 MapLibre 相同的近似，换取不必为旋转盒单独实现命中测试。
- `text-opacity` 同时乘进文字填充与 halo 的 alpha，并参与布局缓存 key。

### 7.8 图标集 SpriteAtlas

图标不走 `StyleSpec`（它不解析 `sprite` 字段），而是单独解码后由图层持有：

```dart
final atlas = await SpriteAtlas.decode(
  json: spriteJsonText,        // <name>.json
  imageBytes: spritePngBytes,  // <name>.png
);

StyleVectorLayer(style: style, features: feats, sprite: atlas);
// MvtVectorLayer 同样有 sprite 参数
```

| 成员 | 说明 |
| --- | --- |
| `SpriteAtlas.decode({json, imageBytes})` | 静态异步；解码失败返回 `null` |
| `atlas['icon-name']` | 取 `SpriteIcon?`（含 `sdf` 标记与像素尺寸） |
| `dispose()` | 释放 `ui.Image`，图层销毁时记得调用 |

绘制尺寸 = 精灵像素 ÷ `pixelRatio` × `icon-size`。图层拿到 `null` 时会照常绘制文字、只是丢掉图标。

---

## 8. 约束与踩坑

1. **`children` 不收指针事件**：手势被 `GlobeGestureOverlay` 拦截，交互 UI 必须放在 `GeoMap` 之外。
2. **平移重建全部 `children`**：`children` 应是轻量、由 `controller` 驱动的纯绘制层，避免重组件。
3. **2D/3D 不要直接调 `setMode`**：用 `mapUseGlobeProvider` 驱动。
4. **Web 不支持 `MbtilesTileSource.open`**：会抛异常，Web 端改用 `HttpTileSource`。
5. **瓦片层级要对齐**：`MbtilesTileSource.open` 会读取真实层级，请让 `options.minZoom/maxZoom` 与之匹配，否则空白。
6. **球面图像细分**：`GlobeImageLayer.subdivisions` 太小会在球面边缘出现明显折角，建议 16–64。
7. **大跨距线务必致密化**：跨半球/跨日期变更线的线要先用 `densifyPath` / `buildGreatCircle`，否则直线会被投影撕裂。
8. **符号的 offset 单位不一致**：`text-offset` 是 **em**（乘 `text-size`），`icon-offset` 是**像素**（直用）—— 同名不同义，见 [6.2](#62-symbol-属性速查)。
9. **`icon-color` 只染 SDF 图标**：普通彩色图标设了也不变色，这是与 MapLibre 一致的行为，见 [6.5](#65-sdf-图标着色)。
10. **沿线标注只对 MVT 生效**：`symbol-placement: 'line'` 在 GeoJSON 源上不会旋转标注，见 [6.4](#64-沿线标注)。

### 8.1 日界线与平面无限滚动

**平面无限滚动**：`FlatProjectionDelegate.panCenter` / `anchorCenter` 把相机经度 **wrap**
（不 clamp 到 ±180），东西方向可无限平移；栅格 `AffineGeometry.worldCopies`（-1..1）与矢量
`visibleWorldCopies` 负责重复世界副本，接缝无缝。等价 MapLibre 的 `worldCopyJump`。

**跨 ±180° 的 GeoJSON 填充**：`StyleVectorLayer` 平面分支先解缠经度得到连续屏幕 x
（`_projectContinuous`），再按可见世界副本平移重绘（`_drawWithCopies`），并对多环做绕向归
一化（`_normalizeRings`）。这等价 MapLibre 的 `getVisibleUnwrappedCoordinates` + 分切片，
跨日界线的多边形不会再被拉成一条横贯整屏的横带。

**`geo_map_core` 导出的反子午线工具**（现已由 `geo_map` 的 barrel 一并 re-export，
`import 'package:geo_map/geo_map.dart';` 即可拿到）：

| 函数 | 说明 |
| --- | --- |
| `unwrapLongitudes(List<double>) → List<double>` | 顺序解缠：相邻 delta 折到 ≤180°，跨日界线的环变连续 |
| `splitRingAtSeam(List<LatLng>, double seamLng) → List<List<LatLng>>` | 在指定经线（如 ±180°）用 Sutherland–Hodgman 把环拆成 1~2 段 |

> **要素命中测试已内置**：用 SDK 的 `GeoFeatureRegistry`（见
> [§ 5 要素查询](#5-要素查询queryrenderedfeatures)）—— 点要素按屏幕半径、面要素按
> 地理空间 point-in-polygon，跨 ±180° / 缩放 / 世界副本 / 球面遮挡都已处理，
> 不必自己写。

---

## 9. 与 app_client 的落地对照

`app_client`（Aero Weather）对 `geo_map` 的封装集中在 `lib/features/map/`：

| 关注点 | 实现位置 | 说明 |
| --- | --- | --- |
| 默认控制器 | `lib/features/map/providers/geo_map_controller_provider.dart` | 默认 2D、中心中国、稳定 Provider 实例 |
| 瓦片源注册 | `lib/features/map/providers/map_tile_source_provider.dart` | `MbtilesRegistryTileSource` 多包路由，稳定实例 |
| 2D/3D 开关 | `lib/features/map/providers/map_mode_provider.dart` | `mapUseGlobeProvider`，默认 `false` |
| 图层构造 | `lib/features/map/layers/layer_builder.dart` | `buildMapLayer` 穷举 `switch`（无 default，强制覆盖） |
| 真实图层范例 | `satellite_layer.dart` / `airport_symbol_layer.dart` / `restricted_area_layer.dart` | 卫星、机场符号、限制区 |
| 弹窗绑定 | `providers/map_feature_registry_provider.dart`（`popup:` 绑定）+ `aero_weather_layout.dart`（`GeoMapPopupHost`） | 面板/弹窗见 [10.3](#103-绑定式弹窗推荐) |

`MbtilesRegistryTileSource` 实现了 `GeoTileSource`，把多个 MBTiles 包按区域路由到统一源，是「自定义源」章节（[3.4](#34-自定义源)）的参考实现。

### 推荐用法骨架

```dart
class AeroMap extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(geoMapControllerProvider);
    final source = ref.watch(mapTileSourceProvider);
    final useGlobe = ref.watch(mapUseGlobeProvider);

    return GeoMap(
      options: GeoMapOptions(
        initialCenter: LatLng(35, 105),
        initialZoom: 4,
        useGlobe: useGlobe,
      ),
      source: source,
      controller: controller,
      children: ref.watch(mapLayersProvider).map(buildMapLayer).toList(),
    );
  }
}
```

---

## 10. 浮层 / 弹窗（Popup）

对标 MapLibre 的 `Popup`：**锚在一个经纬度上、随相机平移缩放跟着走**的卡片。
本包提供三层能力，从"只要定位"到"点了哪层弹哪张卡"依次叠加。

### 10.1 为什么不能放进 `GeoMap.children`

`children` 位于 `GeoMap` 内部的 opaque 手势层（`GlobeGestureOverlay`）之下，收不到指针。
所以**交互 UI 必须放在 `GeoMap` 外层的 `Stack` 里**，与地图平级、位于其后。
这也是本包所有弹窗 widget 唯一的硬约束。

### 10.2 三层结构：状态 / 定位 / 绑定

| 组件 | 职责 | 对应 MapLibre |
| --- | --- | --- |
| `GeoMapPopupController` | 只存**锚点**（`LatLng?`），`show/hide/toggle` | `Popup` 的 open/close 状态 |
| `GeoAnchoredPopup` / `GeoMapPopup` | 每帧重投影锚点、夹进 `keepOut`、渲染任意 child | `Popup.setLngLat()` + 自动 reposition |
| `GeoPopupController` + `GeoMapPopupHost` | 命中仲裁 + 按图层选卡片 | `map.on('click', layerId, handler)` |

纯定位层最小用法（自己管显隐、自己给内容）：

```dart
Stack(
  children: [
    GeoMap(controller: controller, onTap: ...),
    GeoMapPopup(
      controller: controller,
      popup: popup,                 // GeoMapPopupController
      cardSize: const Size(280, 240),   // 卡片最大尺寸，夹取用
      anchorSide: PopupAnchor.bottom,   // 可选，默认 bottom（卡片在锚点上方）
      keepOut: EdgeInsets.only(top: 54, left: 110, right: 85, bottom: 72),
      builder: (context, anchor) => MyCard(onClose: popup.hide),
    ),
  ],
);
```

布局是纯函数，可单独断言：

```dart
// 未夹取位置（逻辑像素）；tail 是卡片朝锚点那侧的尖角间距
final p = anchorOffsetFor(PopupAnchor.bottom, const Offset(100, 100), Size(80, 40), 8);
// p == Offset(60, 52)

// 再夹进 keepOut；锚点出屏 / 非有限 / 球面背半球哨兵（±1e6）→ visible:false
final layout = layoutAnchoredPopup(
  anchor: p, viewport: controller.viewport, card: const Size(80, 40),
  keepOut: const EdgeInsets.all(16),
);
if (layout.visible) { /* Positioned(left: layout.left, top: layout.top) */ }
```

投影分支已内置：平面走 `projectForVector`（折回最近的世界副本，跨日界线才准），
球面走 `project`（背半球返回哨兵 → 布局判隐藏）。宿主不必自己判背半球。

### 10.3 绑定式弹窗（推荐）

先给要素源声明"我点了弹什么"，再挂一个宿主，点击只调一个方法。

**① 绑定**——挂在 `setSource` 上，与要素同生命周期：

```dart
registry.setSource(
  'sigmet',
  features,
  visible: true,
  popup: GeoPopupBinding(
    priority: 10,                        // 重叠命中时的仲裁权重，大者胜
    cardSize: Size(280, 268),            // 夹取用的最大尺寸
    anchor: PopupAnchor.bottom,          // 卡片贴锚点哪一侧
    anchorOf: (hit) => null,             // 默认 null = 锚在点击点
    builder: (context, hit) => SigmetPopupCard(
      hits: [byId[hit.feature.id]!],     // hit 只带冠军那条
      onClose: popup.close,
    ),
  ),
);
```

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `priority` | `0` | 多处命中时大者胜；平手取查询结果里靠前的 |
| `cardSize` | 必填 | 卡片最大逻辑尺寸 |
| `anchor` | `bottom` | 九宫格（见 10.4） |
| `anchorOf` | `null` | 覆盖锚点；默认用**点击点**（`setLngLat(e.lngLat)` 语义） |
| `builder` | 必填 | 卡片构造器，拿 `hit.feature.id` 回查业务对象 |

读取：`registry.popupOf(sourceId)`。运行时挂载/卸载用
`popup.registerPopup(id, binding)` / `popup.unregisterPopup(id)`。

**② 宿主**——全局只挂一个：

```dart
GeoMapPopupHost(
  controller: mapController,
  popup: ref.watch(geoPopupControllerProvider),
  keepOut: EdgeInsets.only(top: 54, left: 110, right: 85, bottom: 72),
),
```

**③ 点击**——命中、仲裁、开关全在控制层：

```dart
popup.handleTap(
  tap,
  controller: mapController,
  registry: registry,
  hits: hits,        // 可选：宿主已查过就传进来，避免二次查询
  pointRadiusPx: GeoEngineTuning.featurePickRadiusPx,
);
```

`handleTap` 内部：`queryFeatures` → 过滤出注册了 binding 的源 → 按 `priority` 选冠军 →
`geoPopup.show(binding.anchorOf?.call(hit) ?? tap)` → 没赢家就 `close()`（closeOnClick）。

控制层**不持有**注册表（每次传 `registry`），所以不会读到旧快照，也不会与 Riverpod 的
`mapFeatureRegistryProvider` 形成循环依赖。渲染侧读 `activeBuilder` / `activeCardSize` /
`activeAnchor`，由宿主喂给 `GeoMapPopup`。

### 10.4 九宫格锚点

`PopupAnchor` 九档（对齐 MapLibre `PositionAnchor`）：

| 值 | 卡片位置 |
| --- | --- |
| `bottom`（默认） | 卡片在锚点**上方**，底边中点对齐 |
| `top` | 卡片在锚点**下方**，顶边中点对齐 |
| `left` / `right` | 卡片在锚点右/左侧，竖边中点对齐 |
| `center` | 中心对齐 |
| `topLeft` / `topRight` / `bottomLeft` / `bottomRight` | 四角对齐 |

与 symbol 的锚点（[7.3](#73-锚点九宫格)）语义一致，但**卡片的九档是"哪个边贴住锚点"**，
不含 `baseline` 之类的文字排版锚点。

### 10.5 约束与踩坑

1. **必须在 `GeoMap` 外层 Stack**（见 10.1），进 `children` 点不到。
2. **宿主只挂一个**：两个 `GeoMapPopupHost` 会画两份卡片（共用一个 popup 状态）。
3. **`cardSize` 写卡片真实最大尺寸**：写小了会被夹进 `keepOut` 后越界。
4. **`keepOut` 要覆盖所有固定 UI**：顶栏/侧栏/底栏/播放条都算，否则卡片被压在下面。
5. **`ChangeNotifierProvider` 会自动 dispose**：不要再 `ref.onDispose(c.dispose)`，
   否则容器销毁时 double dispose，debug 抛 `used after being disposed`。
6. **`builder` 只拿冠军 hit**：要"一张卡列出全部重叠"就自己用同一锚点再查一次
   （点击点即 `popup.geoPopup.anchor`）。
7. **`show` 幂等**：锚点相等不重复 `notifyListeners()`。

---

*文档基于 `geo_map` / `geo_map_core` 源码整理，API 以实际包导出为准。*

*同名 HTML 版由 `docs/build_api_html.py` 从本文件生成 —— 修改本文件后，执行 `python docs/build_api_html.py` 重新生成即可（样式在 `docs/api_style.css`）。*
