import 'dart:math' as math hide Point;
import 'dart:math' show Point;

import 'bounds.dart';
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

/// An abstract representation of a
/// [Coordinate Reference System](https://bit.ly/3iVKpja).
///
/// The main objective of a CRS is to handle the conversion between surface
/// points of objects of different dimensions. In our case 3D and 2D objects.
@immutable
abstract class Crs {
  /// The code
  @nonVirtual
  final String code;

  /// Set to true if the CRS has no bounds.
  @nonVirtual
  final bool infinite;

  /// Wrap the longitude to fit inside the bounds of the [Crs].
  @nonVirtual
  final (double, double)? wrapLng;

  /// Wrap the latitude to fit inside the bounds of the [Crs].
  @nonVirtual
  final (double, double)? wrapLat;

  /// Constant base constructor that sets all values for the abstract [Crs].
  const Crs({
    required this.code,
    required this.infinite,
    this.wrapLng,
    this.wrapLat,
  });

  /// Project a spherical LatLng coordinate into planar space (unscaled).
  Projection get projection;

  /// Scale planar coordinate to scaled map point.
  (double, double) transform(double x, double y, double scale);

  /// Scale map point to planar coordinate.
  (double, double) untransform(double x, double y, double scale);

  /// Converts a point on the sphere surface (with a certain zoom) to a
  /// scaled map point.
  (double, double) latLngToXY(LatLng latlng, double scale);

  /// Similar to [latLngToXY] but converts the XY coordinates to a [Point].
  Point<double> latLngToPoint(LatLng latlng, double zoom) {
    final (x, y) = latLngToXY(latlng, scale(zoom));
    return Point<double>(x, y);
  }

  /// Converts a map point to the sphere coordinate (at a certain zoom).
  LatLng pointToLatLng(Point point, double zoom);

  /// Zoom to Scale function.
  double scale(double zoom) => 256.0 * math.pow(2, zoom);

  /// Scale to Zoom function.
  double zoom(double scale) => math.log(scale / 256) / math.ln2;

  /// Rescales the bounds to a given zoom value.
  Bounds<double>? getProjectedBounds(double zoom);
}

/// Internal base class for CRS with a single zoom-level independent transformation.
@immutable
@internal
abstract class CrsWithStaticTransformation extends Crs {
  @nonVirtual
  @protected
  final _Transformation _transformation;

  @override
  final Projection projection;

  const CrsWithStaticTransformation._({
    required _Transformation transformation,
    required this.projection,
    required super.code,
    required super.infinite,
    super.wrapLng,
    super.wrapLat,
  }) : _transformation = transformation;

  @override
  (double, double) transform(double x, double y, double scale) =>
      _transformation.transform(x, y, scale);

  @override
  (double, double) untransform(double x, double y, double scale) =>
      _transformation.untransform(x, y, scale);

  @override
  (double, double) latLngToXY(LatLng latlng, double scale) {
    final (x, y) = projection.projectXY(latlng);
    return _transformation.transform(x, y, scale);
  }

  @override
  LatLng pointToLatLng(Point point, double zoom) {
    final (x, y) = _transformation.untransform(
      point.x.toDouble(),
      point.y.toDouble(),
      scale(zoom),
    );
    return projection.unprojectXY(x, y);
  }

  @override
  Bounds<double>? getProjectedBounds(double zoom) {
    if (infinite) return null;

    final b = projection.bounds!;
    final s = scale(zoom);
    final (minx, miny) = _transformation.transform(b.min.x, b.min.y, s);
    final (maxx, maxy) = _transformation.transform(b.max.x, b.max.y, s);
    return Bounds<double>(
      Point<double>(minx, miny),
      Point<double>(maxx, maxy),
    );
  }
}

/// Custom CRS for non geographical maps
@immutable
class CrsSimple extends CrsWithStaticTransformation {
  /// Create a new [CrsSimple].
  const CrsSimple()
      : super._(
          code: 'CRS.SIMPLE',
          transformation: const _Transformation(1, 0, -1, 0),
          projection: const _LonLat(),
          infinite: false,
          wrapLat: null,
          wrapLng: null,
        );
}

/// EPSG:3857, The most common CRS used for rendering maps.
@immutable
class Epsg3857 extends CrsWithStaticTransformation {
  static const double _scale = 0.5 / (math.pi * SphericalMercator.r);

  /// Create a new [Epsg3857] object.
  const Epsg3857()
      : super._(
          code: 'EPSG:3857',
          transformation: const _Transformation(_scale, 0.5, -_scale, 0.5),
          projection: const SphericalMercator(),
          infinite: false,
          wrapLng: const (-180, 180),
        );

  @override
  (double, double) latLngToXY(LatLng latlng, double scale) =>
      _transformation.transform(
        SphericalMercator.projectLng(latlng.longitude),
        SphericalMercator.projectLat(latlng.latitude),
        scale,
      );

  @override
  Point<double> latLngToPoint(LatLng latlng, double zoom) {
    final (x, y) = _transformation.transform(
      SphericalMercator.projectLng(latlng.longitude),
      SphericalMercator.projectLat(latlng.latitude),
      scale(zoom),
    );
    return Point<double>(x, y);
  }
}

/// EPSG:4326, A common CRS among GIS enthusiasts.
/// Uses simple Equirectangular projection.
@immutable
class Epsg4326 extends CrsWithStaticTransformation {
  /// Create a new [Epsg4326] CRS instance.
  const Epsg4326()
      : super._(
          projection: const _LonLat(),
          transformation: const _Transformation(1 / 180, 1, -1 / 180, 0.5),
          code: 'EPSG:4326',
          infinite: false,
          wrapLng: const (-180, 180),
        );
}

/// The abstract base [Projection] class, used for coordinate reference
/// systems like [Epsg3857].
/// Inherit from this class if you want to create or implement your own CRS.
@immutable
abstract class Projection {
  /// The [Bounds] for the coordinates of this [Projection].
  final Bounds<double>? bounds;

  /// Base constructor for the abstract [Projection] class that sets the
  /// required fields.
  const Projection(this.bounds);

  /// Converts a [LatLng] to a coordinates and returns them as [Point] object.
  @nonVirtual
  Point<double> project(LatLng latlng) {
    final (x, y) = projectXY(latlng);
    return Point<double>(x, y);
  }

  /// Converts a [LatLng] to geometry coordinates.
  (double, double) projectXY(LatLng latlng);

  /// unproject a cartesian Point to [LatLng].
  @nonVirtual
  LatLng unproject(Point point) =>
      unprojectXY(point.x.toDouble(), point.y.toDouble());

  /// unproject cartesian x,y coordinates to [LatLng].
  LatLng unprojectXY(double x, double y);
}

class _LonLat extends Projection {
  static const _bounds = Bounds<double>.unsafe(
    Point<double>(-180, -90),
    Point<double>(180, 90),
  );

  const _LonLat() : super(_bounds);

  @override
  (double, double) projectXY(LatLng latlng) =>
      (latlng.longitude, latlng.latitude);

  @override
  LatLng unprojectXY(double x, double y) =>
      LatLng(_inclusiveLat(y), _inclusiveLng(x));
}

/// Spherical mercator projection
@immutable
class SphericalMercator extends Projection {
  /// The radius
  static const int r = 6378137;

  /// The maximum latitude
  static const double maxLatitude = 85.0511287798;

  static const double _boundsD = r * math.pi;

  /// The constant Bounds of the [SphericalMercator] projection.
  static const Bounds<double> _bounds = Bounds<double>.unsafe(
    Point<double>(-_boundsD, -_boundsD),
    Point<double>(_boundsD, _boundsD),
  );

  /// Constant constructor for the [SphericalMercator] projection.
  const SphericalMercator() : super(_bounds);

  /// Project the latitude for this [Crs]
  static double projectLat(double latitude) {
    final lat = _clampSym(latitude, maxLatitude);
    final sin = math.sin(lat * math.pi / 180);

    return r / 2 * math.log((1 + sin) / (1 - sin));
  }

  /// Project the longitude for this [Crs]
  static double projectLng(double longitude) {
    return r * math.pi / 180 * longitude;
  }

  @override
  (double, double) projectXY(LatLng latlng) {
    return (
      projectLng(latlng.longitude),
      projectLat(latlng.latitude),
    );
  }

  @override
  LatLng unprojectXY(double x, double y) {
    const d = 180 / math.pi;
    return LatLng(
      _inclusiveLat((2 * math.atan(math.exp(y / r)) - (math.pi / 2)) * d),
      _inclusiveLng(x * d / r),
    );
  }
}

@immutable
class _Transformation {
  final double a;
  final double b;
  final double c;
  final double d;

  const _Transformation(this.a, this.b, this.c, this.d);

  @nonVirtual
  (double, double) transform(double x, double y, double scale) => (
        scale * (a * x + b),
        scale * (c * y + d),
      );

  @nonVirtual
  (double, double) untransform(double x, double y, double scale) => (
        (x / scale - b) / a,
        (y / scale - d) / c,
      );
}

// Num.clamp is slow due to virtual function overhead.
double _clampSym(double value, double limit) =>
    value < -limit ? -limit : (value > limit ? limit : value);

double _inclusiveLat(double value) => _clampSym(value, 90);

double _inclusiveLng(double value) => _clampSym(value, 180);
