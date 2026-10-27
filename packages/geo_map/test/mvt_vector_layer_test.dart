/// End-to-end integration test for [MvtVectorLayer].
///
/// Drives the whole vector-tile pipeline through the real widget tree with an
/// in-memory [GeoTileSource] that returns a hand-built MVT tile (no network, no
/// fixture file): `fetch → decodeMvtTileAsync → buildMvtFillBucket /
/// buildMvtLineBucket → bucket → paint`. This is the path that has no other
/// coverage — the core suite tests decode/bucket in isolation, but never the
/// [MvtVectorLayer]'s `_mappingFor` / `_addPolygon` / `_addPolyline` projection
/// mapping, nor the async decode-into-cache lifecycle inside a widget.
library;

import 'dart:convert';
import 'dart:math' show Point;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'test_helpers.dart';

/// Minimal protobuf writer so this test can mint an MVT tile without a fixture.
///
/// Mirrors the writer in `geo_map_core`'s own MVT tests (kept private there),
/// trimmed to the fields a `Tile` / `TileLayer` / `TileFeature` needs.
class _Wire {
  final BytesBuilder _b = BytesBuilder();

  void _varint(int value) {
    var x = value;
    while (x >= 0x80) {
      _b.addByte((x & 0x7f) | 0x80);
      x >>= 7;
    }
    _b.addByte(x & 0x7f);
  }

  void _tag(int field, int wire) => _varint((field << 3) | wire);

  void rawVarint(int field, int value) {
    _tag(field, 0);
    _varint(value);
  }

  void bytes(int field, List<int> data) {
    _tag(field, 2);
    _varint(data.length);
    _b.add(data);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, _Wire child) => bytes(field, child.toBytes());

  void packed(int field, List<int> values) {
    final child = _Wire();
    for (final v in values) {
      child._varint(v);
    }
    bytes(field, child.toBytes());
  }

  Uint8List toBytes() => _b.toBytes();
}

int _zz(int value) => (value << 1) ^ (value >> 31);
int _cmd(int id, int count) => (count << 3) | id;

_Wire _feature({required int type, required List<int> geometry, int? id}) {
  final f = _Wire();
  if (id != null) f.rawVarint(1, id);
  f.packed(2, const <int>[]); // no tags (features carry no properties here)
  f.rawVarint(3, type);
  f.packed(4, geometry);
  return f;
}

_Wire _layer(String name, List<_Wire> features) {
    final l = _Wire();
    l.string(1, name);
    for (final f in features) {
      l.message(2, f);
    }
    l.rawVarint(5, 4096); // extent
  l.rawVarint(15, 2); // version
  return l;
}

Uint8List _tile(List<_Wire> layers) {
  final t = _Wire();
  for (final l in layers) {
    t.message(3, l);
  }
  return t.toBytes();
}

/// A single tile whose `s` layer holds a full-bleed polygon, a line, and a point
/// at its centre. Normalized to [0,1] by the decoder, so it maps onto whichever
/// covering tile the camera asks for and lands on screen at the camera centre.
Uint8List _sampleTile() => _tile(<_Wire>[
      _layer('s', <_Wire>[
        _feature(
          type: 3, // polygon
          geometry: <int>[
            _cmd(1, 1), _zz(0), _zz(0), //
            _cmd(2, 3), _zz(4096), _zz(0), _zz(0), _zz(4096), _zz(-4096), _zz(0), //
            _cmd(7, 1), // ClosePath
          ],
        ),
        _feature(
          type: 2, // line string
          geometry: <int>[
            _cmd(1, 1), _zz(1024), _zz(2048), //
            _cmd(2, 1), _zz(2048), _zz(0), //
          ],
        ),
        _feature(
          type: 1, // point
          geometry: <int>[
            _cmd(1, 1), _zz(2048), _zz(2048), //
          ],
        ),
      ]),
    ]);

class _MemMvtSource implements GeoTileSource {
  _MemMvtSource(this._bytes);
  final Uint8List _bytes;

  @override
  int get minZoom => 0;

  @override
  int get maxZoom => 12;

  @override
  TileSchemeKind get scheme => TileSchemeKind.webMercator;

  @override
  TileRowOrder get rowOrder => TileRowOrder.xyzTopDown;

  @override
  int get maxConcurrentRequests => 6;

  @override
  String get attribution => 'mem';

  @override
  Future<TileFetchResult> fetch(int z, int x, int y) async =>
      TileFetchResult.ok(_bytes);

  @override
  void dispose() {}
}

StyleSpec _mvtStyle() => StyleSpec.parse(<String, Object?>{
      'version': 8,
      'sources': <String, Object?>{'s': <String, Object?>{'type': 'vector'}},
      'layers': <Object?>[
        <String, Object?>{
          'id': 'fill',
          'type': 'fill',
          'source': 's',
          'source-layer': 's',
          'paint': <String, Object?>{'fill-color': '#e63946', 'fill-opacity': 0.6},
        },
        <String, Object?>{
          'id': 'line',
          'type': 'line',
          'source': 's',
          'source-layer': 's',
          'paint': <String, Object?>{'line-color': '#1d3557', 'line-width': 2},
        },
        <String, Object?>{
          'id': 'label',
          'type': 'symbol',
          'source': 's',
          'source-layer': 's',
          'layout': <String, Object?>{'text-field': 'Hi'},
          'paint': <String, Object?>{'text-color': '#000000', 'text-size': 16},
        },
      ],
    });

const LatLng _center = LatLng(35.86, 104.19);

MapCamera _camera({MapProjectionDelegate? delegate}) => MapCamera(
      crs: const Epsg3857(),
      center: _center,
      zoom: 4.2,
      rotation: 0,
      nonRotatedSize: const Point<double>(800, 600),
      projectionDelegate: delegate,
    );

Widget _host(Widget child, {MapProjectionDelegate? delegate}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MapInheritedModel(camera: _camera(delegate: delegate), child: child),
    );

/// Drives frames until the layer reports decoded tiles, or ~2 s pass.
///
/// The decode runs on a real isolate, which the test's fake-async zone never
/// lets finish — `pump` only advances fake time. Alternating a real `runAsync`
/// wait with a `pump` lets fetch/decode/bucket complete and the diagnostics
/// post-frame callback fire.
Future<void> _pumpUntilReady(
  WidgetTester tester,
  MvtDiagnostics? Function() diag,
) async {
  for (var i = 0; i < 40; i++) {
    if (diag() != null && diag()!.readyCount > 0) return;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }
}

/// Rasterizes the layer's [RepaintBoundary] and counts non-transparent pixels.
///
/// `toImage` runs on the raster thread, so it must leave the fake-async zone or
/// the test hangs until its 10-minute timeout.
Future<int> _opaquePixelsOf(WidgetTester tester) async {
  final rb = tester.element(find.byType(RepaintBoundary)).renderObject!
      as RenderRepaintBoundary;
  var opaque = 0;
  await tester.runAsync(() async {
    final image = await rb.toImage();
    opaque = await countOpaquePixels(image);
  });
  return opaque;
}

void main() {
  testWidgets('fetch → decode → bucket → paint runs without throwing (2D)',
      (tester) async {
    MvtDiagnostics? diag;
    await tester.pumpWidget(
      _host(MvtVectorLayer(
        source: _MemMvtSource(_sampleTile()),
        style: _mvtStyle(),
        onDiagnostics: (d) => diag = d,
      )),
    );
    await _pumpUntilReady(tester, () => diag);

    expect(tester.takeException(), isNull);
    expect(diag, isNotNull, reason: 'diagnostics reported at least once');
    expect(diag!.readyCount, greaterThan(0),
        reason: 'at least one tile decoded and bucketed');
    // Fill polygon + line + placed label must leave marks.
    expect(await _opaquePixelsOf(tester), greaterThan(0));
  });

  testWidgets('fetch → decode → bucket → paint under the globe projector',
      (tester) async {
    MvtDiagnostics? diag;
    await tester.pumpWidget(
      _host(
        MvtVectorLayer(
          source: _MemMvtSource(_sampleTile()),
          style: _mvtStyle(),
          onDiagnostics: (d) => diag = d,
        ),
        delegate: GlobeProjectionDelegate(),
      ),
    );
    await _pumpUntilReady(tester, () => diag);

    expect(tester.takeException(), isNull);
    expect(diag!.readyCount, greaterThan(0));
    expect(await _opaquePixelsOf(tester), greaterThan(0));
  });
}
