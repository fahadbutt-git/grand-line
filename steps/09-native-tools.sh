# shellcheck shell=bash
# Builds the small native helpers in tools/*.swift with Apple's compiler
# (installed with the command line tools). Output: ~/.grand-line/.build/<name>.
# To add a helper, drop a new tools/<name>.swift file in; nothing else changes.
# Then builds the package's own apps in apps/*/ (lib/native-apps.sh).

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
  build_native_apps || failed=1
  return "$failed"
}
