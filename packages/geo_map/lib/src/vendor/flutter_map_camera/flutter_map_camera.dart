/// Barrel for the vendored flutter_map camera subset.
///
/// Extracted from `flutter_map` (fork with the 12 globe patches) so that
/// `geo_map` has zero upstream dependency. Files kept byte-identical where
/// possible; only imports were re-pointed and `Proj4Crs`/proj4dart stripped.
library;

export 'bounds.dart';
export 'camera.dart';
export 'crs.dart';
export 'inherited_model.dart';
export 'latlng_bounds.dart';
export 'map_options.dart';
export 'projection_delegate.dart';
