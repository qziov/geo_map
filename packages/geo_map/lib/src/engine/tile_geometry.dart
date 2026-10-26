/// Rendering backends for the shared tile engine.
///
/// Both backends consume the same [TileDraw] commands (footprint + texture
/// region), so the 2D and the 3D stack can never disagree about *what* to
/// draw — only about *how* the pixels are placed on screen:
///
/// * [SphericalGeometry] — orthographic globe (3D): spherical mesh, horizon
///   culling, polar caps.
/// * [AffineGeometry] — Web Mercator plane (2D): world-pixel rectangles with
///   world copies.
///
/// The camera is passed **per call** (not stored in the backend) so that one
/// backend instance can serve every frame and the mesh cache can be reused
/// across frames.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';

import 'tile_engine.dart';

/// Draws a frame of tile commands.
abstract class TileGeometry {
  const TileGeometry();

  /// Draw one tile command.
  void drawTile(
    Canvas canvas,
    TileDraw draw, {
    required CameraState camera,
    required double opacity,
  });

  /// Draw one polar cap command.
  void drawCap(
    Canvas canvas,
    CapDraw cap, {
    required CameraState camera,
    required double opacity,
  });
}

/// Orthographic (3D globe) geometry.
class SphericalGeometry extends TileGeometry {
  const SphericalGeometry({
    required this.projector,
    required this.scheme,
    this.meshBuilder,
  });

  final GeoProjector projector;
  final TileSchemeKind scheme;

  /// Shared mesh cache — the unit meshes are projection independent, so they
  /// survive panning and zoom changes.
  final TileMeshBuilder? meshBuilder;

  int _subdivFor(TileGrid grid, CameraState camera) {
    final tileScreenPx = 2 * math.pi * camera.radiusPx / grid.cols;
    return (tileScreenPx / GeoEngineTuning.subdivPx)
        .ceil()
        .clamp(GeoEngineTuning.subdivMin, GeoEngineTuning.subdivMax);
  }

  @override
  void drawTile(
    Canvas canvas,
    TileDraw draw, {
    required CameraState camera,
    required double opacity,
  }) {
    final grid = TileGrid.of(scheme, draw.geoKey.z);
    final builder = meshBuilder;
    final mesh = builder != null
        ? builder.unitMesh(
            grid,
            draw.geoKey.x,
            draw.geoKey.y,
            _subdivFor(grid, camera),
          )
        : TileMeshBuilder().unitMesh(
            grid,
            draw.geoKey.x,
            draw.geoKey.y,
            _subdivFor(grid, camera),
          );
    final buffers = TileMeshBuilder.projectMesh(
      mesh,
      projector,
      camera,
      uvOriginX: draw.u0,
      uvOriginY: draw.v0,
      uvSpan: draw.spanU,
    );
    if (buffers.indices.isEmpty) return;
    final paint = Paint()
      ..isAntiAlias = true
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0))
      ..shader = draw.image.shader;
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        buffers.positions,
        textureCoordinates: buffers.uvs,
        indices: buffers.indices,
      ),
      BlendMode.srcOver,
      paint,
    );
  }

  /// Meridian subdivision of a cap strip — one step per degree. A single
  /// column (well under a degree wide wherever the wedge regime applies) stays
  /// a single quad; a full ring gets a round enough silhouette.
  static const double _capDegreesPerStep = 1;

  /// Latitude subdivision of a cap strip (mercator limit → pole).
  static const int _capLatSteps = 8;

  @override
  void drawCap(
    Canvas canvas,
    CapDraw cap, {
    required CameraState camera,
    required double opacity,
  }) {
    // The strip spans an arbitrary longitude interval — one column in the
    // wedge regime, up to a full ring in the smeared regime. Either way it is
    // **one** mesh, so the cap can never turn into a fan of per-column
    // textures again.
    final lngSteps =
        (cap.spanLng / _capDegreesPerStep).ceil().clamp(1, 360).toInt();
    final mesh = PolarCapBuilder.buildSpan(
      startLng: cap.startLng,
      spanLng: cap.spanLng,
      north: cap.north,
      lngSteps: lngSteps,
      latSteps: _capLatSteps,
    );

    final cols = mesh.cols;
    final rows = mesh.rows;
    final count = mesh.vertexCount;
    final stride = cols + 1;
    final positions = Float32List(count * 2);
    final uvs = Float32List(count * 2);
    final depths = Float32List(count);

    final basis = cameraBasis(
        LatLng(camera.clampedLatitude, camera.center.longitude));
    final clip = projector.clipCircle(camera);
    final center = camera.size.center;

    for (var j = 0; j <= rows; j++) {
      for (var i = 0; i <= cols; i++) {
        final idx = j * stride + i;
        final unit = Vec3(
          mesh.unit[idx * 3],
          mesh.unit[idx * 3 + 1],
          mesh.unit[idx * 3 + 2],
        );
        final depth = projector.hasDepth ? unit.dot(basis.forward) : 1.0;
        depths[idx] = depth;

        final p = depth > GeoEngineTuning.epsDepth
            ? projector.projectUnit(unit, camera)
            : null;
        if (p != null) {
          positions[idx * 2] = p.x;
          positions[idx * 2 + 1] = p.y;
        } else if (clip == null) {
          positions[idx * 2] = center.x;
          positions[idx * 2 + 1] = center.y;
        } else {
          // Behind the horizon: clamp onto the silhouette along the **camera**
          // basis. Using the world x/y here (as the first version did) put
          // near-pole vertices — where the world x/y nearly vanish — at the
          // centre of the screen instead of the limb.
          final vx = unit.dot(basis.east);
          final vy = unit.dot(basis.north);
          final len = math.sqrt(vx * vx + vy * vy);
          if (len < 1e-9) {
            positions[idx * 2] = center.x;
            positions[idx * 2 + 1] = center.y;
          } else {
            positions[idx * 2] = center.x + vx / len * clip.radius;
            positions[idx * 2 + 1] = center.y - vy / len * clip.radius;
          }
        }

        // u runs with longitude, v with the (one pixel tall) latitude band.
        uvs[idx * 2] = cap.u0 + (i / cols) * cap.spanU;
        uvs[idx * 2 + 1] = cap.v0 + (j / rows) * cap.vSpan;
      }
    }

    final indices = TileMeshBuilder.cullIndices(mesh.indices, depths);
    if (indices.isEmpty) return;
    final paint = Paint()
      ..isAntiAlias = true
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0))
      ..shader = cap.image.shader;
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: uvs,
        indices: indices,
      ),
      BlendMode.srcOver,
      paint,
    );
  }
}

/// Web Mercator (2D) geometry: world-pixel rectangles.
class AffineGeometry extends TileGeometry {
  const AffineGeometry({required this.scheme});

  final TileSchemeKind scheme;

  /// How many world copies are drawn around the camera longitude.
  static const int worldCopies = 1;

  @override
  void drawTile(
    Canvas canvas,
    TileDraw draw, {
    required CameraState camera,
    required double opacity,
  }) {
    final grid = TileGrid.of(scheme, draw.geoKey.z);
    final world = camera.worldSize;
    final tileW = world / grid.cols;
    final tileH = world / grid.rows;

    final left = (grid.west(draw.geoKey.x) + 180) / 360 * world;
    final top = _rowTop(grid, draw.geoKey.y, world);

    final originX = (camera.center.longitude + 180) / 360 * world -
        camera.size.width / 2;
    final originY = _centerY(world, camera) - camera.size.height / 2;

    final viewport = Rect.fromLTWH(
      0,
      0,
      camera.size.width,
      camera.size.height,
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));

    for (var copy = -worldCopies; copy <= worldCopies; copy++) {
      final dst = Rect.fromLTWH(
        left + copy * world - originX,
        top - originY,
        tileW,
        tileH,
      );
      if (!dst.overlaps(viewport)) continue;
      canvas.drawImageRect(draw.image.image, draw.sourceRect, dst, paint);
    }
  }

  @override
  void drawCap(
    Canvas canvas,
    CapDraw cap, {
    required CameraState camera,
    required double opacity,
  }) {
    // The flat plane ends at the mercator limit — there is no pole to fill.
  }

  double _centerY(double world, CameraState camera) =>
      mercatorTAt(camera.center.latitude) * world;

  double _rowTop(TileGrid grid, int y, double world) {
    if (grid.kind == TileSchemeKind.webMercator) {
      // Mercator rows are uniform in world-Y.
      return y / grid.rows * world;
    }
    // Other grids are mapped through their own latitude bands.
    return mercatorTAt(grid.north(y)) * world;
  }
}
