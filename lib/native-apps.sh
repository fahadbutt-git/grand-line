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
# Needs lib/common.sh (run, ok, warn, move_to_trash).
# An app folder's own build.sh uses the same functions, so there is one way
# to make each app.

APPS_DEST="${GRAND_LINE_APPS_DEST:-/Applications}"
APPS_CONFIG="${GRAND_LINE_APPS_CONFIG:-release}"

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
  # apps/icons is a package every app uses, so a change there rebuilds them all.
  if [[ -f "$stamp" ]] && [[ -z "$(find "$dir" "$REPO_DIR/apps/icons" -path '*/.build' -prune -o \( -name '*.swift' -o -name '*.[chm]' -o -name '*.tsv' -o -name '*.plist' -o -path '*/Resources/*' \) -newer "$stamp" -print -quit 2>/dev/null)" ]]; then
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

# install_app_bundle DIR PRODUCT NAME ID AGENT: wrap the built program in an
# app bundle, sign it for this Mac, and swap it in. The old copy goes to the
# Trash.
install_app_bundle() {
  local dir="$1" product="$2" name="$3" id="$4" agent="$5"
  local out="$dir/.build/$APPS_CONFIG" app="$APPS_DEST/$name.app" new lib fw
  if [[ "$DRY_RUN" == 1 ]]; then
    run "install $name in $app"
    return 0
  fi
  [[ -x "$out/$product" ]] || { warn "The build made no $product program."; return 1; }
  new="$APPS_DEST/.$name.app.new"
  rm -rf "$new"   # only ever our own half-made copy from a failed run
  mkdir -p "$new/Contents/MacOS" "$new/Contents/Resources"
  cp "$out/$product" "$new/Contents/MacOS/$product"
  [[ -d "$dir/Resources/$product" ]] && cp -R "$dir/Resources/$product/." "$new/Contents/Resources/"
  info_plist "$product" "$name" "$id" "$agent" "$dir/Info/$product.plist" > "$new/Contents/Info.plist"
  if [[ -f "$dir/frameworks.tsv" ]]; then
    while IFS=$'\t' read -r lib fw; do
      [[ -z "$lib" || "$lib" == \#* ]] && continue
      [[ -f "$out/lib$lib.dylib" ]] || { warn "The build made no lib$lib.dylib for $name."; rm -rf "$new"; return 1; }
      wrap_framework "$out/lib$lib.dylib" "$fw" "$id.$fw" "$new/Contents/Frameworks/$fw.framework"
      if have codesign && ! codesign --force --sign - "$new/Contents/Frameworks/$fw.framework/Versions/A" >/dev/null 2>&1; then
        warn "Could not sign $fw for $name."; rm -rf "$new"; return 1
      fi
    done < "$dir/frameworks.tsv"
  fi
  # A built app is never "downloaded": no quarantine, so macOS runs it from
  # where it is instead of a translocated copy.
  have xattr && xattr -cr "$new" 2>/dev/null
  if have codesign && ! codesign --force --sign - "$new" >/dev/null 2>&1; then
    warn "Could not sign $name."; rm -rf "$new"; return 1
  fi
  # The installed copy goes to the Trash. A folder's own build.sh replaces
  # its last build in place (GRAND_LINE_APPS_SCRATCH=1): that is build output.
  if [[ -e "$app" && "${GRAND_LINE_APPS_SCRATCH:-0}" == 1 ]]; then rm -rf "$app"
  elif [[ -e "$app" ]]; then move_to_trash "$app"; fi
  mv "$new" "$app"
  [[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$app" >/dev/null 2>&1
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
