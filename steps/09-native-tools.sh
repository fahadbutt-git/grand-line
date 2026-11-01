# shellcheck shell=bash
# Builds the small native helpers in tools/*.swift with Apple's compiler
# (installed with the command line tools). Output: ~/.grand-line/.build/<name>.
# To add a helper, drop a new tools/<name>.swift file in; nothing else changes.
# Then builds the package's own apps in apps/*/ (lib/native-apps.sh), signed
# with the package's own identity so they keep their permissions.

step_native_tools() {
  if ! have swiftc && [[ "$DRY_RUN" == 0 ]]; then
    warn "Apple's Swift compiler is missing, so the text capture and PDF shrink helpers were skipped."
    return 1
  fi
  local build="$REPO_DIR/.build" src name failed=0 identity=0 unusable=0 hash=""
  # shellcheck source=lib/native-apps.sh
  source "$REPO_DIR/lib/native-apps.sh"
  # The identity the apps and helpers are signed with, made once
  # (lib/signing.sh). The unattended update never makes one, and never signs
  # the apps ad hoc in its place, which would cost them their permissions.
  signing_ensure && identity=1
  [[ "$identity" == 1 && "$DRY_RUN" == 0 ]] && { hash="$(signing_identity)" || identity=0; }
  # One macOS will not sign with (its certificate is not trusted for code
  # signing) is not tried at all: the helpers keep their build signature and
  # the apps are signed ad hoc. signing_usable says so once for the run.
  if [[ "$identity" == 1 && "$DRY_RUN" == 0 ]] && ! signing_usable; then
    identity=0; unusable=1
  fi
  run mkdir -p "$build"
  for src in "$REPO_DIR"/tools/*.swift; do
    name="$(basename "$src" .swift)"
    # Rebuild only when the source is newer than the last build.
    if [[ ! -x "$build/$name" || ! "$build/$name" -nt "$src" ]]; then
      if run swiftc -O "$src" -o "$build/$name"; then
        ok "Built $name"
        rm -f "$build/.$name.signed"
      else
        warn "Could not build $name"; failed=1; continue
      fi
    fi
    # Signed with the identity under a fixed name, so a permission given to
    # a helper (downloads-agent's Downloads access) survives a rebuild: macOS
    # ties it to the name and certificate, not to this one build's hash.
    [[ "$identity" == 1 ]] || continue
    if [[ "$DRY_RUN" == 1 ]]; then
      run "sign $name as com.grandline.tool.$name with \"$SIGN_NAME\""; continue
    fi
    [[ "$(cat "$build/.$name.signed" 2>/dev/null)" == "$hash" ]] && continue
    if sign_code "$build/$name" "" "com.grandline.tool.$name"; then
      printf '%s\n' "$hash" > "$build/.$name.signed"
    else
      warn "Could not sign $name (${SIGN_ERROR:-codesign failed}); it keeps its build signature and may ask for its permissions again."
      failed=1
    fi
  done
  if [[ "$unusable" == 1 && "${GRAND_LINE_UNATTENDED:-0}" == 1 ]]; then
    # Not a failure of this run: nothing changes until the certificate is
    # trusted, and the installed apps keep working.
    warn "The apps are not rebuilt unattended while their signing identity cannot sign."
    return "$failed"
  fi
  if [[ "$identity" == 0 && "${GRAND_LINE_UNATTENDED:-0}" == 1 ]]; then
    warn "The apps are not rebuilt unattended until setup has made their signing identity. Run: update"
    return 1
  fi
  build_native_apps || failed=1
  [[ "$DRY_RUN" == 1 ]] || exclude_indexes_from_backup
  # The apps were renamed. Their files move to the new names right after the
  # new apps are installed and before anything starts them, so the first launch
  # finds its settings and index. Every run, so a Mac whose build failed catches
  # up later; once done it changes nothing.
  local rename="$REPO_DIR/migrations/1793472900-rename-apps.sh"
  if [[ "$DRY_RUN" == 1 ]]; then
    run "carry the renamed apps' settings and index over ($(basename "$rename"))"
  elif ! GRAND_LINE_REPO="$REPO_DIR" GRAND_LINE_APPS_DEST="$APPS_DEST" /bin/bash "$rename" </dev/null; then
    warn "Some of the renamed apps' files could not be moved. Setup tries again next run."
    failed=1
  fi
  return "$failed"
}
