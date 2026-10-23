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
}
