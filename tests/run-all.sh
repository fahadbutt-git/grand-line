#!/usr/bin/env bash
# Checks that run anywhere (Linux, a Mac, or GitHub's test machines) without
# installing anything. Run: bash tests/run-all.sh   (add --offline to skip
# the Homebrew catalogue check)

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

OFFLINE=0
[[ "${1:-}" == "--offline" ]] && OFFLINE=1

PASS=0; FAIL=0
pass() { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
fail() {
  printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/        /'; FAIL=$((FAIL + 1))
  # On CI, the failing lines (or the first lines when none say FAIL) as an annotation.
  local why; why="$(printf '%s\n' "${2:-}" | grep -A2 'FAIL' | head -12)"
  [[ -n "$why" ]] || why="$(printf '%s\n' "${2:-}" | head -3)"
  [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::error title=check::$1: $(printf '%s' "$why" | tr '\n' ' ')"
}
check() { local name="$1"; shift; local out; if out="$("$@" 2>&1)"; then pass "$name"; else fail "$name" "$out"; fi; }

SHELL_FILES=()
while IFS= read -r f; do SHELL_FILES+=("$f"); done < <(
  { ls setup.sh publish.sh lib/*.sh steps/*.sh bin/* tests/*.sh tests/stubs/* \
       migrations/*.sh config/grand-line/hooks/*.sample 2>/dev/null; } | sort -u)

echo "Shell scripts"
for f in "${SHELL_FILES[@]}"; do
  check "syntax: $f" bash -n "$f"
done

if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck (all scripts)" shellcheck -x -S warning -e SC1091 "${SHELL_FILES[@]}"
else
  fail "shellcheck is not installed (pip install shellcheck-py)"
fi

# macOS runs these scripts with bash 3.2, so newer bash features must not appear.
bash4="$(grep -nE 'mapfile |readarray |declare -A|local -A|\$\{[a-zA-Z_]+(,,|\^\^)\}|\|&|&>>|coproc |local -n |globstar' \
          "${SHELL_FILES[@]}" | grep -v '^tests/run-all.sh' || true)"
if [[ -z "$bash4" ]]; then pass "no bash 4+ features (macOS ships bash 3.2)"; else fail "bash 4+ features found" "$bash4"; fi

# bash 3.2 also misreads an apostrophe inside a here-document within $( ),
# which only shows on a Mac. Catch the pattern everywhere instead.
heredoc="$(grep -nE '^[^#]*\$\(cat <<' "${SHELL_FILES[@]}" || true)"
if [[ -z "$heredoc" ]]; then pass "no here-documents inside \$( ) (bash 3.2 quoting bug)"; else fail "here-document inside \$( ) breaks on macOS bash 3.2" "$heredoc"; fi

check "executable bits set" bash -c '
  bad=0
  for f in bin/* setup.sh publish.sh tests/*.sh tests/stubs/*; do [[ -x "$f" ]] || { echo "$f"; bad=1; }; done
  exit $bad' 

# On a laptop a missing tool only skips its check. In CI it fails, so a check
# can never pass by quietly not running.
have_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  if [[ -n "${CI:-}" ]]; then fail "$1 is not installed, so its check could not run"
  else echo "  skip  $1 is not installed"; fi
  return 1
}
if have_tool zsh; then
  check "syntax: config/zsh/grand-line.zsh" zsh -n config/zsh/grand-line.zsh
fi
if have_tool tmux; then
  check "tmux.conf loads" tmux -f config/tmux/tmux.conf -L grand-line-test start-server \; kill-server
fi

echo "Config files"
check "aerospace.toml parses" python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    print('tomllib needs Python 3.11; skipped'); raise SystemExit(0)
tomllib.load(open('config/aerospace/aerospace.toml', 'rb'))"
check "karabiner.json parses" python3 -m json.tool config/karabiner/karabiner.json
check "generated files are current with tools/bindings.py" python3 tools/bindings.py --check

check "menu.tsv: path and command, then optional ?guard and ✓check columns" bash -c \
  "grep -v -e '^#' -e '^\$' config/grand-line/menu.tsv | awk -F'\t' '
     NF < 2 || NF > 4 || \$2 == \"\" { print NR\": \"\$0; bad=1; next }
     NF >= 3 && \$3 != \"\" && substr(\$3, 1, 1) != \"?\" { print \"column 3 must start with ?: \"\$0; bad=1 }
     NF == 4 && index(\$4, \"✓\") != 1 { print \"column 4 must start with ✓: \"\$0; bad=1 }
     END { exit bad }'"

check "every package command used by menus and shortcuts exists in bin/" bash -c '
  bad=0
  names=$( { grep -ohE "\\\$HOME/\.grand-line/bin/[a-z-]+" config/grand-line/keybindings.tsv | sed "s#.*/##";
             grep -v "^#" config/grand-line/menu.tsv | cut -f2 | cut -d" " -f1; } | sort -u)
  for name in $names; do
    [[ -f "bin/$name" ]] && continue
    command -v "$name" >/dev/null 2>&1 && continue
    case "$name" in open|pmset|osascript|aerospace|defaults) continue ;; esac
    echo "unknown command: $name"; bad=1
  done; exit $bad'

check "default-apps.tsv: three tab-separated fields per entry" bash -c \
  "grep -v '^#' config/grand-line/default-apps.tsv | awk -F'\t' 'NF != 3 { print NR\": \"\$0; bad=1 } END { exit bad }'"

check "every native helper has a matching source file" bash -c '
  bad=0
  for name in $(grep -ohE "GRAND_LINE_BUILD/[a-z]+|pdfshrink|\bocr\b" bin/* lib/*.sh | sed "s#.*/##" | sort -u); do
    [[ -f "tools/$name.swift" ]] || { echo "tools/$name.swift missing"; bad=1; }
  done
  exit $bad'

check "every theme has its background and all fields" bash -c '
  bad=0
  for t in config/themes/*.theme; do
    for k in LABEL MODE ACCENT ACCENT_HEX BACKGROUND TERM_BG TERM_FG TERM_CURSOR TERM_SELECTION MUTED BG_LIGHTER BG_DARKER PALETTE HIGHLIGHT NVIM; do
      grep -q "^$k=" "$t" || { echo "$t: no $k"; bad=1; }
    done
    [[ "$(sed -n "s/^PALETTE=//p" "$t" | tr -d \" | wc -w | tr -d " ")" == 16 ]] || { echo "$t: PALETTE needs 16 colours"; bad=1; }
    nv=$(sed -n "s/^NVIM=//p" "$t")
    grep -q "\"$nv\"" config/nvim/lua/plugins/theme.lua || { echo "$t: Neovim scheme $nv missing from config/nvim/lua/plugins/theme.lua"; bad=1; }
    bg=$(sed -n "s/^BACKGROUND=//p" "$t")
    [[ -f "backgrounds/$bg" ]] || { echo "$t: backgrounds/$bg missing"; bad=1; }
  done; exit $bad'

check "light themes: every terminal colour reads at 4.5:1 on the background" python3 -c '
import glob, re, sys
def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
def ratio(a, b):
    hi, lo = sorted((lum(a), lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)
bad = 0
for path in sorted(glob.glob("config/themes/*.theme")):
    t = dict(re.findall(r"^([A-Z_0-9]+)=\"?([^\"\n]*)\"?", open(path).read(), re.M))
    bg = t["TERM_BG"]
    colours = [("TERM_FG", t["TERM_FG"])]
    if t["MODE"] == "light":
        colours += [("MUTED", t["MUTED"]), ("HIGHLIGHT", t["HIGHLIGHT"])]
        colours += [("PALETTE %d" % i, c) for i, c in enumerate(t["PALETTE"].split())]
    for name, c in colours:
        if ratio(c, bg) < 4.5:
            print("%s: %s #%s is %.2f:1 on #%s" % (path, name, c, ratio(c, bg), bg)); bad = 1
sys.exit(bad)'

check "every bin/ command has a \"# grandline:summary=\" line (grandline commands lists them)" bash -c '
  bad=0
  for f in bin/*; do grep -q "^# grandline:summary=." "$f" || { echo "$f has no summary"; bad=1; }; done
  exit $bad'

check "migrations are named <unix time>-<slug>.sh" bash -c '
  bad=0
  for f in migrations/*; do [[ "${f##*/}" =~ ^[0-9]{10}-[a-z0-9-]+\.sh$ ]] || { echo "$f"; bad=1; }; done
  exit $bad'

# /Users/me/ is the placeholder home that examples and tests use.
check "every # grandline:arg line is valid JSON (Byakugan reads them)" python3 -c '
import glob, json, re, sys
def ok(line):
    m = re.match(r"# grandline:arg[1-3]=(\{.*\})\s*$", line)
    try: return bool(m) and "type" in json.loads(m.group(1))
    except ValueError: return False
bad = [f"{f}: {l.strip()}" for f in sorted(glob.glob("bin/*")) for l in open(f, errors="ignore")
       if l.startswith("# grandline:arg") and not ok(l)]
print("\n".join(bad)); sys.exit(1 if bad else 0)'

check "no personal paths or secrets committed" bash -c '
  found="$(grep -rnoE "/Users/[a-z]+/|ghp_[A-Za-z0-9]{20}|github_pat_" --exclude-dir=.git --exclude-dir=.build . \
    | grep -v -e "^./tests/run-all.sh:" -e ":/Users/me/\$")"
  [[ -z "$found" ]] || { printf "%s\n" "$found"; exit 1; }'

# Names, emails and places belong in ~/.config/grand-line/personal.env.
check "no email addresses or home coordinates committed" bash -c '
  found="$(git ls-files -z | xargs -0 grep -nIoE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|org|net|ca|edu)|^-?[0-9]{1,2}\.[0-9]+ -?[0-9]{1,3}\.[0-9]+ [A-Z]" 2>/dev/null \
    | grep -vE "noreply|example\.(com|org)|@users\.noreply|apps/.*/Tests/")"
  [[ -z "$found" ]] || { printf "%s\n" "$found"; exit 1; }'

echo "Behaviour"
check "unit tests (menus, shortcuts, overlays, themes, migrations, hooks, ArtCraft)" bash tests/unit.sh
check "dry run of the whole setup changes nothing" bash tests/dryrun.sh

if [[ "$OFFLINE" == 0 ]]; then
  echo "Homebrew catalogue"
  check "every Brewfile entry exists in Homebrew" python3 tests/check_brewfile.py
fi

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" == 0 ]]
