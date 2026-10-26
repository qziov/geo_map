/// geo_map — a self-contained 2D/3D Flutter map engine.
///
/// The rendering stack is a single pipeline shared by both modes: the
/// [TileEngine] owns requests, the decode cache and the fallback chain, while
/// the geometry backend ([SphericalGeometry] / [AffineGeometry]) only decides
/// *where the pixels land*. A fix in one mode therefore cannot leave the
/// other broken.
library;

export 'src/camera/geo_map_controller.dart';
export 'src/diagnostics/geo_diagnostics.dart';
export 'src/engine/tile_engine.dart';
export 'src/engine/tile_geometry.dart';
export 'src/engine/tile_layer.dart';
export 'src/gesture/globe_gesture_overlay.dart';
export 'src/globe/globe_image_layer.dart';
export 'src/globe/geojson_vector_source.dart';
export 'src/globe/globe_projection.dart';
export 'src/globe/flat_tile_layer.dart';
export 'src/globe/globe_tile_layer.dart';
export 'src/globe/globe_vector_layer.dart'
    show
        GlobeVectorLayer,
        GlobePolyline,
        GlobePolygonShape,
        GlobeLabel,
        buildGraticule,
        buildTissot,
        densifyPath;
export 'src/globe/tile_source.dart';
export 'src/source/debug_tiles_source.dart';
export 'src/source/mbtiles_source.dart';
export 'src/vendor/flutter_map_camera/flutter_map_camera.dart'
    hide CrsWithStaticTransformation, Projection;
export 'src/widget/geo_map.dart';
