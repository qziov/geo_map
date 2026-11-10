import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';

void main() {
  testWidgets('FpsOverlay 初始渲染 FPS 标签且不拦截手势', (tester) async {
    // FpsOverlay 内部有 Text，需要 Directionality 祖先（真实树里由 MaterialApp 提供）。
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FpsOverlay(),
      ),
    );

    // 初始窗口尚未走满 1 秒，读数为 0。
    expect(find.text('FPS 0'), findsOneWidget);
    // 纯展示层：不拦截地图手势。
    expect(find.byType(IgnorePointer), findsOneWidget);
  });
}
