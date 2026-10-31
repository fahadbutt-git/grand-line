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
  [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::error title=check::$1: $(printf '%s' "${2:-}" | head -3 | tr '\n' ' ')"
}
check() { local name="$1"; shift; local out; if out="$("$@" 2>&1)"; then pass "$name"; else fail "$name" "$out"; fi; }

SHELL_FILES=()
while IFS= read -r f; do SHELL_FILES+=("$f"); done < <(
  { ls setup.sh publish.sh lib/*.sh steps/*.sh bin/* tests/*.sh tests/stubs/* 2>/dev/null; } | sort -u)

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
  check "syntax: config/zsh/mac-setup.zsh" zsh -n config/zsh/mac-setup.zsh
fi
if have_tool tmux; then
  check "tmux.conf loads" tmux -f config/tmux/tmux.conf -L mac-setup-test start-server \; kill-server
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

check "menu.tsv: two tab-separated fields per entry" bash -c \
  "grep -v -e '^#' -e '^\$' config/mac-setup/menu.tsv | awk -F'\t' 'NF != 2 { print NR\": \"\$0; bad=1 } END { exit bad }'"

check "every package command used by menus and shortcuts exists in bin/" bash -c '
  bad=0
  names=$( { grep -ohE "\\\$HOME/\.mac-setup/bin/[a-z-]+" config/mac-setup/keybindings.tsv | sed "s#.*/##";
             grep -v "^#" config/mac-setup/menu.tsv | cut -f2 | cut -d" " -f1; } | sort -u)
  for name in $names; do
    [[ -f "bin/$name" ]] && continue
    command -v "$name" >/dev/null 2>&1 && continue
    case "$name" in open|pmset|osascript|aerospace|defaults) continue ;; esac
    echo "unknown command: $name"; bad=1
  done; exit $bad'

check "default-apps.tsv: three tab-separated fields per entry" bash -c \
  "grep -v '^#' config/mac-setup/default-apps.tsv | awk -F'\t' 'NF != 3 { print NR\": \"\$0; bad=1 } END { exit bad }'"

check "every native helper has a matching source file" bash -c '
  bad=0
  for name in $(grep -ohE "MAC_SETUP_BUILD/[a-z]+|pdfshrink|\bocr\b" bin/* lib/*.sh | sed "s#.*/##" | sort -u); do
    [[ -f "tools/$name.swift" ]] || { echo "tools/$name.swift missing"; bad=1; }
  done
  exit $bad'

check "every theme has its background and all fields" bash -c '
  bad=0
  for t in config/themes/*.theme; do
    for k in LABEL MODE ACCENT BACKGROUND TERM_BG TERM_FG TERM_CURSOR TERM_SELECTION; do
      grep -q "^$k=" "$t" || { echo "$t: no $k"; bad=1; }
    done
    bg=$(sed -n "s/^BACKGROUND=//p" "$t")
    [[ -f "backgrounds/$bg" ]] || { echo "$t: backgrounds/$bg missing"; bad=1; }
  done; exit $bad'

check "no personal paths or secrets committed" bash -c '
  ! grep -rnE "/Users/[a-z]+/|ghp_[A-Za-z0-9]{20}|github_pat_" --exclude-dir=.git . | grep -v "^./tests/run-all.sh"'

echo "Behaviour"
check "unit tests (menus, shortcuts, ArtCraft asset choice, themes)" bash tests/unit.sh
check "dry run of the whole setup changes nothing" bash tests/dryrun.sh

if [[ "$OFFLINE" == 0 ]]; then
  echo "Homebrew catalogue"
  check "every Brewfile entry exists in Homebrew" python3 tests/check_brewfile.py
fi

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" == 0 ]]
