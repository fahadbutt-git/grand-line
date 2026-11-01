# shellcheck shell=bash
# Installs everything in the Brewfile. Apps already in /Applications that
# Homebrew did not install are left alone instead of failing.

# shellcheck source=lib/file-age.sh
source "$REPO_DIR/lib/file-age.sh"

GATEKEEPER_APPS="${GRAND_LINE_APPS_DEST:-/Applications}"

# apps_now: the apps in /Applications, one path per line.
apps_now() {
  local app
  for app in "$GATEKEEPER_APPS"/*.app; do [[ -e "$app" ]] && printf '%s\n' "$app"; done
  return 0
}

# Some installers switch off macOS's first-open check for their own app. Any
# app this run installed that Apple has not approved (notarized) and that is
# no longer flagged gets the flag back, so macOS asks before it first opens.
# restore_gatekeeper BEFORE START: BEFORE lists the apps there before the run
# (apps_now), START is when it began (seconds since 1970).
restore_gatekeeper() {
  local app stamp before="${1:-}" start="${2:-0}" added
  stamp="0081;$(printf %x "$(date +%s)");grand-line;"
  for app in "$GATEKEEPER_APPS"/*.app; do
    [[ -e "$app" ]] || continue
    # Only apps this run installed or replaced: checking every app (Xcode
    # takes minutes) on every run is what made repeat runs crawl. An app is
    # new when it was not there before, or when macOS records it as added to
    # the folder since the run began. Its modification time says nothing:
    # installers and Homebrew keep the time the app was built.
    if [[ -f "$before" ]] && grep -qxF -- "$app" "$before"; then
      added="$(date_added "$app")" || continue
      [[ "$added" -ge "$start" ]] || continue
    fi
    # The package's own apps are built on this Mac, never downloaded: flagging
    # them would make macOS stop every launch (and setup itself) to ask.
    case "$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)" in com.grandline.*) continue ;; esac
    xattr -p com.apple.quarantine "$app" >/dev/null 2>&1 && continue
    spctl -a -t exec "$app" >/dev/null 2>&1 && continue
    xattr -w com.apple.quarantine "$stamp" "$app" 2>/dev/null \
      && info "$(basename "$app" .app) is not approved by Apple, so macOS will ask before it first opens"
  done
}

step_apps() {
  local work effective
  work="$(mktemp -d)"
  effective="$work/Brewfile"
  cp "$REPO_DIR/Brewfile" "$effective"

  if [[ "$DRY_RUN" == 0 ]]; then
    # One call for what Homebrew already manages, one for the rest.
    local installed missing=()
    installed=" $(brew list --cask -1 2>/dev/null | tr '\n' ' ') "
    local cask
    while IFS= read -r cask; do
      [[ "$installed" == *" ${cask##*/} "* ]] || missing+=("$cask")
    done < <(sed -nE 's/^cask "([^"]+)".*/\1/p' "$REPO_DIR/Brewfile")

    if [[ ${#missing[@]} -gt 0 ]]; then
      # Add the Brewfile's taps first so every cask name is known below.
      local tap
      while IFS= read -r tap; do brew tap "$tap" >/dev/null 2>&1; done \
        < <(sed -nE 's/^tap "([^"]+)".*/\1/p' "$REPO_DIR/Brewfile")
      local token app
      while IFS=$'\t' read -r token app; do
        if [[ -d "/Applications/$(basename "$app")" ]]; then
          info "$(basename "$app" .app) is already installed, leaving it as is"
          printf 'cask "%s"\n' "$token" >> "$work/skip"
        fi
      done < <(brew info --cask --json=v2 "${missing[@]}" 2>/dev/null | jq -r '
        .casks[] | .full_token as $t
        | (.artifacts[]? | select(type == "object" and has("app")) | .app[] | select(type == "string"))
        | "\($t)\t\(.)"')
      if [[ -f "$work/skip" ]]; then
        grep -vF -f "$work/skip" "$REPO_DIR/Brewfile" > "$effective"
      fi

      # Download every missing app at once; installing then runs from the cache.
      info "Downloading ${#missing[@]} apps"
      brew fetch --cask "${missing[@]}" >/dev/null 2>&1 || true
    fi
  fi

  info "Installing apps and tools. The first run takes 20 to 40 minutes."
  local status=0 before="$work/apps-before" start
  apps_now > "$before"; start="$(date +%s)"
  if ! run brew bundle --file="$effective" --no-upgrade; then
    status=1
    warn "Some apps did not install:"
    brew bundle check --file="$effective" --no-upgrade --verbose 2>&1 | sed 's/^/    /'
  else
    ok "Every app in the Brewfile is installed"
  fi
  [[ "$DRY_RUN" == 0 ]] && restore_gatekeeper "$before" "$start"
  [[ "$DRY_RUN" == 0 ]] && brew cleanup --prune=all -q >/dev/null 2>&1
  rm -rf "$work"
  return "$status"
}
