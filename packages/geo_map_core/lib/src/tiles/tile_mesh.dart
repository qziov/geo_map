/// Tile mesh: unit-sphere vertex cache + per-frame projection into screen space.
///
/// Design constraint (plan §7.1): vertices are cached on the unit sphere, so
/// panning does **not** rebuild geometry — the layer can reuse `ui.Vertices`
/// through `canvas.transform`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../camera/camera_state.dart';
import '../math/geodesy.dart';
import '../projection/geo_projector.dart';
import '../tuning/geo_engine_tuning.dart';
import 'tile_scheme.dart';

/// Cached geometry in unit-sphere space (projection independent).
class UnitMesh {
  UnitMesh(this.unit, this.uv, this.indices, this.subdiv, this.vertexCount);

  final Float32List unit; // x,y,z per vertex
  final Float32List uv; // texture coordinates in image pixels
  final Uint16List indices; // base grid triangle soup
  final int subdiv;
  final int vertexCount;
}

/// One frame's projection result, ready for `ui.Vertices.raw`.
class MeshBuffers {
  MeshBuffers(this.positions, this.uvs, this.depths, this.indices);

  final Float32List positions; // screen px, interleaved
  final Float32List uvs; // image px
  final Float32List depths; // dot(unit, cameraForward)
  final Uint16List indices; // culled triangle soup
}

class TileMeshBuilder {
  final Map<String, UnitMesh> _cache = {};

  /// Cache misses — asserted by `mesh_reuse_test`.
  int buildCount = 0;

  int get cachedCount => _cache.length;

  UnitMesh unitMesh(TileGrid grid, int x, int y, int subdiv) {
    final key = '${grid.kind.name}/${grid.zoom}/$x/$y/$subdiv';
    final cached = _cache[key];
    if (cached != null) return cached;
    buildCount++;

    final n = subdiv.clamp(GeoEngineTuning.subdivMin, GeoEngineTuning.subdivMax);
    final count = (n + 1) * (n + 1);
    final unit = Float32List(count * 3);
    final uv = Float32List(count * 2);

    final west = grid.west(x);
    final east = grid.east(x);

    for (var j = 0; j <= n; j++) {
      final lat = grid.latitudeAt(y, j / n);
      for (var i = 0; i <= n; i++) {
        final lng = west + (east - west) * (i / n);
        final v = Vec3.of(LatLng(lat, lng));
        final idx = j * (n + 1) + i;
        unit[idx * 3] = v.x;
        unit[idx * 3 + 1] = v.y;
        unit[idx * 3 + 2] = v.z;
        uv[idx * 2] = (i / n) * GeoEngineTuning.tileSize;
        uv[idx * 2 + 1] = (j / n) * GeoEngineTuning.tileSize;
      }
    }

    final mesh = UnitMesh(unit, uv, _gridIndices(n), n, count);
    _cache[key] = mesh;
    return mesh;
  }

  /// Project a cached unit mesh for [camera].
  ///
  /// Hidden vertices are clamped onto the limb (never NaN) so partial tiles keep
  /// their silhouette; [cullIndices] then drops only fully-hidden triangles.
  ///
  /// [uvOriginX]/[uvOriginY]/[uvSpan] re-map the tile's `[0,tileSize]` UV space
  /// into a parent image's **pixel** space (parent-tile fallback and overzoom).
  /// The common path (origin 0, full span) reuses the cached UV array without
  /// allocating.
  MeshBuffers project(
    UnitMesh mesh,
    GeoProjector projector,
    CameraState camera, {
    Float32List? positionBuffer,
    Float32List? depthBuffer,
    double uvOriginX = 0,
    double uvOriginY = 0,
    double uvSpan = GeoEngineTuning.tileSizeD,
  }) =>
      projectMesh(
        mesh,
        projector,
        camera,
        positionBuffer: positionBuffer,
        depthBuffer: depthBuffer,
        uvOriginX: uvOriginX,
        uvOriginY: uvOriginY,
        uvSpan: uvSpan,
      );

  /// The projection core — stateless, so it can be used without a builder.
  static MeshBuffers projectMesh(
    UnitMesh mesh,
    GeoProjector projector,
    CameraState camera, {
    Float32List? positionBuffer,
    Float32List? depthBuffer,
    double uvOriginX = 0,
    double uvOriginY = 0,
    double uvSpan = GeoEngineTuning.tileSizeD,
  }) {
    final count = mesh.vertexCount;
    final positions =
        positionBuffer != null && positionBuffer.length >= count * 2
            ? positionBuffer
            : Float32List(count * 2);
    final depths = depthBuffer != null && depthBuffer.length >= count
        ? depthBuffer
        : Float32List(count);

    final center = camera.size.center;
    final basis = cameraBasis(
        LatLng(camera.clampedLatitude, camera.center.longitude));
    final clip = projector.clipCircle(camera);

    for (var i = 0; i < count; i++) {
      final unit = Vec3(
        mesh.unit[i * 3],
        mesh.unit[i * 3 + 1],
        mesh.unit[i * 3 + 2],
      );
      final depth = projector.hasDepth ? unit.dot(basis.forward) : 1.0;
      depths[i] = depth;

      final p = depth > GeoEngineTuning.epsDepth
          ? projector.projectUnit(unit, camera)
          : null;
      if (p != null) {
        positions[i * 2] = p.x;
        positions[i * 2 + 1] = p.y;
        continue;
      }
      // Hidden: clamp radially onto the limb.
      if (clip == null) {
        final flat = projector.project(unit.toLatLng(), camera);
        positions[i * 2] = flat?.x ?? center.x;
        positions[i * 2 + 1] = flat?.y ?? center.y;
      } else {
        final vx = unit.dot(basis.east);
        final vy = unit.dot(basis.north);
        final len = math.sqrt(vx * vx + vy * vy);
        if (len < 1e-9) {
          positions[i * 2] = center.x;
          positions[i * 2 + 1] = center.y;
        } else {
          positions[i * 2] = center.x + vx / len * clip.radius;
          positions[i * 2 + 1] = center.y - vy / len * clip.radius;
        }
      }
    }

    final fullBand = uvOriginX == 0 &&
        uvOriginY == 0 &&
        uvSpan == GeoEngineTuning.tileSizeD;
    Float32List outUv = mesh.uv;
    if (!fullBand) {
      outUv = Float32List(count * 2);
      // The mesh UVs run over `[0, tileSize]`; scale them into the parent's
      // pixel space.
      final k = uvSpan / GeoEngineTuning.tileSizeD;
      for (var i = 0; i < count; i++) {
        outUv[i * 2] = uvOriginX + mesh.uv[i * 2] * k;
        outUv[i * 2 + 1] = uvOriginY + mesh.uv[i * 2 + 1] * k;
      }
    }

    return MeshBuffers(
        positions, outUv, depths, cullIndices(mesh.indices, depths));
  }

  /// Drop triangles whose three corners are all behind the horizon.
  static Uint16List cullIndices(Uint16List source, Float32List depths) {
    final out = <int>[];
    for (var i = 0; i + 2 < source.length; i += 3) {
      final a = source[i], b = source[i + 1], c = source[i + 2];
      if (depths[a] <= GeoEngineTuning.epsDepth &&
          depths[b] <= GeoEngineTuning.epsDepth &&
          depths[c] <= GeoEngineTuning.epsDepth) {
        continue;
      }
      out.addAll([a, b, c]);
    }
    return Uint16List.fromList(out);
  }

  static Uint16List _gridIndices(int n) {
    final out = <int>[];
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final i00 = j * (n + 1) + i;
        final i10 = i00 + 1;
        final i01 = i00 + n + 1;
        final i11 = i01 + 1;
        out.addAll([i00, i10, i11, i00, i11, i01]);
      }
    }
    return Uint16List.fromList(out);
  }

  void clear() {
    _cache.clear();
    buildCount = 0;
  }
}

/// The sub-rectangle of a parent image that holds one descendant tile.
///
/// Web Mercator rows are exact halves of their parent row (see
/// `tile_scheme.dart`: `north(2y) == parent.north(y)`), so the descendant
/// occupies an **axis-aligned** rectangle of the parent image:
///
/// ```text
/// u0 = (childX mod 2^dz) / 2^dz * parentWidth
/// v0 = (childY mod 2^dz) / 2^dz * parentHeight
/// span = parentWidth / 2^dz
/// ```
///
/// This is the maplibre `getFadeProperties` / parent-tile fade mechanism, and
/// it is also how **overzoom** is expressed: the renderer draws the geometry
/// of the deeper (render) cell but samples the shallower (data) image.
({double u0, double v0, double spanU, double spanV}) parentUvRect({
  required int childX,
  required int childY,
  required int dz,
  required double parentWidth,
  required double parentHeight,
}) {
  final n = 1 << dz;
  final spanU = parentWidth / n;
  final spanV = parentHeight / n;
  return (
    u0: (childX % n) * spanU,
    v0: (childY % n) * spanV,
    spanU: spanU,
    spanV: spanV,
  );
}

/// Project a descendant tile while sampling a **parent** image.
///
/// The geometry comes from [childMesh] (the deeper, finer grid) and the UV
/// from the parent's sub-rectangle. Getting this backwards — parent geometry
/// with a child UV — stretches a quarter of the parent image across the whole
/// parent footprint and is the classic source of "mosaic blocks" during a zoom
/// transition.
///
/// [uvSpan] is expressed in the parent image's own pixel space, so the caller
/// must pass the *actual* decoded image size, not the nominal tile size.
MeshBuffers projectChildWithParentUv({
  required UnitMesh childMesh,
  required GeoProjector projector,
  required CameraState camera,
  required double parentWidth,
  required double parentHeight,
  required int childX,
  required int childY,
  required int dz,
  Float32List? positionBuffer,
  Float32List? depthBuffer,
}) {
  final rect = parentUvRect(
    childX: childX,
    childY: childY,
    dz: dz,
    parentWidth: parentWidth,
    parentHeight: parentHeight,
  );
  // The mesh UVs run over `[0, tileSize]`; `projectMesh` scales them into the
  // parent's pixel space via `uvSpan / tileSize`. The child's own extent must
  // cover exactly the parent's sub-rectangle, so `uvSpan` is that rectangle's
  // width in parent pixels.
  return TileMeshBuilder.projectMesh(
    childMesh,
    projector,
    camera,
    positionBuffer: positionBuffer,
    depthBuffer: depthBuffer,
    uvOriginX: rect.u0,
    uvOriginY: rect.v0,
    uvSpan: rect.spanU,
  );
}
