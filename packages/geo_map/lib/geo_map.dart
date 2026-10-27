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
// Re-export the style-spec API so apps only need `package:geo_map/geo_map.dart`.
export 'package:geo_map_core/geo_map_core.dart'
    show
        StyleSpec,
        StyleDocument,
        StyleLayer,
        StyleColor,
        PropertyValue,
        Expr,
        ExpressionContext,
        GeoJsonFeature,
        GeoJsonGeometry,
        // Geometry subclasses: needed to build features in code, not only by
        // parsing a FeatureCollection.
        PointGeometry,
        LineStringGeometry,
        PolygonGeometry,
        MultiLineStringGeometry,
        MultiPolygonGeometry,
        parseGeoJsonFeatures,
        compileFilter,
        FeaturePredicate,
        // Needed to implement `GeoTileSource` outside this package.
        GeoEngineTuning,
        GeoTileSource,
        TileFetchResult,
        TileFailureKind,
        TileRowOrder,
        TileSchemeKind,
        // Building a sprite atlas in code needs the index types.
        SpriteIndex,
        SpriteIcon;
export 'src/style/style_controller.dart';
export 'src/style/sprite_atlas.dart';
export 'src/style/style_vector_layer.dart';
export 'src/style/mvt_vector_layer.dart';
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
        buildGreatCircle,
        densifyPath;
export 'src/globe/tile_source.dart';
export 'src/source/debug_tiles_source.dart';
// MBTiles needs `dart:io` + sqlite3. On web the stub keeps the name but throws,
// so importing this barrel never drags `dart:io` into a browser build.
export 'src/source/mbtiles_source.dart'
    if (dart.library.js_interop) 'src/source/mbtiles_source_stub.dart';
export 'src/vendor/flutter_map_camera/flutter_map_camera.dart'
    hide CrsWithStaticTransformation, Projection;
export 'src/widget/geo_map.dart';
