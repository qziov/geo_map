/// Known paint/layout properties for the M1 layer types, with defaults.
///
/// Aligns with `@maplibre/maplibre-gl-style-spec` `reference/v8.json`
/// (`paint_fill:6383`, `paint_line:6896`, `layout_fill:966`, `layout_line:1175`).
/// Defaults match `v8.json` (`fill-color` `#000000`, `line-width` 1, …).
library;

enum StylePropertyType { number, color, boolean, string, array }

class StylePropertyDef {
  const StylePropertyDef(
    this.type, {
    this.defaultValue,
    this.dataDriven = false,
    this.interpolated = false,
  });

  final StylePropertyType type;
  final Object? defaultValue;
  final bool dataDriven;
  final bool interpolated;
}

/// `layerType -> paint property -> definition`.
const Map<String, Map<String, StylePropertyDef>> layerPaintDefs = {
  'fill': {
    'fill-color': StylePropertyDef(StylePropertyType.color,
        defaultValue: '#000000', dataDriven: true, interpolated: true),
    'fill-opacity': StylePropertyDef(StylePropertyType.number,
        defaultValue: 1, interpolated: true),
    'fill-outline-color': StylePropertyDef(StylePropertyType.color,
        dataDriven: true, interpolated: true),
    'fill-antialias':
        StylePropertyDef(StylePropertyType.boolean, defaultValue: true),
  },
  'line': {
    'line-color': StylePropertyDef(StylePropertyType.color,
        defaultValue: '#000000', dataDriven: true, interpolated: true),
    'line-width': StylePropertyDef(StylePropertyType.number,
        defaultValue: 1, dataDriven: true, interpolated: true),
    'line-opacity': StylePropertyDef(StylePropertyType.number,
        defaultValue: 1, interpolated: true),
    'line-gap-width': StylePropertyDef(StylePropertyType.number,
        defaultValue: 0, dataDriven: true, interpolated: true),
  },
};

/// `layerType -> layout property -> definition`.
const Map<String, Map<String, StylePropertyDef>> layerLayoutDefs = {
  'fill': {
    'fill-sort-key':
        StylePropertyDef(StylePropertyType.number, dataDriven: true),
    'visibility':
        StylePropertyDef(StylePropertyType.string, defaultValue: 'visible'),
  },
  'line': {
    'line-join':
        StylePropertyDef(StylePropertyType.string, defaultValue: 'miter'),
    'line-cap': StylePropertyDef(StylePropertyType.string, defaultValue: 'butt'),
    'line-sort-key':
        StylePropertyDef(StylePropertyType.number, dataDriven: true),
    'visibility':
        StylePropertyDef(StylePropertyType.string, defaultValue: 'visible'),
  },
};
