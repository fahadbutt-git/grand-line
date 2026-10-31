# shellcheck shell=bash
# Installs the ArtCraft apps listed in config/grand-line/artcraft.tsv from their
# latest GitHub releases, all at once. Re-running only downloads newer releases.

# Pick the macOS download from a release's JSON: a .dmg before a .zip, Apple
# silicon or universal builds only, never another platform or a web build.
artcraft_pick_asset() {
  jq -r '
    [.assets[]
      | select(.name | test("\\.(dmg|zip)$"; "i"))
      | select(.name | test("mac|darwin|apple|universal|aarch64|arm64"; "i"))
      | select(.name | test("x86_64|x64|intel|amd64|windows|win64|win32|msvc|linux|android|web|wasm"; "i") | not)
    ]
    | sort_by(if (.name | test("\\.dmg$"; "i")) then 0 else 1 end)
    | .[0] // empty
    | [.name, .browser_download_url, (.digest // "")] | @tsv'
}

# Latest release tag without using the GitHub API (no rate limit): the
# /releases/latest page redirects to /releases/tag/<tag>.
artcraft_latest_tag() {
  curl -fsSI --retry 3 --connect-timeout 10 -o /dev/null -w '%{redirect_url}' \
    "https://github.com/$1/releases/latest" | sed -n 's#.*/releases/tag/##p'
}

artcraft_release_json() {
  local repo="$1"
  if have gh && gh auth status >/dev/null 2>&1; then
    gh api "repos/$repo/releases/latest"
  else
    local auth=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl -fsSL --retry 3 --connect-timeout 10 "${auth[@]+"${auth[@]}"}" \
      "https://api.github.com/repos/$repo/releases/latest"
  fi
}

# Installs one app. Prints progress. Exit code 0 on success, 2 when the
# release simply has no Mac build yet (a warning, not a failure), 1 otherwise.
artcraft_install_one() {
  local app="$1" repo="$2" state="$GRAND_LINE_STATE/artcraft"
  mkdir -p "$state"

  local tag installed_path
  tag="$(artcraft_latest_tag "$repo")"
  installed_path="$(cat "$state/$app.path" 2>/dev/null)"
  if [[ -n "$tag" && -d "$installed_path" && "$(cat "$state/$app.tag" 2>/dev/null)" == "$tag" ]]; then
    echo "  ✓ $app $tag already installed"
    return 0
  fi

  local release asset name url digest
  release="$(artcraft_release_json "$repo")" || { echo "  ! $app: could not reach GitHub releases for $repo"; return 1; }
  tag="$(jq -r '.tag_name // empty' <<<"$release")"
  asset="$(artcraft_pick_asset <<<"$release")"
  if [[ -z "$asset" ]]; then
    echo "  ! $app: release ${tag:-unknown} has no macOS download yet. Install it from the ArtCraft Launcher (https://getartcraft.com/apps)."
    return 2
  fi
  IFS=$'\t' read -r name url digest <<<"$asset"

  local work; work="$(mktemp -d)"
  if ! curl -fsSL --retry 3 --connect-timeout 10 -o "$work/$name" "$url"; then
    echo "  ! $app: download failed"; rm -rf "$work"; return 1
  fi
  # Catches a damaged download. Trust in the app itself comes from its
  # signature, checked before it is copied into /Applications.
  if [[ "$digest" == sha256:* ]] && [[ "$(shasum -a 256 "$work/$name" | cut -d' ' -f1)" != "${digest#sha256:}" ]]; then
    echo "  ! $app: the download does not match GitHub's checksum, so it was not installed"
    rm -rf "$work"; return 1
  fi

  local found="" mounted=0
  case "$name" in
    *.dmg|*.DMG)
      mkdir -p "$work/mnt"
      if hdiutil attach -nobrowse -noautoopen -quiet -mountpoint "$work/mnt" "$work/$name"; then
        mounted=1
        found="$(find "$work/mnt" -maxdepth 2 -name '*.app' -type d | head -1)"
      fi
      ;;
    *)
      mkdir -p "$work/unzipped"
      ditto -x -k "$work/$name" "$work/unzipped" && \
        found="$(find "$work/unzipped" -maxdepth 3 -name '*.app' -type d | head -1)"
      ;;
  esac

  local status=0 dest team="" trusted=0 known
  [[ -n "$found" ]] && team="$(codesign -dv "$found" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  known="$(cat "$state/$app.team" 2>/dev/null)"
  if [[ -z "$found" ]]; then
    echo "  ! $app: no app found inside $name"; status=1
  elif [[ "$(basename "$found")" != "$app.app" ]]; then
    # Only ever install the app this line is for, so a bad release cannot
    # replace another app (Chrome, Claude...) in /Applications.
    echo "  ! $app: the download contains $(basename "$found") instead of $app.app, so nothing was installed"; status=1
  elif [[ -n "$known" && "$team" != "$known" ]]; then
    # The developer that signed this app before must sign its updates.
    echo "  ! $app: this release is signed by ${team:-nobody}, not by $known as before, so it was not installed"; status=1
  else
    # Signed, notarized apps are trusted as Apple would trust them. Anything
    # else gets the quarantine flag, so macOS checks it the first time it opens.
    codesign --verify --deep --strict "$found" 2>/dev/null && spctl -a -t exec "$found" 2>/dev/null && trusted=1
    dest="/Applications/$(basename "$found")"
    # Copy beside the old version first, then swap: the old one goes to the
    # Trash, and a failed copy leaves the old one working.
    rm -rf "$dest.new"   # only ever a leftover of this package's own copy
    if ditto "$found" "$dest.new" && move_to_trash "$dest" && mv "$dest.new" "$dest"; then
      if [[ "$trusted" == 0 ]]; then
        xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");grand-line;" "$dest" 2>/dev/null
        echo "  ! $app: not notarized by Apple, so macOS will ask before it first opens"
      fi
      [[ -n "$team" ]] && printf '%s\n' "$team" > "$state/$app.team"
      register_app "$dest"
      printf '%s\n' "$tag" > "$state/$app.tag"
      printf '%s\n' "$dest" > "$state/$app.path"
      echo "  ✓ Installed $(basename "$dest") $tag"
    else
      rm -rf "$dest.new"
      echo "  ! $app: could not copy into /Applications"; status=1
    fi
  fi

  if [[ "$mounted" == 1 ]] && ! hdiutil detach -quiet "$work/mnt" && ! hdiutil detach -force -quiet "$work/mnt"; then
    echo "  ! $app: could not unmount the disk image; it is left in $work"
    return 1
  fi
  rm -rf "$work"
  return "$status"
}

step_artcraft() {
  local list="$REPO_DIR/config/grand-line/artcraft.tsv"
  local app repo _role
  if [[ "$DRY_RUN" == 1 ]]; then
    while IFS=$'\t' read -r app repo _role; do
      [[ -z "$app" || "$app" == \#* ]] && continue
      run "install $app from the latest release of github.com/$repo"
    done < "$list"
    return 0
  fi

  # Download and install every app in parallel, then report in list order.
  local logs pids=() apps=() i failed=0
  logs="$(mktemp -d)"
  while IFS=$'\t' read -r app repo _role; do
    [[ -z "$app" || "$app" == \#* ]] && continue
    artcraft_install_one "$app" "$repo" > "$logs/$app.log" 2>&1 &
    pids+=("$!"); apps+=("$app")
  done < "$list"
  local rc
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}"; rc=$?
    cat "$logs/${apps[$i]}.log"
    if [[ $rc -eq 2 ]]; then
      WARNINGS+=("${apps[$i]} has no Mac build yet; its file types use the fallback app.")
    elif [[ $rc -ne 0 ]]; then
      failed=1
      WARNINGS+=("${apps[$i]} did not install. See the lines above.")
    fi
  done
  rm -rf "$logs"
  return "$failed"
}
