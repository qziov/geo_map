import 'package:geo_map_core/geo_map_core.dart';
import 'package:test/test.dart';

MvtFeature _polygon(List<List<Vec2>> rings) => MvtFeature(
      type: MvtGeomType.polygon,
      properties: const {},
      geometry: rings,
    );

MvtLayer _layer(List<MvtFeature> features, {int extent = 10}) => MvtLayer(
      name: 'test',
      extent: extent,
      version: 2,
      features: features,
    );

List<Vec2> _rect(double x, double y, double w, double h) => [
      Vec2(x, y),
      Vec2(x + w, y),
      Vec2(x + w, y + h),
      Vec2(x, y + h),
      Vec2(x, y),
    ];

void main() {
  group('buildMvtFillBucket', () {
    test('classifies outer + hole and normalizes to [0,1]', () {
      final layer = _layer([
        _polygon([
          _rect(0, 0, 10, 10),
          [
            const Vec2(2, 2),
            const Vec2(2, 4),
            const Vec2(4, 4),
            const Vec2(4, 2),
            const Vec2(2, 2),
          ],
        ]),
      ]);

      final polygons = buildMvtFillBucket(layer);
      expect(polygons, hasLength(1));
      expect(polygons.single.rings, hasLength(2));

      final outer = polygons.single.rings.first;
      expect(outer.first.x, 0);
      expect(outer.first.y, 0);
      expect(outer[1].x, 1);
      expect(outer[1].y, 0);

      final hole = polygons.single.rings[1];
      expect(hole.first.x, closeTo(0.2, 1e-9));
      expect(hole.first.y, closeTo(0.2, 1e-9));
    });

    test('two same-wound outers produce two polygons', () {
      final layer = _layer([
        _polygon([_rect(0, 0, 10, 10), _rect(20, 0, 10, 10)]),
      ]);

      final polygons = buildMvtFillBucket(layer);
      expect(polygons, hasLength(2));
      expect(polygons[0].rings, hasLength(1));
      expect(polygons[1].rings, hasLength(1));
    });

    test('carries feature properties for data-driven paint', () {
      final layer = _layer([
        MvtFeature(
          type: MvtGeomType.polygon,
          properties: const {'CONTINENT': 'Asia'},
          geometry: [_rect(0, 0, 10, 10)],
        ),
      ]);

      expect(
        buildMvtFillBucket(layer).single.properties['CONTINENT'],
        'Asia',
      );
    });

    test('normalizes a hole to the opposite winding of the outer ring', () {
      final outer = _rect(0, 0, 10, 10);
      // Reverse the hole so it is opposite the outer ring and groups as one
      // polygon; the bucket must keep the two orientations opposite.
      final hole = _rect(2, 2, 4, 4).reversed.toList();
      final layer = _layer([
        _polygon([outer, hole]),
      ]);

      final polygons = buildMvtFillBucket(layer);
      expect(polygons, hasLength(1));
      final signs = polygons.single.rings
          .map((r) => mvtRingSignedArea(r).isNegative)
          .toList();
      expect(signs, hasLength(2));
      expect(signs[0], isNot(signs[1]));
    });
  });

  group('buildMvtLineBucket', () {
    test('keeps polylines and normalizes by extent', () {
      final layer = MvtLayer(
        name: 'roads',
        extent: 4096,
        version: 2,
        features: [
          MvtFeature(
            type: MvtGeomType.lineString,
            properties: const {},
            geometry: [
              [const Vec2(0, 0), const Vec2(4096, 0)],
            ],
          ),
        ],
      );

      final lines = buildMvtLineBucket(layer);
      expect(lines, hasLength(1));
      expect(lines.single.points, hasLength(2));
      expect(lines.single.points.first.x, 0);
      expect(lines.single.points.last.x, 1);
    });

    test('skips single-point rings', () {
      final layer = MvtLayer(
        name: 'pts',
        extent: 16,
        version: 2,
        features: [
          MvtFeature(
            type: MvtGeomType.point,
            properties: const {},
            geometry: [
              [const Vec2(4, 4)],
            ],
          ),
        ],
      );

      expect(buildMvtLineBucket(layer), isEmpty);
    });

    test('carries feature properties for data-driven stroke', () {
      final layer = MvtLayer(
        name: 'lines',
        extent: 10,
        version: 2,
        features: [
          MvtFeature(
            type: MvtGeomType.lineString,
            properties: const {'name': 'Equator'},
            geometry: [
              [const Vec2(0, 0), const Vec2(10, 0)],
            ],
          ),
        ],
      );

      expect(buildMvtLineBucket(layer).single.properties['name'], 'Equator');
    });
  });

  group('mvtTilePointToLatLng', () {
    const extent = 4096.0;

    test('z0 tile corners hit the web-mercator limits', () {
      final nw = mvtTilePointToLatLng(
        const Vec2(0, 0),
        z: 0,
        tileX: 0,
        tileY: 0,
        extent: extent,
      );
      expect(nw.longitude, -180);
      expect(nw.latitude, closeTo(85.0511, 0.01));

      final se = mvtTilePointToLatLng(
        const Vec2(extent, extent),
        z: 0,
        tileX: 0,
        tileY: 0,
        extent: extent,
      );
      expect(se.longitude, 180);
      expect(se.latitude, closeTo(-85.0511, 0.01));
    });

    test('z0 tile centre is the equator at the prime meridian', () {
      final centre = mvtTilePointToLatLng(
        const Vec2(extent / 2, extent / 2),
        z: 0,
        tileX: 0,
        tileY: 0,
        extent: extent,
      );
      expect(centre.longitude, closeTo(0, 1e-9));
      expect(centre.latitude, closeTo(0, 1e-9));
    });

    test('z1 north-west tile centre lands at 66.5N / 90W', () {
      final centre = mvtTilePointToLatLng(
        const Vec2(extent / 2, extent / 2),
        z: 1,
        tileX: 0,
        tileY: 0,
        extent: extent,
      );
      expect(centre.longitude, closeTo(-90, 1e-9));
      expect(centre.latitude, closeTo(66.5132, 0.01));
    });
  });
}
