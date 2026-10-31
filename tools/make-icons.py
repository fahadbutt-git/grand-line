#!/usr/bin/env python3
"""Draws the bundled app icons (AppIcon.icns) for Nexus, Sight, Grand Line Index and Iceberg.

The apps draw their icons again at run time from the active theme
(apps/icons). This script draws the same glyphs, read from the table in
apps/icons/Sources/AppIcon/Glyphs.swift, in a theme's colours, so an app has
an icon before it first runs. Pure Python: PNGs are written with zlib and the
.icns container by hand, so nothing needs installing.

  python3 tools/make-icons.py                  graphite, into each app's Resources
  python3 tools/make-icons.py --theme daylight
  python3 tools/make-icons.py --previews DIR   also write DIR/<App>-<theme>.png (1024 and 32)
  python3 tools/make-icons.py --theme signal-dark --previews DIR --previews-only
  python3 tools/make-icons.py --check          the table parses and every .icns is sound
  python3 tools/make-icons.py --theme nord --out DIR
                                               write DIR/<App>/AppIcon.icns instead (bin/theme
                                               puts these in the installed apps)
"""
import argparse
import math
import os
import re
import struct
import sys
import zlib
from array import array

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLYPHS = os.path.join(ROOT, "apps/icons/Sources/AppIcon/Glyphs.swift")
THEMES = os.path.join(ROOT, "config/themes")
# glyph table name, theme key, where the .icns goes
APPS = [
    ("nexus", "ICON_FILES", "apps/finder/Resources/Nexus/AppIcon.icns", "Nexus"),
    ("sight", "ICON_SEARCH", "apps/finder/Resources/Sight/AppIcon.icns", "Sight"),
    # The index agent shows only in Login Items and Privacy & Security, under
    # Sight's glyph, the app it mostly serves.
    ("sight", "ICON_SEARCH", "apps/finder/Resources/GrandLineIndex/AppIcon.icns", "GrandLineIndex"),
    ("iceberg", "ICON_NOTCH", "apps/iceberg/Resources/Iceberg/AppIcon.icns", "Iceberg"),
]
SIZE = 1024
ICNS_TYPES = [(b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64),
              (b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024)]
DETAIL_SIZE = 64   # IconGlyphs.detailSize: smaller icons leave the fine detail out
ROLES = ("tile", "ink", "accent", "soft", "shade", "ice", "deep", "vessel", "pale")


# --- the glyph table ---------------------------------------------------------

def read_tables(path=GLYPHS):
    text = open(path, encoding="utf-8").read()
    tables = {}
    for name, body in re.findall(r"static let (\w+): \[IconMark\] = \[(.*?)\n    \]", text, re.S):
        marks = []
        for kind, role, values in re.findall(r"IconMark\(\.(\w+), \.(\w+), \[([-0-9., ]*)\]\)", body):
            marks.append((kind, role, [float(v) for v in values.split(",") if v.strip()]))
        tables[name] = marks
    return tables


# --- colours, as apps/icons/Sources/AppIcon/IconTheme.swift ---------------------

def hex_color(text):
    if text is None:
        return None
    t = text.strip().lstrip("#")
    if len(t) != 6 or any(c not in "0123456789abcdefABCDEF" for c in t):
        return None
    return tuple(int(t[i:i + 2], 16) / 255 for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def luminance(c):
    lin = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def parse_theme(text):
    """One file's KEY=value lines, read as ThemeSource.parse reads them."""
    values = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        for prefix in ("export ", "export\t"):
            if line.startswith(prefix):
                line = line[len(prefix):].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if not re.match(r"^[A-Z_][A-Z0-9_]*$", key):
            continue
        if value[:1] in ("\"", "'"):
            end = value.find(value[0], 1)
            value = value[1:end] if end >= 0 else value[1:]
        else:
            note = re.search(r"[ \t]#", value)
            if note:
                value = value[:note.start()].strip()
        values[key] = value
    return values


MAX_DEPTH = 8   # ThemeSource.maxDepth


def read_theme(name, folder=THEMES):
    """The theme's keys with what it inherits through EXTENDS (the nearest
    file that sets a key wins), as the apps and lib/templates.sh read it."""
    chain, seen, current = [], set(), name
    while current is not None:
        if current in seen:
            raise SystemExit("make-icons: EXTENDS=%s leads back to %s (a loop)" % (current, current))
        if len(chain) >= MAX_DEPTH:
            raise SystemExit("make-icons: %s: EXTENDS goes more than %d themes deep" % (name, MAX_DEPTH))
        if not re.match(r"^[a-z0-9][a-z0-9_-]*$", current):
            raise SystemExit("make-icons: %r is not a theme name" % current)
        seen.add(current)
        path = os.path.join(folder, current + ".theme")
        try:
            with open(path, encoding="utf-8") as f:
                values = parse_theme(f.read())
        except OSError:
            if not chain:
                raise
            raise SystemExit("make-icons: EXTENDS=%s names no theme (%s.theme is missing)" % (current, current))
        chain.append(values)
        current = values.get("EXTENDS")
    merged = {}
    for values in reversed(chain):
        merged.update(values)
    merged.pop("EXTENDS", None)
    return merged


def palette(values, app_key):
    def color(key):
        return hex_color(values.get(key))
    style = (values.get("ICON_STYLE") or "line").lower()
    if style not in ("line", "solid", "mono"):
        style = "line"
    background, foreground = color("TERM_BG"), color("TERM_FG")
    mode = (values.get("MODE") or "").lower()
    dark = mode == "dark" if mode in ("dark", "light") else luminance(background or (0, 0, 0)) < 0.4
    accent_key = color("ICON_ACCENT") or color("ACCENT_HEX") or color("HIGHLIGHT")
    app = color(app_key) or accent_key or hex_color("409cff")
    dark_tile, light_ink = hex_color("1c1c1e"), hex_color("e5e5e7")
    if style == "line":
        tile = color("ICON_TILE") or ((background or dark_tile) if dark else dark_tile)
        ink = color("ICON_INK") or ((foreground or light_ink) if dark else light_ink)
        accent = app
    elif style == "solid":
        tile, ink, accent = app, color("ICON_INK") or dark_tile, hex_color("f5f5f7")
    else:
        tile, ink, accent = color("ICON_TILE") or (0, 0, 0), app, mix(app, (1, 1, 1), 0.45)
    soft = color("ICON_SOFT") or mix(tile, accent, 0.24)
    shade = ink if luminance(ink) < luminance(tile) else tile
    if style == "line":
        ice = ink if luminance(tile) < 0.4 else mix(accent, (1, 1, 1), 0.55)
    elif style == "solid":
        ice = mix(tile, (1, 1, 1), 0.7)
    else:
        ice = ink
    return {"tile": tile, "ink": ink, "accent": accent, "soft": soft, "shade": shade, "ice": ice,
            "deep": mix(accent, (0, 0, 0), 0.42), "vessel": mix(accent, (0, 0, 0), 0.24),
            "pale": mix(accent, hex_color("fff6dc"), 0.8)}


# --- drawing: signed distances, one pixel of anti-aliasing -------------------

def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    t = 0.0 if length == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length))
    ex, ey = px - (ax + t * dx), py - (ay + t * dy)
    return math.sqrt(ex * ex + ey * ey)


def shape(kind, v):
    """(bounding box, distance function): negative inside."""
    if kind == "rrect":
        x, y, w, h, r = v
        cx, cy, hx, hy = x + w / 2, y + h / 2, w / 2 - r, h / 2 - r
        def d(px, py):
            qx, qy = abs(px - cx) - hx, abs(py - cy) - hy
            outside = math.hypot(max(qx, 0), max(qy, 0))
            return outside + min(max(qx, qy), 0) - r
        return (x, y, x + w, y + h), d
    if kind == "disc":
        cx, cy, r = v
        return (cx - r, cy - r, cx + r, cy + r), lambda px, py: math.hypot(px - cx, py - cy) - r
    if kind == "ring":
        cx, cy, r, w = v
        e = r + w / 2
        return (cx - e, cy - e, cx + e, cy + e), lambda px, py: abs(math.hypot(px - cx, py - cy) - r) - w / 2
    if kind == "arc":
        cx, cy, r, w, a0, a1 = v
        e = r + w / 2
        span = (a1 - a0) % 360
        ends = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in (a0, a1)]
        def d(px, py):
            ang = (math.degrees(math.atan2(py - cy, px - cx)) - a0) % 360
            if ang <= span:
                return abs(math.hypot(px - cx, py - cy) - r) - w / 2
            return min(math.hypot(px - ex, py - ey) for ex, ey in ends) - w / 2
        return (cx - e, cy - e, cx + e, cy + e), d
    if kind == "segment":
        x1, y1, x2, y2, w = v
        e = w / 2
        return (min(x1, x2) - e, min(y1, y2) - e, max(x1, x2) + e, max(y1, y2) + e), \
            lambda px, py: seg_dist(px, py, x1, y1, x2, y2) - e
    if kind == "polygon":
        pts = list(zip(v[0::2], v[1::2]))
        edges = list(zip(pts, pts[1:] + pts[:1]))
        def d(px, py):
            inside = False
            best = 1e9
            for (ax, ay), (bx, by) in edges:
                if (ay > py) != (by > py) and px < (bx - ax) * (py - ay) / (by - ay) + ax:
                    inside = not inside
                best = min(best, seg_dist(px, py, ax, ay, bx, by))
            return -best if inside else best
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return (min(xs), min(ys), max(xs), max(ys)), d
    if kind == "ellipse":
        cx, cy, rx, ry = v
        def d(px, py):
            return (math.hypot((px - cx) / rx, (py - cy) / ry) - 1) * min(rx, ry)
        return (cx - rx, cy - ry, cx + rx, cy + ry), d
    if kind == "lens":
        cx, cy, a, h, w = v
        r = (a * a + h * h) / (2 * h)
        upper, lower = cy - h + r, cy + h - r
        def body(px, py):
            return max(math.hypot(px - cx, py - upper) - r, math.hypot(px - cx, py - lower) - r)
        e = w / 2
        box = (cx - a - e, cy - h - e, cx + a + e, cy + h + e)
        if w <= 0:
            return box, body
        return box, lambda px, py: abs(body(px, py)) - e
    raise ValueError("unknown mark kind " + kind)


class Canvas:
    def __init__(self, size):
        self.size = size
        self.r = array("f", bytes(4 * size * size))
        self.g = array("f", bytes(4 * size * size))
        self.b = array("f", bytes(4 * size * size))
        self.a = array("f", bytes(4 * size * size))

    def paint(self, kind, values, color, scale=1.0):
        box, dist = shape(kind, values)
        n = self.size
        x0, y0 = max(0, int(box[0] * scale) - 2), max(0, int(box[1] * scale) - 2)
        x1, y1 = min(n, int(box[2] * scale) + 3), min(n, int(box[3] * scale) + 3)
        cr, cg, cb = color
        inv = 1 / scale
        R, G, B, A = self.r, self.g, self.b, self.a
        for y in range(y0, y1):
            py = (y + 0.5) * inv
            row = y * n
            for x in range(x0, x1):
                cov = 0.5 - dist((x + 0.5) * inv, py) * scale
                if cov <= 0:
                    continue
                if cov > 1:
                    cov = 1.0
                i = row + x
                keep = 1 - cov
                R[i] = cr * cov + R[i] * keep
                G[i] = cg * cov + G[i] * keep
                B[i] = cb * cov + B[i] * keep
                A[i] = cov + A[i] * keep

    def rgba(self):
        out = bytearray(4 * self.size * self.size)
        for i in range(self.size * self.size):
            a = self.a[i]
            if a <= 0:
                continue
            # Stored premultiplied; PNG wants straight alpha.
            out[4 * i] = min(255, round(self.r[i] / a * 255))
            out[4 * i + 1] = min(255, round(self.g[i] / a * 255))
            out[4 * i + 2] = min(255, round(self.b[i] / a * 255))
            out[4 * i + 3] = min(255, round(a * 255))
        return out


def downsample(rgba, size):
    """Half the size, averaging premultiplied 2x2 blocks."""
    half = size // 2
    out = bytearray(4 * half * half)
    for y in range(half):
        for x in range(half):
            acc = [0.0, 0.0, 0.0, 0.0]
            for oy in (0, 1):
                for ox in (0, 1):
                    i = 4 * ((2 * y + oy) * size + 2 * x + ox)
                    a = rgba[i + 3] / 255
                    acc[0] += rgba[i] * a
                    acc[1] += rgba[i + 1] * a
                    acc[2] += rgba[i + 2] * a
                    acc[3] += a
            j = 4 * (y * half + x)
            if acc[3] > 0:
                out[j] = min(255, round(acc[0] / acc[3]))
                out[j + 1] = min(255, round(acc[1] / acc[3]))
                out[j + 2] = min(255, round(acc[2] / acc[3]))
                out[j + 3] = min(255, round(acc[3] / 4 * 255))
    return out


def png(rgba, size):
    raw = b"".join(b"\x00" + bytes(rgba[4 * size * y:4 * size * (y + 1)]) for y in range(size))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def icns(pngs):
    body = b"".join(kind + struct.pack(">I", len(data) + 8) + data for kind, data in pngs)
    return b"icns" + struct.pack(">I", len(body) + 8) + body


def read_icns(data):
    """The entries of an .icns file, or raises ValueError."""
    if data[:4] != b"icns" or struct.unpack(">I", data[4:8])[0] != len(data):
        raise ValueError("not an icns file")
    entries, at = {}, 8
    while at < len(data):
        kind, length = data[at:at + 4], struct.unpack(">I", data[at + 4:at + 8])[0]
        if length < 8 or at + length > len(data):
            raise ValueError("broken entry")
        entries[kind] = data[at + 8:at + length]
        at += length
    return entries


def glyph_marks(tables, name, pixels):
    """As IconGlyph.marks(pixels:): NAME, then NAMEDetail from DETAIL_SIZE up, then NAMETop."""
    detail = tables.get(name + "Detail", []) if pixels >= DETAIL_SIZE else []
    return tables[name] + detail + tables.get(name + "Top", [])


def draw(tables, marks, colors):
    canvas = Canvas(SIZE)
    for kind, role, values in tables["tile"] + marks:
        canvas.paint(kind, values, colors[role])
    return canvas.rgba()


def render_sizes(tables, name, colors):
    """Every size the .icns holds, each halved from the one above."""
    sizes = {}
    rgba, size = draw(tables, glyph_marks(tables, name, SIZE), colors), SIZE
    sizes[size] = rgba
    while size > DETAIL_SIZE:
        rgba = downsample(rgba, size)
        size //= 2
        sizes[size] = rgba
    if tables.get(name + "Detail"):
        rgba, size = draw(tables, glyph_marks(tables, name, 32), colors), SIZE
    while size > 16:
        rgba = downsample(rgba, size)
        size //= 2
        if size <= 32:
            sizes[size] = rgba
    return sizes


def check(tables):
    problems = []
    for name in ["tile"] + [a[0] for a in APPS]:
        if not tables.get(name):
            problems.append("Glyphs.swift: no marks in the %s table" % name)
    for marks in tables.values():
        for kind, role, values in marks:
            try:
                shape(kind, values)
            except (ValueError, TypeError) as error:
                problems.append("Glyphs.swift: %s %s: %s" % (kind, values, error))
            if role not in ROLES:
                problems.append("Glyphs.swift: unknown role " + role)
    for _, _, path, _ in APPS:
        try:
            entries = read_icns(open(os.path.join(ROOT, path), "rb").read())
            for kind, size in ICNS_TYPES:
                data = entries.get(kind, b"")
                if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != (size, size):
                    problems.append("%s: %s is not a %d px PNG" % (path, kind.decode(), size))
        except (OSError, ValueError) as error:
            problems.append("%s: %s" % (path, error))
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--theme", default="graphite")
    parser.add_argument("--previews", metavar="DIR")
    parser.add_argument("--only", choices=[a[3] for a in APPS])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--out", metavar="DIR", help="write DIR/<App>/AppIcon.icns, leave the package's own")
    parser.add_argument("--previews-only", action="store_true", help="write the previews, leave the .icns files")
    args = parser.parse_args()
    tables = read_tables()
    if args.check:
        problems = check(tables)
        print("\n".join(problems))
        return 1 if problems else 0
    values = read_theme(args.theme)
    for name, key, path, product in APPS:
        if args.only and args.only != product:
            continue
        sizes = render_sizes(tables, name, palette(values, key))
        if not args.previews_only:
            if args.out:
                target = os.path.join(args.out, product, "AppIcon.icns")
            else:
                target = os.path.join(ROOT, path)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as f:
                f.write(icns([(kind, png(sizes[s], s)) for kind, s in ICNS_TYPES]))
            print("wrote", target if args.out else path)
        if args.previews:
            os.makedirs(args.previews, exist_ok=True)
            preview = os.path.join(args.previews, "%s-%s.png" % (product, args.theme))
            with open(preview, "wb") as f:
                f.write(png(sizes[SIZE], SIZE))
            print("wrote", preview)
            small = os.path.join(args.previews, "%s-%s-32.png" % (product, args.theme))
            with open(small, "wb") as f:
                f.write(png(sizes[32], 32))
    return 0


if __name__ == "__main__":
    sys.exit(main())
