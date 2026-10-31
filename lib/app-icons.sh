# shellcheck shell=bash
# Finder and the Dock show an app's bundled icon until it runs, so after a
# theme change the installed apps get icons drawn in the new theme's colours
# (tools/make-icons.py). Changing a file inside an app breaks its signature,
# so each app is copied, given the icon, signed again with the package's
# identity (lib/signing.sh) and swapped in. Its designated requirement stays
# the same, so its permissions are kept. Without the identity nothing is
# changed: an ad-hoc signature would cost the app its permissions.
# Needs lib/signing.sh.

APP_ICONS_DEST="${GRAND_LINE_APPS_DEST:-/Applications}"
APP_ICONS_LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# installed_own_apps REPO: "folder<TAB>product<TAB>name<TAB>bundle id" for each
# of the package's apps that is installed.
installed_own_apps() {
  local repo="$1" list product name id _
  for list in "$repo"/apps/*/apps.tsv; do
    [[ -f "$list" ]] || continue
    while IFS=$'\t' read -r product name id _; do
      [[ -z "$product" || "$product" == \#* ]] && continue
      [[ -d "$APP_ICONS_DEST/$name.app" ]] && printf '%s\t%s\t%s\t%s\n' "$(dirname "$list")" "$product" "$name" "$id"
    done < "$list"
  done
  return 0
}

# app_icons_wanted REPO: the identity exists and at least one app is installed.
app_icons_wanted() {
  command -v codesign >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || return 1
  signing_identity >/dev/null || return 1
  [[ -n "$(installed_own_apps "$1")" ]]
}

# refresh_app_icons THEME REPO
refresh_app_icons() {
  local theme="$1" repo="$2" work dir product name id app icon new old changed=0
  app_icons_wanted "$repo" || return 0
  work="$(mktemp -d)" || return 1
  if ! python3 "$repo/tools/make-icons.py" --theme "$theme" --out "$work" >/dev/null 2>&1; then
    rm -rf "$work"; return 1
  fi
  while IFS=$'\t' read -r dir product name id; do
    icon="$work/$product/AppIcon.icns"
    app="$APP_ICONS_DEST/$name.app"
    [[ -f "$icon" && -d "$app/Contents/Resources" ]] || continue
    cmp -s "$icon" "$app/Contents/Resources/AppIcon.icns" && continue
    # The copies are the package's own build output, identical to the
    # installed app apart from the icon.
    new="$APP_ICONS_DEST/.$name.app.icon"; old="$APP_ICONS_DEST/.$name.app.old"
    rm -rf "$new" "$old"
    if command -v ditto >/dev/null 2>&1; then ditto "$app" "$new" 2>/dev/null; else cp -Rp "$app" "$new"; fi \
      || { rm -rf "$new"; continue; }
    cp "$icon" "$new/Contents/Resources/AppIcon.icns"
    if ! sign_code "$new" "$dir/Entitlements/$product.entitlements" "$id" || ! signing_check "$new" >/dev/null; then
      rm -rf "$new"; continue
    fi
    if mv "$app" "$old"; then
      if mv "$new" "$app"; then
        rm -rf "$old"
        touch "$app"
        [[ -x "$APP_ICONS_LSREGISTER" ]] && "$APP_ICONS_LSREGISTER" -f "$app" >/dev/null 2>&1
        changed=1
      else
        mv "$old" "$app"; rm -rf "$new"
      fi
    else
      rm -rf "$new"
    fi
  done < <(installed_own_apps "$repo")
  signing_lock
  rm -rf "$work"
  [[ "$changed" == 1 ]] && echo "App icons now match $theme"
  return 0
}
