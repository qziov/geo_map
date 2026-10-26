/// A minimal style-spec model (M1 spike): sources + layers + paint/layout
/// properties that are either constants or expressions.
///
/// Aligns with MapLibre's style JSON (`v8.json` `$root`/`layer`) and the
/// `PropertyValue` / `PossiblyEvaluatedPropertyValue` split in
/// `src/style/properties.ts`: a property keeps its raw/expression form and is
/// evaluated against an [ExpressionContext] at draw time.
library;

import 'expression.dart';
import 'style_color.dart';

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
  });

  final String id;

  /// `fill` or `line` in the M1 subset.
  final String type;
  final String? source;
  final String? sourceLayer;
  final num? minZoom;
  final num? maxZoom;
  final Map<String, PropertyValue> paint;
  final Map<String, PropertyValue> layout;

  /// Paint properties whose values are colors (so constants are parsed to
  /// [StyleColor] and interpolation mixes in RGB).
  static const Set<String> _colorProps = {
    'fill-color',
    'fill-outline-color',
    'line-color',
  };

  static StyleLayer parse(Map<String, Object?> json) {
    Map<String, PropertyValue> parseProps(Object? raw, {required bool isPaint}) {
      final out = <String, PropertyValue>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          final key = '$k';
          out[key] = PropertyValue.fromJson(
            v,
            isColor: isPaint && _colorProps.contains(key),
          );
        });
      }
      return out;
    }

    return StyleLayer(
      id: '${json['id'] ?? ''}',
      type: '${json['type'] ?? ''}',
      source: json['source']?.toString(),
      sourceLayer: json['source-layer']?.toString(),
      minZoom: json['minzoom'] as num?,
      maxZoom: json['maxzoom'] as num?,
      paint: parseProps(json['paint'], isPaint: true),
      layout: parseProps(json['layout'], isPaint: false),
    );
  }

  /// MapLibre visibility: `minzoom <= zoom < maxzoom`.
  bool isVisibleAt(double zoom) {
    if (minZoom != null && zoom < minZoom!) return false;
    if (maxZoom != null && zoom >= maxZoom!) return false;
    return true;
  }
}

/// A paint/layout value: a constant, or an expression evaluated per draw.
class PropertyValue {
  PropertyValue._(this._constant, this._expr, this.isColor);

  factory PropertyValue.fromJson(Object? json, {bool isColor = false}) {
    if (isExpressionJson(json)) {
      return PropertyValue._(null, parseExpression(json), isColor);
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
