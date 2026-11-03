#!/usr/bin/env python3
"""Generate a Chinese, dartdoc-equivalent API reference for `geo_map`.

Reads `api_ref_raw.json` (produced by `extract_api_ref.py`) and emits
`geo_map_api_zh.md`: a definitions-only reference (classes / enums /
typedefs / functions / constants + their member signatures) with Chinese
section scaffolding and Chinese translations of the type-level `///` docs.

Member-level `///` comments are kept verbatim (they are terse and reference
parameter names), but each is labelled with a Chinese kind badge.
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
RAW = HERE / "api_ref_raw.json"
OUT = HERE / "geo_map_api_zh.md"

# --- Chinese translations of the type-level doc comments ---------------------
# Keyed by symbol name. Symbols without an entry fall back to the verbatim
# English `///` text (many have no doc comment at all).
TYPE_DOC_ZH = {
    # ---- package:geo_map ----
    "TileImage": "一张已解码的瓦片图像及其着色器。",
    "TileResolution": (
        "一块屏幕瓦片将如何被填充。\n\n"
        "* `exact`（精确）— 请求的瓦片本身可用。\n"
        "* `ancestor`（祖先）— 用更粗的一层瓦片拉伸覆盖请求的足迹；"
        "`ancestorDz` 说明它上溯了几级（UV 为子矩形）。\n"
        "* `descendants`（后代）— 更细的瓦片已加载并覆盖请求的足迹"
        "（对应 MapLibre 的 `_retainLoadedChildren`）。"
    ),
    "TileDraw": (
        "屏幕瓦片的一条绘制指令。\n\n"
        "`geoKey` 是**足迹**（覆盖世界的哪一块），UV 值是 `image` 内部"
        "的**纹理区域**（以图像像素计）。"
    ),
    "CapDraw": (
        "极冠绘制指令（仅 Web Mercator）。\n\n"
        "一条极冠指令覆盖一个**经度区间**，而非单一列，因此两种情形形状一致：\n\n"
        "* 单列宽（`spanLng == grid.tileWidthDeg`）— 一条清晰的楔形，用该列自身瓦片贴图；\n"
        "* 最宽至 `360°` — 一条被涂抹的条带，用单张图像贴图，用于相机身处极冠内部时。"
    ),
    "TileEngine": "瓦片引擎：选择、请求、缓存、回退。",
    "TileGeometry": "负责绘制一帧瓦片指令。",
    "SphericalGeometry": "正交（3D 地球）几何。",
    "AffineGeometry": "Web Mercator（2D）几何：世界像素矩形。",
    "TileLayerMode": "该图层以哪种投影渲染。",
    "TileLayer": (
        "同时服务于 2D 与 3D 的栅格瓦片图层。\n\n"
        "### 引擎归属\n\n"
        "图层接受一个可选的 `engine`。一旦注入，**它归宿主所有**，图层绝不得释放它："
        "共享引擎的全部意义在于 2D 与 3D 图层能互换而不丢失缓存，而正在卸载的图层"
        "并不知道是否有兄弟图层即将以同一引擎挂载。\n\n"
        "若此处搞反，后果并不 subtle——释放被注入的引擎会杀死所有在途解码"
        "（`_decode` 在 `_disposed` 时丢弃该帧），下一次构建即断言"
        "`A TileEngine was used after being disposed`，表现为“地球底图永远加载不出来”。"
    ),
    "GeoFeatureRegistry": "可查询要素的注册表。",
    "GlobeImageLayer": (
        "绘制在地球表面的图像叠加层（气象雷达、卫星条带等）。\n\n"
        "flutter_map 的 `OverlayImageLayer` 把图像映射到四角构成的四边形上，"
        "在球面上看起来像一张平铺的纸：没有曲率、没有地平线裁剪。本图层把 bounds"
        "细分为网格并对每个顶点做投影，于是叠加层贴合地表并会在其背后消失。"
    ),
    "GeoJsonVectorSource": (
        "为调试叠加层加载矢量数据。\n\n"
        "此处的“矢量底图”指：通过 HTTP 拉取一个 GeoJSON `FeatureCollection`，"
        "把其中的线稿喂给 [GlobeVectorLayer]。矢量**瓦片**（MVT）需要完整的"
        "样式 / protobuf 管线；GeoJSON 已足以肉眼验证投影是否正确。"
    ),
    "GlobeProjectionDelegate": (
        "通过（仅 fork 版）`MapProjectionDelegate` 钩子接入 flutter_map 的正交地球投影。\n\n"
        "屏幕空间取代世界空间：\n"
        "* `project()` 返回**屏幕像素**（或远侧点的远端坐标，交给 flutter_map 自带的剔除移除）；\n"
        "* `pixelOrigin` 被 fork 版 `MapCamera` 强制为零；\n"
        "* `pixelBounds` 即视口。"
    ),
    "GlobePolyline": "绘制在屏幕空间中的球面上的折线。",
    "GlobePolygonShape": (
        "球面上的填充多边形（填充 + 描边），用于地球模式以取代 flutter_map 的"
        "`PolygonLayer`——后者的绘制器无法裁剪到地平线。"
    ),
    "GlobeLabel": "锚定在地理坐标点上的文本标签。",
    "GlobeVectorLayer": (
        "地球的矢量调试图层。\n\n"
        "刻意**不**使用 flutter_map 的 `PolylineLayer`/`PolygonLayer`：那些图层在"
        "`camera.project` 之后用 `crs.transform` 再次投影，一旦启用了投影代理就错了。"
        "此处每个顶点都经过 `camera.project`（即代理）与大圆加密，因此本图层也充当"
        "那些图层日后所需实现的参考。"
    ),
    "GlobeRasterSource": "为 [GeoTileSource] 保留的向后兼容别名。",
    "HttpTileSource": (
        "基于 HTTP 的 WMTS / XYZ。\n\n"
        "URL 构建（模板、TMS 翻转、quadkey、bbox、子域、ratio）委托给 core 中的纯"
        " [TileUrlBuilder]，因此在那里有单元测试。本类只负责 404 与网络故障的区分；"
        "套接字本身是 `platform/http_get.dart` 中的共享传输，它有浏览器实现，故本文件可编译到 web。\n\n"
        "`urlTemplate` 支持 `{z}`、`{x}`、`{y}`、`{TileMatrix}`、`{TileRow}`、`{TileCol}`、"
        "`{prefix}`、`{ratio}`、`{quadkey}`、`{bbox}`、`{bbox-epsg-3857}`。"
        "RESTful WMTS 与纯 XYZ 模板均可用。"
    ),
    "MvtDiagnostics": (
        "图层当前正在做什么，供调试 HUD 使用。\n\n"
        "`dataZoom` 是瓦片被请求的层级（0..source.maxZoom），即 `round(camera zoom)`"
        "——并非 HUD 通常显示的连续相机缩放。`readyCount` / `tileCount` 说明已解码的"
        "可见瓦片数量，`lastStatusCode` 在源为 HTTP 时透出传输状态。\n\n"
        "`firstFailed` 标出 `failedCount` 背后那块瓦片（`z/x/y · status`）。没有它，"
        "“一块瓦片失败”的报告无法诊断——关键在于它告诉你那是边界瓦片、越界坐标还是限流。"
    ),
    "MvtVectorLayer": (
        "通过 [StyleSpec] 渲染的矢量瓦片。\n\n"
        "传输以 [GeoTileSource] 注入，因此同一图层可配合 HTTP、MBTiles 或测试桩工作。"
    ),
    "GeoMap": "`GeoMap`——宿主控件。子控件堆叠在栅格图层之上。",
    "GeoMapScope": "供子控件只读访问相机的入口：`GeoMapScope.of(context).camera`。",
    "AnchoredPopupLayout": "纯布局结果（`left/top` 为逻辑像素）。",
    "GeoMapPopupController": (
        "跟随地图的浮层显隐状态（对标 MapLibre `Popup` 的 open/close）。\n\n"
        "只持有**锚点**：内容由宿主通过 [GeoMapPopup.builder] 注入。状态因此与业务"
        "完全解耦，SIGMET / 机场 / POI 等任意图层共用同一套“显示—关闭”逻辑。"
    ),
    "GeoMapPopup": (
        "把 [GeoMapPopupController] 的显隐状态接到 [GeoAnchoredPopup] 上。\n\n"
        "自监听 [popup]：调用 `popup.show/hide` 即自动重绘，宿主无需在父级 `watch`。"
        "业务内容通过 [builder]（入参含锚点）注入——这就是留给宿主的“接口”：在此"
        "返回自己的卡片（含关闭按钮，关闭按钮调用 [GeoMapPopupController.hide]）。"
    ),
    "PopupAnchor": (
        "浮层锚点——九宫格位置（MapLibre `PositionAnchor`）。\n\n"
        "决定卡片的哪条边 / 角贴住由 [GeoMapPopupController] 携带的锚点经纬度。"
        "默认 [bottom]，即保持现有的“卡片浮在锚点上方”行为。"
    ),
    "GeoPopupBinding": (
        "把一个图层（其在 [GeoFeatureRegistry] 中的 `sourceId`）与点击该图层时"
        "弹出的卡片绑定起来。\n\n"
        "这是 MapLibre `map.on('click', layerId, handler)` 的 SDK 等价物：在我们的模型里"
        "“图层”就是一个 `sourceId`，把弹窗绑定到它就是业务图层声明“我被命中时渲染这张卡片”。"
        "命中测试、锚点投影、定位与关闭全部由 [GeoPopupController] 处理——业务侧只需提供"
        " [builder]（卡片）及少量元数据。"
    ),
    "GeoPopupCard": (
        "统一的弹窗卡片外壳。\n\n"
        "结构：\n"
        "- 最外层 [GestureDetector]（`behavior: opaque`）吞掉卡片内的空白点击，"
        "避免漏给下面的地图（等价于 MapLibre Popup 作为独立 DOM 覆盖层的事件隔离）。\n"
        "- [header] 右侧可带一个 SDK 关闭按钮（[onClose] 非空时渲染），命中区 ≥32px。"
    ),
    "GeoPopupController": (
        " [GeoFeatureRegistry] 与共享的 [GeoMapPopupController] 之间的粘合层。\n\n"
        "使用流程见库级文档注释。宿主应用持有一个实例（通常通过把底层弹窗控制器"
        "接入的 Riverpod provider）。"
    ),
    "GeoMapPopupHost": (
        "弹窗控制层的渲染宿主。\n\n"
        "在 `GeoMap` 之外、作为外层 `Stack` 的**直接子级**恰好挂载一个（与 [GeoMapPopup]"
        "同一约束：必须是外层 `Stack` 的直接子级，绝不可位于 `GeoMap.children` 之内）。"
        "它从 [popup] 读取已打开的绑定并渲染对应卡片，每次相机移动时由底层"
        " [GeoMapPopup] 重新定位。"
    ),
    "LatLngBounds": "由西北角与东南角约束而成的矩形包围盒数据结构。",
    # ---- package:geo_map_core (re-exported) ----
    "Expr": "一个已解析的表达式节点。",
    "ExpressionContext": (
        "表达式的求值输入。\n\n"
        "对应 MapLibre 的 `EvaluationParameters` / `EvaluationContext`：`zoom` 是"
        " spike 阶段唯一需要的全局量；`properties` 替代要素的属性表（这正是 `get`/`has`"
        " 让表达式依赖要素的原因）。"
    ),
    "FeaturePredicate": (
        "在某一缩放层级上对单个要素的谓词。\n\n"
        "zoom 可选，因此没有相机的调用方（测试、从不提及 `[\\\"zoom\\\"]` 的过滤器）"
        "仍可询问 `matches(props)`；此时含义为“zoom 0”。"
    ),
    "GeoGeometryKind": "一次查询可考量的几何种类。",
    "GeoTileSource": "栅格瓦片提供者（HTTP、MBTiles 等）。",
    "PropertyValue": "一个绘制 / 布局值：常量，或每次绘制时求值的表达式。",
    "SpriteIcon": "图集中某个图标的矩形区域。",
    "SpriteIndex": "单个精灵的 名称 → 图标 查找表。",
    "TileFailureKind": (
        "一块瓦片为何无法生成。\n\n"
        "区分很关键：缺失的瓦片（404）**不得**被黑名单（MapLibre `tile_manager.ts`"
        " 的 `_loadTile` 只是再次 `update()` 并持续回退到父 / 子瓦片），而网络错误是"
        "瞬时的，应快速重试。"
    ),
    "TileFetchResult": (
        "单次瓦片请求的结果。\n\n"
        "MapLibre 在“服务器声明无此瓦片”（404——永不黑名单，引擎持续回退）与"
        "“请求中断”（网络错误——快速重试）之间划出硬界限。把两者都坍缩成 `null`"
        "正是旧引擎在两次失败后把瓦片拉黑的原因。"
    ),
    "TileRowOrder": (
        "**线上**使用的行序。\n\n"
        "内部（规范）行序始终是 XYZ——第 0 行是网格的北缘。某些服务（TMS、MBTiles）"
        "从南边数行，因此在构建 URL 或从本地文件读取行时必须翻转行索引。\n\n"
        "MapLibre 用一行实现：`tile_id.ts` L48 `y = scheme === 'tms' ? 2^z - y - 1 : y`。"
    ),
    "normalizeRingWinding": (
        "把绕向与外环一致的环反转。\n\n"
        "Canvas 用非零环绕规则填充，因此绕向与外环相同的洞**不会**穿透；将其反转即可"
        "恢复孔洞。外环保持朝向不变，单环多边形原样返回。"
    ),
    "parseGeoJsonFeatures": "解析一个 GeoJSON `FeatureCollection` 或单个 `Feature`。",
    "pointInMultiPolygon": (
        " [point] 是否落在 [polygons]（MultiPolygon）的任一子多边形内。\n\n"
        "各子多边形独立求值（并集语义），与渲染器绘制方式一致——每个环一次 `addPolygon`。"
    ),
    "pointInPolygon": (
        " [point] 是否落在多边形 [rings] 内（首环 = 外环，其余 = 洞）。\n\n"
        "内部为“外环减洞”（RFC 7946）。边界处理：落在**外环**边界上的点算内部；"
        "落在**洞**边界上的点算外部——洞优先。"
    ),
    "pointInRing": (
        " [point] 是否落在闭合环 [ring] 内。\n\n"
        "使用奇偶规则，因此环的绕向无关。`includeBoundary` 决定恰好落在边上的点"
        "是否算内部（默认：算）。顶点少于三个的环返回 `false`。"
    ),
    "ringSignedArea": (
        " [ring] 的带符号面积，在**展开后**的经度上度量。\n\n"
        "正值表示逆时针。展开很关键：靠近 ±180° 的环否则会翻转符号，悄然改变"
        "哪个环被当作外环。"
    ),
    "splitRingAtSeam": (
        "在经线 [seamLng] 处切分 [ring]，返回一个或两个闭合片段。\n\n"
        "先展开环，因此 +179°/−179° 的边会被识别为跨越接缝。若环完全位于一侧，"
        "则原样返回 `[ring]`。顶点少于三个的片段被丢弃。\n\n"
        "这对应 MapLibre 在切片时于 ±180° 切分 GeoJSON 的行为。渲染器自身只需要"
        " [unwrapLongitudes] 加世界副本；此辅助函数让该行为可测试，并允许调用方显式裁剪。"
    ),
    "unwrapLongitudes": (
        "顺序展开 [lons]，使每对相邻差值都落在 (-180, 180]。\n\n"
        "`out[0] == lons[0]`；`out[i] = out[i-1] + wrapLongitude(lons[i] - lons[i-1])`。"
        "一条从 +179° “跳”到 −179° 的环会变成 +179° → +181°（2° 步长）而非 −358° 步长，"
        "从而可被连续投影。"
    ),
}

KIND_ZH = {
    "class": "类",
    "mixin": "混入",
    "enum": "枚举",
    "typedef": "类型定义",
    "extension": "扩展",
    "function": "函数",
    "constant": "常量",
}
EN_PLURAL = {
    "class": "Classes",
    "mixin": "Mixins",
    "enum": "Enums",
    "typedef": "Typedefs",
    "extension": "Extensions",
    "function": "Functions",
    "constant": "Constants",
}
MEMBER_KIND_ZH = {
    "constructor": "构造",
    "method": "方法",
    "getter": "取值",
    "setter": "赋值",
    "field": "字段",
    "operator": "运算符",
    "enum-value": "枚举值",
}
# Order members are grouped under a type.
MEMBER_ORDER = ["constructor", "method", "operator", "getter", "setter", "field", "enum-value"]


def dedupe_types(blocks):
    """Return a list of unique types, preferring the non-stub source file."""
    best = {}
    for blk in blocks:
        for t in blk.get("types", []):
            name = t["name"]
            f = blk.get("file", "")
            is_stub = "stub" in f
            if name not in best or (not is_stub and "stub" in best[name].get("_file", "")):
                t2 = dict(t)
                t2["_file"] = f
                best[name] = t2
    return list(best.values())


def fmt_signature(sig):
    sig = (sig or "").strip()
    # Collapse internal whitespace for readability but keep it one-ish block.
    return sig


def render_type(t):
    name = t["name"]
    kind = t["kind"]
    out = []
    out.append(f"#### `{name}` （{KIND_ZH.get(kind, kind)}）\n")
    sig = fmt_signature(t.get("signature"))
    if sig:
        out.append("```dart")
        out.append(sig)
        out.append("```\n")
    doc = TYPE_DOC_ZH.get(name) or t.get("doc")
    if doc:
        out.append(doc.strip() + "\n")
    members = t.get("members", [])
    if members:
        out.append("\n**成员**\n")
        by_kind = {}
        for m in members:
            by_kind.setdefault(m["kind"], []).append(m)
        for mk in MEMBER_ORDER:
            if mk not in by_kind:
                continue
            out.append(f"\n##### {MEMBER_KIND_ZH.get(mk, mk)}\n")
            for m in by_kind[mk]:
                msig = fmt_signature(m.get("signature")) or m["name"]
                md = (m.get("doc") or "").strip()
                line = f"- `{msig}`"
                if md:
                    line += f" — {md}"
                out.append(line)
        out.append("")
    out.append("\n---\n")
    return "\n".join(out)


def render_library(title, types, functions, constants):
    out = [f"## {title}\n"]
    # group types by kind
    by_kind = {}
    for t in types:
        by_kind.setdefault(t["kind"], []).append(t)
    for tk in ["class", "mixin", "enum", "typedef", "extension", "function", "constant"]:
        items = sorted(by_kind.get(tk, []), key=lambda x: x["name"])
        if not items:
            continue
        out.append(f"### {KIND_ZH.get(tk, tk)}（{EN_PLURAL.get(tk, tk)}）\n")
        # index of names
        out.append(", ".join(f"`{t['name']}`" for t in items))
        out.append("")
        for t in items:
            out.append(render_type(t))
    if functions:
        out.append(f"### 函数（Functions）\n")
        out.append(", ".join(f"`{f['name']}`" for f in sorted(functions, key=lambda x: x["name"])))
        out.append("")
        for f in sorted(functions, key=lambda x: x["name"]):
            out.append(f"#### `{f['name']}` （函数）\n")
            sig = fmt_signature(f.get("signature"))
            if sig:
                out.append("```dart")
                out.append(sig)
                out.append("```\n")
            doc = TYPE_DOC_ZH.get(f["name"]) or f.get("doc")
            if doc:
                out.append(doc.strip() + "\n")
            out.append("\n---\n")
    if constants:
        out.append("### 常量（Constants）\n")
        for c in sorted(constants, key=lambda x: x["name"]):
            out.append(f"#### `{c['name']}` （常量）\n")
            sig = fmt_signature(c.get("signature"))
            if sig:
                out.append("```dart")
                out.append(sig)
                out.append("```\n")
            doc = c.get("doc")
            if doc:
                out.append(doc.strip() + "\n")
            out.append("\n---\n")
    return "\n".join(out)


def main():
    data = json.loads(RAW.read_text(encoding="utf-8"))
    geo_types = dedupe_types(data["geo_map"])
    geo_funcs = [f for blk in data["geo_map"] for f in blk.get("functions", [])]
    geo_consts = [c for blk in data["geo_map"] for c in blk.get("constants", [])]
    core = data["geo_map_core_reexport"]

    md = []
    md.append("# geo_map API 参考（中文版）\n")
    md.append(
        "> 本文件由源码自动提取生成，等价于 dartdoc 在线参考"
        "（https://qziov.github.io/geo_map/api/geo_map/），但**只保留定义**："
        "类 / 接口 / 枚举 / 类型定义 / 函数 / 常量及其签名，不含使用示例。\n\n"
        "> 各符号下方的说明为源码 `///` 文档的**中文译注**；成员级说明保留原文"
        "（简洁且引用参数名，便于对照）。\n"
    )
    md.append("---\n")
    md.append(render_library("库 `package:geo_map`", geo_types, geo_funcs, geo_consts))
    md.append(
        render_library(
            "库 `package:geo_map_core`（再导出部分）",
            core,
            [],
            [],
        )
    )
    OUT.write_text("\n".join(md), encoding="utf-8")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
