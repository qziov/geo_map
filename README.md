# geo_map

A self-contained 2D/3D Flutter map engine — **zero flutter_map dependency**.

- **2D**：Web Mercator 平面（仿射瓦片）
- **3D**：正交球面（globe），含极帽填充、地平线剔除、父级瓦片回退
- **一键切换**：`GeoMapOptions(useGlobe: false)`，center/zoom 连续，
  且 2D/3D **共用同一份瓦片缓存**（切换零成本）
- **可插拔投影**：所有渲染通过 `MapProjectionDelegate` 接口，新增投影只需一个类
- **MBTiles 离线底图**：WAL 自愈、真实层级探测（不信任 metadata）
- **over/under-zoom**：数据层级不足时自动钳制到最近有瓦层级并缩放绘制
  （MapLibre overscale 语义），缺失瓦片自动回退父级（UV 子矩形）
- **404 不拉黑**：失败分级 + 退避重试，缺瓦只会变模糊，不会变黑

## 包结构

| 包 | 内容 |
| --- | --- |
| `packages/geo_map` | Flutter 壳：`GeoMap` widget、统一渲染栈、手势、MBTiles 源、vendored camera |
| `packages/geo_map_core` | 纯 Dart 数学核心（投影/相机/网格/选片/极帽/请求计划/回退/URL），189 项测试，无 `dart:ui` |

`packages/geo_map_core` 里的投影、网格与选片是**唯一的真相源**：2D 与 3D
共用同一条 `TileDraw` 管线，只有"像素落在哪里"由几何后端决定
（`SphericalGeometry` / `AffineGeometry`）—— 一个模式的修复不可能让另一个模式
继续坏着。

`lib/src/vendor/flutter_map_camera/` 内含从 flutter_map（12 补丁 fork）提取的
`MapCamera` + 投影委托层 —— 冻结快照，**零上游依赖**（flutter_map/proj4dart 均
不出现在依赖中）。BSD-3-Clause，上游版权声明保留。

## Quick start

```dart
import 'package:geo_map/geo_map.dart';

final source = await MbtilesTileSource.open(
  id: 'base',
  assetPath: 'assets/tiles/base.mbtiles',
);

GeoMap(
  options: const GeoMapOptions(
    initialCenter: LatLng(30, 105),
    initialZoom: 4.2,
    minZoom: 2,
    maxZoom: 8,
    useGlobe: true,          // false = 2D 平面
  ),
  source: source,
  onTap: (latLng) => debugPrint('$latLng'),
  children: [
    GlobeVectorLayer(lines: buildGraticule()),   // 经纬网
    GlobeVectorLayer(lines: buildTissot()),      // 投影变形指示圈
  ],
)
```

依赖：只有用到 `MbtilesTileSource` 时才需要 `sqlite3_flutter_libs`（原生 SQLite）+
`path_provider`。HTTP 传输是条件实现（io 走 `HttpClient`，web 走 XHR），
所以 `package:geo_map/geo_map.dart` 在浏览器里可直接 import；MBTiles 在 web 上
是 stub，调用即抛 `UnsupportedError`。

完整可运行示例见 [`example/`](example/)：
- `lib/main.dart` —— **web 可运行**的画廊（MVT 矢量 / 样式图层 / 球面叠加 / 投影切换）；
- `lib/native/mbtiles_demo.dart` —— 仅 native 的 MBTiles 离线底图。

## 文档

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — 分层与数据流
- [MAPLIBRE_ALIGNMENT.md](docs/MAPLIBRE_ALIGNMENT.md) — 与 MapLibre 的接口对齐表与演进路线
- API 文档（中文入口）：[qziov.github.io/geo_map](https://qziov.github.io/geo_map/)（CI 自动发布，见 `.github/workflows/docs.yml`；API 参考正文与界面为英文）

## 路线图

- [x] 3D globe + 2D mercator + 一键切换
- [x] MBTiles 离线 + over/under-zoom + 父级回退
- [x] Web 可编译（HTTP 传输条件实现；MBTiles 走 stub）
- [x] M1: style spec JSON + 表达式求值器（参照 maplibre-gl-js）
- [x] M2: 矢量瓦片 MVT + fill/line bucket（参照 maplibre-native）
- [ ] M2 收尾: fill-outline、symbol 前置的分桶整理
- [ ] GPU 后端（draw plan 抽取）
- [ ] M3: symbol 碰撞检测与标注避让
- [ ] 三端（Android/iOS/鸿蒙）打包验证

## Development

```bash
cd packages/geo_map_core && dart pub get && dart analyze && dart test
cd packages/geo_map      && flutter pub get && flutter analyze lib

# 示例：web 构建同时是“整包能不能在浏览器里编译”的验收
cd example && flutter pub get && flutter build web --release
```

## License

BSD-3-Clause（含 flutter_map 派生代码声明，见 [LICENSE](LICENSE)）。
