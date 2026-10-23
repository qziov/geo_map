# 架构

```
GeoMap (widget/geo_map.dart)          组装：InheritedModel(camera) + 图层 + 手势
  │
  ├─ vendor/flutter_map_camera/       ★ fork 提取的相机层（冻结快照）
  │    MapCamera · Crs(Epsg3857/4326) · MapProjectionDelegate（接口）
  │    GlobeProjectionDelegate（3D 正交）· FlatProjectionDelegate（2D 仿射）
  │
  ├─ globe/                           lab 已验证渲染图层
  │    GlobeTileLayer   3D 瓦片（单位球 mesh + over/under-zoom + 父级回退 + 极帽）
  │    FlatTileLayer    2D 瓦片（drawImageRect + 同套数据语义）
  │    GlobeVectorLayer 矢量（线/面/点/标签）+ buildGraticule/buildTissot
  │    GlobeImageLayer  影像叠加
  │
  ├─ gesture/globe_gesture_overlay    手势（pan/锚点捏合/双击/fling/tap/滚轮）
  ├─ source/mbtiles_source            MBTiles（WAL 自愈 + 真实层级探测）
  ├─ camera/geo_map_controller        控制器（持 MapCamera + delegate）
  └─ experimental/                    自研 Vertices 管线（P4 备选，未导出）
```

## 数据流

1. 手势 → `GeoMapController`（move/panBy/zoomAround）
2. 控制器同步 `MapCamera` 值对象 + `delegate.updateCamera(center, zoom, size)`
3. `notifyListeners` → `MapInheritedModel` 重建 → 图层 painter 取 `MapCamera.of(context)`
4. 图层 painter：选片（over/under-zoom clamp）→ 父级回退（UV 子矩形）→ 渲染集垫底 → 绘制

## 关键机制

| 机制 | 说明 |
| --- | --- |
| over/under-zoom | 数据层级 = round(cameraZoom) 钳到真实有瓦层级；绘制尺寸按 cameraZoom 缩放 |
| 父级回退 | 瓦片缺失走祖先链，UV 取子矩形；缺失即请求，2 次失败拉黑 |
| 渲染集垫底 | 缩放切换时旧渲染集先画（`addRenderTile` 必须在命中判定后，防空集污染） |
| 极帽 | mercator 数据止于 ±85.05°，行边缘 1px 向极点拉伸 |
