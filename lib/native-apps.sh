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
  local dir="$1" stamp print
  stamp="$GRAND_LINE_STATE/built-$(basename "$dir")"
  print="$(app_fingerprint "$dir")"
  if [[ -n "$print" && "$(cat "$stamp" 2>/dev/null)" == "$print" ]]; then
    return 0
  fi
  APPS_KEPT=0
  build_and_install "$dir" || return 1
  # An installed copy kept for want of an identity that signs is not this
  # build: the next run tries again.
  [[ "$APPS_KEPT" == 1 ]] && return 0
  [[ "$DRY_RUN" == 1 ]] || { mkdir -p "$GRAND_LINE_STATE" && printf '%s\n' "$print" > "$stamp"; }
}

# app_fingerprint DIR: one hash of every file that goes into the apps in DIR
# (their sources, Info, Resources and the rest), apps/icons (every app uses
# it) and the lib files that bundle and sign them. A changed, added or
# deleted file changes it, so the stamp never misses a change that a
# "newer than" test would (a deletion, or a change to how bundles are made).
app_fingerprint() {
  local dir="$1" rel f files
  rel="${dir#"$REPO_DIR"/}"
  {
    if [[ "$rel" != "$dir" ]] && git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
      # The files git would track (build output is ignored), as they are now.
      files="$(git -C "$REPO_DIR" ls-files -co --exclude-standard -- "$rel" apps/icons lib/native-apps.sh lib/signing.sh 2>/dev/null \
        | LC_ALL=C sort -u | while IFS= read -r f; do [[ -f "$REPO_DIR/$f" ]] && printf '%s\n' "$f"; done)"
      [[ -n "$files" ]] && paste -d ' ' <(printf '%s\n' "$files") \
        <(printf '%s\n' "$files" | git -C "$REPO_DIR" hash-object --stdin-paths)
    else
      find "$dir" "$REPO_DIR/apps/icons" -path '*/.build' -prune -o -type f -print 2>/dev/null | LC_ALL=C sort \
        | while IFS= read -r f; do printf '%s %s\n' "${f#"$REPO_DIR"/}" "$(cksum < "$f")"; done
      cksum < "$(dirname "${BASH_SOURCE[0]}")/native-apps.sh"
      cksum < "$(dirname "${BASH_SOURCE[0]}")/signing.sh"
    fi
  } | cksum | awk '{ print $1 "-" $2 }'
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
  # Without an identity macOS lists as valid, the new copy is signed ad hoc.
  # That costs nothing when there is no installed copy or it is ad hoc (or
  # not signed) itself. An installed copy signed with the identity shows it
  # did sign on this Mac (older macOS signs with an untrusted certificate), so
  # it is tried once more; if it cannot sign, that copy is kept, since an ad
  # hoc one in its place would lose its permissions, and the next run tries
  # again.
  SIGN_TRY_IDENTITY=0
  if have codesign && ! signing_usable && ! adhoc_costs_nothing "$app"; then
    signing_identity >/dev/null || { keep_installed_copy "$name" ""; return 0; }
    SIGN_TRY_IDENTITY=1
  fi
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
      if have codesign && ! sign_code "$new/Contents/Frameworks/$fw.framework/Versions/A"; then
        [[ "$SIGN_TRY_IDENTITY" == 1 ]] && { signing_lock; keep_installed_copy "$name" "$new"; return 0; }
        if ! { adhoc_costs_nothing "$app" && sign_code_adhoc "$new/Contents/Frameworks/$fw.framework/Versions/A"; }; then
          warn "Could not sign $fw for $name: $SIGN_ERROR"; rm -rf "$new"; return 1
        fi
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
      [[ "$SIGN_TRY_IDENTITY" == 1 ]] && { signing_lock; keep_installed_copy "$name" "$new"; return 0; }
      # A first install still gets a working app, signed ad hoc for now, as
      # does one whose installed copy is ad hoc already (nothing is lost).
      if ! adhoc_costs_nothing "$app" || ! sign_code_adhoc "$new" "$dir/Entitlements/$product.entitlements"; then
        signing_lock; warn "Could not sign $name ($first). The installed copy is kept."; rm -rf "$new"; return 1
      fi
      SIGN_ADHOC_FALLBACK=1
      warn "Signed $name ad hoc, since the local signing identity could not sign it: $first"
    fi
    signing_lock
    if ! why="$(signing_check "$new")"; then
      SIGN_TRY_IDENTITY=0
      warn "$why. The installed copy is kept."; rm -rf "$new"; return 1
    fi
  fi
  SIGN_TRY_IDENTITY=0
  # A running copy is stopped and started again from the new one, so it never
  # keeps running from the Trash.
  local running=0 label reinstall=0 decision
  label="$(service_label "$dir" "$product")"
  [[ -e "$app" ]] && reinstall=1
  # A background service is restarted by launchd (below), not here.
  if [[ -z "$label" && -e "$app" && "${GRAND_LINE_APPS_SCRATCH:-0}" != 1 ]] && pgrep -x "$product" >/dev/null 2>&1; then
    running=1
  fi
  # The unattended update never swaps an app you are using: the new copy
  # waits beside it and goes in at the next quiet moment (apply_staged_apps).
  if [[ "$running" == 1 && "${GRAND_LINE_UNATTENDED:-0}" == 1 ]]; then
    decision="$(swap_probe "$id" "$product")"
    if [[ "$decision" != swap ]]; then
      stage_app_bundle "$new" "$name" "${decision#stage:}"
      return 0
    fi
  fi
  # The installed copy goes to the Trash, then the new one takes its place.
  swap_in "$new" "$app" || { rm -rf "$new"; return 1; }
  [[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$app" >/dev/null 2>&1
  # A staged copy from an earlier run is older than this one.
  rm -rf "$APPS_DEST/.$name.app.staged"
  [[ "$running" == 1 ]] && relaunch_app "$app" "$product" "$agent"

  if [[ -n "$label" && "${GRAND_LINE_APPS_SCRATCH:-0}" != 1 ]]; then
    register_service "$app" "$product" "$label" "$reinstall"
  fi
  # bin/update reads the list of apps it replaced, for its one notification.
  [[ -n "${GRAND_LINE_APPS_REPORT:-}" ]] && printf '%s\n' "$name" >> "$GRAND_LINE_APPS_REPORT"
  ok "Installed $name"
}

# keep_installed_copy NAME [NEW]: the installed copy, signed with the
# identity, stays as it is (NEW, the copy that could not be signed the same
# way, is removed), and the build is tried again next run.
keep_installed_copy() {
  warn "Kept the installed $1: it is signed with \"$SIGN_NAME\", which cannot sign on this Mac now, and an ad hoc copy would ask for its permissions again."
  [[ -n "${2:-}" ]] && rm -rf "$2"
  APPS_KEPT=1
  SIGN_TRY_IDENTITY=0
}

# adhoc_costs_nothing APP: an ad hoc signed copy may take APP's place: there
# is no installed copy, or it is signed ad hoc itself, or not at all.
adhoc_costs_nothing() {
  [[ ! -e "$1" ]] || code_is_adhoc "$1" || ! codesign -d "$1" >/dev/null 2>&1
}

# swap_in NEW APP: the installed copy to the Trash, then NEW in its place.
# When the old copy cannot be moved (it needs a password the unattended run
# does not have, or macOS's App Management refused), nothing changes: the
# old copy stays and keeps working, and it fails, so the next run tries
# again. NEW is never moved into an existing bundle: the rename refuses a
# folder that is there. A folder's own build.sh replaces its last build in
# place (GRAND_LINE_APPS_SCRATCH=1): that is build output.
swap_in() {
  local new="$1" app="$2" name
  name="$(basename "$app" .app)"
  if [[ -e "$app" || -L "$app" ]]; then
    if [[ "${GRAND_LINE_APPS_SCRATCH:-0}" == 1 ]]; then
      rm -rf "$app"
    elif ! move_to_trash "$app" && [[ -e "$app" || -L "$app" ]]; then
      warn "The installed $name could not be moved to the Trash, so it is kept and the new version was not installed. Setup tries again next run."
      return 1
    fi
  fi
  if [[ -e "$app" || -L "$app" ]]; then
    warn "$app is still there, so the new version of $name was not installed."
    return 1
  fi
  # rename(2): one step, and it never puts NEW inside a folder at APP.
  if ! perl -e 'exit(rename($ARGV[0], $ARGV[1]) ? 0 : 1)' "$new" "$app"; then
    warn "Could not put the new version of $name in place."
    return 1
  fi
}

# relaunch_app APP PRODUCT AGENT: quit the running copy (SIGTERM, which the
# apps treat as a normal quit) and start the new one in the background:
# `open -g` never brings it forward or takes the keyboard, and an app with a
# Dock icon (AGENT not yes) also starts hidden (-j), so no window appears
# over what you are doing.
relaunch_app() {
  local app="$1" product="$2" agent="$3" _
  pkill -TERM -x "$product" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$product" >/dev/null 2>&1 || break; sleep 0.5; done
  if [[ "$agent" == yes ]]; then open -g "$app" >/dev/null 2>&1
  else open -g -j "$app" >/dev/null 2>&1; fi
  return 0
}

# swap_decision IDLE FRONT ID BUSY SHARING PRESENTING: whether the unattended
# update may replace a running app now. IDLE is seconds since the last key
# or pointer move, FRONT the bundle id of the app in front, BUSY 1 when the
# app says it is mid-task, SHARING 1 while the screen is shared, PRESENTING 1
# while something keeps the display awake (a presentation, a video call, a
# film). Prints swap, or stage:<why>.
SWAP_IDLE_SECONDS=600
swap_decision() {
  local idle="${1:-0}" front="$2" id="$3" busy="$4" sharing="$5" presenting="$6"
  [[ "$idle" =~ ^[0-9]+$ ]] || idle=0
  if [[ "$sharing" == 1 ]]; then echo "stage:the screen is being shared"
  elif [[ "$presenting" == 1 ]]; then echo "stage:something is presenting or playing"
  elif [[ -n "$front" && "$front" == "$id" ]]; then echo "stage:it is the app in front"
  elif [[ "$busy" == 1 ]]; then echo "stage:it is in the middle of something"
  elif (( idle < SWAP_IDLE_SECONDS )); then echo "stage:the Mac is in use"
  else echo swap
  fi
}

# swap_probe ID PRODUCT: swap_decision with this Mac's readings, each one a
# single cheap command.
swap_probe() {
  local id="$1" product="$2" idle front busy=0 sharing=0 presenting=0 marker pid
  idle="$(ioreg -c IOHIDSystem -d 4 2>/dev/null | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }')"
  front="$(lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed -n 's/.*"CFBundleIdentifier"="\([^"]*\)".*/\1/p')"
  marker="$HOME/.local/state/grand-line-runtime/$(printf '%s' "$product" | tr '[:upper:]' '[:lower:]').busy"
  if [[ -f "$marker" ]]; then
    pid="$(head -1 "$marker" 2>/dev/null)"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && busy=1
  fi
  pgrep -x screensharingd >/dev/null 2>&1 && sharing=1
  pmset -g assertions 2>/dev/null | grep -qE '^[[:space:]]*PreventUserIdleDisplaySleep[[:space:]]+1' && presenting=1
  swap_decision "${idle:-0}" "$front" "$id" "$busy" "$sharing" "$presenting"
}

# stage_app_bundle NEW NAME WHY: keep the new, signed copy beside the
# installed one ($APPS_DEST/.NAME.app.staged) for apply_staged_apps.
stage_app_bundle() {
  local new="$1" name="$2" why="$3" staged="$APPS_DEST/.$2.app.staged"
  rm -rf "$staged"
  mv "$new" "$staged"
  ok "$name: the new version waits ($why); it goes in when the Mac is idle, at the next update or login"
  [[ -n "${GRAND_LINE_APPS_REPORT:-}" ]] && printf '%s\n' "$name (waiting)" >> "$GRAND_LINE_APPS_REPORT"
  return 0
}

# apply_staged_apps: put in the copies an earlier unattended run left
# waiting: at once for an app that is not running, and for a running one
# only when swap_probe says the moment is quiet. bin/update runs it first.
apply_staged_apps() {
  local list product name id agent staged app
  for list in "$REPO_DIR"/apps/*/apps.tsv; do
    [[ -f "$list" ]] || continue
    while IFS=$'\t' read -r product name id agent; do
      [[ -z "$product" || "$product" == \#* ]] && continue
      staged="$APPS_DEST/.$name.app.staged"
      app="$APPS_DEST/$name.app"
      [[ -d "$staged" ]] || continue
      local running=0
      pgrep -x "$product" >/dev/null 2>&1 && running=1
      if [[ "$running" == 1 && "$(swap_probe "$id" "$product")" != swap ]]; then continue; fi
      if [[ "$DRY_RUN" == 1 ]]; then run "put in the waiting copy of $name"; continue; fi
      # When the old copy cannot be moved, the waiting one keeps waiting.
      swap_in "$staged" "$app" || continue
      [[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$app" >/dev/null 2>&1
      [[ "$running" == 1 ]] && relaunch_app "$app" "$product" "$agent"
      ok "Installed the waiting copy of $name"
    done < "$list"
  done
  return 0
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
