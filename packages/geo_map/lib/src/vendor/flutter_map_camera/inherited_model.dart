/// Minimal stand-in for flutter_map's `MapInheritedModel`: only the camera
/// lookup (`maybeCameraOf`) that the vendored `MapCamera.of` needs.
library;

import 'package:flutter/widgets.dart';

import 'camera.dart';

class MapInheritedModel extends InheritedWidget {
  const MapInheritedModel({
    required this.camera,
    required super.child,
    super.key,
  });

  final MapCamera camera;

  static MapInheritedModel? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapInheritedModel>();

  static MapCamera? maybeCameraOf(BuildContext context) =>
      maybeOf(context)?.camera;

  @override
  bool updateShouldNotify(MapInheritedModel oldWidget) =>
      camera != oldWidget.camera;
}
