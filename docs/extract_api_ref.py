#!/usr/bin/env python3
"""Extract the public API surface of the `geo_map` library from source.

This mirrors what `dart doc` enumerates (Classes / Enums / Mixins /
Typedefs / Functions / Constants) but is dependency-free and lets us emit a
Chinese reference. It scans:

  * geo_map's own public files (the ones `geo_map.dart` exports), and
  * a whitelist of re-exported `geo_map_core` symbols (the `show ...` list).

Output: a JSON blob with signatures + captured `///` doc comments, grouped
by kind. Run with no args to print a summary; pass `--json out.json` to dump.
"""
import argparse
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent  # geo_map monorepo root
PKG = REPO / "packages" / "geo_map"
GEO_MAP_LIB = PKG / "lib"
CORE_LIB = REPO / "packages" / "geo_map_core" / "lib"

# geo_map.dart's `show ...` re-export list from geo_map_core.
CORE_WHITELIST = {
    "StyleSpec", "StyleDocument", "StyleLayer", "StyleColor", "PropertyValue",
    "Expr", "ExpressionContext", "GeoJsonFeature", "GeoJsonGeometry",
    "PointGeometry", "LineStringGeometry", "PolygonGeometry",
    "MultiLineStringGeometry", "MultiPolygonGeometry", "parseGeoJsonFeatures",
    "compileFilter", "FeaturePredicate", "GeoEngineTuning", "GeoTileSource",
    "TileFetchResult", "TileFailureKind", "TileRowOrder", "TileSchemeKind",
    "SpriteIndex", "SpriteIcon", "GeoGeometryKind", "pointInRing",
    "pointInPolygon", "pointInMultiPolygon", "ringSignedArea",
    "normalizeRingWinding", "unwrapLongitudes", "splitRingAtSeam",
}

# Files geo_map.dart exports (plus the vendor camera that defines LatLng/Bounds).
GEO_MAP_FILES = [
    "lib/geo_map.dart",
    "lib/src/camera/geo_map_controller.dart",
    "lib/src/diagnostics/geo_diagnostics.dart",
    "lib/src/engine/tile_engine.dart",
    "lib/src/engine/tile_geometry.dart",
    "lib/src/engine/tile_layer.dart",
    "lib/src/gesture/globe_gesture_overlay.dart",
    "lib/src/query/geo_feature_registry.dart",
    "lib/src/query/geo_pick_projection.dart",
    "lib/src/globe/globe_image_layer.dart",
    "lib/src/globe/geojson_vector_source.dart",
    "lib/src/globe/globe_projection.dart",
    "lib/src/globe/flat_tile_layer.dart",
    "lib/src/globe/globe_tile_layer.dart",
    "lib/src/globe/globe_vector_layer.dart",
    "lib/src/globe/tile_source.dart",
    "lib/src/source/debug_tiles_source.dart",
    "lib/src/source/mbtiles_source.dart",
    "lib/src/source/mbtiles_source_stub.dart",
    "lib/src/style/style_controller.dart",
    "lib/src/style/sprite_atlas.dart",
    "lib/src/style/style_vector_layer.dart",
    "lib/src/style/mvt_vector_layer.dart",
    "lib/src/widget/geo_map.dart",
    "lib/src/widget/geo_anchored_popup.dart",
    "lib/src/widget/geo_popup_binding.dart",
    "lib/src/widget/geo_popup_card.dart",
    "lib/src/widget/geo_popup_controller.dart",
    "lib/src/vendor/flutter_map_camera/flutter_map_camera.dart",
    "lib/src/vendor/flutter_map_camera/latlng.dart",
    "lib/src/vendor/flutter_map_camera/latlng_bounds.dart",
]

# ---------------------------------------------------------------------------
# Lexer: split a file into (doc, code) pairs while tracking declarations.
# ---------------------------------------------------------------------------

def lex(text):
    """Return list of (doc_or_None, code_line). Doc lines are `///`."""
    # Strip ALL block comments (incl. multi-line) first so their `{x}`/`{y}`
    # placeholders never corrupt brace-depth tracking.
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    out = []
    pending_doc = []
    for raw in text.split("\n"):
        s = raw.strip()
        if s.startswith("///"):
            pending_doc.append(s[3:].strip())
            continue
        if s.startswith("/**") or s.startswith("/*"):
            # capture block doc, strip leading '*'
            inner = re.sub(r"^/\*+", "", s)
            inner = re.sub(r"\*+/$", "", inner)
            for part in inner.split("\n"):
                pending_doc.append(part.strip().lstrip("*").strip())
            continue
        # strip inline block comments and // comments (keep :// urls)
        cl = re.sub(r"/\*.*?\*/", "", raw)
        cl = re.sub(r"(?<!:)//[^\n]*", "", cl)
        if cl.strip() == "":
            pending_doc = []  # blank line breaks doc association
            out.append((None, cl))
            continue
        doc = "\n".join(pending_doc) if pending_doc else None
        pending_doc = []
        out.append((doc, cl.rstrip()))
    return out


# ---------------------------------------------------------------------------
# Brace-aware parser.
# ---------------------------------------------------------------------------

def code_without_strings(line):
    """Drop line comments and short string literals so their `{`/`}` never
    corrupt brace-depth tracking (e.g. a JSON/regex literal)."""
    s = re.sub(r"(?<!:)//[^\n]*", "", line)
    s = re.sub(r"'[^']*'", "''", s)
    s = re.sub(r'"[^"]*"', '""', s)
    s = re.sub(r"`[^`]*`", "``", s)
    return s


def brace_net(line):
    s = code_without_strings(line)
    return s.count("{") - s.count("}")


def advance_past_decl(lines, start, end):
    """Return index just past a declaration (including its body).

    Robust to nested braces: the declaration *body* opener is the first `{`
    that occurs while parenthesis depth is 0 (so parameter lists like
    `foo({int x})` and named params never count), and we return after its
    matching `}`. Nested braces inside the body are counted so a stray `}`
    (e.g. a constructor parameter-list close) never ends the span early.
    Single-line declarations end at the first `;` at paren 0."""
    paren = 0
    body_open = -1
    depth = 0
    j = start
    while j < end:
        _, c2 = lines[j]
        s = code_without_strings(c2)
        for ch in s:
            if ch == "(":
                paren += 1
            elif ch == ")":
                paren -= 1
            elif ch == "{":
                if body_open == -1 and paren == 0:
                    body_open = j
                    depth = 1
                elif body_open != -1:
                    depth += 1
            elif ch == "}":
                if body_open != -1:
                    depth -= 1
                    if depth == 0:
                        return j + 1
        if body_open == -1 and paren == 0 and c2.rstrip().endswith(";"):
            return j + 1
        j += 1
    return end


CLASS_KIND = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:(abstract|sealed|final|interface|base|mixin)\s+)*"
    r"(class|mixin|enum|typedef|extension)\s+(\w+)")
MEMBER_RE = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:(?:static|final|const|late|abstract|external|covariant|factory|async|sync)\s+)*"
    r"(?:(\w[\w<>?,.\s\[\]]*?)\s+)?(get\s+\w+|\w+\s*\.\s*\w+|set\s+\w+|\w+)\s*(\(|:|=|;|\{)")
CTOR_RE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s*)*(\w+)\s*\.\s*\w*\s*\(")

# Leading identifiers that can never start a real declaration.
KEYWORDS = {
    "if", "for", "while", "switch", "return", "else", "do", "try", "catch",
    "finally", "throw", "assert", "break", "continue", "export", "import",
    "library", "part", "enum", "class", "mixin", "typedef", "extension",
    "await", "yield", "var",
}


def brace_depth_of(lines):
    """Compute net brace depth per line (ignoring strings is overkill)."""
    depths = []
    d = 0
    for _, cl in lines:
        opens = cl.count("{") - cl.count("}")
        # crude string protection: ignore braces inside single quotes
        d += opens
        depths.append(d)
    return depths


def collect_statement(lines, start, end_exclusive):
    """Collect the declaration head (up to, but not including, the body `{`
    or the terminating `;` at parenthesis depth 0). Method/constructor bodies
    are never included."""
    parts = []
    for i in range(start, end_exclusive):
        _, cl = lines[i]
        parts.append(cl.strip())
    full = "\n".join(p for p in parts if p)
    return _truncate_decl(full)


def _truncate_decl(full):
    """Cut `full` at the first top-level `;` or `{` (paren depth 0), respecting
    string literals so a `;`/`{` inside a string never terminates the decl."""
    paren = 0
    i = 0
    n = len(full)
    buf = []
    instr = None  # ', ", `
    while i < n:
        c = full[i]
        if instr:
            buf.append(c)
            if c == instr and (i + 1 >= n or full[i + 1] != instr):
                instr = None
            i += 1
            continue
        if c in "'\"`":
            instr = c
            buf.append(c)
            i += 1
            continue
        if c == "(":
            paren += 1
            buf.append(c)
        elif c == ")":
            paren -= 1
            buf.append(c)
        elif c in ";{" and paren == 0:
            break
        else:
            buf.append(c)
        i += 1
    sig = "".join(buf).strip()
    sig = re.sub(r"\n{3,}", "\n\n", sig)
    return sig.strip()


def parse_members(lines, a, b):
    """Parse direct-children members of a class spanning lines[a:b]
    (exclusive of the outer braces).

    Depth- and parenthesis-aware: a line is only treated as a member
    declaration when we are at class-body level (brace depth 0) and outside
    any `(` — so method bodies and constructor parameter lists never leak in.
    """
    members = []
    i = a
    depth = 0   # brace depth relative to class body
    paren = 0   # parenthesis depth (params / expressions)
    while i < b:
        doc, cl = lines[i]
        if cl.strip() == "" or cl.strip().startswith("//"):
            i += 1
            continue
        # Only match a real member at class-body level, outside parentheses.
        if depth == 0 and paren == 0:
            m = MEMBER_RE.match(cl)
            if m:
                # A nested type declared inside the class body is NOT a member.
                if CLASS_KIND.match(cl):
                    i = advance_past_decl(lines, i, b)
                    depth = 0
                    paren = 0
                    continue
                name = m.group(2)
                typ = m.group(1)
                # Function-typed members: `void Function(...) name` — the regex
                # captures `Function` as the name; recover the real field name
                # (the identifier after the closing `)` of the function type).
                if name == "Function":
                    after = cl.split(")", 1)[1] if ")" in cl else cl
                    toks = re.findall(r"\w+", after)
                    if toks:
                        name = toks[0]
                        kind = "field"
                    else:
                        i = advance_past_decl(lines, i, b)
                        depth = 0
                        paren = 0
                        continue
                # Operator overloads: `bool operator ==(Object other)`.
                opm = re.search(r"operator\s+([^\s(]+)", cl)
                if opm:
                    name = "operator " + opm.group(1)
                    kind = "method"
                elif name.startswith("get "):
                    kind = "getter"
                    name = name[4:].strip()
                elif name.startswith("set "):
                    kind = "setter"
                    name = name[4:].strip()
                elif re.match(r"^\w+\.\w+$", name):
                    kind = "constructor"          # Class.named
                    name = name.replace(" ", "")
                elif m.group(3) == "(" or name.endswith("("):
                    if typ is None and name[:1].isupper():
                        kind = "constructor"      # ClassName(...) no return type
                    else:
                        kind = "method"
                    name = name.rstrip("(").strip()
                else:
                    kind = "field"                # no params, not accessor => field
                clean = name.split("(")[0].split(".")[0].strip()
                # Skip non-members: private, initializer-list (`:`), method
                # calls (`.`), typeless statements/calls, or typeless
                # assignments (initializer entries).
                typeless = typ is None and not name[:1].isupper()
                skip = (clean.startswith("_") or "." in clean
                        or m.group(3) == ":" or typeless
                        or (re.match(r"^\s*\w+\s*=", cl)
                            and not re.match(r"^\s*(?:final|const|late|var)", cl)))
                if not skip:
                    sig = collect_statement(lines, i, b)
                    members.append({"name": clean, "kind": kind, "signature": sig,
                                    "doc": doc})
                # Always skip the entire declaration (body or fat-arrow
                # expression) so its internals are never re-parsed as members.
                i = advance_past_decl(lines, i, b)
                depth = 0
                paren = 0
                continue
        # Not a member (or inside a body / parens): consume the line, tracking
        # depth and paren so we resume only at class-body level.
        depth += brace_net(cl)
        paren = _update_paren(paren, cl)
        i += 1
    return members


def _update_paren(paren, line):
    """Track parenthesis depth on a comment/string-stripped line."""
    s = code_without_strings(line)
    for ch in s:
        if ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
    return max(paren, 0)


def parse_file(path, whitelist=None):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    lines = lex(text)
    # compute overall depth per line for top-level span detection
    depths = []
    d = 0
    for _, cl in lines:
        d += cl.count("{") - cl.count("}")
        depths.append(d)
    types = []
    functions = []
    typedefs = []
    constants = []
    i = 0
    n = len(lines)
    while i < n:
        doc, cl = lines[i]
        if cl.strip() == "" or cl.strip().startswith("//") or cl.strip().startswith("@"):
            i += 1
            continue
        m = CLASS_KIND.match(cl)
        if m:
            modifier = m.group(1) or ""
            kind_kw = m.group(2)
            name = m.group(3)
            if name.startswith("_"):
                i = advance_past_decl(lines, i, n)
                continue
            # span to matching close brace
            j = advance_past_decl(lines, i, n) - 1
            sig = collect_statement(lines, i, j + 1)
            body_a, body_b = i + 1, j  # children span
            members = parse_members(lines, body_a, body_b) if kind_kw in ("class", "mixin") else []
            if kind_kw == "enum":
                # extract values
                vals = []
                for k in range(body_a, body_b):
                    _, ec = lines[k]
                    vm = re.match(r"^\s*([A-Za-z_]\w*)\s*(,|;|\{|$)", ec)
                    if vm and not ec.strip().startswith("//"):
                        vals.append(vm.group(1))
                members = [{"name": v, "kind": "enum-value", "signature": v, "doc": None} for v in vals]
            if kind_kw == "typedef":
                kind = "typedef"
                types.append({"name": name, "kind": "typedef", "signature": sig, "doc": doc, "members": []})
                typedefs.append(name)
            else:
                kind = {"class": "class", "mixin": "mixin", "enum": "enum", "extension": "extension"}[kind_kw]
                prefix = (modifier + " ").strip()
                types.append({"name": name, "kind": kind, "signature": sig, "doc": doc, "members": members})
            i = j + 1
            continue
        # top-level function / variable
        fm = re.match(r"^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:(?:external|static|const|final|late|async)\s+)*([\w<>?,.\s\[\]]+?)\s+([A-Za-z_]\w*)\s*\(", cl)
        if fm and not cl.strip().startswith("import") and not cl.strip().startswith("export"):
            lead = re.sub(r"^@\w+(?:\([^)]*\))?\s*", "", cl.strip()).split()[0]
            if lead in KEYWORDS:
                i += 1
                continue
            # It's a function.
            sig = collect_statement(lines, i, n)
            name = fm.group(2)
            if not name.startswith("_"):
                functions.append({"name": name, "signature": sig, "doc": doc})
            i = advance_past_decl(lines, i, n)
            continue
        # top-level constant / variable: `const X =` / `final X =` / `var X`
        vm = re.match(r"^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:const|final|var|late)\s+(?:[\w<>?,.\s\[\]]+\s+)?([A-Za-z_]\w*)\s*=", cl)
        if vm and not cl.strip().startswith("import"):
            name = vm.group(1)
            if not name.startswith("_"):
                constants.append({"name": name, "signature": collect_statement(lines, i, n), "doc": doc})
            i += 1
            continue
        i += 1
    return {"types": types, "functions": functions, "constants": constants}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", help="dump full json to this path")
    args = ap.parse_args()

    result = {"geo_map": [], "geo_map_core_reexport": []}
    for rel in GEO_MAP_FILES:
        p = PKG / rel
        if p.is_file():
            r = parse_file(p)
            result["geo_map"].append({"file": rel, **r})

    # geo_map_core: parse every file, keep only whitelisted symbols.
    core_symbols = {}
    for f in sorted(CORE_LIB.rglob("*.dart")):
        if "test" in str(f):
            continue
        r = parse_file(f)
        for t in r["types"]:
            if t["name"] in CORE_WHITELIST:
                core_symbols.setdefault(t["name"], t)
        for fn in r["functions"]:
            if fn["name"] in CORE_WHITELIST:
                core_symbols.setdefault(fn["name"], {"name": fn["name"], "kind": "function",
                                                     "signature": fn["signature"], "doc": fn["doc"], "members": []})
        for c in r["constants"]:
            if c["name"] in CORE_WHITELIST:
                core_symbols.setdefault(c["name"], {"name": c["name"], "kind": "constant",
                                                    "signature": c["signature"], "doc": c["doc"], "members": []})

    # summary
    geo_types = [t for blk in result["geo_map"] for t in blk["types"]]
    print("geo_map own types: %d" % len(geo_types))
    kinds = {}
    for t in geo_types:
        kinds[t["kind"]] = kinds.get(t["kind"], 0) + 1
    print("  by kind:", kinds)
    print("geo_map functions: %d, constants: %d" % (
        sum(len(b["functions"]) for b in result["geo_map"]),
        sum(len(b["constants"]) for b in result["geo_map"])))
    print("geo_map_core re-exported resolved: %d / %d" % (len(core_symbols), len(CORE_WHITELIST)))
    missing = CORE_WHITELIST - set(core_symbols)
    if missing:
        print("  MISSING from core parse:", sorted(missing))

    if args.json:
        dump = {"geo_map": result["geo_map"],
                "geo_map_core_reexport": sorted(core_symbols.values(), key=lambda x: x["name"])}
        pathlib.Path(args.json).write_text(json.dumps(dump, ensure_ascii=False, indent=2), encoding="utf-8")
        print("wrote", args.json)


if __name__ == "__main__":
    main()
