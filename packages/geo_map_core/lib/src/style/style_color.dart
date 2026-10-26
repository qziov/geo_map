/// A minimal CSS color used by style paint values.
///
/// Pure Dart (no `dart:ui`) so it can be unit-tested and reused by the core
/// style evaluator; the Flutter layer converts it to `ui.Color` at draw time.
library;

class StyleColor {
  const StyleColor(this.r, this.g, this.b, [this.a = 255]);

  final int r;
  final int g;
  final int b;
  final int a;

  static const Map<String, int> _named = {
    'black': 0x000000ff,
    'white': 0xffffffff,
    'red': 0xff0000ff,
    'green': 0x008000ff,
    'blue': 0x0000ffff,
    'transparent': 0x00000000,
    'gray': 0x808080ff,
    'grey': 0x808080ff,
  };

  /// Parse a CSS color: `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, a
  /// few named colors, an `0xAARRGGBB` int, or an existing [StyleColor].
  static StyleColor parse(Object? value) {
    if (value is StyleColor) return value;
    if (value is int) {
      return StyleColor(
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      );
    }
    if (value is String) {
      final s = value.trim().toLowerCase();
      if (s.startsWith('#')) {
        var hex = s.substring(1);
        if (hex.length == 3) {
          hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
        }
        if (hex.length == 6) hex = '${hex}ff';
        if (hex.length == 8) {
          final v = int.tryParse(hex, radix: 16);
          if (v != null) {
            return StyleColor(
              (v >> 24) & 0xff,
              (v >> 16) & 0xff,
              (v >> 8) & 0xff,
              v & 0xff,
            );
          }
        }
        throw FormatException('bad hex color: $value');
      }
      final named = _named[s];
      if (named != null) {
        return StyleColor(
          (named >> 24) & 0xff,
          (named >> 16) & 0xff,
          (named >> 8) & 0xff,
          named & 0xff,
        );
      }
      final m = RegExp(r'^rgba?\(([^)]+)\)$').firstMatch(s);
      if (m != null) {
        final parts = m.group(1)!.split(',').map((p) => p.trim()).toList();
        if (parts.length < 3 || parts.length > 4) {
          throw FormatException('bad rgb(): $value');
        }
        int channel(String p) => p.endsWith('%')
            ? (double.parse(p.substring(0, p.length - 1)) * 255 / 100).round()
            : double.parse(p).round();
        final alpha =
            parts.length == 4 ? (double.parse(parts[3]) * 255).round() : 255;
        return StyleColor(
          channel(parts[0]),
          channel(parts[1]),
          channel(parts[2]),
          alpha,
        );
      }
    }
    throw FormatException('not a color: $value');
  }

  static StyleColor lerp(StyleColor x, StyleColor y, double t) => StyleColor(
        (x.r + (y.r - x.r) * t).round(),
        (x.g + (y.g - x.g) * t).round(),
        (x.b + (y.b - x.b) * t).round(),
        (x.a + (y.a - x.a) * t).round(),
      );

  String toCss() {
    String h(int v) => v.toRadixString(16).padLeft(2, '0');
    return a == 255
        ? '#${h(r)}${h(g)}${h(b)}'
        : '#${h(r)}${h(g)}${h(b)}${h(a)}';
  }

  @override
  bool operator ==(Object other) =>
      other is StyleColor &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'StyleColor(${toCss()})';
}
