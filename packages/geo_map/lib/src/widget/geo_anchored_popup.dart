/// 锚定某个经纬度、随地图平移/缩放移动的浮层（对标 MapLibre
/// `new Popup().setLngLat()`）。
///
/// 为什么不放在 `GeoMap.children`：children 位于 opaque 手势层（`GlobeGestureOverlay`）
/// 之下，收不到指针；交互 UI 必须放在 `GeoMap` 外层的 `Stack` 里（见
/// `GeoMap` 的 build）。本 widget 设计为**纯展示容器**：宿主负责决定何时显示
/// （以及 anchor 取哪个地理点），并把任意业务卡片作为 [child] 传入。
///
/// 投影分支（关键，否则跨日界线/球面会错位）：
/// - 平面：用 [FlatProjectionDelegate.projectForVector] —— 经度折回离相机最近的世界副本；
/// - 球面：用 [MapProjectionDelegate.project] —— 背半球/临界带返回哨兵（±1e6），
///   交给 [layoutAnchoredPopup] 判 `visible:false`，避免气泡贴在地球边缘。
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../camera/geo_map_controller.dart';
import '../vendor/flutter_map_camera/flat_projection_delegate.dart'
    show FlatProjectionDelegate;
import '../vendor/flutter_map_camera/projection_delegate.dart'
    show MapProjectionDelegate;

/// 纯布局结果（`left/top` 是逻辑像素）。
class AnchoredPopupLayout {
  const AnchoredPopupLayout({
    required this.left,
    required this.top,
    required this.visible,
  });

  static const hidden = AnchoredPopupLayout(left: 0, top: 0, visible: false);

  /// 卡片左上角相对视口的偏移。
  final double left;

  /// 卡片左上角相对视口的偏移。
  final double top;

  /// 是否应显示（锚点出屏/非有限/被遮挡时为 false）。
  final bool visible;
}

/// 计算卡片左上角：卡片**底边中点**对准 [anchor]，再夹进 [keepOut]。
///
/// [anchor] / [viewport] / [card] 都是逻辑像素。锚点出屏、非有限、或球面背半球
/// 哨兵（`±1e6`）时返回 `visible:false`。宿主据此决定是否渲染卡片。
AnchoredPopupLayout layoutAnchoredPopup({
  required Offset anchor,
  required Size viewport,
  required Size card,
  required EdgeInsets keepOut,
  double tail = 8,
  double slop = 32,
}) {
  if (viewport.isEmpty || !anchor.dx.isFinite || !anchor.dy.isFinite) {
    return AnchoredPopupLayout.hidden;
  }
  // 球面背半球 `project` 返回 (-1e6,-1e6)，而 isVisible 在临界带仍可能为 true，
  // 这里用视口倍数的硬阈值兜住。
  if (anchor.dx.abs() > viewport.width * 4 ||
      anchor.dy.abs() > viewport.height * 4) {
    return AnchoredPopupLayout.hidden;
  }
  if (anchor.dx < -slop ||
      anchor.dy < -slop ||
      anchor.dx > viewport.width + slop ||
      anchor.dy > viewport.height + slop) {
    return AnchoredPopupLayout.hidden;
  }
  final maxLeft = (viewport.width - keepOut.right - card.width)
      .clamp(keepOut.left, viewport.width);
  final maxTop = (viewport.height - keepOut.bottom - card.height)
      .clamp(keepOut.top, viewport.height);
  final left = (anchor.dx - card.width / 2).clamp(keepOut.left, maxLeft);
  final top = (anchor.dy - card.height - tail).clamp(keepOut.top, maxTop);
  return AnchoredPopupLayout(left: left, top: top, visible: true);
}

/// 跟随地图的浮层：每次相机变化重新投影 [anchor] 并重定位 [child]。
///
/// 纯展示容器——宿主自行决定 [anchor]（如点击命中的地理点）与 [child]（业务卡片）。
class GeoAnchoredPopup extends StatelessWidget {
  const GeoAnchoredPopup({
    super.key,
    required this.controller,
    required this.anchor,
    required this.child,
    required this.keepOut,
    required this.cardSize,
  });

  final GeoMapController controller;
  final LatLng anchor;
  final Widget child;
  final EdgeInsets keepOut;

  /// 用于夹取的卡片逻辑尺寸（实际卡片可更小）。
  final Size cardSize;

  Offset _project() {
    final MapProjectionDelegate d = controller.delegate;
    // 平面用 projectForVector：折回离相机最近的世界副本（跨日界线才准）；
    // 球面用 project：被遮挡返回哨兵，交给布局判 hidden。
    return d is FlatProjectionDelegate
        ? d.projectForVector(anchor)
        : d.project(anchor);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.viewport.isEmpty) return const SizedBox.shrink();
        if (!controller.delegate.isVisible(anchor)) {
          return const SizedBox.shrink();
        }
        final layout = layoutAnchoredPopup(
          anchor: _project(),
          viewport: controller.viewport,
          card: cardSize,
          keepOut: keepOut,
        );
        if (!layout.visible) return const SizedBox.shrink();
        return Positioned(
          left: layout.left,
          top: layout.top,
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        );
      },
    );
  }
}

/// 跟随地图的浮层显隐状态（对标 MapLibre `Popup` 的 open/close）。
///
/// 只持有**锚点**：内容由宿主通过 [GeoMapPopup.builder] 注入。状态因此与业务
/// 完全解耦，SIGMET / 机场 / POI 等任意图层共用同一套"显示—关闭"逻辑。
class GeoMapPopupController extends ChangeNotifier {
  LatLng? _anchor;

  /// 当前锚点；`null` 表示浮层隐藏。
  LatLng? get anchor => _anchor;

  /// 是否处于打开状态。
  bool get isOpen => _anchor != null;

  /// 在 [anchor] 处打开（覆盖式：重复 open 同一锚点幂等）。
  void show(LatLng anchor) {
    if (_anchor == anchor) return;
    _anchor = anchor;
    notifyListeners();
  }

  /// 关闭浮层（锚点置空）。
  void hide() {
    if (_anchor == null) return;
    _anchor = null;
    notifyListeners();
  }

  /// 点同一锚点切换开/关（MapLibre `togglePopup` 语义）。
  void toggle(LatLng anchor) => isOpen ? hide() : show(anchor);
}

/// 把 [GeoMapPopupController] 的显隐状态接到 [GeoAnchoredPopup] 上。
///
/// 自监听 [popup]：调用 `popup.show/hide` 即自动重绘，宿主无需在父级 `watch`。
/// 业务内容通过 [builder]（入参含锚点）注入——这就是留给宿主的"接口"：在此
/// 返回自己的卡片（含关闭按钮，关闭按钮调用 [GeoMapPopupController.hide]）。
class GeoMapPopup extends StatelessWidget {
  const GeoMapPopup({
    super.key,
    required this.controller,
    required this.popup,
    required this.builder,
    required this.keepOut,
    required this.cardSize,
  });

  /// 地图相机（用于每帧重投影锚点）。
  final GeoMapController controller;

  /// 浮层显隐状态。
  final GeoMapPopupController popup;

  /// 业务内容构造器：给定锚点，返回卡片。
  final Widget Function(BuildContext context, LatLng anchor) builder;

  /// 留白区（顶栏 / 侧栏 / 底栏尺寸），浮层不会盖进去。
  final EdgeInsets keepOut;

  /// 用于夹取的卡片逻辑尺寸（实际卡片可更小）。
  final Size cardSize;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: popup,
      builder: (context, _) {
        final anchor = popup.anchor;
        if (anchor == null) return const SizedBox.shrink();
        return GeoAnchoredPopup(
          controller: controller,
          anchor: anchor,
          keepOut: keepOut,
          cardSize: cardSize,
          child: builder(context, anchor),
        );
      },
    );
  }
}
