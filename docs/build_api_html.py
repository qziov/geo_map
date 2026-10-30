#!/usr/bin/env python3
"""Render `geo_map_api.md` into the styled, sidebar-bearing `geo_map_api.html`.

Usage
-----
    python build_api_html.py                      # docs/geo_map_api.md -> docs/geo_map_api.html
    python build_api_html.py other.md             # custom markdown input
    python build_api_html.py in.md out.html       # custom input and output

Files
-----
    api_style.css     page styling (edit this to restyle the page)
    geo_map_api.md    source of truth -- edit this, then re-run this script
    geo_map_api.html  generated artifact; keep it in sync after editing the .md

Why a hand-rolled converter instead of a markdown library: the target HTML has a
fixed shell (sticky sidebar + `.toc` block + scroll-spy script) that generic
converters do not produce, and this keeps the tool dependency-free -- a plain
Python 3 install is enough.

Supported markdown subset (the rest is rendered as paragraphs):
    # / ## / ### headings       tables with a `| --- |` separator row
    ``` fenced code             - / * unordered lists, 1. ordered lists
    > blockquotes               `code`, **bold**, *italic*, [text](#anchor)

Two markdown-structuring quirks this script deliberately relies on:
  * the source's own `## 目录` heading is dropped -- the sidebar and `.toc` are
    generated from the section list instead;
  * the link-only list right after it (the in-markdown TOC) is dropped too, for
    the same reason. Dropping them keeps the sidebar at sec0..secN.
"""

import argparse
import html
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_MD = HERE / "geo_map_api.md"
DEFAULT_HTML = HERE / "geo_map_api.html"
CSS_FILE = HERE / "api_style.css"

# Scroll-spy: highlights the sidebar entry of the section currently in view.
PAGE_SCRIPT = """
<script>
  // 滚动高亮当前章节
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
  }, { rootMargin: '-20% 0px -70% 0px' });
  sections.forEach(s => s && obs.observe(s));
</script>
"""


def slugify(text):
    """GitHub-style anchor: lowercase, keep CJK/word chars/hyphens, spaces -> '-'."""
    t = text.strip().replace("`", "").replace("**", "").replace("*", "")
    t = t.lower()
    t = re.sub(r"[^\w\u4e00-\u9fff\- ]+", "", t, flags=re.UNICODE)
    return re.sub(r"\s+", "-", t.strip())


def inline(text):
    """Escape HTML, then apply code spans / links / bold / italic."""
    s = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    stash = []

    def stash_code(m):
        stash.append(m.group(1))
        return "\x00%d\x00" % (len(stash) - 1)

    # Code spans first, so their contents are never re-formatted.
    s = re.sub(r"`([^`]+)`", stash_code, s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", s)

    for i, code in enumerate(stash):
        s = s.replace("\x00%d\x00" % i, "<code>%s</code>" % code)
    return s


def render_table(rows):
    """rows: '| a | b |' lines, with the `| --- |` separator at index 1."""

    def cells(line):
        line = line.strip()
        if line.startswith("|"):
            line = line[1:]
        if line.endswith("|"):
            line = line[:-1]
        return [c.strip() for c in line.split("|")]

    head = cells(rows[0])
    out = [
        "<table>",
        "<thead><tr>" + "".join("<th>%s</th>" % inline(c) for c in head) + "</tr></thead>",
        "<tbody>",
    ]
    for row in rows[2:]:
        out.append("<tr>" + "".join("<td>%s</td>" % inline(c) for c in cells(row)) + "</tr>")
    out += ["</tbody>", "</table>"]
    return "\n".join(out)


LIST_RE = re.compile(r"^\s*[-*]\s+")
OLIST_RE = re.compile(r"^\s*\d+\.\s+")
LINK_ONLY_RE = re.compile(r"^\[[^\]]+\]\(#[^)]+\)$")
HR = ("---", "***", "___")


def convert(md_text):
    """Return (body_html, [(anchor, title), ...]) for the top-level sections."""
    lines = md_text.split("\n")
    out, sections = [], []
    i = 0
    seen_h2 = False
    sec_index = 0

    while i < len(lines):
        line = lines[i]

        if line.strip().startswith("```"):
            i += 1
            buf = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            out.append("<pre><code>%s</code></pre>" % html.escape("\n".join(buf)))
            continue

        if line.strip().startswith("|"):
            buf = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                buf.append(lines[i])
                i += 1
            out.append(render_table(buf))
            continue

        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            level, title = len(m.group(1)), m.group(2).strip()
            if level == 1:
                out.append("<h1>%s</h1>" % inline(title))
            elif level == 2:
                if title == "目录":  # replaced by the generated .toc block
                    i += 1
                    continue
                anchor = "sec%d" % sec_index
                sections.append((anchor, title))
                sec_index += 1
                seen_h2 = True
                out.append('<h2 id="%s">%s</h2>' % (anchor, inline(title)))
            else:
                out.append('<h3 id="%s">%s</h3>' % (slugify(title), inline(title)))
            i += 1
            continue

        if line.strip().startswith(">"):
            buf = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip().lstrip(">").strip())
                i += 1
            body = inline(" ".join(buf))
            # The blockquote before the first section is the lead paragraph.
            out.append('<p class="lead">%s</p>' % body if not seen_h2
                       else '<div class="callout">%s</div>' % body)
            continue

        if line.strip() in HR:
            i += 1
            continue

        if LIST_RE.match(line):
            buf = []
            while i < len(lines) and LIST_RE.match(lines[i]):
                buf.append(LIST_RE.sub("", lines[i]).strip())
                i += 1
            # Drop the in-markdown TOC (link-only list before the first section).
            if not seen_h2 and buf and all(LINK_ONLY_RE.match(b) for b in buf):
                continue
            out.append("<ul>\n" + "\n".join("<li>%s</li>" % inline(b) for b in buf) + "\n</ul>")
            continue

        if OLIST_RE.match(line):
            buf = []
            while i < len(lines) and OLIST_RE.match(lines[i]):
                buf.append(OLIST_RE.sub("", lines[i]).strip())
                i += 1
            out.append("<ol>\n" + "\n".join("<li>%s</li>" % inline(b) for b in buf) + "\n</ol>")
            continue

        if not line.strip():
            i += 1
            continue

        buf = [line.strip()]
        i += 1
        while i < len(lines):
            nxt = lines[i]
            if (not nxt.strip() or nxt.strip().startswith(("|", ">", "#", "```"))
                    or LIST_RE.match(nxt) or OLIST_RE.match(nxt)
                    or nxt.strip() in HR):
                break
            buf.append(nxt.strip())
            i += 1
        out.append("<p>%s</p>" % inline(" ".join(buf)))

    return "\n".join(out), sections


PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>geo_map API 文档</title>
<style>
{css}
</style>
</head>
<body>
<div class="layout">
  <nav class="sidebar">
    <div class="brand">geo_map<small>API 文档 · Dart / Flutter</small></div>
    <h2>目录</h2>
    <ul>
{sidebar}
    </ul>
  </nav>

  <main class="content">
    <div class="toc">
      <strong>章节</strong>
      <ul>
{toc}
      </ul>
    </div>

{body}
  </main>
</div>
{script}
</body>
</html>
"""


def main(argv=None):
    ap = argparse.ArgumentParser(description="Build geo_map_api.html from its markdown.")
    ap.add_argument("md", nargs="?", default=str(DEFAULT_MD), help="input markdown")
    ap.add_argument("out", nargs="?", default=str(DEFAULT_HTML), help="output html")
    args = ap.parse_args(argv)

    md_path = pathlib.Path(args.md)
    out_path = pathlib.Path(args.out)
    if not md_path.is_file():
        sys.exit("markdown not found: %s" % md_path)
    if not CSS_FILE.is_file():
        sys.exit("stylesheet not found: %s" % CSS_FILE)

    body, sections = convert(md_path.read_text(encoding="utf-8"))
    if not sections:
        sys.exit("no '##' sections found in %s -- nothing to build" % md_path)

    sidebar = "\n".join('      <li><a href="#%s">%s</a></li>' % (a, inline(t))
                        for a, t in sections)
    toc = "\n".join('        <li><a href="#%s">%s</a></li>' % (a, inline(t))
                    for a, t in sections)

    # rstrip only: the stylesheet's own leading indentation is intentional.
    doc = PAGE.format(css=CSS_FILE.read_text(encoding="utf-8").rstrip(),
                      sidebar=sidebar, toc=toc, body=body, script=PAGE_SCRIPT.strip())
    out_path.write_text(doc, encoding="utf-8")
    print("wrote %s (%d bytes, %d sections)" % (out_path, len(doc), len(sections)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
