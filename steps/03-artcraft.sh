# shellcheck shell=bash
# Installs the ArtCraft apps listed in config/grand-line/artcraft.tsv from their
# latest GitHub releases, all at once. Re-running only downloads newer releases.
#
# An app is installed only when it is signed by a developer (a Team ID), its
# signature is intact, Apple has notarized it, and the Team ID is the one
# pinned in artcraft.tsv (fourth column). With no pin yet ("-"), the Team ID
# seen on the first notarized install is remembered on this Mac and every
# later release must match it; setup prints it so you can pin it in the file.
# The checksum GitHub lists only catches a damaged download: it comes from
# the same place as the download.

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
# release simply has no Mac build yet, 3 when it was refused (unsigned, not
# notarized or another developer); those two are warnings, not failures: a
# refusal is the signature policy doing its job. 1 otherwise (GitHub could
# not be reached, the download failed or was damaged, the copy failed).
#
# A refused release is remembered ($state/APP.refused: its tag and the Team
# ID pin it was checked against), so later runs do not download it, or ask
# GitHub's rate-limited API about it, again: only a newer release, or a
# changed pin, is tried.
artcraft_install_one() {
  local app="$1" repo="$2" pinned="${3:-}" state="$GRAND_LINE_STATE/artcraft"
  [[ "$pinned" == "-" ]] && pinned=""
  mkdir -p "$state"

  local tag installed_path
  tag="$(artcraft_latest_tag "$repo")"
  installed_path="$(cat "$state/$app.path" 2>/dev/null)"
  if [[ -n "$tag" && -d "$installed_path" && "$(cat "$state/$app.tag" 2>/dev/null)" == "$tag" ]]; then
    echo "  ✓ $app $tag already installed"
    return 0
  fi
  if [[ -n "$tag" && "$(cat "$state/$app.refused" 2>/dev/null)" == "$tag|$pinned" ]]; then
    echo "  ! $app: release $tag did not pass the signature checks when it was tried, so it was not downloaded again. A newer release will be."
    return 3
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

  local status=0 dest team="" expected
  [[ -n "$found" ]] && team="$(codesign -dv "$found" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  [[ "$team" == "not set" ]] && team=""
  expected="${pinned:-$(cat "$state/$app.team" 2>/dev/null)}"
  if [[ -z "$found" ]]; then
    echo "  ! $app: no app found inside $name"; status=1
  elif [[ "$(basename "$found")" != "$app.app" ]]; then
    # Only ever install the app this line is for, so a bad release cannot
    # replace another app (Zen, Claude...) in /Applications.
    echo "  ! $app: the download contains $(basename "$found") instead of $app.app, so nothing was installed"; status=1
  elif ! codesign --verify --deep --strict "$found" 2>/dev/null; then
    echo "  ! $app: the app is unsigned or its signature is broken, so it was not installed"; status=3
  elif [[ -z "$team" ]]; then
    echo "  ! $app: the app is not signed by a developer (no Team ID), so it was not installed"; status=3
  elif [[ -n "$expected" && "$team" != "$expected" ]]; then
    # The developer pinned (or seen first) must sign every release.
    echo "  ! $app: this release is signed by Team ID $team, not $expected, so it was not installed"; status=3
  elif ! spctl -a -t exec "$found" 2>/dev/null; then
    echo "  ! $app: Apple has not notarized this release, so it was not installed"; status=3
  else
    dest="/Applications/$(basename "$found")"
    # Copy beside the old version first, then swap: the old one goes to the
    # Trash, and a failed copy leaves the old one working.
    rm -rf "$dest.new"   # only ever a leftover of this package's own copy
    if ditto "$found" "$dest.new" && move_to_trash "$dest" && mv "$dest.new" "$dest"; then
      if [[ -z "$expected" ]]; then
        printf '%s\n' "$team" > "$state/$app.team"
        echo "  ! $app: first install, signed by Team ID $team and notarized by Apple. Later releases must match it."
        echo "    To pin it for every Mac, put $team in the fourth column of $app in config/grand-line/artcraft.tsv"
      fi
      register_app "$dest"
      printf '%s\n' "$tag" > "$state/$app.tag"
      printf '%s\n' "$dest" > "$state/$app.path"
      rm -f "$state/$app.refused"
      echo "  ✓ Installed $(basename "$dest") $tag"
    else
      rm -rf "$dest.new"
      echo "  ! $app: could not copy into /Applications"; status=1
    fi
  fi

  [[ "$status" == 3 && -n "$tag" ]] && printf '%s\n' "$tag|$pinned" > "$state/$app.refused"
  if [[ "$mounted" == 1 ]] && ! hdiutil detach -quiet "$work/mnt" && ! hdiutil detach -force -quiet "$work/mnt"; then
    echo "  ! $app: could not unmount the disk image; it is left in $work"
    # A refusal stays a refusal; anything else that left a disk mounted fails.
    [[ "$status" == 3 ]] && return 3
    return 1
  fi
  rm -rf "$work"
  return "$status"
}

step_artcraft() {
  local list="$REPO_DIR/config/grand-line/artcraft.tsv"
  local app repo _role team
  if [[ "$DRY_RUN" == 1 ]]; then
    while IFS=$'\t' read -r app repo _role team; do
      [[ -z "$app" || "$app" == \#* ]] && continue
      run "install $app from the latest release of github.com/$repo"
    done < "$list"
    return 0
  fi

  # Download and install every app in parallel, then report in list order.
  # Only real errors fail the step: a release with no Mac build, or one the
  # signature checks refused, is a warning and the step still succeeds.
  local logs pids=() apps=() i failed=0
  logs="$(mktemp -d)"
  while IFS=$'\t' read -r app repo _role team; do
    [[ -z "$app" || "$app" == \#* ]] && continue
    artcraft_install_one "$app" "$repo" "$team" > "$logs/$app.log" 2>&1 &
    pids+=("$!"); apps+=("$app")
  done < "$list"
  local rc
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}"; rc=$?
    cat "$logs/${apps[$i]}.log"
    if [[ $rc -eq 2 ]]; then
      WARNINGS+=("${apps[$i]} has no Mac build yet; its file types use the fallback app.")
    elif [[ $rc -eq 3 ]]; then
      WARNINGS+=("${apps[$i]} was not installed: its release did not pass the signature checks (see above).")
    elif [[ $rc -ne 0 ]]; then
      failed=1
      WARNINGS+=("${apps[$i]} did not install. See the lines above.")
    fi
  done
  rm -rf "$logs"
  return "$failed"
}
