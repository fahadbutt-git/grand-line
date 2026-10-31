#!/usr/bin/env bash
# Security checks, run by tests/run-all.sh, GitHub's tests and grandline
# publish. Each mode prints what it found and fails when it found anything.
#   security-checks.sh --secrets        keys and tokens in the package's files
#   security-checks.sh --diff RANGE     keys and tokens in lines a git range adds
#   security-checks.sh --actions        every GitHub action pinned to a commit,
#                                       read-only token by default
#   security-checks.sh --remote-code    nothing downloaded is piped into a shell
#                                       or eval'd
#   security-checks.sh --entitlements   the apps ask for no more than the allowed
#                                       exceptions to hardened runtime
#   security-checks.sh --bundles DIR    every app in DIR is signed with hardened
#                                       runtime (macOS, after the apps are built)
#   security-checks.sh                  all but --diff and --bundles

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# Key and token shapes, as gitleaks finds them. Placeholders such as
# AKIAXXXXXXXXXXXXXXXX do not match (they are not the right alphabet).
SECRET_RE='AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}'
SECRET_RE+='|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}'
SECRET_RE+='|glpat-[A-Za-z0-9_-]{20,}'
SECRET_RE+='|xox[abposr]-[A-Za-z0-9-]{10,}|hooks\.slack\.com/services/T[A-Za-z0-9_/]+'
SECRET_RE+='|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|-----BEGIN OPENSSH PRIVATE KEY-----'
SECRET_RE+='|AIza[0-9A-Za-z_-]{35}'
SECRET_RE+='|sk-ant-[A-Za-z0-9_-]{20,}|sk-(proj-)?[A-Za-z0-9]{32,}'
SECRET_RE+='|(sk|rk)_live_[0-9A-Za-z]{20,}'
SECRET_RE+='|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
SECRET_RE+="|(api[_-]?key|secret|token|passw(or)?d)[\"']?[[:space:]]*[:=][[:space:]]*[\"'][A-Za-z0-9/+_=.-]{20,}[\"']"
# This file names the shapes, so it is the one file not scanned.
SELF="tests/security-checks.sh"

FAIL=0
bad() { printf '%s\n' "$1"; FAIL=1; }

tracked_files() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git ls-files -z
  else
    find . -type f -not -path './.git/*' -not -path '*/.build/*' -print0
  fi
}

check_secrets() {
  local found
  found="$(tracked_files | grep -zv -e "^$SELF\$" -e "^\./$SELF\$" \
    | xargs -0 grep -nIoE -- "$SECRET_RE" 2>/dev/null)"
  [[ -z "$found" ]] || bad "Possible keys or tokens (move them to ~/.config/grand-line, outside the package):
$found"
}

check_diff() {
  local found
  found="$(git diff --unified=0 --no-color "$1" -- . ":(exclude)$SELF" 2>/dev/null \
    | grep -E '^\+[^+]' | grep -nE -- "$SECRET_RE")"
  [[ -z "$found" ]] || bad "Lines being sent look like keys or tokens:
$found"
}

check_actions() {
  local f found
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [[ -f "$f" ]] || continue
    # uses: owner/repo@<40 hex> # vX.Y.Z  (local ./ actions and docker:// are fine)
    found="$(grep -nE '^[[:space:]-]*uses:' "$f" \
      | grep -vE 'uses:[[:space:]]*(\./|docker://)' \
      | grep -vE 'uses:[[:space:]]*[^@[:space:]]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]')"
    [[ -z "$found" ]] || bad "$f: actions not pinned to a full commit SHA with its version in a comment:
$found"
    grep -qE '^permissions:' "$f" || bad "$f: no workflow-level permissions (set permissions: contents: read)"
    grep -nE '^[[:space:]]*(pull_request_target|workflow_run):' "$f" | grep -q . \
      && bad "$f: pull_request_target or workflow_run runs untrusted code with a privileged token"
    found="$(grep -nE '^[[:space:]]*run:.*\$\{\{[[:space:]]*(github\.event\.|inputs\.)' "$f")"
    [[ -z "$found" ]] || bad "$f: event or input text inside run: (pass it through env: instead):
$found"
    found="$(grep -nE 'actions/checkout@' "$f" | wc -l | tr -d ' ')"
    [[ "$found" == "$(grep -cE 'persist-credentials:[[:space:]]*false' "$f")" ]] \
      || bad "$f: every checkout needs persist-credentials: false (the token stays out of .git/config)"
  done
}

check_remote_code() {
  local files=() f found
  while IFS= read -r f; do files+=("$f"); done < <(
    { ls setup.sh publish.sh lib/*.sh steps/*.sh bin/* migrations/*.sh config/zsh/*.zsh \
         apps/*/build.sh .github/workflows/*.yml 2>/dev/null; } | sort -u)
  # curl or wget piped into a shell; a shell running what curl printed;
  # eval or source of anything downloaded.
  found="$(grep -HnE '(curl|wget)[^|#]*\|[[:space:]]*(sudo[[:space:]]+)?(/bin/|/usr/bin/(env[[:space:]]+)?)?(ba|z|da|k)?sh\b|(ba|z)?sh[[:space:]]+(-c[[:space:]]+)?["'"'"']?\$\((curl|wget)|(ba|z)?sh[[:space:]]+<\((curl|wget)|(eval|source|\.)[[:space:]]+["'"'"']?[<$]\((curl|wget)' \
    "${files[@]}" 2>/dev/null)"
  [[ -z "$found" ]] || bad "Downloaded code run without being checked first:
$found"
  # eval only on the output of tools already installed here.
  found="$(grep -HnE '(^|[^_[:alnum:]])eval[[:space:]]' "${files[@]}" 2>/dev/null \
    | grep -vE 'eval[[:space:]]+"\$\((starship|zoxide|mise|"?\$\{?BREW_BIN\}?"?|\$\{BREW_BIN\})[[:space:]]' \
    | grep -vE 'eval \\"\\\$\(\$\{BREW_BIN\} shellenv\)\\"' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')"
  [[ -z "$found" ]] || bad "eval outside the allowed tool set-up lines:
$found"
}

ALLOWED_ENTITLEMENTS="com.apple.security.automation.apple-events com.apple.security.personal-information.calendars"
check_entitlements() {
  local f key
  for f in apps/*/Entitlements/*.entitlements; do
    [[ -f "$f" ]] || continue
    while IFS= read -r key; do
      [[ " $ALLOWED_ENTITLEMENTS " == *" $key "* ]] || bad "$f asks for $key, which is not on the allowed list in $SELF"
    done < <(sed -n 's#.*<key>\([^<]*\)</key>.*#\1#p' "$f")
  done
}

check_bundles() {
  local dir="$1" app detail n=0
  for app in "$dir"/*.app; do
    [[ -d "$app" ]] || continue
    n=$((n + 1))
    detail="$(codesign -d --verbose "$app" 2>&1)"
    if ! printf '%s\n' "$detail" | grep -qE 'flags=0x[0-9a-f]+\([^)]*runtime'; then
      bad "$(basename "$app") is not signed with hardened runtime: $(printf '%s\n' "$detail" | grep -E 'flags=' | head -1)"
    fi
    codesign --verify --deep --strict "$app" 2>/dev/null || bad "$(basename "$app") does not verify (codesign --verify --deep --strict)"
    if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -qE 'disable-library-validation|allow-dyld-environment-variables|allow-unsigned-executable-memory|get-task-allow'; then
      bad "$(basename "$app") weakens hardened runtime in its entitlements"
    fi
  done
  [[ "$n" -gt 0 ]] || bad "No apps in $dir"
}

case "${1:-all}" in
  --secrets) check_secrets ;;
  --diff) [[ -n "${2:-}" ]] || { echo "usage: security-checks.sh --diff RANGE" >&2; exit 2; }; check_diff "$2" ;;
  --actions) check_actions ;;
  --remote-code) check_remote_code ;;
  --entitlements) check_entitlements ;;
  --bundles) [[ -d "${2:-}" ]] || { echo "usage: security-checks.sh --bundles DIR" >&2; exit 2; }; check_bundles "$2" ;;
  all) check_secrets; check_actions; check_remote_code; check_entitlements ;;
  *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
exit "$FAIL"
