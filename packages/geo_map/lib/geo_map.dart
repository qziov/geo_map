/// geo_map — a self-contained 2D/3D Flutter map engine.
///
/// 1.0 rendering stack: vendored flutter_map camera (12-patch fork extraction)
/// + the lab-proven globe layers. The self-built Vertices pipeline is kept in
/// `src/experimental/` (not exported) pending P4.
library;

export 'src/camera/geo_map_controller.dart';
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
