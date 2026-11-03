#!/usr/bin/env python3
"""Render the Chinese API reference into a dartdoc-style HTML page.

Reads `api_ref_raw.json` (from extract_api_ref.py) and reuses the Chinese
translations / kind labels from `generate_api_zh.py`, so the HTML stays in
sync with `geo_map_api_zh.md`.

Usage:  python build_api_zh_html.py
Output: docs/geo_map_api_zh.html
"""
import html
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
RAW = HERE / "api_ref_raw.json"
OUT = HERE / "geo_map_api_zh.html"
CSS_FILE = HERE / "api_style.css"

sys.path.insert(0, str(HERE))
from generate_api_zh import (  # noqa: E402
    TYPE_DOC_ZH, KIND_ZH, EN_PLURAL, MEMBER_KIND_ZH, MEMBER_ORDER, dedupe_types,
)

GROUP_ORDER = ["class", "mixin", "enum", "typedef", "extension", "function", "constant"]


def esc(s):
    return html.escape(s or "", quote=False)


def reindent(sig):
    """Cosmetic: indent continuation lines of a multi-line signature."""
    lines = sig.split("\n")
    out = [lines[0]]
    for ln in lines[1:]:
        t = ln.strip()
        out.append("  " + t if t and t[0] not in ")}]" else t)
    return "\n".join(out)


STASH = []


def _stash(m):
    STASH.append(m.group(1))
    return "\x00%d\x00" % (len(STASH) - 1)


def inline(text):
    """Escape + `code` / **bold** / *italic*."""
    STASH.clear()
    s = esc(text)
    s = re.sub(r"`([^`]+)`", _stash, s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", s)
    for i, c in enumerate(STASH):
        s = s.replace("\x00%d\x00" % i, "<code>%s</code>" % esc(c))
    return s


CJK = re.compile(r"[\u4e00-\u9fff]")


def join_lines(lines):
    """Join wrapped lines; no space when both sides are CJK characters."""
    out = ""
    for ln in lines:
        if out and CJK.search(out[-1]) and ln and CJK.search(ln[0]):
            out += ln
        else:
            out += (" " if out else "") + ln
    return out


def render_doc(doc):
    """Render a `///` doc string (may contain bullets, **bold**, `code`,
    and a `### sub-heading`) into HTML."""
    if not doc:
        return ""
    out, para, bullets = [], [], []

    def flush_p():
        if para:
            out.append("<p>%s</p>" % inline(join_lines(para)))
            para.clear()

    def flush_b():
        if bullets:
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % inline(b) for b in bullets))
            bullets.clear()

    for raw in doc.split("\n"):
        s = raw.strip()
        if s.startswith("### "):
            flush_p()
            flush_b()
            out.append('<h5 class="doc-sub">%s</h5>' % inline(s[4:]))
        elif s.startswith(("- ", "* ")):
            flush_p()
            bullets.append(s[2:])
        elif not s:
            flush_p()
            flush_b()
        else:
            flush_b()
            para.append(s)
    flush_p()
    flush_b()
    return "\n".join(out)


def member_html(m):
    sig = (m.get("signature") or m["name"]).strip()
    doc = (m.get("doc") or "").strip()
    if "\n" in sig:
        sig_html = '<pre class="msig"><code>%s</code></pre>' % esc(reindent(sig))
    else:
        sig_html = "<code>%s</code>" % esc(sig)
    tail = ' <span class="mdoc">%s</span>' % inline(doc) if doc else ""
    return "<li>%s%s</li>" % (sig_html, tail)


def symbol_html(item, prefix):
    name = item["name"]
    kind = item["kind"]
    sid = "%s-%s" % (prefix, name)
    parts = ['<section class="symbol" id="%s">' % sid]
    parts.append('<h4 class="sym"><span class="nm">%s</span>'
                 '<span class="badge">%s</span></h4>' % (esc(name), KIND_ZH.get(kind, kind)))
    sig = (item.get("signature") or "").strip()
    if sig:
        parts.append('<pre class="sig"><code>%s</code></pre>' % esc(reindent(sig)))
    doc = TYPE_DOC_ZH.get(name) or item.get("doc")
    if doc:
        parts.append(render_doc(doc))
    members = item.get("members", [])
    if members:
        by_kind = {}
        for m in members:
            by_kind.setdefault(m["kind"], []).append(m)
        parts.append('<div class="members">')
        parts.append("<h5>成员</h5>")
        for mk in MEMBER_ORDER:
            if mk not in by_kind:
                continue
            parts.append("<h6>%s</h6>" % MEMBER_KIND_ZH.get(mk, mk))
            parts.append("<ul>")
            parts.extend(member_html(m) for m in by_kind[mk])
            parts.append("</ul>")
        parts.append("</div>")
    parts.append("</section>")
    return "\n".join(parts), sid, name


def group_html(kind, items, prefix, out_symbols):
    zh = KIND_ZH.get(kind, kind)
    en = EN_PLURAL.get(kind, kind)
    h = ['<h3 id="%s-grp-%s">%s<span class="cnt">%d</span></h3>'
         % (prefix, kind, esc("%s（%s）" % (zh, en)), len(items))]
    # chip index for quick jumps
    chips = "".join('<a class="chip" href="#%s-%s">%s</a>'
                    % (prefix, t["name"], esc(t["name"])) for t in items)
    h.append('<div class="chips">%s</div>' % chips)
    for t in items:
        body, sid, _ = symbol_html(t, prefix)
        out_symbols.append((sid, t["name"]))
        h.append(body)
    return "\n".join(h)


def library_html(title, items, prefix, out_symbols):
    by_kind = {}
    for t in items:
        by_kind.setdefault(t["kind"], []).append(t)
    h = ['<h2 id="%s-lib">%s</h2>' % (prefix, title)]
    for kind in GROUP_ORDER:
        group = sorted(by_kind.get(kind, []), key=lambda x: x["name"])
        if group:
            h.append(group_html(kind, group, prefix, out_symbols))
    return "\n".join(h)


EXTRA_CSS = """
  /* --- API reference additions --- */
  .sidebar .lib {
    font-size: 12px; color: #ffd28a; margin: 20px 0 6px;
    font-family: Consolas, monospace; font-weight: 600;
  }
  .sidebar details { margin: 2px 0; }
  .sidebar summary {
    cursor: pointer; font-size: 13px; font-weight: 600; color: #8aa0bd;
    padding: 5px 10px; user-select: none;
  }
  .sidebar summary .cnt {
    font-weight: 400; color: #64778f; margin-left: 6px; font-size: 12px;
  }
  .sidebar summary:hover { color: #c8d2e0; }
  h3 .cnt, h4 .cnt {
    font-size: 12px; font-weight: 500; color: var(--maplibre-muted);
    margin-left: 8px; vertical-align: middle;
  }
  h3 { border-bottom: 1px solid var(--maplibre-border); padding-bottom: 6px; margin-top: 44px; }
  .chips { margin: 10px 0 6px; display: flex; flex-wrap: wrap; gap: 6px; }
  .chip {
    font-size: 12.5px; background: #f2f5fa; border: 1px solid var(--maplibre-border);
    border-radius: 999px; padding: 2px 10px; color: #2b62d9;
  }
  .chip:hover { background: #e6edfb; text-decoration: none; }
  section.symbol { margin: 36px 0 8px; padding-top: 8px; }
  h4.sym {
    font-size: 20px; margin: 0 0 6px; display: flex; align-items: center; gap: 10px;
    scroll-margin-top: 16px;
  }
  h4.sym .nm { font-family: Consolas, monospace; }
  .badge {
    font-size: 11.5px; background: #eaf1ff; color: #2b62d9;
    border: 1px solid #c9d9fb; padding: 1px 9px; border-radius: 999px; font-weight: 600;
    flex-shrink: 0;
  }
  pre.sig { margin: 8px 0 10px; }
  h5.doc-sub { font-size: 15px; margin: 18px 0 6px; }
  .members { margin-top: 10px; }
  .members h5 {
    font-size: 13px; color: var(--maplibre-muted); margin: 20px 0 4px;
    border-bottom: 1px solid var(--maplibre-border); padding-bottom: 4px;
    text-transform: none; letter-spacing: 0;
  }
  .members h6 {
    font-size: 12px; color: #51607a; margin: 14px 0 4px; font-weight: 700;
  }
  .members ul { list-style: none; padding: 0; margin: 0; }
  .members li {
    padding: 7px 0 7px 12px; border-left: 2px solid #eef1f5; margin: 0;
  }
  .members li:hover { border-left-color: var(--maplibre-blue); background: #fafbfd; }
  .members pre.msig { padding: 8px 12px; margin: 2px 0; display: inline-block; min-width: 60%; }
  .members li > code { font-size: 13px; }
  .mdoc { color: var(--maplibre-muted); font-size: 13.5px; margin-left: 8px; }
  .members li pre.msig + .mdoc { display: block; margin-left: 0; margin-top: 4px; }
  .footer { margin-top: 72px; }
"""

SCROLL_SPY = """
<script>
  const links = Array.from(document.querySelectorAll('.sidebar li a'));
  const sections = links.map(a => document.querySelector(a.getAttribute('href')));
  const obs = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        links.forEach(l => l.classList.remove('active'));
        const idx = sections.indexOf(e.target);
        if (idx >= 0) links[idx].classList.add('active');
      }
    });
  }, { rootMargin: '-10% 0px -80% 0px' });
  sections.forEach(s => s && obs.observe(s));
</script>
"""

PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>geo_map API 参考（中文版）</title>
<style>
{css}
{extra}
</style>
</head>
<body>
<div class="layout">
  <nav class="sidebar">
    <div class="brand">geo_map<small>API 参考 · 中文版 · 只列定义</small></div>
{sidebar}
  </nav>

  <main class="content">
    <h1>geo_map API 参考（中文版）</h1>
    <p class="lead">由源码自动提取生成，等价于 dartdoc 在线参考
    （<a href="https://qziov.github.io/geo_map/api/geo_map/">qziov.github.io/geo_map/api/geo_map</a>），
    只保留<strong>类 / 接口 / 枚举 / 类型定义 / 函数 / 常量</strong>及其签名，不含使用示例。</p>
    <p class="lead">符号说明为源码 <code>///</code> 文档的中文译注；成员级说明保留原文（简洁且引用参数名，便于对照）。</p>
{body}
    <div class="footer">由 <code>docs/extract_api_ref.py</code> + <code>docs/build_api_zh_html.py</code> 从源码生成 ·
    与 <code>docs/geo_map_api_zh.md</code> 同源</div>
  </main>
</div>
{script}
</body>
</html>
"""


def sidebar_html(libs):
    """libs: list of (title, [(kind, [items])]) — nested collapsible nav."""
    out = []
    for lib_title, groups, prefix in libs:
        out.append('    <div class="lib">%s</div>' % esc(lib_title))
        for kind, items in groups:
            zh = KIND_ZH.get(kind, kind)
            out.append('    <details open>')
            out.append('      <summary>%s<span class="cnt">%d</span></summary>' % (esc(zh), len(items)))
            out.append('      <ul>')
            for t in items:
                out.append('        <li><a href="#%s-%s">%s</a></li>'
                           % (prefix, t["name"], esc(t["name"])))
            out.append('      </ul>')
            out.append('    </details>')
    return "\n".join(out)


def main():
    data = json.loads(RAW.read_text(encoding="utf-8"))
    geo_types = dedupe_types(data["geo_map"])
    geo_funcs = [{"name": f["name"], "kind": "function", "signature": f["signature"],
                  "doc": f["doc"], "members": []}
                 for blk in data["geo_map"] for f in blk.get("functions", [])]
    core = data["geo_map_core_reexport"]

    spy_symbols = []

    def collect(prefix, items):
        for t in sorted(items, key=lambda x: x["name"]):
            spy_symbols.append(("%s-%s" % (prefix, t["name"]), t["name"]))

    collect("gm", geo_types + geo_funcs)
    collect("core", core)

    libs = [
        ("package:geo_map", _groups(geo_types + geo_funcs), "gm"),
        ("package:geo_map_core", _groups(core), "core"),
    ]

    body_gm = library_html("库 <code>package:geo_map</code>", geo_types + geo_funcs, "gm", [])
    # library_html emits symbol ids too; rebuild spy from collect() above (same order).
    body_core = library_html("库 <code>package:geo_map_core</code>（再导出部分）", core, "core", [])

    # Rebuild body with symbol anchors registered (library_html's out_symbols unused here).

    doc = PAGE.format(
        css=CSS_FILE.read_text(encoding="utf-8").rstrip(),
        extra=EXTRA_CSS.strip(),
        sidebar=sidebar_html(libs),
        body=body_gm + "\n" + body_core,
        script=SCROLL_SPY.strip(),
    )
    OUT.write_text(doc, encoding="utf-8")
    print("wrote %s (%d bytes, %d symbols)" % (OUT, len(doc), len(spy_symbols)))


def _groups(items):
    by_kind = {}
    for t in items:
        by_kind.setdefault(t["kind"], []).append(t)
    return [(k, sorted(by_kind[k], key=lambda x: x["name"]))
            for k in GROUP_ORDER if k in by_kind]


if __name__ == "__main__":
    main()
