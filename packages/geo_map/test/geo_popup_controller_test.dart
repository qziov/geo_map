import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

GeoMapController _flatController() {
  final controller = GeoMapController(
    useGlobe: false,
    initialCenter: const LatLng(0, 0),
    initialZoom: 4,
    minZoom: 1,
    maxZoom: 18,
  );
  controller.setViewport(const Size(800, 600));
  return controller;
}

GeoJsonFeature _dot(String id, double lat, double lng) => GeoJsonFeature(
      id: id,
      geometry: PointGeometry(LatLng(lat, lng)),
    );

GeoJsonFeature _box(String id) => GeoJsonFeature(
      id: id,
      geometry: PolygonGeometry(<List<LatLng>>[
        <LatLng>[
          LatLng(-5, -5),
          LatLng(-5, 5),
          LatLng(5, 5),
          LatLng(5, -5),
          LatLng(-5, -5),
        ],
      ]),
    );

Widget _card(BuildContext _, GeoQueryHit __) => const SizedBox.shrink();

void main() {
  group('GeoPopupController — opening', () {
    test('a tapped source with a popup opens it', () {
      final controller = _flatController();
      addTearDown(controller.dispose);
      final geoPopup = GeoMapPopupController();
      final registry = GeoFeatureRegistry()
        ..setSource(
          'dots',
          [_dot('a', 0, 0)],
          popup: GeoPopupBinding(
            cardSize: const Size(280, 200),
            builder: _card,
          ),
        );
      final popup = GeoPopupController(geoPopup);

      popup.handleTap(const LatLng(0, 0), controller: controller, registry: registry);

      expect(geoPopup.isOpen, isTrue);
      expect(popup.activeBuilder, isNotNull);
      expect(popup.activeCardSize, equals(const Size(280, 200)));
    });

    test('a tapped source without a popup closes any open popup', () {
      final controller = _flatController();
      addTearDown(controller.dispose);
      final geoPopup = GeoMapPopupController();
      final registry = GeoFeatureRegistry()
        ..setSource('dots', [_dot('a', 0, 0)]); // no popup
      final popup = GeoPopupController(geoPopup);
      geoPopup.show(const LatLng(0, 0)); // pretend something is open
      expect(geoPopup.isOpen, isTrue);

      popup.handleTap(const LatLng(0, 0), controller: controller, registry: registry);

      expect(geoPopup.isOpen, isFalse);
      expect(popup.activeBuilder, isNull);
    });

    test('a tap with no hit closes any open popup', () {
      final controller = _flatController();
      addTearDown(controller.dispose);
      final geoPopup = GeoMapPopupController();
      final registry = GeoFeatureRegistry();
      final popup = GeoPopupController(geoPopup);
      geoPopup.show(const LatLng(0, 0));

      popup.handleTap(const LatLng(0, 0), controller: controller, registry: registry);

      expect(geoPopup.isOpen, isFalse);
    });

    test('overlapping sources: higher priority wins', () {
      final controller = _flatController();
      addTearDown(controller.dispose);
      final geoPopup = GeoMapPopupController();
      final registry = GeoFeatureRegistry()
        ..setSource(
          'low',
          [_dot('low1', 0, 0)],
          popup: GeoPopupBinding(
            priority: 1,
            cardSize: const Size(10, 10),
            builder: _card,
          ),
        )
        ..setSource(
          'high',
          [_dot('high1', 0, 0)],
          popup: GeoPopupBinding(
            priority: 10,
            cardSize: const Size(20, 20),
            builder: _card,
          ),
        );
      final popup = GeoPopupController(geoPopup);

      popup.handleTap(const LatLng(0, 0), controller: controller, registry: registry);

      expect(popup.activeCardSize, equals(const Size(20, 20)));
    });

    test('anchor defaults to the tap point, not the feature geometry', () {
      final controller = _flatController();
      addTearDown(controller.dispose);
      final geoPopup = GeoMapPopupController();
      final registry = GeoFeatureRegistry()
        ..setSource(
          'areas',
          [_box('a')],
          popup: GeoPopupBinding(
            cardSize: const Size(10, 10),
            builder: _card,
          ),
        );
      final popup = GeoPopupController(geoPopup);

      // Tap inside the polygon but away from any vertex: the anchor must be the
      // tap point (1, 1), proving it is not derived from the feature geometry.
      popup.handleTap(const LatLng(1, 1), controller: controller, registry: registry);

      expect(geoPopup.anchor, equals(const LatLng(1, 1)));
    });
  });

  group('GeoPopupController — imperative registration', () {
    test('registerPopup opens on hit; unregisterPopup drops it', () {
      final controller = _flatController();
      addTearDown(controller.dispose);
      final geoPopup = GeoMapPopupController();
      final registry = GeoFeatureRegistry()..setSource('dots', [_dot('a', 0, 0)]);
      final popup = GeoPopupController(geoPopup);

      popup.registerPopup(
        'dots',
        GeoPopupBinding(cardSize: const Size(10, 10), builder: _card),
      );
      popup.handleTap(const LatLng(0, 0), controller: controller, registry: registry);
      expect(geoPopup.isOpen, isTrue);

      popup.unregisterPopup('dots');
      popup.handleTap(const LatLng(0, 0), controller: controller, registry: registry);
      expect(geoPopup.isOpen, isFalse);
    });
  });

  group('GeoFeatureRegistry — popupOf', () {
    test('returns the binding set via setSource', () {
      final registry = GeoFeatureRegistry();
      final binding = GeoPopupBinding(
        cardSize: const Size(10, 10),
        builder: _card,
      );
      registry.setSource('dots', [_dot('a', 0, 0)], popup: binding);
      expect(registry.popupOf('dots'), same(binding));
    });
    test('returns null when no popup was set', () {
      final registry = GeoFeatureRegistry()..setSource('dots', [_dot('a', 0, 0)]);
      expect(registry.popupOf('dots'), isNull);
    });
  });

  // 回归：hot reload 改到 provider 源码时，Riverpod 的 `invalidateSelf()` 会
  // **先 runOnDispose() 再重建**（`ProviderElementBase.invalidateSelf`）。这段
  // "僵尸期"内点地图仍会把事件送到旧实例上——必须安静丢弃，而不是让
  // `notifyListeners()` 抛 assert 打断手势链路（线上表现：改完代码第一次点地图
  // 报 `A GeoPopupController was used after being disposed`）。
  group('GeoPopupController — disposed safety', () {
    test('handleTap / close after dispose are no-ops and never throw', () {
      final controller = _flatController();
      addTearDown(controller.dispose);
      final geoPopup = GeoMapPopupController();
      final registry = GeoFeatureRegistry()
        ..setSource(
          'dots',
          [_dot('a', 0, 0)],
          popup: GeoPopupBinding(
            cardSize: const Size(10, 10),
            builder: _card,
          ),
        );
      final popup = GeoPopupController(geoPopup);

      popup.handleTap(const LatLng(0, 0), controller: controller, registry: registry);
      expect(geoPopup.isOpen, isTrue);

      popup.dispose();
      expect(popup.isDisposed, isTrue);

      expect(
        () => popup.handleTap(
          const LatLng(0, 0),
          controller: controller,
          registry: registry,
        ),
        returnsNormally,
      );
      expect(() => popup.close(), returnsNormally);
      // 已销毁 → 不再改动共享锚点（下一个实例接管）
      expect(geoPopup.isOpen, isTrue);
    });

    test('GeoMapPopupController.show / hide after dispose are no-ops', () {
      final geoPopup = GeoMapPopupController()..dispose();
      expect(geoPopup.isDisposed, isTrue);

      expect(() => geoPopup.show(const LatLng(1, 2)), returnsNormally);
      expect(geoPopup.anchor, isNull);
      expect(() => geoPopup.hide(), returnsNormally);
      expect(() => geoPopup.toggle(const LatLng(1, 2)), returnsNormally);
      expect(geoPopup.isOpen, isFalse);
    });
  });
}
