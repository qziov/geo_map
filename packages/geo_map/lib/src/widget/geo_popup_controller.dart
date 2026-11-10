/// The popup control layer — MapLibre's `map.on('click', layerId, handler)`
/// plus a single shared `Popup`, assembled for our source-based hit model.
///
/// A business layer registers a [GeoPopupBinding] (either via
/// [GeoFeatureRegistry.setSource]'s `popup:` argument, or imperatively with
/// [registerPopup]); on every map tap the host calls [handleTap] (passing the
/// current [GeoFeatureRegistry]), which asks the registry what was hit, picks
/// the winning source by [GeoPopupBinding.priority], opens the shared
/// [GeoMapPopupController] at the anchor, and remembers which binding/card to
/// render. The render host ([GeoMapPopupHost]) then reads [activeBuilder] and
/// draws the right card.
///
/// The controller owns no camera state (that is [GeoMapController]), no
/// projection (that is in [GeoAnchoredPopup]), and no feature data (the registry
/// is passed in per tap, so it always sees the host's latest snapshot). It is
/// framework-agnostic — it does not depend on Riverpod or any app state
/// container.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../camera/geo_map_controller.dart';
import '../query/geo_feature_registry.dart';
import 'geo_anchored_popup.dart';
import 'geo_popup_binding.dart';

/// The currently-open popup: which source won, its binding, and the hit.
class _ActivePopup {
  const _ActivePopup(this.sourceId, this.binding, this.hit);

  final String sourceId;
  final GeoPopupBinding binding;
  final GeoQueryHit hit;
}

/// Glue between [GeoFeatureRegistry] and the shared [GeoMapPopupController].
///
/// See the library doc comment for the usage flow. One instance is owned by the
/// host app (typically via a Riverpod provider that wires in the underlying
/// popup controller).
class GeoPopupController extends ChangeNotifier {
  /// [geoPopup] is the shared show/hide/anchor state, owned by the host. The
  /// feature registry is passed to [handleTap] per tap so the controller never
  /// holds a stale snapshot.
  GeoPopupController(this.geoPopup);

  final GeoMapPopupController geoPopup;

  bool _disposed = false;

  /// Whether [dispose] has run.
  ///
  /// 宿主可能在这个窗口里仍然调到本实例：Riverpod 的 `invalidateSelf()`
  /// （hot reload 改到 provider 源码时的常规路径，或业务主动 `ref.invalidate`）
  /// 会**先 `runOnDispose()` 再重建**，也就是说 notify 监听方的 dispose 先发生、
  /// 新实例下一帧才出现。旧实例这段"僵尸期"内收到的点击必须安静地丢弃，
  /// 而不是让 `notifyListeners()` 抛 assert 打断整条手势链路。
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// [ChangeNotifier.notifyListeners] + "已销毁则跳过"。
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Imperative bindings (the literal `map.on('click', id, handler)` form), keyed
  /// by source id. Merged with [GeoFeatureRegistry.popupOf] at query time.
  final Map<String, GeoPopupBinding> _imperative = <String, GeoPopupBinding>{};

  /// Bind a popup to [sourceId] imperatively. Call from a layer's setup and pair
  /// it with [unregisterPopup] on teardown so stale bindings never fire.
  void registerPopup(String sourceId, GeoPopupBinding binding) {
    if (_disposed) return;
    _imperative[sourceId] = binding;
    if (_active?.sourceId == sourceId) _safeNotify();
  }

  /// Drop an imperative binding. If it is the one currently shown, the popup
  /// closes.
  void unregisterPopup(String sourceId) {
    _imperative.remove(sourceId);
    if (_active?.sourceId == sourceId) close();
  }

  GeoPopupBinding? _bindingOf(String sourceId, GeoFeatureRegistry registry) =>
      _imperative[sourceId] ?? registry.popupOf(sourceId);

  _ActivePopup? _active;

  /// The card builder for the open popup, or `null` when nothing is open. The
  /// render host calls this with the projected anchor.
  Widget? Function(BuildContext context, LatLng anchor)? get activeBuilder =>
      _active == null
          ? null
          : (context, anchor) => _active!.binding.builder(context, _active!.hit);

  /// The open card's maximum size, for keepOut clamping.
  Size get activeCardSize => _active?.binding.cardSize ?? const Size(280, 240);

  /// The open card's anchor side (nine-grid).
  PopupAnchor get activeAnchor => _active?.binding.anchor ?? PopupAnchor.bottom;

  /// The hit that opened the current popup, or `null` when nothing is open.
  ///
  /// Hosts use it for business reactions tied to the winning hit (e.g. "the
  /// selected typhoon track point must follow the tapped one").
  GeoQueryHit? get activeHit => _active?.hit;

  /// The source id of the current popup, or `null` when nothing is open.
  String? get activeSourceId => _active?.sourceId;

  /// The single entry point for a map tap.
  ///
  /// Queries [registry], filters to sources that registered a popup, and opens
  /// the highest-priority one. No hit, or a hit on a source without a popup
  /// (e.g. an airport that only fires a SnackBar), closes any open popup.
  ///
  /// Pass [hits] when the host already ran the query (it usually needs the same
  /// results for its own business reactions) — this avoids querying twice.
  ///
  /// Disposed controller (see [isDisposed]) → no-op: the popup it owned no longer
  /// exists, and the freshly created replacement will handle the next tap.
  ///
  /// Returns the query result so the host can reuse it for its own reactions
  /// (SnackBar / selection) without querying a second time.
  List<GeoQueryHit> handleTap(
    LatLng tap, {
    required GeoMapController controller,
    required GeoFeatureRegistry registry,
    double? pointRadiusPx,
    List<GeoQueryHit>? hits,
  }) {
    if (_disposed) return const <GeoQueryHit>[];

    final results = hits ??
        registry.queryFeatures(
          tap,
          controller: controller,
          pointRadiusPx: pointRadiusPx,
        );

    GeoPopupBinding? winner;
    GeoQueryHit? winnerHit;
    String? winnerSource;
    for (final hit in results) {
      final binding = _bindingOf(hit.sourceId, registry);
      if (binding == null) continue;
      if (winner == null || binding.priority > winner.priority) {
        winner = binding;
        winnerHit = hit;
        winnerSource = hit.sourceId;
      }
    }

    if (winner == null || winnerHit == null || winnerSource == null) {
      close();
      return results;
    }

    _active = _ActivePopup(winnerSource, winner, winnerHit);
    geoPopup.show(winner.anchorOf?.call(winnerHit) ?? tap);
    _safeNotify();
    return results;
  }

  /// Close the popup (anchor cleared, active binding dropped).
  void close() {
    if (_disposed) return;
    if (_active == null && !geoPopup.isOpen) return;
    _active = null;
    geoPopup.hide();
    _safeNotify();
  }
}

/// Render host for the popup control layer.
///
/// Mount exactly one of these as a direct child of the `Stack` outside `GeoMap`
/// (same constraint as [GeoMapPopup]: it must be a direct child of the outer
/// `Stack`, never inside `GeoMap.children`). It reads the open binding from
/// [popup] and renders the matching card, repositioned on every camera move by
/// the underlying [GeoMapPopup].
class GeoMapPopupHost extends StatelessWidget {
  const GeoMapPopupHost({
    super.key,
    required this.controller,
    required this.popup,
    required this.keepOut,
  });

  /// Map camera (re-projects the anchor each frame).
  final GeoMapController controller;

  /// The popup control layer that decides what to show.
  final GeoPopupController popup;

  /// Insets the card never covers (top bar / side bar / bottom bar).
  final EdgeInsets keepOut;

  @override
  Widget build(BuildContext context) {
    return GeoMapPopup(
      controller: controller,
      popup: popup.geoPopup,
      cardSize: popup.activeCardSize,
      anchorSide: popup.activeAnchor,
      keepOut: keepOut,
      builder: (context, anchor) =>
          popup.activeBuilder?.call(context, anchor) ?? const SizedBox.shrink(),
    );
  }
}
