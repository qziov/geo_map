/// Compiles a MapLibre filter into a predicate over a feature's properties.
///
/// Supports the legacy filter syntax (`["==", "class", "park"]`, `in`, `has`,
/// `all/any/none`) and, for operands written as expressions (`["get", "x"]`,
/// `["+", ["zoom"], 1]`), falls back to the expression evaluator.
///
/// **Filters may depend on zoom.** MapLibre evaluates a filter with
/// `new EvaluationParameters(zoom)` (`src/data/feature_index.ts:235`,
/// `src/tile/tile.ts:454`), so `["zoom"]` is legal inside one — a style can gate
/// a layer by zoom without a separate `minzoom`. The predicate therefore takes
/// the zoom as an argument; evaluating with a constant 0 (as an earlier version
/// did) silently turns every zoom-dependent filter into "as if at z0".
library;

import 'expression.dart';

/// Predicate over one feature at one zoom level.
///
/// The zoom is optional so a caller that has no camera (a test, a filter that
/// never mentions `["zoom"]`) can still ask `matches(props)`; it then means
/// "zoom 0".
typedef FeaturePredicate = bool Function(
  Map<String, Object?> properties, [
  double? zoom,
]);

/// Always-match predicate (a layer without a filter).
const FeaturePredicate matchAllFeatures = _matchAll;

bool _matchAll(Map<String, Object?> _, [double? __]) => true;

FeaturePredicate compileFilter(Object? json) {
  if (json == null) return matchAllFeatures;
  if (json is! List || json.isEmpty) {
    throw FormatException('bad filter: $json');
  }
  final op = json.first;
  if (op is! String) {
    throw const FormatException('filter[0] must be an operator string');
  }
  switch (op) {
    case '==':
      return _comparison(json, (a, b) => a == b);
    case '!=':
      return _comparison(json, (a, b) => a != b);
    case '<':
      return _numeric(json, (a, b) => a < b);
    case '>':
      return _numeric(json, (a, b) => a > b);
    case '<=':
      return _numeric(json, (a, b) => a <= b);
    case '>=':
      return _numeric(json, (a, b) => a >= b);
    case 'in':
      return _in(json, negate: false);
    case '!in':
      return _in(json, negate: true);
    case 'has':
      return (p, [_]) => p.containsKey(json[1]);
    case '!has':
      return (p, [_]) => !p.containsKey(json[1]);
    case 'all':
      final subs = [for (var i = 1; i < json.length; i++) compileFilter(json[i])];
      return (p, [zoom]) => subs.every((f) => f(p, zoom));
    case 'any':
      final subs = [for (var i = 1; i < json.length; i++) compileFilter(json[i])];
      return (p, [zoom]) => subs.any((f) => f(p, zoom));
    case 'none':
      final subs = [for (var i = 1; i < json.length; i++) compileFilter(json[i])];
      return (p, [zoom]) => subs.every((f) => !f(p, zoom));
    default:
      throw FormatException('unsupported filter operator: $op');
  }
}

FeaturePredicate _comparison(List json, bool Function(Object?, Object?) test) {
  if (json.length < 3) {
    throw FormatException('filter "${json.first}" needs 2 operands');
  }
  final left = json[1];
  final right = json[2];
  return (p, [zoom]) {
    final z = zoom ?? 0;
    final a = _left(left, p, z);
    final b = _right(right, p, z);
    // Normalize 1 vs 1.0 so numeric equality is not type-sensitive.
    if (a is num && b is num) return test(a.toDouble(), b.toDouble());
    return test(a, b);
  };
}

FeaturePredicate _numeric(List json, bool Function(num, num) test) {
  if (json.length < 3) {
    throw FormatException('filter "${json.first}" needs 2 operands');
  }
  final left = json[1];
  final right = json[2];
  return (p, [zoom]) {
    final z = zoom ?? 0;
    final a = _left(left, p, z);
    final b = _right(right, p, z);
    if (a is num && b is num) return test(a, b);
    return false;
  };
}

FeaturePredicate _in(List json, {required bool negate}) {
  final key = json[1];
  final values = <Object?>[];
  for (var i = 2; i < json.length; i++) {
    final v = json[i];
    if (v is List) {
      values.addAll(v);
    } else {
      values.add(v);
    }
  }
  return (p, [zoom]) {
    final hit = values.contains(_left(key, p, zoom ?? 0));
    return negate ? !hit : hit;
  };
}

/// Left operand: a bare string is a property key; a list is an expression.
Object? _left(Object? v, Map<String, Object?> properties, double zoom) {
  if (v is List) {
    return parseExpression(v)
        .evaluate(ExpressionContext(zoom: zoom, properties: properties));
  }
  if (v is String) return properties[v];
  return v;
}

/// Right operand: only a list is evaluated; scalars are literals, never keys.
Object? _right(Object? v, Map<String, Object?> properties, double zoom) {
  if (v is List) {
    return parseExpression(v)
        .evaluate(ExpressionContext(zoom: zoom, properties: properties));
  }
  return v;
}
