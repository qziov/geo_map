/// Compiles a MapLibre filter into a predicate over a feature's properties.
///
/// Supports the legacy filter syntax (`["==", "class", "park"]`, `in`, `has`,
/// `all/any/none`) and, for operands written as expressions (`["get", "x"]`),
/// falls back to the expression evaluator. Zoom is not allowed in filters
/// (MapLibre rejects it), so operands are evaluated with `zoom: 0`.
library;

import 'expression.dart';

typedef FeaturePredicate = bool Function(Map<String, Object?> properties);

/// Always-match predicate (a layer without a filter).
const FeaturePredicate matchAllFeatures = _matchAll;

bool _matchAll(Map<String, Object?> _) => true;

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
      return (p) => p.containsKey(json[1]);
    case '!has':
      return (p) => !p.containsKey(json[1]);
    case 'all':
      final subs = [for (var i = 1; i < json.length; i++) compileFilter(json[i])];
      return (p) => subs.every((f) => f(p));
    case 'any':
      final subs = [for (var i = 1; i < json.length; i++) compileFilter(json[i])];
      return (p) => subs.any((f) => f(p));
    case 'none':
      final subs = [for (var i = 1; i < json.length; i++) compileFilter(json[i])];
      return (p) => subs.every((f) => !f(p));
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
  return (p) {
    final a = _left(left, p);
    final b = _right(right, p);
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
  return (p) {
    final a = _left(left, p);
    final b = _right(right, p);
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
  return (p) {
    final hit = values.contains(_left(key, p));
    return negate ? !hit : hit;
  };
}

/// Left operand: a bare string is a property key; a list is an expression.
Object? _left(Object? v, Map<String, Object?> properties) {
  if (v is List) {
    return parseExpression(v)
        .evaluate(ExpressionContext(zoom: 0, properties: properties));
  }
  if (v is String) return properties[v];
  return v;
}

/// Right operand: only a list is evaluated; scalars are literals, never keys.
Object? _right(Object? v, Map<String, Object?> properties) {
  if (v is List) {
    return parseExpression(v)
        .evaluate(ExpressionContext(zoom: 0, properties: properties));
  }
  return v;
}
