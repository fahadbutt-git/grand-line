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
  local build="$REPO_DIR/.build" src name failed=0
  run mkdir -p "$build"
  for src in "$REPO_DIR"/tools/*.swift; do
    name="$(basename "$src" .swift)"
    # Rebuild only when the source is newer than the last build.
    if [[ -x "$build/$name" && "$build/$name" -nt "$src" ]]; then
      continue
    fi
    if run swiftc -O "$src" -o "$build/$name"; then
      ok "Built $name"
    else
      warn "Could not build $name"; failed=1
    fi
  done
  # shellcheck source=lib/native-apps.sh
  source "$REPO_DIR/lib/native-apps.sh"
  # The identity the apps are signed with, made once (lib/signing.sh). The
  # unattended update never makes one, and never signs ad hoc in its place,
  # which would cost the apps their permissions: it leaves them for you.
  if ! signing_ensure && [[ "${GRAND_LINE_UNATTENDED:-0}" == 1 ]]; then
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
