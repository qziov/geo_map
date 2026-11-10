import 'package:flutter_test/flutter_test.dart';
import 'package:geo_map/geo_map.dart';

/// Regression for the "controller forces a repaint every frame" defect.
///
/// `_StyleVectorPainter` / `_MvtPainter` decide `shouldRepaint` by comparing
/// the `StyleSpec` identity. `GeoStyleController.spec` keeps that identity
/// stable until a mutation bumps `revision`, which is exactly the condition
/// the renderers need: no repaint when nothing changed, one repaint when it
/// did.
StyleSpec _sample() => StyleSpec.parse(const <String, Object?>{
      'version': 8,
      'sources': <String, Object?>{
        's': <String, Object?>{'type': 'vector'},
      },
      'layers': <Object?>[
        <String, Object?>{
          'id': 'bg',
          'type': 'background',
          'paint': <String, Object?>{'background-color': '#ffffff'},
        },
        <String, Object?>{
          'id': 'ln',
          'type': 'line',
          'source': 's',
          'source-layer': 'x',
          'paint': <String, Object?>{'line-color': '#ff0000'},
        },
      ],
    });

void main() {
  group('GeoStyleController.spec (revision cache)', () {
    test('keeps one identity until a real mutation, then one new identity', () {
      final controller = GeoStyleController(_sample());
      addTearDown(controller.dispose);

      final initial = controller.spec;
      expect(identical(initial, controller.spec), isTrue,
          reason: 'unchanged style must not force shouldRepaint');
      expect(controller.revision, 0);

      controller.setPaintProperty('ln', 'line-color', '#00ff00');
      expect(controller.revision, 1);

      final changed = controller.spec;
      expect(identical(initial, changed), isFalse,
          reason: 'a mutation must produce a repaint');
      expect(identical(changed, controller.spec), isTrue,
          reason: 'but only one repaint, not one per frame');
    });

    test('a no-op mutation does not bump revision or invalidate the cache', () {
      final controller = GeoStyleController(_sample());
      addTearDown(controller.dispose);

      final initial = controller.spec;
      controller.removeSource('missing');
      controller.removeLayer('missing');
      controller.moveLayer('missing');

      expect(controller.revision, 0);
      expect(identical(initial, controller.spec), isTrue);
    });

    test('successive mutations each yield a fresh spec', () {
      final controller = GeoStyleController(_sample());
      addTearDown(controller.dispose);

      final a = controller.spec;
      controller.addLayer(StyleLayer.parse(const <String, Object?>{
        'id': 'extra',
        'type': 'background',
        'paint': <String, Object?>{'background-color': '#000000'},
      }));
      final b = controller.spec;
      controller.setVisibility('extra', 'none');
      final c = controller.spec;

      expect(controller.revision, 2);
      expect(identical(a, b), isFalse);
      expect(identical(b, c), isFalse);
      expect(controller.document.layer('extra'), isNotNull);
    });
  });

  test('StyleDocument.toSpec() itself is not cached (why the controller cache exists)',
      () {
    final document = StyleDocument.fromSpec(_sample());
    expect(identical(document.toSpec(), document.toSpec()), isFalse);
  });
}
