/// A minimal style-spec model (M1): sources + layers + paint/layout properties
/// that are either constants or expressions, plus a compiled feature filter.
///
/// Aligns with MapLibre's style JSON (`v8.json` `$root`/`layer`) and the
/// `PropertyValue` / `PossiblyEvaluatedPropertyValue` split in
/// `src/style/properties.ts`: a property keeps its raw/expression form and is
/// evaluated against an [ExpressionContext] at draw time. Defaults come from
/// [layerPaintDefs] / [layerLayoutDefs] (matching `v8.json`).
library;

import 'expression.dart';
import 'style_color.dart';
import 'style_filter.dart';
import 'style_properties.dart';

class StyleSpec {
  StyleSpec({
    required this.version,
    required this.sources,
    required this.layers,
  });

  final int version;
  final Map<String, Map<String, Object?>> sources;
  final List<StyleLayer> layers;

  static StyleSpec parse(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt() ?? 8;

    final sources = <String, Map<String, Object?>>{};
    final rawSources = json['sources'];
    if (rawSources is Map) {
      rawSources.forEach((k, v) {
        if (v is Map) sources['$k'] = Map<String, Object?>.from(v);
      });
    }

    final layers = <StyleLayer>[];
    final rawLayers = json['layers'];
    if (rawLayers is List) {
      for (final l in rawLayers) {
        if (l is Map) layers.add(StyleLayer.parse(Map<String, Object?>.from(l)));
      }
    }

    return StyleSpec(version: version, sources: sources, layers: layers);
  }
}

class StyleLayer {
  StyleLayer({
    required this.id,
    required this.type,
    this.source,
    this.sourceLayer,
    this.minZoom,
    this.maxZoom,
    this.paint = const {},
    this.layout = const {},
    this.filter = matchAllFeatures,
  });

  final String id;

  /// `fill` or `line` in the M1 subset (other types parse but are not drawn).
  final String type;
  final String? source;
  final String? sourceLayer;
  final num? minZoom;
  final num? maxZoom;
  final Map<String, PropertyValue> paint;
  final Map<String, PropertyValue> layout;

  /// Compiled filter over feature properties (always-true when absent).
  final FeaturePredicate filter;

  /// Whether the M1 renderer can draw this layer type.
  bool get isSupported => type == 'fill' || type == 'line';

  static StyleLayer parse(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}';
    final type = '${json['type'] ?? ''}';
    final paintDefs =
        layerPaintDefs[type] ?? const <String, StylePropertyDef>{};
    final layoutDefs =
        layerLayoutDefs[type] ?? const <String, StylePropertyDef>{};

    Map<String, PropertyValue> parseProps(
      Object? raw,
      Map<String, StylePropertyDef> defs,
    ) {
      final out = <String, PropertyValue>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          final key = '$k';
          out[key] = PropertyValue.fromJson(
            v,
            isColor: defs[key]?.type == StylePropertyType.color,
          );
        });
      }
      // Apply spec defaults for known properties that were not set.
      defs.forEach((key, def) {
        if (out.containsKey(key) || def.defaultValue == null) return;
        out[key] = PropertyValue.fromJson(
          def.defaultValue,
          isColor: def.type == StylePropertyType.color,
        );
      });
      return out;
    }

    return StyleLayer(
      id: id,
      type: type,
      source: json['source']?.toString(),
      sourceLayer: json['source-layer']?.toString(),
      minZoom: json['minzoom'] as num?,
      maxZoom: json['maxzoom'] as num?,
      paint: parseProps(json['paint'], paintDefs),
      layout: parseProps(json['layout'], layoutDefs),
      filter: compileFilter(json['filter']),
    );
  }

  /// Evaluate any paint or layout property (paint first, then layout).
  Object? valueOf(String name, ExpressionContext ctx) {
    final pv = paint[name] ?? layout[name];
    return pv?.evaluate(ctx);
  }

  double? number(String name, ExpressionContext ctx) {
    final v = valueOf(name, ctx);
    return v is num ? v.toDouble() : null;
  }

  StyleColor? color(String name, ExpressionContext ctx) {
    final v = valueOf(name, ctx);
    if (v == null) return null;
    return v is StyleColor ? v : StyleColor.parse(v);
  }

  String? string(String name, ExpressionContext ctx) =>
      valueOf(name, ctx)?.toString();

  bool? boolean(String name, ExpressionContext ctx) {
    final v = valueOf(name, ctx);
    return v is bool ? v : null;
  }

  /// MapLibre visibility: `minzoom <= zoom < maxzoom` and `visibility != none`.
  bool isVisibleAt(double zoom) {
    if (minZoom != null && zoom < minZoom!) return false;
    if (maxZoom != null && zoom >= maxZoom!) return false;
    if (string('visibility', ExpressionContext(zoom: zoom)) == 'none') {
      return false;
    }
    return true;
  }
}

/// A paint/layout value: a constant, or an expression evaluated per draw.
class PropertyValue {
  PropertyValue._(this._constant, this._expr, this.isColor);

  factory PropertyValue.fromJson(Object? json, {bool isColor = false}) {
    if (isExpressionJson(json)) {
      final expr = parseExpression(json);
      validateZoomUsage(expr);
      return PropertyValue._(null, expr, isColor);
    }
    return PropertyValue._(json, null, isColor);
  }

  final Object? _constant;
  final Expr? _expr;
  final bool isColor;

  bool get isExpression => _expr != null;

  /// True when the value does not depend on feature properties.
  bool get isFeatureConstant => _expr?.isFeatureConstant ?? true;

  /// True when the value does not depend on zoom.
  bool get isZoomConstant => _expr?.isZoomConstant ?? true;

  Object? evaluate(ExpressionContext ctx) {
    final v = _expr != null ? _expr.evaluate(ctx) : _constant;
    if (isColor && v != null) return StyleColor.parse(v);
    return v;
  }
}
