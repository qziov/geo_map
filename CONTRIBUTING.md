# Contributing

## 开发环境

- Flutter >= 3.24（Dart >= 3.6）

## 常用命令

```bash
cd packages/geo_map_core
dart pub get && dart analyze && dart test   # 纯 Dart 核心回归

cd packages/geo_map
flutter pub get && dart analyze             # Flutter 壳

# 宿主（开发用，含 example 同款代码）
cd ../globe_lab && flutter run -t lib/main_geo.dart -d windows
```

## 约定

1. **常量进 `geo_engine_tuning.dart`**（core），渲染/手势不得散落魔法数
2. **投影器无状态**：所有实现走 `MapProjectionDelegate`，相机作为参数
3. **渲染缺陷必须先写失败测试**（core 可测的部分）或带 `[geo_map:*]` 诊断日志复现
4. **vendored 目录**（`lib/src/vendor/flutter_map_camera/`）保持与上游 fork 的
   可 diff 性——除 import/剥离外不做风格化改动
5. 提交信息用 conventional commits（feat/fix/docs/chore）

## 测试基线

- `geo_map_core` 82+ 测试全绿
- 宿主冒烟：Windows 运行 15 秒无异常日志
