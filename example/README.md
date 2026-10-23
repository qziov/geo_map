# geo_map example

```bash
# 1. 放入你的 MBTiles 底图
mkdir -p assets/tiles
cp /path/to/your/base.mbtiles assets/tiles/base.mbtiles

# 2. 运行
flutter pub get
flutter run -d windows   # 或 android / 任意目标
```

功能：3D 球面 / 2D 平面一键切换（center/zoom 连续）、经纬网、
over/under-zoom（数据层级不足自动钳制 + 父级瓦片回退）。
