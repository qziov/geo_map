/// A minimal, source-aligned subset of the MapLibre expression language.
///
/// Aligns with `@maplibre/maplibre-gl-style-spec` (v26) `expression/`:
/// parsing (`parsing_context.ts`), the operator table
/// (`compound_expression.ts`, `definitions/*.ts`), the evaluation context
/// (`evaluation_context.ts`) and the feature/zoom constant analysis
/// (`index.ts` `isFeatureConstant` / `isGlobalPropertyConstant`).
///
/// Supported here (spike): literal, get, has, zoom, `== != > < >= <=`,
/// `all any !`, `interpolate` (linear / exponential), `step`, `case`,
/// `coalesce`, `to-number/to-string/to-color`. Everything else throws a
/// [FormatException] — deliberately loud rather than silently wrong.
library;

import 'dart:math' as math;

import 'style_color.dart';

/// The evaluation inputs for an expression.
///
/// Mirrors MapLibre's `EvaluationParameters` / `EvaluationContext`: `zoom` is
/// the only global needed for a spike; `properties` stands in for a feature's
/// property map (which is why `get`/`has` make an expression feature-dependent).
class ExpressionContext {
  const ExpressionContext({
    required this.zoom,
    this.properties = const {},
    this.variables = const {},
  });

  final double zoom;
  final Map<String, Object?> properties;

  /// Bindings introduced by [`let`] expressions.
  final Map<String, Object?> variables;
}

/// A parsed expression node.
abstract class Expr {
  const Expr();

  Object? evaluate(ExpressionContext ctx);

  /// True when the value does **not** depend on feature properties.
  bool get isFeatureConstant;

  /// True when the value does **not** depend on the zoom.
  bool get isZoomConstant;

  /// True when this is a compile-time constant.
  bool get isConstant => isFeatureConstant && isZoomConstant;
}

// --- leaves ------------------------------------------------------------------

class LiteralExpr extends Expr {
  const LiteralExpr(this.value);
  final Object? value;

  @override
  Object? evaluate(ExpressionContext ctx) => value;
  @override
  bool get isFeatureConstant => true;
  @override
  bool get isZoomConstant => true;
}

class GetExpr extends Expr {
  const GetExpr(this.key);
  final String key;

  @override
  Object? evaluate(ExpressionContext ctx) => ctx.properties[key];
  @override
  bool get isFeatureConstant => false;
  @override
  bool get isZoomConstant => true;
}

class HasExpr extends Expr {
  const HasExpr(this.key);
  final String key;

  @override
  Object? evaluate(ExpressionContext ctx) =>
      ctx.properties.containsKey(key) && ctx.properties[key] != null;
  @override
  bool get isFeatureConstant => false;
  @override
  bool get isZoomConstant => true;
}

class ZoomExpr extends Expr {
  const ZoomExpr();

  @override
  Object? evaluate(ExpressionContext ctx) => ctx.zoom;
  @override
  bool get isFeatureConstant => true;
  @override
  bool get isZoomConstant => false;
}

// --- logic / comparison ------------------------------------------------------

class ComparisonExpr extends Expr {
  ComparisonExpr(this.op, this.left, this.right);
  final String op;
  final Expr left;
  final Expr right;

  @override
  Object? evaluate(ExpressionContext ctx) {
    final a = left.evaluate(ctx);
    final b = right.evaluate(ctx);
    switch (op) {
      case '==':
        return a == b;
      case '!=':
        return a != b;
    }
    if (a is num && b is num) {
      switch (op) {
        case '>':
          return a > b;
        case '<':
          return a < b;
        case '>=':
          return a >= b;
        case '<=':
          return a <= b;
      }
    }
    throw StateError(
        'cannot compare "$op" ${a.runtimeType} with ${b.runtimeType}');
  }

  @override
  bool get isFeatureConstant =>
      left.isFeatureConstant && right.isFeatureConstant;
  @override
  bool get isZoomConstant => left.isZoomConstant && right.isZoomConstant;
}

class NotExpr extends Expr {
  const NotExpr(this.arg);
  final Expr arg;

  @override
  Object? evaluate(ExpressionContext ctx) => !_truthy(arg.evaluate(ctx));
  @override
  bool get isFeatureConstant => arg.isFeatureConstant;
  @override
  bool get isZoomConstant => arg.isZoomConstant;
}

class LogicalExpr extends Expr {
  const LogicalExpr(this.all, this.args);
  final bool all;
  final List<Expr> args;

  @override
  Object? evaluate(ExpressionContext ctx) {
    if (all) {
      for (final a in args) {
        if (!_truthy(a.evaluate(ctx))) return false;
      }
      return true;
    }
    for (final a in args) {
      if (_truthy(a.evaluate(ctx))) return true;
    }
    return false;
  }

  @override
  bool get isFeatureConstant => args.every((a) => a.isFeatureConstant);
  @override
  bool get isZoomConstant => args.every((a) => a.isZoomConstant);
}

bool _truthy(Object? v) => v == true;

// --- interpolation / stepping ------------------------------------------------

class InterpolateExpr extends Expr {
  InterpolateExpr(this.input, this.stops, this.outputs, {this.base = 1.0});

  final Expr input;
  final List<num> stops;
  final List<Expr> outputs;

  /// `1.0` = linear; `> 1` = exponential with this base.
  final double base;

  @override
  Object? evaluate(ExpressionContext ctx) {
    final z = (input.evaluate(ctx) as num).toDouble();
    if (z <= stops.first) return outputs.first.evaluate(ctx);
    if (z >= stops.last) return outputs.last.evaluate(ctx);
    for (var i = 0; i < stops.length - 1; i++) {
      final z0 = stops[i].toDouble();
      final z1 = stops[i + 1].toDouble();
      if (z >= z0 && z <= z1) {
        final t = _factor(z, z0, z1);
        return _mix(outputs[i].evaluate(ctx), outputs[i + 1].evaluate(ctx), t);
      }
    }
    return outputs.last.evaluate(ctx);
  }

  double _factor(double z, double z0, double z1) {
    if (base == 1.0) return (z - z0) / (z1 - z0);
    return (math.pow(base, z - z0) - 1) / (math.pow(base, z1 - z0) - 1);
  }

  Object? _mix(Object? a, Object? b, double t) {
    if (a is num && b is num) return a + (b - a) * t;
    if (a is StyleColor && b is StyleColor) return StyleColor.lerp(a, b, t);
    // Color stops inside `interpolate` are usually string literals; parse them
    // here (MapLibre resolves them by the property type at compile time).
    if (a is String && b is String) {
      return StyleColor.lerp(StyleColor.parse(a), StyleColor.parse(b), t);
    }
    throw StateError(
        'interpolate cannot mix ${a.runtimeType} and ${b.runtimeType}');
  }

  @override
  bool get isFeatureConstant =>
      input.isFeatureConstant && outputs.every((o) => o.isFeatureConstant);
  @override
  bool get isZoomConstant =>
      input.isZoomConstant && outputs.every((o) => o.isZoomConstant);
}

class StepExpr extends Expr {
  StepExpr(this.input, this.fallback, this.stops, this.outputs);
  final Expr input;
  final Expr fallback;
  final List<num> stops;
  final List<Expr> outputs;

  @override
  Object? evaluate(ExpressionContext ctx) {
    final z = (input.evaluate(ctx) as num).toDouble();
    if (stops.isEmpty || z < stops.first) return fallback.evaluate(ctx);
    var chosen = fallback;
    for (var i = 0; i < stops.length; i++) {
      if (z >= stops[i]) chosen = outputs[i];
    }
    return chosen.evaluate(ctx);
  }

  @override
  bool get isFeatureConstant =>
      input.isFeatureConstant &&
      fallback.isFeatureConstant &&
      outputs.every((o) => o.isFeatureConstant);
  @override
  bool get isZoomConstant =>
      input.isZoomConstant &&
      fallback.isZoomConstant &&
      outputs.every((o) => o.isZoomConstant);
}

// --- case / coalesce ---------------------------------------------------------

class CaseExpr extends Expr {
  CaseExpr(this.pairs, this.fallback);
  final List<(Expr, Expr)> pairs;
  final Expr fallback;

  @override
  Object? evaluate(ExpressionContext ctx) {
    for (final (cond, value) in pairs) {
      if (_truthy(cond.evaluate(ctx))) return value.evaluate(ctx);
    }
    return fallback.evaluate(ctx);
  }

  @override
  bool get isFeatureConstant =>
      pairs.every((p) => p.$1.isFeatureConstant && p.$2.isFeatureConstant) &&
      fallback.isFeatureConstant;
  @override
  bool get isZoomConstant =>
      pairs.every((p) => p.$1.isZoomConstant && p.$2.isZoomConstant) &&
      fallback.isZoomConstant;
}

class CoalesceExpr extends Expr {
  const CoalesceExpr(this.args);
  final List<Expr> args;

  @override
  Object? evaluate(ExpressionContext ctx) {
    for (final a in args) {
      final v = a.evaluate(ctx);
      if (v != null) return v;
    }
    return null;
  }

  @override
  bool get isFeatureConstant => args.every((a) => a.isFeatureConstant);
  @override
  bool get isZoomConstant => args.every((a) => a.isZoomConstant);
}

// --- coercion ----------------------------------------------------------------

class ToNumberExpr extends Expr {
  const ToNumberExpr(this.arg);
  final Expr arg;

  @override
  Object? evaluate(ExpressionContext ctx) {
    final v = arg.evaluate(ctx);
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1.0 : 0.0;
    if (v is String) return double.tryParse(v);
    return null;
  }

  @override
  bool get isFeatureConstant => arg.isFeatureConstant;
  @override
  bool get isZoomConstant => arg.isZoomConstant;
}

class ToStringExpr extends Expr {
  const ToStringExpr(this.arg);
  final Expr arg;

  @override
  Object? evaluate(ExpressionContext ctx) => arg.evaluate(ctx)?.toString();
  @override
  bool get isFeatureConstant => arg.isFeatureConstant;
  @override
  bool get isZoomConstant => arg.isZoomConstant;
}

class ToColorExpr extends Expr {
  const ToColorExpr(this.arg);
  final Expr arg;

  @override
  Object? evaluate(ExpressionContext ctx) => StyleColor.parse(arg.evaluate(ctx));
  @override
  bool get isFeatureConstant => arg.isFeatureConstant;
  @override
  bool get isZoomConstant => arg.isZoomConstant;
}

// --- let / var / match / in / to-boolean --------------------------------------

class LetExpr extends Expr {
  LetExpr(this.bindings, this.body);

  final List<(String, Expr)> bindings;
  final Expr body;

  @override
  Object? evaluate(ExpressionContext ctx) {
    final vars = Map<String, Object?>.of(ctx.variables);
    for (final (name, value) in bindings) {
      vars[name] = value.evaluate(ExpressionContext(
        zoom: ctx.zoom,
        properties: ctx.properties,
        variables: vars,
      ));
    }
    return body.evaluate(ExpressionContext(
      zoom: ctx.zoom,
      properties: ctx.properties,
      variables: vars,
    ));
  }

  @override
  bool get isFeatureConstant =>
      bindings.every((b) => b.$2.isFeatureConstant) && body.isFeatureConstant;

  @override
  bool get isZoomConstant =>
      bindings.every((b) => b.$2.isZoomConstant) && body.isZoomConstant;
}

class VarExpr extends Expr {
  const VarExpr(this.name);
  final String name;

  @override
  Object? evaluate(ExpressionContext ctx) => ctx.variables[name];

  // The enclosing `let` accounts for the dependency; a bare `var` is constant.
  @override
  bool get isFeatureConstant => true;

  @override
  bool get isZoomConstant => true;
}

class MatchExpr extends Expr {
  MatchExpr(this.input, this.pairs, this.fallback);

  final Expr input;

  /// label (a scalar, or a list of scalars) -> output.
  final List<(Object?, Expr)> pairs;
  final Expr fallback;

  @override
  Object? evaluate(ExpressionContext ctx) {
    final v = input.evaluate(ctx);
    for (final (label, out) in pairs) {
      if (label is List) {
        if (label.contains(v)) return out.evaluate(ctx);
      } else if (label == v) {
        return out.evaluate(ctx);
      }
    }
    return fallback.evaluate(ctx);
  }

  @override
  bool get isFeatureConstant =>
      input.isFeatureConstant &&
      pairs.every((p) => p.$2.isFeatureConstant) &&
      fallback.isFeatureConstant;

  @override
  bool get isZoomConstant =>
      input.isZoomConstant &&
      pairs.every((p) => p.$2.isZoomConstant) &&
      fallback.isZoomConstant;
}

class InExpr extends Expr {
  const InExpr(this.needle, this.haystack);
  final Expr needle;
  final Expr haystack;

  @override
  Object? evaluate(ExpressionContext ctx) {
    final h = haystack.evaluate(ctx);
    final n = needle.evaluate(ctx);
    if (h is List) return h.contains(n);
    if (h is String) return h.contains('$n');
    return false;
  }

  @override
  bool get isFeatureConstant =>
      needle.isFeatureConstant && haystack.isFeatureConstant;

  @override
  bool get isZoomConstant => needle.isZoomConstant && haystack.isZoomConstant;
}

class ToBooleanExpr extends Expr {
  const ToBooleanExpr(this.arg);
  final Expr arg;

  @override
  Object? evaluate(ExpressionContext ctx) {
    final v = arg.evaluate(ctx);
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true';
    return false;
  }

  @override
  bool get isFeatureConstant => arg.isFeatureConstant;

  @override
  bool get isZoomConstant => arg.isZoomConstant;
}

// --- parser ------------------------------------------------------------------

/// True when [json] is an expression array (first element is an operator).
bool isExpressionJson(Object? json) =>
    json is List && json.isNotEmpty && json.first is String;

/// Parse a style property value that may be a literal or an expression array.
Expr parseExpression(Object? json) {
  if (json is List) return _parseArray(json);
  return LiteralExpr(json);
}

Expr _parseArray(List json) {
  if (json.isEmpty) throw const FormatException('empty expression');
  final op = json.first;
  if (op is! String) {
    throw const FormatException('expression[0] must be a string');
  }
  switch (op) {
    case 'literal':
      return LiteralExpr(json[1]);
    case 'get':
      return GetExpr(_string(json[1]));
    case 'has':
      return HasExpr(_string(json[1]));
    case 'zoom':
      return const ZoomExpr();
    case '==':
    case '!=':
    case '>':
    case '<':
    case '>=':
    case '<=':
      return ComparisonExpr(
          op, parseExpression(json[1]), parseExpression(json[2]));
    case 'all':
      return LogicalExpr(true, _exprList(json, 1));
    case 'any':
      return LogicalExpr(false, _exprList(json, 1));
    case '!':
      return NotExpr(parseExpression(json[1]));
    case 'interpolate':
      return _parseInterpolate(json);
    case 'step':
      return _parseStep(json);
    case 'case':
      return _parseCase(json);
    case 'coalesce':
      return CoalesceExpr(_exprList(json, 1));
    case 'let':
      return _parseLet(json);
    case 'var':
      return VarExpr(_string(json[1]));
    case 'match':
      return _parseMatch(json);
    case 'in':
      return InExpr(parseExpression(json[1]), parseExpression(json[2]));
    case 'to-number':
      return ToNumberExpr(parseExpression(json[1]));
    case 'to-string':
      return ToStringExpr(parseExpression(json[1]));
    case 'to-color':
      return ToColorExpr(parseExpression(json[1]));
    case 'to-boolean':
      return ToBooleanExpr(parseExpression(json[1]));
    // Arithmetic. MapLibre's v8 spec allows these in any expression, including
    // filters (`["<=", ["get", "rank"], ["+", ["zoom"], 1]]` is a common way to
    // gate labels by zoom).
    case '+':
      return ArithmeticExpr(ArithmeticOp.add, _operands(json));
    case '-':
      return ArithmeticExpr(ArithmeticOp.subtract, _operands(json));
    case '*':
      return ArithmeticExpr(ArithmeticOp.multiply, _operands(json));
    case '/':
      return ArithmeticExpr(ArithmeticOp.divide, _operands(json));
    case '%':
      return ArithmeticExpr(ArithmeticOp.modulo, _operands(json));
    default:
      throw FormatException('unsupported expression operator: $op');
  }
}

/// Operands of an n-ary arithmetic node.
List<Expr> _operands(List json) {
  if (json.length < 2) {
    throw FormatException('${json.first}: needs at least one operand');
  }
  return [for (var i = 1; i < json.length; i++) parseExpression(json[i])];
}

enum ArithmeticOp { add, subtract, multiply, divide, modulo }

/// n-ary arithmetic, folded left to right.
///
/// `+` doubles as string concatenation when every operand is a string (v8 spec
/// does the same). Division and modulo by zero yield `null` instead of
/// `Infinity`, because every consumer here treats a non-number as "no value".
class ArithmeticExpr extends Expr {
  const ArithmeticExpr(this.op, this.operands);

  final ArithmeticOp op;
  final List<Expr> operands;

  @override
  Object? evaluate(ExpressionContext ctx) {
    if (operands.length == 1) {
      final only = operands.first.evaluate(ctx);
      if (op == ArithmeticOp.subtract) {
        return only is num ? -only.toDouble() : null;
      }
      return only is num ? only.toDouble() : only;
    }

    var acc = operands.first.evaluate(ctx);
    for (var i = 1; i < operands.length; i++) {
      final next = operands[i].evaluate(ctx);
      if (op == ArithmeticOp.add && acc is String && next is String) {
        acc = acc + next;
        continue;
      }
      if (acc is! num || next is! num) return null;
      final a = acc.toDouble();
      final b = next.toDouble();
      acc = switch (op) {
        ArithmeticOp.add => a + b,
        ArithmeticOp.subtract => a - b,
        ArithmeticOp.multiply => a * b,
        ArithmeticOp.divide => b == 0 ? null : a / b,
        ArithmeticOp.modulo => b == 0 ? null : a % b,
      };
      if (acc == null) return null;
    }
    return acc;
  }

  @override
  bool get isFeatureConstant =>
      operands.every((e) => e.isFeatureConstant);

  @override
  bool get isZoomConstant => operands.every((e) => e.isZoomConstant);
}

Expr _parseInterpolate(List json) {
  final spec = json[1];
  if (spec is! List || spec.isEmpty || spec.first is! String) {
    throw const FormatException('interpolate: bad interpolation spec');
  }
  final kind = spec.first as String;
  var base = 1.0;
  if (kind == 'exponential') {
    base = (spec.length > 1 ? _number(spec[1]) : 2).toDouble();
  } else if (kind != 'linear') {
    throw FormatException('interpolate: unsupported interpolation "$kind"');
  }
  final input = parseExpression(json[2]);
  final stops = <num>[];
  final outputs = <Expr>[];
  for (var i = 3; i + 1 < json.length; i += 2) {
    stops.add(_number(json[i]));
    outputs.add(parseExpression(json[i + 1]));
  }
  _checkStops(stops, minimum: 2);
  return InterpolateExpr(input, stops, outputs, base: base);
}

Expr _parseStep(List json) {
  if (json.length < 4 || (json.length - 3).isOdd) {
    throw const FormatException('step: bad form (want input, default, stops...)');
  }
  final input = parseExpression(json[1]);
  final fallback = parseExpression(json[2]);
  final stops = <num>[];
  final outputs = <Expr>[];
  for (var i = 3; i + 1 < json.length; i += 2) {
    stops.add(_number(json[i]));
    outputs.add(parseExpression(json[i + 1]));
  }
  _checkStops(stops, minimum: 1);
  return StepExpr(input, fallback, stops, outputs);
}

Expr _parseCase(List json) {
  if (json.length < 4 || json.length.isOdd) {
    throw const FormatException('case: want condition/value pairs + fallback');
  }
  final pairs = <(Expr, Expr)>[];
  for (var i = 1; i + 2 < json.length; i += 2) {
    pairs.add((parseExpression(json[i]), parseExpression(json[i + 1])));
  }
  return CaseExpr(pairs, parseExpression(json.last));
}

Expr _parseLet(List json) {
  // ['let', name, value, ..., body]
  if (json.length < 4 || json.length.isOdd) {
    throw const FormatException('let: want name/value pairs + body');
  }
  final bindings = <(String, Expr)>[];
  for (var i = 1; i + 2 < json.length; i += 2) {
    bindings.add((_string(json[i]), parseExpression(json[i + 1])));
  }
  return LetExpr(bindings, parseExpression(json.last));
}

Expr _parseMatch(List json) {
  // ['match', input, label, output, ..., fallback]
  if (json.length < 4 || json.length.isEven) {
    throw const FormatException('match: want input, pairs + fallback');
  }
  final pairs = <(Object?, Expr)>[];
  for (var i = 2; i + 2 < json.length; i += 2) {
    pairs.add((json[i], parseExpression(json[i + 1])));
  }
  return MatchExpr(parseExpression(json[1]), pairs, parseExpression(json.last));
}

/// Enforce MapLibre's rule: `zoom` may only appear as the direct input of a
/// `step` / `interpolate` (a zoom curve), never nested elsewhere.
///
/// This is a pragmatic version of `findZoomCurve` (`[SPEC] expression/index.ts:721`);
/// it does not additionally require the curve to be at the very top level, so
/// `['==', ['step', ['zoom'], ...], 5]` is accepted here (MapLibre rejects it).
void validateZoomUsage(Expr root) {
  if (!_zoomAllowed(root, allowed: false)) {
    throw const FormatException(
        'zoom may only be the input of a step/interpolate');
  }
}

bool _zoomAllowed(Expr e, {required bool allowed}) {
  if (e is ZoomExpr) return allowed;
  if (e is StepExpr) {
    return _zoomAllowed(e.input, allowed: true) &&
        _zoomAllowed(e.fallback, allowed: false) &&
        e.outputs.every((o) => _zoomAllowed(o, allowed: false));
  }
  if (e is InterpolateExpr) {
    return _zoomAllowed(e.input, allowed: true) &&
        e.outputs.every((o) => _zoomAllowed(o, allowed: false));
  }
  for (final c in _children(e)) {
    if (!_zoomAllowed(c, allowed: false)) return false;
  }
  return true;
}

Iterable<Expr> _children(Expr e) {
  if (e is ComparisonExpr) return [e.left, e.right];
  if (e is NotExpr) return [e.arg];
  if (e is LogicalExpr) return e.args;
  if (e is CaseExpr) {
    return [for (final p in e.pairs) ...[p.$1, p.$2], e.fallback];
  }
  if (e is CoalesceExpr) return e.args;
  if (e is ToNumberExpr) return [e.arg];
  if (e is ToStringExpr) return [e.arg];
  if (e is ToColorExpr) return [e.arg];
  if (e is ToBooleanExpr) return [e.arg];
  if (e is LetExpr) return [for (final b in e.bindings) b.$2, e.body];
  if (e is MatchExpr) return [e.input, ...e.pairs.map((p) => p.$2), e.fallback];
  if (e is InExpr) return [e.needle, e.haystack];
  return const [];
}

void _checkStops(List<num> stops, {required int minimum}) {
  if (stops.length < minimum) {
    throw FormatException('interpolate/step: at least $minimum stop(s)');
  }
  for (var i = 1; i < stops.length; i++) {
    if (stops[i] <= stops[i - 1]) {
      throw const FormatException('stops must be strictly increasing');
    }
  }
}

List<Expr> _exprList(List json, int start) =>
    [for (var i = start; i < json.length; i++) parseExpression(json[i])];

String _string(Object? v) {
  if (v is String) return v;
  throw FormatException('expected a string, got $v');
}

num _number(Object? v) {
  if (v is num) return v;
  throw FormatException('expected a number, got $v');
}
