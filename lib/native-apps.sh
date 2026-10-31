# shellcheck shell=bash
# Builds the package's own apps (Log Pose, Byakugan, Den Den) from apps/*/
# and installs each one in /Applications.
#
# Each app folder holds a Swift package and an apps.tsv naming what it makes:
#   product <TAB> app name <TAB> bundle id <TAB> menu-bar only (yes/no)
# Extra Info.plist keys for a product go in apps/<folder>/Info/<product>.plist
# (bare <key>/<value> lines), and its icon and other files in
# apps/<folder>/Resources/<product>/.
# Needs lib/common.sh (run, ok, warn, move_to_trash).

APPS_DEST="${GRAND_LINE_APPS_DEST:-/Applications}"

# build_native_apps: build every app whose sources changed since its last
# build. Returns 1 if any failed, and keeps the installed copy then.
build_native_apps() {
  local list failed=0
  for list in "$REPO_DIR"/apps/*/apps.tsv; do
    [[ -f "$list" ]] || continue
    build_app_folder "$(dirname "$list")" || failed=1
  done
  return "$failed"
}

build_app_folder() {
  local dir="$1" stamp product name id agent
  stamp="$GRAND_LINE_STATE/built-$(basename "$dir")"
  if [[ -f "$stamp" ]] && [[ -z "$(find "$dir" -path "$dir/.build" -prune -o \( -name '*.swift' -o -name '*.tsv' -o -name '*.plist' -o -path '*/Resources/*' \) -newer "$stamp" -print -quit)" ]]; then
    return 0
  fi
  if ! run swift build -c release --package-path "$dir"; then
    warn "Could not build the apps in apps/$(basename "$dir"). The installed copies are kept."
    return 1
  fi
  while IFS=$'\t' read -r product name id agent; do
    [[ -z "$product" || "$product" == \#* ]] && continue
    install_app_bundle "$dir" "$product" "$name" "$id" "$agent" || return 1
  done < "$dir/apps.tsv"
  [[ "$DRY_RUN" == 1 ]] || { mkdir -p "$GRAND_LINE_STATE" && touch "$stamp"; }
}

# install_app_bundle DIR PRODUCT NAME ID AGENT: wrap the built program in an
# app bundle, sign it for this Mac, and swap it in. The old copy goes to the
# Trash.
install_app_bundle() {
  local dir="$1" product="$2" name="$3" id="$4" agent="$5"
  local bin="$dir/.build/release/$product" app="$APPS_DEST/$name.app" new
  if [[ "$DRY_RUN" == 1 ]]; then
    run "install $name in $app"
    return 0
  fi
  [[ -x "$bin" ]] || { warn "The build made no $product program."; return 1; }
  new="$APPS_DEST/.$name.app.new"
  rm -rf "$new"   # only ever our own half-made copy from a failed run
  mkdir -p "$new/Contents/MacOS" "$new/Contents/Resources"
  cp "$bin" "$new/Contents/MacOS/$product"
  [[ -d "$dir/Resources/$product" ]] && cp -R "$dir/Resources/$product/." "$new/Contents/Resources/"
  info_plist "$product" "$name" "$id" "$agent" "$dir/Info/$product.plist" > "$new/Contents/Info.plist"
  if have codesign && ! codesign --force --sign - "$new" >/dev/null 2>&1; then
    warn "Could not sign $name."; rm -rf "$new"; return 1
  fi
  [[ -e "$app" ]] && move_to_trash "$app"
  mv "$new" "$app"
  local lsreg=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  [[ -x "$lsreg" ]] && "$lsreg" -f "$app" >/dev/null 2>&1
  ok "Installed $name"
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
