# shellcheck shell=bash
# Builds the package's own apps (Nexus, Sight, Iceberg) from apps/*/
# and installs each one in /Applications.
#
# Each app folder holds a Swift package and an apps.tsv naming what it makes:
#   product <TAB> app name <TAB> bundle id <TAB> menu-bar only (yes/no)
# Extra Info.plist keys for a product go in apps/<folder>/Info/<product>.plist
# (bare <key>/<value> lines), and its icon and other files in
# apps/<folder>/Resources/<product>/. The icon is AppIcon.icns, drawn by
# tools/make-icons.py and named by CFBundleIconFile in the Info fragment; the
# apps redraw it in the theme's colours when they run (apps/icons). Dynamic libraries the app loads at run
# time are listed in apps/<folder>/frameworks.tsv (library product <TAB>
# framework name); each is built and goes in Contents/Frameworks.
# Apps are signed with hardened runtime by the package's own signing identity
# (lib/signing.sh), so macOS keeps their permissions across rebuilds. An app's
# entitlements, the few exceptions to hardened runtime it needs, are in
# apps/<folder>/Entitlements/<product>.entitlements.
# Needs lib/common.sh (run, ok, warn, move_to_trash).
# An app folder's own build.sh uses the same functions, so there is one way
# to make each app.

APPS_DEST="${GRAND_LINE_APPS_DEST:-/Applications}"
APPS_CONFIG="${GRAND_LINE_APPS_CONFIG:-release}"
# shellcheck source=lib/signing.sh
source "$(dirname "${BASH_SOURCE[0]}")/signing.sh"

# build_native_apps: build every app whose sources changed since its last
# build. Returns 1 if any failed, and keeps the installed copy then.
build_native_apps() {
  local list failed=0
  # The unattended update never builds code that is not a signature-checked
  # commit: a change on this Mac (yours, or another program's) waits until
  # you run setup or update yourself.
  if [[ "${GRAND_LINE_UNATTENDED:-0}" == 1 ]] && ! apps_tree_clean; then
    warn "The apps' sources have changes that are not in a checked commit, so they were not rebuilt. Run: update"
    return 1
  fi
  for list in "$REPO_DIR"/apps/*/apps.tsv; do
    [[ -f "$list" ]] || continue
    build_app_folder "$(dirname "$list")" || failed=1
  done
  return "$failed"
}

build_app_folder() {
  local dir="$1" stamp product name id agent
  stamp="$GRAND_LINE_STATE/built-$(basename "$dir")"
  # apps/icons is a package every app uses, so a change there rebuilds them all.
  if [[ -f "$stamp" ]] && [[ -z "$(find "$dir" "$REPO_DIR/apps/icons" -path '*/.build' -prune -o \( -name '*.swift' -o -name '*.[chm]' -o -name '*.tsv' -o -name '*.plist' -o -name '*.entitlements' -o -path '*/Bundle/*' -o -path '*/Resources/*' \) -newer "$stamp" -print -quit 2>/dev/null)" ]]; then
    return 0
  fi
  build_and_install "$dir" || return 1
  [[ "$DRY_RUN" == 1 ]] || { mkdir -p "$GRAND_LINE_STATE" && touch "$stamp"; }
}

# build_and_install DIR: build the package and install each app it lists.
build_and_install() {
  local dir="$1" product name id agent
  if ! run swift build -c "$APPS_CONFIG" --package-path "$dir"; then
    warn "Could not build the apps in apps/$(basename "$dir"). The installed copies are kept."
    return 1
  fi
  local lib fw
  if [[ -f "$dir/frameworks.tsv" ]]; then
    while IFS=$'\t' read -r lib fw; do
      [[ -z "$lib" || "$lib" == \#* ]] && continue
      run swift build -c "$APPS_CONFIG" --package-path "$dir" --product "$lib" \
        || { warn "Could not build $lib in apps/$(basename "$dir")."; return 1; }
    done < "$dir/frameworks.tsv"
  fi
  while IFS=$'\t' read -r product name id agent; do
    [[ -z "$product" || "$product" == \#* ]] && continue
    install_app_bundle "$dir" "$product" "$name" "$id" "$agent" || return 1
  done < "$dir/apps.tsv"
}

# service_label DIR PRODUCT: the launchd label of a product that is a
# background service (its Bundle folder holds a launch agent), or nothing.
service_label() {
  local plist
  for plist in "$1/Bundle/$2/Library/LaunchAgents/"*.plist; do
    [[ -f "$plist" ]] && { basename "$plist" .plist; return 0; }
  done
  return 0
}

# register_service APP PRODUCT LABEL REINSTALLED: the service registers its
# own launch agent with macOS (SMAppService), as you, never with sudo. It
# prints enabled, requires approval, or an error. A new copy of a running
# service is started again by launchd.
register_service() {
  local app="$1" product="$2" label="$3" reinstall="$4" out
  out="$("$app/Contents/MacOS/$product" --register 2>&1)"
  if [[ $? -eq 0 ]]; then
    ok "$(basename "$app" .app) runs in the background"
  elif [[ "$out" == *"requires approval"* ]]; then
    warn "Allow $(basename "$app" .app) to run: System Settings, General, Login Items, Allow in the Background, $(basename "$app" .app)"
  else
    warn "$(basename "$app" .app) could not register its background service: ${out:-no answer}"
  fi
  if [[ "$reinstall" == 1 ]]; then
    launchctl kickstart -k "gui/$(id -u)/$label" >/dev/null 2>&1
  fi
  return 0
}

# apps_tree_clean: nothing that goes into an app differs from the last commit,
# including new files the build would pick up.
apps_tree_clean() {
  git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  [[ -z "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all -- apps lib tools 2>/dev/null)" ]]
}

# install_app_bundle DIR PRODUCT NAME ID AGENT: wrap the built program in an
# app bundle, sign it for this Mac, and swap it in. The old copy goes to the
# Trash.
install_app_bundle() {
  local dir="$1" product="$2" name="$3" id="$4" agent="$5"
  local out="$dir/.build/$APPS_CONFIG" app="$APPS_DEST/$name.app" new lib fw
  if [[ "$DRY_RUN" == 1 ]]; then
    run "install $name in $app"
    if [[ -n "$(service_label "$dir" "$product")" ]]; then
      run "$app/Contents/MacOS/$product --register"
    fi
    return 0
  fi
  [[ -x "$out/$product" ]] || { warn "The build made no $product program."; return 1; }
  new="$APPS_DEST/.$name.app.new"
  rm -rf "$new"   # only ever our own half-made copy from a failed run
  mkdir -p "$new/Contents/MacOS" "$new/Contents/Resources"
  cp "$out/$product" "$new/Contents/MacOS/$product"
  [[ -d "$dir/Resources/$product" ]] && cp -R "$dir/Resources/$product/." "$new/Contents/Resources/"
  info_plist "$product" "$name" "$id" "$agent" "$dir/Info/$product.plist" > "$new/Contents/Info.plist"
  # Files that belong elsewhere in the bundle (a background service's launch
  # agent plist in Contents/Library/LaunchAgents), so the signature seals them.
  [[ -d "$dir/Bundle/$product" ]] && cp -R "$dir/Bundle/$product/." "$new/Contents/"
  if [[ -f "$dir/frameworks.tsv" ]]; then
    while IFS=$'\t' read -r lib fw; do
      [[ -z "$lib" || "$lib" == \#* ]] && continue
      [[ -f "$out/lib$lib.dylib" ]] || { warn "The build made no lib$lib.dylib for $name."; rm -rf "$new"; return 1; }
      wrap_framework "$out/lib$lib.dylib" "$fw" "$id.$fw" "$new/Contents/Frameworks/$fw.framework"
      if have codesign && ! sign_code "$new/Contents/Frameworks/$fw.framework/Versions/A" \
        && ! { [[ ! -e "$app" ]] && sign_code_adhoc "$new/Contents/Frameworks/$fw.framework/Versions/A"; }; then
        warn "Could not sign $fw for $name: $SIGN_ERROR"; rm -rf "$new"; return 1
      fi
    done < "$dir/frameworks.tsv"
  fi
  # A built app is never "downloaded": no quarantine, so macOS runs it from
  # where it is instead of a translocated copy.
  have xattr && xattr -cr "$new" 2>/dev/null
  if have codesign; then
    local why
    SIGN_ADHOC_FALLBACK=0
    if ! sign_code "$new" "$dir/Entitlements/$product.entitlements" "$id"; then
      local first="$SIGN_ERROR"
      # A first install still gets a working app, signed ad hoc for now.
      if [[ -e "$app" ]] || ! sign_code_adhoc "$new" "$dir/Entitlements/$product.entitlements"; then
        signing_lock; warn "Could not sign $name ($first). The installed copy is kept."; rm -rf "$new"; return 1
      fi
      SIGN_ADHOC_FALLBACK=1
      warn "Signed $name ad hoc, since the local signing identity could not sign it: $first"
    fi
    signing_lock
    if ! why="$(signing_check "$new")"; then
      warn "$why. The installed copy is kept."; rm -rf "$new"; return 1
    fi
  fi
  # A running copy is stopped and started again from the new one, so it never
  # keeps running from the Trash.
  local running=0 label reinstall=0
  label="$(service_label "$dir" "$product")"
  [[ -e "$app" ]] && reinstall=1
  # A background service is restarted by launchd (below), not here.
  if [[ -z "$label" && -e "$app" && "${GRAND_LINE_APPS_SCRATCH:-0}" != 1 ]] && pgrep -x "$product" >/dev/null 2>&1; then
    running=1
  fi
  # The installed copy goes to the Trash. A folder's own build.sh replaces
  # its last build in place (GRAND_LINE_APPS_SCRATCH=1): that is build output.
  if [[ -e "$app" && "${GRAND_LINE_APPS_SCRATCH:-0}" == 1 ]]; then rm -rf "$app"
  elif [[ -e "$app" ]]; then move_to_trash "$app"; fi
  mv "$new" "$app"
  [[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$app" >/dev/null 2>&1
  if [[ "$running" == 1 ]]; then
    pkill -TERM -x "$product" >/dev/null 2>&1
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$product" >/dev/null 2>&1 || break; sleep 0.5; done
    open -g "$app" >/dev/null 2>&1
  fi
  if [[ -n "$label" && "${GRAND_LINE_APPS_SCRATCH:-0}" != 1 ]]; then
    register_service "$app" "$product" "$label" "$reinstall"
  fi
  # bin/update reads the list of apps it replaced, for its one notification.
  [[ -n "${GRAND_LINE_APPS_REPORT:-}" ]] && printf '%s\n' "$name" >> "$GRAND_LINE_APPS_REPORT"
  ok "Installed $name"
}

# wrap_framework LIB NAME ID DEST: a framework bundle holding one library.
wrap_framework() {
  local lib="$1" fw="$2" id="$3" dest="$4"
  mkdir -p "$dest/Versions/A/Resources"
  cp "$lib" "$dest/Versions/A/$fw"
  cat > "$dest/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$fw</string>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleName</key><string>$fw</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
EOF
  ln -sfn A "$dest/Versions/Current"
  ln -sfn "Versions/Current/$fw" "$dest/$fw"
  ln -sfn Versions/Current/Resources "$dest/Resources"
}

info_plist() {
  local product="$1" name="$2" id="$3" agent="$4" extra="$5" version
  version="$(git -C "$REPO_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$product</string>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
EOF
  [[ "$agent" == yes ]] && echo "  <key>LSUIElement</key><true/>"
  [[ -f "$extra" ]] && sed 's/^/  /' "$extra"
  printf '</dict>\n</plist>\n'
}

# exclude_indexes_from_backup: keep the apps' file-name indexes, search
# history and caches out of Time Machine. They list every file name in your
# home folder and what you typed into Sight, and are rebuilt when missing.
# tmutil marks each item itself (no password); a file the app later replaces
# loses the mark, so every setup and update marks them again.
exclude_indexes_from_backup() {
  have tmutil || return 0
  local support="$HOME/Library/Application Support" item app
  for app in Nexus Sight "Grand Line Index"; do
    for item in "$support/$app"/*index* "$support/$app"/*Index* "$support/$app"/*.snapshot "$support/$app/usage.json"; do
      [[ -e "$item" ]] || continue
      run tmutil addexclusion "$item" >/dev/null 2>&1
    done
  done
  for item in "$HOME"/Library/Caches/com.grandline.*; do
    [[ -e "$item" ]] && run tmutil addexclusion "$item" >/dev/null 2>&1
  done
  return 0
}
