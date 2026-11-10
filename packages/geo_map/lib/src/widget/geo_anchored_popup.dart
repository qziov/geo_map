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
import '../camera/projection_mode.dart' show projectMapPoint;
import '../vendor/flutter_map_camera/projection_delegate.dart'
    show MapProjectionDelegate;
import 'geo_popup_binding.dart';

/// 卡片子树的稳定 key：显隐切换时让 Element / RenderObject 保持同一身份。
const _kPopupCardKey = ValueKey<String>('geo_popup_card');

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

/// 卡片左上角的「未夹取」位置（九宫格）。
///
/// 给定投影后的锚点 [point] 与卡片尺寸 [card]，返回卡片左上角应处的逻辑像素，
/// 再交由 [layoutAnchoredPopup] 夹进 [EdgeInsets]。[tail] 是卡片朝向锚点那一侧
/// 留出的小尖角间距（仅 top/bottom/left/right 用；四角忽略）。
///
/// 纯函数，可纯 Dart 断言测试。
Offset anchorOffsetFor(PopupAnchor side, Offset point, Size card, double tail) {
  final w = card.width;
  final h = card.height;
  switch (side) {
    case PopupAnchor.center:
      return Offset(point.dx - w / 2, point.dy - h / 2);
    case PopupAnchor.top: // 卡片在锚点下方
      return Offset(point.dx - w / 2, point.dy + tail);
    case PopupAnchor.bottom: // 卡片在锚点上方（默认，保持旧行为）
      return Offset(point.dx - w / 2, point.dy - h - tail);
    case PopupAnchor.left: // 卡片在锚点右侧
      return Offset(point.dx + tail, point.dy - h / 2);
    case PopupAnchor.right: // 卡片在锚点左侧
      return Offset(point.dx - w - tail, point.dy - h / 2);
    case PopupAnchor.topLeft:
      return Offset(point.dx + tail, point.dy + tail);
    case PopupAnchor.topRight:
      return Offset(point.dx - w - tail, point.dy + tail);
    case PopupAnchor.bottomLeft:
      return Offset(point.dx + tail, point.dy - h - tail);
    case PopupAnchor.bottomRight:
      return Offset(point.dx - w - tail, point.dy - h - tail);
  }
}

/// 计算卡片左上角：按 [anchorSide] 九宫格把卡片某一侧对准 [anchor]，再夹进 [keepOut]。
///
/// [anchor] / [viewport] / [card] 都是逻辑像素。锚点出屏、非有限、或球面背半球
/// 哨兵（`±1e6`）时返回 `visible:false`。宿主据此决定是否渲染卡片。
///
/// [anchorSide] 默认 [PopupAnchor.bottom]，与旧行为（底边中点对准锚点）一致；
/// 其余八档见 [PopupAnchor]。
AnchoredPopupLayout layoutAnchoredPopup({
  required Offset anchor,
  required Size viewport,
  required Size card,
  required EdgeInsets keepOut,
  PopupAnchor anchorSide = PopupAnchor.bottom,
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
  final unclamped = anchorOffsetFor(anchorSide, anchor, card, tail);
  final maxLeft = (viewport.width - keepOut.right - card.width)
      .clamp(keepOut.left, viewport.width);
  final maxTop = (viewport.height - keepOut.bottom - card.height)
      .clamp(keepOut.top, viewport.height);
  final left = unclamped.dx.clamp(keepOut.left, maxLeft);
  final top = unclamped.dy.clamp(keepOut.top, maxTop);
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
    this.anchorSide = PopupAnchor.bottom,
  });

  final GeoMapController controller;

  /// 锚点；`null` 表示强制隐藏。
  ///
  /// 隐藏时仍返回同一个 `Positioned` + `Offstage` 结构，只切 `offstage`，
  /// 以免 Stack 子节点在两种 RenderObject 之间翻转（见 [build] 注释）。
  final LatLng? anchor;

  final Widget child;
  final EdgeInsets keepOut;

  /// 用于夹取的卡片逻辑尺寸（实际卡片可更小）。
  final Size cardSize;

  /// 卡片贴锚点的哪一侧（九宫格）。默认 [PopupAnchor.bottom]（卡片在锚点上方）。
  final PopupAnchor anchorSide;

  Offset _project(LatLng a) {
    final MapProjectionDelegate d = controller.delegate;
    // 平面用 projectForVector：折回离相机最近的世界副本（跨日界线才准）；
    // 球面用 project：被遮挡返回哨兵，交给布局判 hidden。
    // T5d: 分支收口到 projectMapPoint，语义完全不变。
    return projectMapPoint(d, a);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final a = anchor;
        final layout = (a == null ||
                controller.viewport.isEmpty ||
                !controller.delegate.isVisible(a))
            ? AnchoredPopupLayout.hidden
            : layoutAnchoredPopup(
                anchor: _project(a),
                viewport: controller.viewport,
                card: cardSize,
                keepOut: keepOut,
                anchorSide: anchorSide,
              );

        // 关键：**恒定**返回 Positioned，只切 Offstage。
        //
        // 旧实现在「隐藏」时返回 SizedBox.shrink()、「显示」时返回 Positioned，
        // 让 Stack 的同一个子节点在两种 RenderObject 之间反复 attach/detach；
        // Flutter 3.47 的语义树会在这种翻转后残留 `_SemanticsParentData`
        // （debug 下每帧报 `!semantics.parentDataDirty`）。
        // Offstage 始终挂载子树：offstage 时 hitTest 返回 false、不 paint，
        // 且 `visitChildrenForSemantics` 直接跳过，语义上等价于隐藏。
        return Positioned(
          left: layout.left,
          top: layout.top,
          child: Offstage(
            key: const ValueKey('geo_anchored_popup'),
            offstage: !layout.visible,
            child: Material(
              type: MaterialType.transparency,
              // 浮层作为独立覆盖层：吞掉内部点击，避免漏给下面的地图
              // （对齐 MapLibre Popup 的 DOM 事件隔离）。内层按钮更深，仍优先。
              // excludeFromSemantics：该层只负责拦截、没有可读内容；保留命中
              // 行为，但不往语义树里塞 RenderSemanticsGestureHandler。
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () {},
                child: KeyedSubtree(key: _kPopupCardKey, child: child),
              ),
            ),
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

  bool _disposed = false;

  /// 是否已 dispose（语义同 `GeoPopupController.isDisposed`：Riverpod 的
  /// `invalidateSelf()` —— hot reload 改到 provider 源码时的常规路径 —— 会
  /// 先 dispose 再重建，这段窗口内的 `show/hide` 必须安静丢弃）。
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 当前锚点；`null` 表示浮层隐藏。
  LatLng? get anchor => _anchor;

  /// 是否处于打开状态。
  bool get isOpen => _anchor != null;

  /// 在 [anchor] 处打开（覆盖式：重复 open 同一锚点幂等）。
  void show(LatLng anchor) {
    if (_disposed || _anchor == anchor) return;
    _anchor = anchor;
    _safeNotify();
  }

  /// 关闭浮层（锚点置空）。
  void hide() {
    if (_disposed || _anchor == null) return;
    _anchor = null;
    _safeNotify();
  }

  /// 点同一锚点切换开/关（MapLibre `togglePopup` 语义）。
  void toggle(LatLng anchor) => isOpen ? hide() : show(anchor);
}

/// 把 [GeoMapPopupController] 的显隐状态接到 [GeoAnchoredPopup] 上。
///
/// 自监听 [popup]：调用 `popup.show/hide` 即自动重绘，宿主无需在父级 `watch`。
/// 业务内容通过 [builder]（入参含锚点）注入——这就是留给宿主的"接口"：在此
/// 返回自己的卡片（含关闭按钮，关闭按钮调用 [GeoMapPopupController.hide]）。
class GeoMapPopup extends StatefulWidget {
  const GeoMapPopup({
    super.key,
    required this.controller,
    required this.popup,
    required this.builder,
    required this.keepOut,
    required this.cardSize,
    this.anchorSide = PopupAnchor.bottom,
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

  /// 卡片贴锚点的哪一侧（九宫格）。默认 [PopupAnchor.bottom]（卡片在锚点上方）。
  final PopupAnchor anchorSide;

  @override
  State<GeoMapPopup> createState() => _GeoMapPopupState();
}

class _GeoMapPopupState extends State<GeoMapPopup> {
  /// 最后一次构建出的卡片。
  ///
  /// 关闭（`popup.anchor == null`）时刻意保留：锚点传 null 让
  /// [GeoAnchoredPopup] 切到 offstage，但 child 仍是同一棵子树，
  /// Stack 子节点的 RenderObject 不会被 attach/detach。
  Widget? _card;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.popup,
      builder: (context, _) {
        final a = widget.popup.anchor;
        // 仅赋值、不 setState：这里本来就在 build 内。
        if (a != null) _card = widget.builder(context, a);
        return GeoAnchoredPopup(
          key: const ValueKey('geo_map_popup_anchored'),
          controller: widget.controller,
          anchor: a,
          keepOut: widget.keepOut,
          cardSize: widget.cardSize,
          anchorSide: widget.anchorSide,
          child: _card ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
