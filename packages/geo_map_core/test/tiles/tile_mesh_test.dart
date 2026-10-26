import 'dart:math' as math;
import 'dart:typed_data';

import 'package:geo_map_core/geo_map_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

CameraState _cam({
  LatLng center = const LatLng(30, 100),
  double zoom = 5,
}) =>
    CameraState(
      center: center,
      zoom: zoom,
      size: const ViewportSize(800, 600),
      minZoom: 0,
      maxZoom: 22,
    );


void main() {
  const ortho = OrthographicProjector();
  const merc = MercatorProjector();

  group('unit mesh cache', () {
    test('builds once and reuses', () {
      final builder = TileMeshBuilder();
      final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
      final a = builder.unitMesh(grid, 8, 5, 8);
      final b = builder.unitMesh(grid, 8, 5, 8);
      expect(identical(a, b), isTrue);
      expect(builder.buildCount, 1);
      expect(a.vertexCount, 81);
    });

    test('uv corners map to the image corners', () {
      final builder = TileMeshBuilder();
      final grid = TileGrid.of(TileSchemeKind.webMercator, 2);
      final mesh = builder.unitMesh(grid, 1, 1, 6);
      final n = mesh.subdiv;
      expect(mesh.uv[0], 0);
      expect(mesh.uv[1], 0);
      final last = (n + 1) * (n + 1) - 1;
      expect(mesh.uv[last * 2], closeTo(GeoEngineTuning.tileSize, 1e-6));
      expect(mesh.uv[last * 2 + 1], closeTo(GeoEngineTuning.tileSize, 1e-6));
    });

    test('panning does not rebuild geometry', () {
      final builder = TileMeshBuilder();
      final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
      final mesh = builder.unitMesh(grid, 8, 5, 8);
      final camA = _cam();
      builder.project(mesh, ortho, camA);
      final buildsAfterFirst = builder.buildCount;

      final camB = CameraMath.panByPixels(camA, ortho, 1, 0);
      builder.project(mesh, ortho, camB);
      expect(builder.buildCount, buildsAfterFirst);
    });
  });

  group('projection of meshes', () {
    test('centre tile covers the viewport centre', () {
      final builder = TileMeshBuilder();
      final camera = _cam(center: const LatLng(45, 90), zoom: 6);
      final grid = TileGrid.of(TileSchemeKind.webMercator, 6);
      final key = TileKey(6, grid.xOf(90), grid.yOf(45));
      final mesh = builder.unitMesh(grid, key.x, key.y, 8);
      final buffers = builder.project(mesh, ortho, camera);
      expect(buffers.positions.length, mesh.vertexCount * 2);
      for (var i = 0; i < mesh.vertexCount; i++) {
        expect(buffers.positions[i * 2].isFinite, isTrue);
        expect(buffers.positions[i * 2 + 1].isFinite, isTrue);
      }
      expect(buffers.indices.length, greaterThan(0));
    });

    test('mesh for a tile on the far side is fully culled', () {
      final builder = TileMeshBuilder();
      final camera = _cam(center: const LatLng(60, 0), zoom: 4);
      final grid = TileGrid.of(TileSchemeKind.webMercator, 4);
      // South-west tile on the opposite hemisphere.
      final mesh = builder.unitMesh(grid, 1, 14, 6);
      final buffers = builder.project(mesh, ortho, camera);
      expect(buffers.indices, isEmpty);
    });

    test('mercator meshes are never culled', () {
      final builder = TileMeshBuilder();
      final camera = _cam();
      final grid = TileGrid.of(TileSchemeKind.webMercator, 3);
      final mesh = builder.unitMesh(grid, 6, 2, 6);
      final buffers = builder.project(mesh, merc, camera);
      expect(buffers.indices.length, mesh.indices.length);
    });

    test('limb vertices are clamped onto the disc', () {
      final builder = TileMeshBuilder();
      final camera = _cam(center: const LatLng(0, 0), zoom: 2);
      final grid = TileGrid.of(TileSchemeKind.webMercator, 3);
      final mesh = builder.unitMesh(grid, 0, 0, 6);
      final buffers = builder.project(mesh, ortho, camera);
      final radius = camera.radiusPx;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final dx = buffers.positions[i * 2] - camera.size.width / 2;
        final dy = buffers.positions[i * 2 + 1] - camera.size.height / 2;
        final d = math.sqrt(dx * dx + dy * dy);
        expect(d, lessThanOrEqualTo(radius + 1e-3));
      }
    });
  });

  group('index culling', () {
    test('drops triangles that are fully behind', () {
      final source = Uint16List.fromList([0, 1, 2, 3, 4, 5]);
      final depths = Float32List.fromList([-0.5, -0.4, -0.3, 0.5, 0.6, 0.7]);
      final out = TileMeshBuilder.cullIndices(source, depths);
      expect(out.length, 3);
      expect(out.toList(), [3, 4, 5]);
    });

    test('keeps a triangle with a single front vertex', () {
      final source = Uint16List.fromList([0, 1, 2]);
      final depths = Float32List.fromList([-0.5, -0.4, 0.3]);
      expect(TileMeshBuilder.cullIndices(source, depths).length, 3);
    });
  });

  group('parent uv rectangle', () {
    test('the sub-rectangle is the exact quarter of the parent', () {
      final r = parentUvRect(
        childX: 1,
        childY: 0,
        dz: 1,
        parentWidth: 256,
        parentHeight: 256,
      );
      expect(r.u0, 128);
      expect(r.v0, 0);
      expect(r.spanU, 128);
      expect(r.spanV, 128);
    });

    test('dz=2 splits the parent into sixteenths', () {
      final r = parentUvRect(
        childX: 2,
        childY: 3,
        dz: 2,
        parentWidth: 256,
        parentHeight: 256,
      );
      expect(r.u0, 128);
      expect(r.v0, 192);
      expect(r.spanU, 64);
      expect(r.spanV, 64);
    });

    test('a 512 px parent scales accordingly', () {
      final r = parentUvRect(
        childX: 1,
        childY: 1,
        dz: 1,
        parentWidth: 512,
        parentHeight: 512,
      );
      expect(r.u0, 256);
      expect(r.spanU, 256);
    });

    test('the four children tile the parent exactly', () {
      final rects = [
        for (var j = 0; j < 2; j++)
          for (var i = 0; i < 2; i++)
            parentUvRect(
              childX: i,
              childY: j,
              dz: 1,
              parentWidth: 256,
              parentHeight: 256,
            ),
      ];
      var covered = 0.0;
      for (final r in rects) {
        covered += r.spanU * r.spanV;
      }
      expect(covered, closeTo(256 * 256, 1e-6));
    });
  });

  group('parent fallback projection', () {
    test('geometry comes from the child, uv from the parent sub-rect', () {
      final builder = TileMeshBuilder();
      final camera = _cam(zoom: 5);
      final parentGrid = TileGrid.of(TileSchemeKind.webMercator, 4);
      final childGrid = TileGrid.of(TileSchemeKind.webMercator, 5);
      final parent = builder.unitMesh(parentGrid, 8, 5, 8);
      final child = builder.unitMesh(childGrid, 17, 11, 8);

      final parentBuffers = TileMeshBuilder.projectMesh(
        parent,
        ortho,
        camera,
      );
      final childBuffers = projectChildWithParentUv(
        childMesh: child,
        projector: ortho,
        camera: camera,
        parentWidth: 256,
        parentHeight: 256,
        childX: 17,
        childY: 11,
        dz: 1,
      );

      // The child's geometry must cover the same area as its own cell in the
      // parent grid — i.e. it is *inside* the parent's footprint.
      final parentMinX = parentBuffers.positions
          .reduce(math.min);
      final parentMaxX = parentBuffers.positions
          .reduce(math.max);
      final childMinX = childBuffers.positions
          .reduce(math.min);
      final childMaxX = childBuffers.positions
          .reduce(math.max);
      expect(childMinX, greaterThanOrEqualTo(parentMinX - 1e-3));
      expect(childMaxX, lessThanOrEqualTo(parentMaxX + 1e-3));
      expect(childMaxX - childMinX, lessThan(parentMaxX - parentMinX));
    });

    test('the sampled uv falls inside the parent sub-rectangle', () {
      final builder = TileMeshBuilder();
      final camera = _cam(zoom: 5);
      final childGrid = TileGrid.of(TileSchemeKind.webMercator, 5);
      final child = builder.unitMesh(childGrid, 17, 11, 8);
      final rect = parentUvRect(
        childX: 17,
        childY: 11,
        dz: 1,
        parentWidth: 256,
        parentHeight: 256,
      );
      final buffers = projectChildWithParentUv(
        childMesh: child,
        projector: ortho,
        camera: camera,
        parentWidth: 256,
        parentHeight: 256,
        childX: 17,
        childY: 11,
        dz: 1,
      );
      for (var i = 0; i < child.vertexCount; i++) {
        final u = buffers.uvs[i * 2];
        final v = buffers.uvs[i * 2 + 1];
        expect(u, greaterThanOrEqualTo(rect.u0 - 1e-6));
        expect(u, lessThanOrEqualTo(rect.u0 + rect.spanU + 1e-6));
        expect(v, greaterThanOrEqualTo(rect.v0 - 1e-6));
        expect(v, lessThanOrEqualTo(rect.v0 + rect.spanV + 1e-6));
      }
    });

    test('uv equivalence: the child samples the same pixels as the parent', () {
      // A 4x4 sample grid: the child's uv at parameter (s,t) must point at
      // the same parent pixel as the parent's own uv at the matching point.
      final builder = TileMeshBuilder();
      final camera = _cam(zoom: 5);
      final parentGrid = TileGrid.of(TileSchemeKind.webMercator, 4);
      final childGrid = TileGrid.of(TileSchemeKind.webMercator, 5);
      final child = builder.unitMesh(childGrid, 17, 11, 4);
      expect(parentGrid.cols, lessThan(childGrid.cols));
      final rect = parentUvRect(
        childX: 17,
        childY: 11,
        dz: 1,
        parentWidth: 256,
        parentHeight: 256,
      );
      final buffers = projectChildWithParentUv(
        childMesh: child,
        projector: ortho,
        camera: camera,
        parentWidth: 256,
        parentHeight: 256,
        childX: 17,
        childY: 11,
        dz: 1,
      );
      final n = child.subdiv;
      for (var j = 0; j <= n; j++) {
        for (var i = 0; i <= n; i++) {
          final idx = j * (n + 1) + i;
          // Normalised position inside the child cell.
          final su = i / n;
          final sv = j / n;
          // Expected parent pixel.
          final expectedU = rect.u0 + su * rect.spanU;
          final expectedV = rect.v0 + sv * rect.spanV;
          expect(buffers.uvs[idx * 2], closeTo(expectedU, 1e-3));
          expect(buffers.uvs[idx * 2 + 1], closeTo(expectedV, 1e-3));
        }
      }
    });
  });
}
