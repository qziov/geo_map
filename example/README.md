# geo_map example

演示工程，两条入口：

| 入口 | 目标平台 | 内容 |
| --- | --- | --- |
| `lib/main.dart` | **web** / desktop / mobile | 可运行 demo 画廊（4 个页面） |
| `lib/native/mbtiles_demo.dart` | **仅 native**（`dart:io` + sqlite3） | MBTiles 离线底图 |

```bash
flutter pub get

# 浏览器
flutter run -d chrome
# 或产出静态站点
flutter build web --release   # → build/web

# 只能在本机跑的 MBTiles 示例
flutter run -t lib/native/mbtiles_demo.dart -d windows
```

## 可运行的页面（`lib/demos/`）

| 页面 | 覆盖的 API | 依赖 |
| --- | --- | --- |
| `mvt_demo.dart` | `MvtVectorLayer`（fill / line / `line-dasharray` / 数据驱动着色 / 世界副本 / 地平线裁剪） | demotiles 网络瓦片 |
| `style_demo.dart` | `StyleVectorLayer` + style spec（filter、zoom 插值） | 零网络 |
| `overlay_demo.dart` | `GlobeVectorLayer`、`buildGraticule`、`buildTissot`、`buildGreatCircle`、`densifyPath` | 零网络 |
| `projection_demo.dart` | `GeoMapOptions.useGlobe` 2D/3D 切换、`DebugTilesSource` 摆放校验 | 零网络 |

底图统一用离线的 `DebugTilesSource`：它把 `z/x/y` 画在瓦片上，所以瓦片边界、
矢量几何、投影三者是否对齐，一屏之内就能看出来。

## 为什么 MBTiles 不能上 web

`MbtilesTileSource` 需要 `dart:io`（把资产拷到可写目录）和 sqlite3（原生库）。
浏览器里两者都不存在。为了不让这个依赖把整包拖下水：

- HTTP 传输拆成了条件实现 —— `lib/src/platform/http_get.dart`
  在 io 上走共享 `HttpClient`，在 web 上走 XHR；
- `mbtiles_source.dart` 通过条件导出让位给 `mbtiles_source_stub.dart`，
  web 上类型仍在、调用即抛 `UnsupportedError`。

所以 `package:geo_map/geo_map.dart` 可以在浏览器里直接 import —— 这一点由
`flutter build web` 本身验证，不靠人工保证。

已知边界：web 传输用 `dart:html`（XHR），**JS 后端可用，wasm 后端暂不支持**
（`flutter build web --wasm` 会报 `dart:html` 不可用）。要上 wasm 时把
`lib/src/platform/http_get_web.dart` 换成 `package:web` + `fetch` 即可，其余代码不用动。

## 放自己的 MBTiles

```bash
mkdir -p assets/tiles
cp /path/to/your/base.mbtiles assets/tiles/base.mbtiles
# 然后改 lib/native/mbtiles_demo.dart 里的 assetPath
```
