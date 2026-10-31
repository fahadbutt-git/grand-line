# shellcheck shell=bash
# Installs everything in the Brewfile. Apps already in /Applications that
# Homebrew did not install are left alone instead of failing.

# Some installers switch off macOS's first-open check for their own app. Any
# app in /Applications that Apple has not approved (notarized) and that is no
# longer flagged gets the flag back, so macOS asks before it first opens.
restore_gatekeeper() {
  local app stamp
  stamp="0081;$(printf %x "$(date +%s)");mac-setup;"
  for app in /Applications/*.app; do
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
  local status=0
  if ! run brew bundle --file="$effective" --no-upgrade; then
    status=1
    warn "Some apps did not install:"
    brew bundle check --file="$effective" --no-upgrade --verbose 2>&1 | sed 's/^/    /'
  else
    ok "Every app in the Brewfile is installed"
  fi
  [[ "$DRY_RUN" == 0 ]] && restore_gatekeeper
  [[ "$DRY_RUN" == 0 ]] && brew cleanup --prune=all -q >/dev/null 2>&1
  rm -rf "$work"
  return "$status"
}
