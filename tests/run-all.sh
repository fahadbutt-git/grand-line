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
  { ls setup.sh publish.sh lib/*.sh steps/*.sh bin/* tests/*.sh tests/perf/*.sh tests/stubs/* \
       migrations/*.sh config/grand-line/hooks/*.sample 2>/dev/null; } | sort -u)

echo "Shell scripts"
for f in "${SHELL_FILES[@]}"; do
  check "syntax: $f" bash -n "$f"
done

if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck (all scripts)" shellcheck -x -S warning -e SC1091 "${SHELL_FILES[@]}"
  # Notes that matter for security fail too: unquoted expansions (word
  # splitting and globbing of paths), \$(...) run as a command, eval of an
  # array, find -exec sh -c with {}, rm -rf "\$var/" with an empty var, ssh
  # and here-documents expanding on the wrong side.
  check "shellcheck security notes (SC2086 SC2046 SC2091 SC2294 SC2156 SC2115 SC2216 SC2029 SC2087)" \
    shellcheck -x -S info -i SC2086,SC2046,SC2091,SC2294,SC2156,SC2115,SC2216,SC2029,SC2087 -e SC1091 "${SHELL_FILES[@]}"
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
check "karabiner.json parses" python3 -m json.tool config/karabiner/karabiner.json
check "generated files are current with tools/bindings.py" python3 tools/bindings.py --check

check "menu.tsv: path and command, then optional ?guard, ✓check and !question columns" bash -c \
  "grep -v -e '^#' -e '^\$' config/grand-line/menu.tsv | awk -F'\t' '
     NF < 2 || NF > 5 || \$2 == \"\" { print NR\": \"\$0; bad=1; next }
     NF >= 3 && \$3 != \"\" && substr(\$3, 1, 1) != \"?\" { print \"column 3 must start with ?: \"\$0; bad=1 }
     NF >= 4 && \$4 != \"\" && index(\$4, \"✓\") != 1 { print \"column 4 must start with ✓: \"\$0; bad=1 }
     NF == 4 && \$4 == \"\" { print \"column 4 is empty: \"\$0; bad=1 }
     NF == 5 && substr(\$5, 1, 1) != \"!\" { print \"column 5 must start with !: \"\$0; bad=1 }
     \$2 ~ /^power (sleep|logout|restart|shutdown)/ && (NF < 5 || length(\$5) < 2) { print \"irreversible entry needs a !question: \"\$0; bad=1 }
     END { exit bad }'"

check "every package command used by menus and shortcuts exists in bin/" bash -c '
  bad=0
  names=$( { grep -ohE "\\\$HOME/\.grand-line/bin/[a-z-]+" config/grand-line/keybindings.tsv | sed "s#.*/##";
             grep -v "^#" config/grand-line/menu.tsv | cut -f2 | cut -d" " -f1; } | sort -u)
  for name in $names; do
    [[ -f "bin/$name" ]] && continue
    command -v "$name" >/dev/null 2>&1 && continue
    case "$name" in open|pmset|osascript|defaults) continue ;; esac
    echo "unknown command: $name"; bad=1
  done; exit $bad'

check "default-apps.tsv: three tab-separated fields per entry" bash -c \
  "grep -v '^#' config/grand-line/default-apps.tsv | awk -F'\t' 'NF != 3 { print NR\": \"\$0; bad=1 } END { exit bad }'"

check "every app names an icon in its Info fragment, and the icon is in its Resources" bash -c '
  bad=0
  for list in apps/*/apps.tsv; do
    dir="${list%/apps.tsv}"
    while IFS=$'"'"'\t'"'"' read -r product _; do
      [[ -z "$product" || "$product" == \#* ]] && continue
      icon="$(sed -n "s#.*<key>CFBundleIconFile</key><string>\([^<]*\)</string>.*#\1#p" "$dir/Info/$product.plist" 2>/dev/null)"
      [[ -n "$icon" ]] || { echo "$dir/Info/$product.plist: no CFBundleIconFile"; bad=1; continue; }
      [[ -f "$dir/Resources/$product/$icon.icns" ]] || { echo "$dir/Resources/$product/$icon.icns missing"; bad=1; }
    done < "$list"
  done; exit $bad'
check "app icons: the glyph table parses and every AppIcon.icns is sound (tools/make-icons.py --check)" python3 tools/make-icons.py --check

check "every native helper has a matching source file" bash -c '
  bad=0
  for name in $(grep -ohE "GRAND_LINE_BUILD/[a-z]+|pdfshrink|\bocr\b" bin/* lib/*.sh | sed "s#.*/##" | sort -u); do
    [[ -f "tools/$name.swift" ]] || { echo "tools/$name.swift missing"; bad=1; }
  done
  exit $bad'

check "every bin/ command has a \"# grandline:summary=\" line (grandline commands lists them)" bash -c '
  bad=0
  for f in bin/*; do grep -q "^# grandline:summary=." "$f" || { echo "$f has no summary"; bad=1; }; done
  exit $bad'

check "migrations are named <unix time>-<slug>.sh" bash -c '
  bad=0
  for f in migrations/*; do [[ "${f##*/}" =~ ^[0-9]{10}-[a-z0-9-]+\.sh$ ]] || { echo "$f"; bad=1; }; done
  exit $bad'

# /Users/me/ is the placeholder home that examples and tests use.
check "every # grandline:arg line is valid JSON (Sight reads them)" python3 -c '
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
    | grep -v -e "^./tests/run-all.sh:" -e "^./tests/security-checks.sh:" -e ":/Users/me/\$")"
  [[ -z "$found" ]] || { printf "%s\n" "$found"; exit 1; }'

# Names, emails and places belong in ~/.config/grand-line/personal.env.
check "no email addresses or home coordinates committed" bash -c '
  found="$(git ls-files -z | xargs -0 grep -nIoE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|org|net|ca|edu)|^-?[0-9]{1,2}\.[0-9]+ -?[0-9]{1,3}\.[0-9]+ [A-Z]" 2>/dev/null \
    | grep -vE "noreply|example\.(com|org)|@users\.noreply|apps/.*/Tests/")"
  [[ -z "$found" ]] || { printf "%s\n" "$found"; exit 1; }'

echo "Resource budgets"
check "budget measurements: the parsers read macOS's tools (tests/perf/measure.py selftest)" python3 tests/perf/measure.py selftest
check "launch agents: no endless KeepAlive, watched jobs throttled, background priority (tests/perf/agents.sh)" bash tests/perf/agents.sh /dev/null
check "the budgets file has every limit the report reads" python3 -c '
import sys; sys.path.insert(0, "tests/perf"); import measure
b = measure.read_budgets("tests/perf/budgets.env")
need = ["IDLE_CPU_PER_APP", "IDLE_CPU_TOTAL", "IDLE_WAKEUPS_PER_APP", "IDLE_GPU_MS_PER_S", "RSS_MB_Sight",
        "RSS_MB_Iceberg", "RSS_MB_GrandLineIndex", "DECAY_CPU", "DECAY_SECONDS", "RSS_GROWTH_PCT", "SHELL_MEDIAN_MS"]
missing = [k for k in need if k not in b]
print(missing); sys.exit(1 if missing else 0)'

echo "Security"
check "no keys or tokens in the package's files" bash tests/security-checks.sh --secrets
check "every GitHub action pinned to a commit SHA, read-only token, no credentials left in .git" bash tests/security-checks.sh --actions
check "nothing downloaded is piped into a shell or eval'd" bash tests/security-checks.sh --remote-code
check "the apps ask for no exceptions to hardened runtime beyond the allowed list" bash tests/security-checks.sh --entitlements

echo "Behaviour"
check "unit tests (menus, shortcuts, overlays, migrations, hooks, ArtCraft)" bash tests/unit.sh
check "dry run of the whole setup changes nothing" bash tests/dryrun.sh

if [[ "$OFFLINE" == 0 ]]; then
  echo "Homebrew catalogue"
  check "every Brewfile entry exists in Homebrew" python3 tests/check_brewfile.py
fi

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" == 0 ]]
