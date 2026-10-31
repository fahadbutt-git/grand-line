# shellcheck shell=bash
# Installs the R packages listed in config/mac-setup/r-packages.txt.

step_r_packages() {
  local rscript="" candidate
  for candidate in "$(command -v Rscript 2>/dev/null)" /usr/local/bin/Rscript \
                   /Library/Frameworks/R.framework/Resources/bin/Rscript; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then rscript="$candidate"; break; fi
  done
  if [[ -z "$rscript" && "$DRY_RUN" == 0 ]]; then
    warn "R is not installed yet, so R packages were skipped. Run: bash ~/mac-setup/setup.sh --only r-packages"
    return 1
  fi

  local list="$REPO_DIR/config/mac-setup/r-packages.txt"
  local code="pkgs <- setdiff(trimws(readLines('$list')), ''); pkgs <- pkgs[!startsWith(pkgs, '#')]; \
have <- function(p) nzchar(system.file(package = p)); \
missing <- pkgs[!vapply(pkgs, have, logical(1))]; \
if (length(missing)) install.packages(missing, repos = 'https://cloud.r-project.org', type = 'binary', Ncpus = 4L); \
still <- pkgs[!vapply(pkgs, have, logical(1))]; \
if (length(still)) { message('Not installed: ', paste(still, collapse = ', ')); quit(status = 1) }"

  info "Installing R packages (binary builds, a few minutes the first time)"
  run "${rscript:-Rscript}" -e "$code" || return 1
  ok "R packages ready"
}
