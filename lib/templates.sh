# shellcheck shell=bash
# Theme files and templates. Sourced by bin/theme and the tests.
#
# A theme file (config/themes/NAME.theme) is format 1 of DESIGN.md, "Theme
# format": KEY=value lines, # comments, values optionally in quotes. A file
# may name one parent with EXTENDS=NAME (a theme in the same folder); its keys
# come first and the file's own replace them. Reading a theme always runs the
# checker, which fills the defaults and rejects bad values with FILE:LINE
# messages, so nothing renders from a half-written theme.
#
# Templates, as in Omarchy: every file in config/themed/NAME.tpl is rendered
# to NAME. A {{ KEY }} placeholder takes any key of the resolved theme, plus
# NAME (the theme's file name) and COLOR0 to COLOR15 (the PALETTE, in order).
# A colour key comes in four forms:
#   {{ KEY }}      #rrggbb
#   {{ KEY.hex }}  rrggbb
#   {{ KEY.rgb }}  r,g,b         (0 to 255)
#   {{ KEY.dec }}  r g b         (0 to 1, three decimals: 0.341 0.706 0.941)
# Templates written before the forms existed put a # in front ("#{{ KEY }}");
# they still render one #. An unknown key or form is left as written.
#
# The program below is POSIX awk (macOS ships the one true awk), and stays
# free of the apostrophe character because it sits in single quotes.

# The newest format this package reads.
THEME_FORMAT=1

_THEME_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function shown(p) { return (root != "" && index(p, root "/") == 1) ? substr(p, length(root) + 2) : p }
function report(sev, path, line, msg) {
  if (sev == "error") errors++; else warnings++
  nmsg++; msgs[nmsg] = shown(path) (line > 0 ? ":" line : "") ": " sev ": " msg
}
function at(key, sev, msg) { report(sev, (key in vfile) ? vfile[key] : file, (key in vline) ? vline[key] : 0, msg) }
function ishex(v) { return length(v) == 6 && v !~ /[^0-9a-fA-F]/ }
function hexval(s,    i, n) {
  s = tolower(s); n = 0
  for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
  return n
}
function chan(h, i) { return hexval(substr(h, i * 2 + 1, 2)) / 255 }
function mix(a, b, t,    i, x, out) {
  out = ""
  for (i = 0; i < 3; i++) {
    x = chan(a, i) + (chan(b, i) - chan(a, i)) * t
    if (x < 0) x = 0
    if (x > 1) x = 1
    out = out sprintf("%02x", int(x * 255 + 0.5))
  }
  return out
}
function lum(h,    i, c, l) {
  l = 0
  for (i = 0; i < 3; i++) {
    c = chan(h, i)
    c = (c <= 0.04045) ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4
    l += (i == 0 ? 0.2126 : (i == 1 ? 0.7152 : 0.0722)) * c
  }
  return l
}
function contrast(a, b,    x, y) { x = lum(a); y = lum(b); return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05) }
function colourkey(k) {
  if (k == "KIND_STYLE") return 0
  return k ~ /^(TERM_(BG|FG|CURSOR|SELECTION)|ACCENT_HEX|MUTED|BG_LIGHTER|BG_DARKER|HIGHLIGHT|SIDEBAR|FIELD|LINE|NOTCH_(PANEL|CARD|LINE)|ICON_(TILE|INK|ACCENT|SOFT|FILES|SEARCH|NOTCH)|KIND_[A-Z]+|COLOR[0-9]+|COLOR_[A-Z0-9_]+)$/
}

# Reads one file of the chain into fval[n, KEY] and fline[n, KEY].
# Returns -1 when the file cannot be opened.
function readfile(path, n,    row, got, lineno, key, value, q, rest, e) {
  lineno = 0; fkeys[n] = ""
  while ((got = (getline row < path)) > 0) {
    lineno++
    row = trim(row)
    if (row == "" || substr(row, 1, 1) == "#") continue
    sub(/^export[ \t]+/, "", row)
    if (row !~ /^[A-Z_][A-Z0-9_]*[ \t]*=/) { report("warning", path, lineno, "not a KEY=value line (keys are upper case); ignored"); continue }
    key = trim(substr(row, 1, index(row, "=") - 1))
    value = trim(substr(row, index(row, "=") + 1))
    q = substr(value, 1, 1)
    if (q == "\"" || q == "\047") {
      rest = substr(value, 2); e = index(rest, q)
      if (e == 0) { report("warning", path, lineno, key " has no closing quote"); value = rest }
      else value = substr(rest, 1, e - 1)
    } else sub(/[ \t]+#.*$/, "", value)
    if ((n, key) in fval) report("warning", path, lineno, key " is set twice in this file; this line wins")
    else fkeys[n] = fkeys[n] " " key
    fval[n, key] = value; fline[n, key] = lineno
  }
  close(path)
  return (got < 0 && lineno == 0) ? -1 : 0
}

# Follows EXTENDS from the file to its root, then lays the files over each
# other from the root down: val, vfile and vline hold every key.
function resolve(    cur, n, i, j, k, nk, keys, ext, dir, base) {
  n = 0; cur = file
  while (cur != "") {
    base = cur; sub(/^.*\//, "", base); sub(/\.theme$/, "", base)
    if (base in seen) {
      report("error", chain[n], fline[n, "EXTENDS"], "EXTENDS=" fval[n, "EXTENDS"] " leads back to " base " (a loop)")
      break
    }
    seen[base] = 1
    n++; chain[n] = cur
    if (readfile(cur, n) < 0) {
      if (n == 1) report("error", cur, 0, "cannot be read")
      else report("error", chain[n - 1], fline[n - 1, "EXTENDS"], "EXTENDS=" fval[n - 1, "EXTENDS"] " names no theme (" shown(cur) " is missing)")
      n--; break
    }
    if (!((n, "EXTENDS") in fval)) break
    ext = fval[n, "EXTENDS"]
    if (ext !~ /^[a-z0-9][a-z0-9_-]*$/) { report("error", cur, fline[n, "EXTENDS"], "EXTENDS=" ext " must be the name of a theme in the same folder"); break }
    if (n >= 8) { report("error", cur, fline[n, "EXTENDS"], "EXTENDS goes more than 8 themes deep"); break }
    dir = cur
    if (sub(/\/[^\/]*$/, "", dir) == 0) dir = "."
    cur = dir "/" ext ".theme"
  }
  norder = 0
  for (i = n; i >= 1; i--) {
    nk = split(fkeys[i], keys, " ")
    for (j = 1; j <= nk; j++) {
      k = keys[j]
      if (k == "EXTENDS") continue
      if (!(k in val)) order[++norder] = k
      val[k] = fval[i, k]; vfile[k] = chain[i]; vline[k] = fline[i, k]
    }
  }
}

function setdefault(k, v) { if (!(k in val) && v != "") { val[k] = v; order[++norder] = k } }
function choice(k, list,    v) {
  if (!(k in val)) return
  v = tolower(val[k])
  if (index(" " list " ", " " v " ") == 0) { at(k, "error", k "=" val[k] " must be one of: " list); delete val[k] }
  else val[k] = v
}
function number(k, lo, hi) {
  if (!(k in val)) return
  if (val[k] !~ /^[0-9]+$/ || val[k] + 0 < lo || val[k] + 0 > hi) { at(k, "error", k "=" val[k] " must be a whole number from " lo " to " hi); delete val[k] }
}
function need(fg, bg, ratio, what,    r) {
  if (!(fg in val) || !(bg in val)) return
  r = contrast(val[fg], val[bg])
  if (r < ratio) at(fg, "warning", sprintf("%s #%s is %.2f:1 on %s #%s; %s needs %.1f:1", fg, val[fg], r, what, val[bg], fg == "MUTED" ? "secondary text" : "text", ratio))
}

# Checks every value, then fills the defaults (DESIGN.md, "Theme format").
function validate(    i, k, v, n, parts, bad, dark, kinds, kk) {
  for (i = 1; i <= norder; i++) {
    k = order[i]; v = val[k]
    if (k == "PALETTE") {
      n = split(v, parts, /[ \t]+/); bad = ""
      for (kk = 1; kk <= n; kk++) {
        sub(/^#/, "", parts[kk])
        if (!ishex(parts[kk])) bad = bad " " parts[kk]
      }
      if (n != 16) { at(k, "error", "PALETTE has " n " colours; it needs 16"); delete val[k] }
      else if (bad != "") { at(k, "error", "PALETTE has colours that are not six-digit hex:" bad); delete val[k] }
      else { v = ""; for (kk = 1; kk <= 16; kk++) v = v (kk > 1 ? " " : "") tolower(parts[kk]); val[k] = v }
    } else if (k ~ /^COLOR([0-9]|1[0-5])$/) {
      at(k, "warning", k " comes from PALETTE; this line is ignored"); delete val[k]
    } else if (colourkey(k)) {
      sub(/^#/, "", v)
      if (!ishex(v)) { at(k, "error", k "=" val[k] " is not a six-digit hex colour"); delete val[k] }
      else val[k] = tolower(v)
    } else if (k == "FORMAT") {
      if (v !~ /^[0-9]+$/ || v + 0 < 1) { at(k, "error", "FORMAT=" v " must be a format number (" format ")"); delete val[k] }
      else if (v + 0 > format) { at(k, "error", "FORMAT=" v " is newer than this version reads (" format "); update the package"); delete val[k] }
    } else if (k == "ACCENT") {
      if (v !~ /^(-1|[0-6]|multicolor)$/) { at(k, "error", "ACCENT=" v " must be -1 to 6 or multicolor"); delete val[k] }
    } else if (k == "LABEL") {
      if (v == "") { at(k, "error", "LABEL is empty"); delete val[k] }
    } else if (k == "FAMILY" || k == "NVIM") {
      if (v !~ /^[a-z0-9][a-z0-9_-]*$/) { at(k, "error", k "=" v " must be a lower-case name"); delete val[k] }
    } else if (k == "BACKGROUND") {
      if (v == "" || v ~ /\// || substr(v, 1, 1) == ".") { at(k, "error", "BACKGROUND=" v " must be a file name in backgrounds/"); delete val[k] }
    } else if (k == "FONT_UI" || k == "FONT_MONO") {
      if (v == "") { at(k, "error", k " is empty"); delete val[k] }
    } else if (k == "MODE") choice(k, "dark light")
    else if (k == "ICON_STYLE") choice(k, "line solid mono")
    else if (k == "KIND_STYLE") choice(k, "tag dot solid text")
    else if (k == "UI_DENSITY") choice(k, "compact regular comfortable")
    else if (k == "UI_MOTION") choice(k, "full reduced")
    else if (k == "FONT_SIZE") number(k, 9, 24)
    else if (k == "RADIUS_WINDOW") number(k, 0, 32)
    else if (k == "RADIUS_CHIP") number(k, 0, 16)
    else if (k == "SPACING_UNIT") number(k, 2, 16)
  }

  if (!("FORMAT" in vline)) report("warning", file, 0, "FORMAT is missing; read as format " format)
  if (!("LABEL" in vline)) report("error", file, 0, "LABEL is missing")
  if (!("MODE" in vline)) report("error", file, 0, "MODE is missing")
  if (!("TERM_BG" in vline)) report("error", file, 0, "TERM_BG is missing")
  if (!("TERM_FG" in vline)) report("error", file, 0, "TERM_FG is missing")
  if (!("PALETTE" in vline)) report("error", file, 0, "PALETTE is missing")

  if ("PALETTE" in val) {
    n = split(val["PALETTE"], parts, " ")
    for (i = 1; i <= n; i++) { val["COLOR" (i - 1)] = parts[i]; order[++norder] = "COLOR" (i - 1) }
  }
  dark = ("MODE" in val) ? val["MODE"] == "dark" : (("TERM_BG" in val) && lum(val["TERM_BG"]) < 0.4)
  setdefault("FORMAT", format)
  setdefault("ACCENT_HEX", ("HIGHLIGHT" in val) ? val["HIGHLIGHT"] : (("COLOR4" in val) ? val["COLOR4"] : ""))
  setdefault("HIGHLIGHT", ("ACCENT_HEX" in val) ? val["ACCENT_HEX"] : "")
  setdefault("TERM_CURSOR", ("ACCENT_HEX" in val) ? val["ACCENT_HEX"] : "")
  if ("TERM_BG" in val) {
    if ("ACCENT_HEX" in val) setdefault("TERM_SELECTION", mix(val["TERM_BG"], val["ACCENT_HEX"], 0.25))
    if ("TERM_FG" in val) {
      setdefault("MUTED", mix(val["TERM_FG"], val["TERM_BG"], 0.45))
      setdefault("BG_LIGHTER", mix(val["TERM_BG"], val["TERM_FG"], 0.04))
      setdefault("BG_DARKER", dark ? mix(val["TERM_BG"], "000000", 0.3) : mix(val["TERM_BG"], val["TERM_FG"], 0.1))
    }
  }
  split("FOLDER:ACCENT_HEX DOCUMENT:COLOR4 PDF:COLOR1 PRESENTATION:COLOR3 SPREADSHEET:COLOR2 IMAGE:COLOR5 VIDEO:COLOR13 CODE:COLOR11 ARCHIVE:COLOR9 TEXT:MUTED", kinds, " ")
  for (i = 1; i <= 10; i++) {
    split(kinds[i], parts, ":")
    if (parts[2] in val) setdefault("KIND_" parts[1], val[parts[2]])
  }
  setdefault("ACCENT", "-1")
  setdefault("BACKGROUND", dark ? "graphite.jpg" : "daylight.jpg")
  setdefault("NVIM", "vscode")
  setdefault("ICON_STYLE", "line")
  setdefault("KIND_STYLE", "tag")
  setdefault("FONT_UI", "SF Pro"); setdefault("FONT_MONO", "SF Mono"); setdefault("FONT_SIZE", "13")
  setdefault("RADIUS_WINDOW", "10"); setdefault("RADIUS_CHIP", "5"); setdefault("SPACING_UNIT", "4")
  setdefault("UI_MOTION", "full")

  sidebar = ("SIDEBAR" in val) ? "SIDEBAR" : "BG_LIGHTER"
  need("TERM_FG", "TERM_BG", 4.5, "TERM_BG")
  need("TERM_FG", sidebar, 4.5, sidebar)
  need("MUTED", "TERM_BG", 3, "TERM_BG")
  need("MUTED", sidebar, 3, sidebar)
}

function flush(to,    i) { for (i = 1; i <= nmsg; i++) print msgs[i] > to }

# The value for a placeholder, or the sentinel when it is not known.
function lookup(token, afterhash,    dot, base, form, h) {
  dot = index(token, ".")
  if (dot) { base = substr(token, 1, dot - 1); form = substr(token, dot + 1) } else { base = token; form = "" }
  if (!(base in val)) return UNKNOWN
  if (!colourkey(base) || !ishex(val[base])) return form == "" ? val[base] : UNKNOWN
  h = val[base]
  if (form == "") return afterhash ? h : "#" h
  if (form == "hex") return h
  if (form == "rgb") return hexval(substr(h, 1, 2)) "," hexval(substr(h, 3, 2)) "," hexval(substr(h, 5, 2))
  if (form == "dec") return sprintf("%.3f %.3f %.3f", chan(h, 0), chan(h, 1), chan(h, 2))
  return UNKNOWN
}
function render(line,    out, open, stop, token, pre, rep) {
  out = ""
  while ((open = index(line, "{{")) > 0) {
    stop = index(substr(line, open + 2), "}}")
    if (stop == 0) break
    token = trim(substr(line, open + 2, stop - 1))
    pre = substr(line, 1, open - 1)
    rep = lookup(token, (out pre) ~ /#$/)
    if (rep == UNKNOWN) out = out substr(line, 1, open + stop + 2)
    else out = out pre rep
    line = substr(line, open + stop + 3)
  }
  return out line
}

BEGIN {
  UNKNOWN = "\001"
  resolve()
  validate()
  failed = errors > 0 || (strict && warnings > 0)
  if (mode == "check") { flush("/dev/stdout"); exit failed }
  flush("/dev/stderr")
  if (failed) exit 1
  if (mode == "resolve") {
    for (i = 1; i <= norder; i++) {
      k = order[i]
      if (!(k in val) || k ~ /^COLOR([0-9]|1[0-5])$/ || (k in printed)) continue
      printed[k] = 1
      v = val[k]
      if (v ~ /[ \t#"]/ || v == "") v = "\"" v "\""
      print k "=" v
    }
    exit 0
  }
  # render: ARGV holds template and output pairs.
  val["NAME"] = name
  for (i = 1; i < ARGC; i += 2) {
    template = ARGV[i]; output = ARGV[i + 1]
    printf "" > output
    while ((getline line < template) > 0) print render(line) > output
    close(template); close(output)
  }
  exit 0
}'

# theme_resolve FILE [ROOT]: the theme with its parents and defaults, one
# KEY=value line per key (quoted when the value has a space). Problems go to
# stderr as FILE:LINE messages, shown relative to ROOT; fails on an error.
theme_resolve() {
  awk -v mode=resolve -v file="$1" -v root="${2:-}" -v strict=0 -v format="$THEME_FORMAT" "$_THEME_AWK"
}

# theme_check FILE [ROOT] [STRICT]: prints every problem as FILE:LINE:
# error|warning: message. Fails on an error, or on a warning when STRICT is 1.
theme_check() {
  awk -v mode=check -v file="$1" -v root="${2:-}" -v strict="${3:-0}" -v format="$THEME_FORMAT" "$_THEME_AWK"
}

# theme_get FILE KEY: one resolved value, quotes removed ("" when unset or the
# theme has errors).
theme_get() {
  local line
  line="$(theme_resolve "$1" 2>/dev/null | grep -m1 "^$2=")" || return 0
  line="${line#*=}"; line="${line#\"}"; line="${line%\"}"
  printf '%s\n' "$line"
}

# render_templates THEME_FILE NAME OUT_DIR TEMPLATE_DIR...
# A template in an earlier folder wins over one of the same name in a later
# folder, so pass the user's folder first. One awk process checks the theme
# and renders every template; a theme with errors renders nothing.
render_templates() {
  local theme="$1" name="$2" out="$3" dir tpl base seen=" "
  local pairs=()
  shift 3
  for dir in "$@"; do
    for tpl in "$dir"/*.tpl; do
      [[ -f "$tpl" ]] || continue
      base="${tpl##*/}"; base="${base%.tpl}"
      [[ "$seen" == *" $base "* ]] && continue
      seen="$seen$base "
      pairs+=("$tpl" "$out/$base")
    done
  done
  mkdir -p "$out" || return 1
  awk -v mode=render -v file="$theme" -v name="$name" -v strict=0 -v format="$THEME_FORMAT" \
    "$_THEME_AWK" ${pairs[@]+"${pairs[@]}"}
}
