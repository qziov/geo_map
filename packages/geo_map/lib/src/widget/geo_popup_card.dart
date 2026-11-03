/// A standard popup card shell (MapLibre `Popup` 的卡片外观 + 关闭按钮).
///
/// 业务只提供内容（[GeoPopupCard.header] / [GeoPopupCard.child]）与主题
/// （[GeoPopupCard.decoration]）；"卡片内空白点击不穿透地图"与"关闭按钮的
/// 可点区域"由本组件统一保证 —— 避免每个业务卡片各写一套 16px 的
/// [GestureDetector]。
library;

import 'package:flutter/material.dart';

/// 统一的弹窗卡片外壳。
///
/// 结构：
/// - 最外层 [GestureDetector]（`behavior: opaque`）吞掉卡片内的空白点击，
///   避免漏给下面的地图（等价于 MapLibre Popup 作为独立 DOM 覆盖层的事件隔离）。
/// - [header] 右侧可带一个 SDK 关闭按钮（[onClose] 非空时渲染），命中区 ≥32px。
class GeoPopupCard extends StatelessWidget {
  const GeoPopupCard({
    super.key,
    required this.child,
    this.header,
    this.onClose,
    this.width = 280,
    this.padding = const EdgeInsets.all(12),
    this.decoration,
  });

  /// 卡片内容。
  final Widget child;

  /// 标题区（业务排版）。为 null 时不渲染标题行。
  final Widget? header;

  /// 关闭回调；非空时在标题行右侧渲染关闭按钮。
  final VoidCallback? onClose;

  /// 卡片宽度（逻辑像素）。
  final double width;

  /// 内容内边距。
  final EdgeInsets padding;

  /// 卡片背景/边框/阴影；为 null 时使用主题色的默认外观。
  final BoxDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasHeader = header != null || onClose != null;
    return GestureDetector(
      // 卡片内空白点击不落到地图；内层按钮（更深）仍优先响应。
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        width: width,
        padding: padding,
        decoration: decoration ??
            BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: const [
                BoxShadow(color: Color(0x59000000), blurRadius: 10),
              ],
            ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasHeader)
              Row(
                children: [
                  if (header != null) Expanded(child: header!) else const Spacer(),
                  if (onClose != null)
                    IconButton(
                      onPressed: onClose,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      iconSize: 18,
                      color: scheme.onSurfaceVariant,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            if (hasHeader) const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
