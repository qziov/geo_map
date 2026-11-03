/// 实时帧率显示（调试 / 性能分析用）。
///
/// 用一个 [Ticker] 在每个 vsync 计帧，按约 1 秒的滑动窗口算出 FPS 并显示。
///
/// 关键点：一个已启动的 [Ticker] 会持续请求每一帧，所以挂载后整条渲染管线
/// 保持 ~60fps 心跳 —— 这正是 FPS 表想要的（否则空闲无动画时引擎不排帧，
/// 读数会停）。代价是开启期间持续重绘，因此它**只在 [GeoMapOptions.showFps]
/// 为 true 时被挂载**，关闭时零开销、不触发任何帧。
///
/// 用 [IgnorePointer] 包裹：纯展示，不拦截地图手势。
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class FpsOverlay extends StatefulWidget {
  const FpsOverlay({super.key});

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<FpsOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _frames = 0;
  int _fps = 0;
  late DateTime _windowStart;

  @override
  void initState() {
    super.initState();
    _windowStart = DateTime.now();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    _frames++;
    final now = DateTime.now();
    final elapsedMs = now.difference(_windowStart).inMilliseconds;
    if (elapsedMs >= 1000) {
      // 用真实流逝毫秒归一，避免抖动时整数跳变。
      _fps = (_frames * 1000 / elapsedMs).round();
      _frames = 0;
      _windowStart = now;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fps = _fps;
    final color = switch (fps) {
      >= 55 => const Color(0xFF3FB950), // 绿：流畅
      >= 30 => const Color(0xFFD29922), // 黄：一般
      _ => const Color(0xFFF85149), // 红：偏低
    };
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 110, bottom: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x88000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'FPS $fps',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
