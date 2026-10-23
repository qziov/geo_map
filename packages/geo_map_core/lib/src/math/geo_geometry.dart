/// Self-contained geometry primitives so `geo_map_core` stays free of `dart:ui`.
library;

import 'dart:math' as math;

class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double k) => Vec2(x * k, y * k);

  double distanceTo(Vec2 o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));

  @override
  String toString() => 'Vec2(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

class ViewportSize {
  const ViewportSize(this.width, this.height);

  final double width;
  final double height;

  Vec2 get center => Vec2(width / 2, height / 2);
  double get diagonal => math.sqrt(width * width + height * height);
}

class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(double lat, double lng) =>
      lat >= south && lat <= north && lng >= west && lng <= east;

  @override
  String toString() => 'GeoBounds($south,$west,$north,$east)';
}
