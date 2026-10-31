# shellcheck shell=bash
# Which changes from GitHub this Mac accepts without asking.
#
# A change is applied by itself only when every new commit carries an SSH
# signature from a key listed in ~/.config/grand-line/allowed_signers. That
# file is outside the package on purpose: a change to the package cannot add
# its own key. Setup writes it once from your git signing key
# (git config user.signingkey with gpg.format ssh); you can add other keys
# you sign with, one line each, in the format of ssh-keygen's ALLOWED SIGNERS:
#   you@example.com namespaces="git" ssh-ed25519 AAAA...
# With no key there, an update you run yourself shows the new commits and
# asks, and the unattended one stops and tells you.

ALLOWED_SIGNERS="${GRAND_LINE_ALLOWED_SIGNERS:-$HOME/.config/grand-line/allowed_signers}"

# signing_public_key: your git signing key as "type base64", or nothing.
signing_public_key() {
  local key format file
  format="$(git config --global --get gpg.format 2>/dev/null)"
  key="$(git config --global --get user.signingkey 2>/dev/null)"
  [[ "$format" == ssh && -n "$key" ]] || return 1
  key="${key#key::}"
  case "$key" in
    ssh-*|ecdsa-*|sk-*) printf '%s\n' "$key" | awk '{ print $1, $2 }'; return 0 ;;
  esac
  file="${key/#\~/$HOME}"
  [[ "$file" == *.pub ]] || file="$file.pub"
  [[ -f "$file" ]] || return 1
  awk 'NF >= 2 { print $1, $2; exit }' "$file"
}

# trust_init: write the allowed signers file once, readable only by you.
# Prints what it did.
trust_init() {
  local key who dir
  # A key set up after the first run is added once, while the file lists none.
  if [[ -f "$ALLOWED_SIGNERS" ]]; then
    [[ "$(trusted_keys)" == 0 ]] || return 0
    key="$(signing_public_key)" || return 0
    who="$(git config --global --get user.email 2>/dev/null)"; [[ -n "$who" ]] || who="grand-line"
    printf '%s namespaces="git" %s\n' "$who" "$key" >> "$ALLOWED_SIGNERS"
    echo "Updates signed with your git signing key now apply by themselves"
    return 0
  fi
  dir="$(dirname "$ALLOWED_SIGNERS")"
  (umask 077 && mkdir -p "$dir") || return 1
  chmod 700 "$dir" 2>/dev/null
  key="$(signing_public_key)" || key=""
  who="$(git config --global --get user.email 2>/dev/null)"; [[ -n "$who" ]] || who="grand-line"
  (
    umask 077
    {
      echo "# Keys whose signed commits update this Mac by themselves (see lib/update-trust.sh)."
      echo "# One per line: principal namespaces=\"git\" key-type base64-key"
      [[ -n "$key" ]] && printf '%s namespaces="git" %s\n' "$who" "$key"
    } > "$ALLOWED_SIGNERS"
  ) || return 1
  if [[ -n "$key" ]]; then echo "Updates signed with your git signing key apply by themselves"
  else echo "No git signing key found, so updates from GitHub ask you first (keys go in $ALLOWED_SIGNERS)"; fi
}

# trusted_keys: how many keys the file lists.
trusted_keys() {
  grep -cvE '^[[:space:]]*(#|$)' "$ALLOWED_SIGNERS" 2>/dev/null || true
}

# commit_trusted REPO SHA: the commit has an SSH signature that verifies
# against the allowed signers file. GPG signatures are not accepted, because
# gpg would trust any key in your keyring rather than only these.
commit_trusted() {
  local repo="$1" sha="$2"
  [[ -s "$ALLOWED_SIGNERS" ]] || return 1
  git -C "$repo" cat-file commit "$sha" 2>/dev/null | grep -q '^gpgsig -----BEGIN SSH SIGNATURE-----' || return 1
  git -C "$repo" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$ALLOWED_SIGNERS" \
    verify-commit "$sha" >/dev/null 2>&1
}

# untrusted_commits REPO OLD NEW: the commits in OLD..NEW that are not
# trusted, oldest first, one "sha subject" per line.
untrusted_commits() {
  local repo="$1" old="$2" new="$3" sha
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    commit_trusted "$repo" "$sha" || git -C "$repo" log -1 --format='%h %s' "$sha"
  done < <(git -C "$repo" rev-list --reverse "$old..$new")
  return 0
}

# ask QUESTION: yes only when someone at the keyboard answers yes.
ask() {
  [[ "${STRICT:-1}" == 0 && -t 0 ]] || return 1
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" == [yY]* ]]
}

# package_update REPO: fetch, check every new commit, then apply them.
# Returns 0 when the package is current, 2 when something waits for you, 1
# when GitHub could not be reached. With STRICT=1 (no one at the keyboard)
# only trusted commits are applied and nothing is asked. Adds to the caller's
# arrays changed (what it applied) and needs (what waits for you).
package_update() {
  local REPO="$1" branch upstream old new count untrusted dirty
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || return 0
  branch="$(git -C "$REPO" branch --show-current)"
  upstream="$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || {
    echo "No GitHub copy to update from${branch:+ for branch $branch}."; return 0; }
  old="$(git -C "$REPO" rev-parse -q --verify "$upstream")"
  if ! git -C "$REPO" fetch -q "${upstream%%/*}"; then
    echo "Could not reach GitHub."; return 1
  fi
  new="$(git -C "$REPO" rev-parse -q --verify "$upstream")" || return 1

  # GitHub's history only ever grows. A rewritten history is never applied.
  if [[ -n "$old" && "$old" != "$new" ]] && ! git -C "$REPO" merge-base --is-ancestor "$old" "$new"; then
    echo "GitHub's copy was rewritten (force-pushed), so nothing was applied. Check it before updating:"
    echo "  git -C $REPO log --oneline $old...$new"
    needs+=("GitHub's copy was rewritten; check it before updating")
    return 2
  fi
  count="$(git -C "$REPO" rev-list --count "HEAD..$new")"
  if [[ "$count" == 0 ]]; then
    echo "The package is up to date."
    return 0
  fi
  echo "$count new change(s) on GitHub:"
  git -C "$REPO" log --format='  %h %s (%an, %ad)' --date=short "HEAD..$new"

  untrusted="$(untrusted_commits "$REPO" HEAD "$new")"
  if [[ -n "$untrusted" ]]; then
    echo "Not signed by a key in $ALLOWED_SIGNERS:"
    printf '%s\n' "$untrusted" | sed 's/^/  /'
    if [[ "${STRICT:-1}" == 1 ]]; then
      needs+=("$(printf '%s\n' "$untrusted" | grep -c .) new change(s) are not signed by a key you trust. Run update to review them")
      return 2
    fi
    echo
    echo "What they change:"
    git -C "$REPO" --no-pager diff --stat "HEAD...$new"
    echo "See every line with: git -C $REPO log -p HEAD..$new"
    if ! ask "Apply these changes and run what they contain?"; then
      echo "Not applied. Nothing from GitHub ran."
      needs+=("changes on GitHub not applied")
      return 2
    fi
  fi

  # Your own commits not yet on GitHub are replayed on top of GitHub's.
  # Unattended, a tree with edits not saved in git is left alone.
  dirty="$(git -C "$REPO" status --porcelain --untracked-files=no)"
  if [[ "${STRICT:-1}" == 1 && -n "$dirty" ]]; then
    if ! git -C "$REPO" merge-base --is-ancestor HEAD "$new" || ! git -C "$REPO" merge -q --ff-only "$new" 2>/dev/null; then
      echo "Edits on this Mac (not saved in git) touch the same files, so nothing was applied:"
      printf '%s\n' "$dirty" | sed 's/^/  /'
      needs+=("your unsaved edits in $REPO block the update")
      return 2
    fi
  elif git -C "$REPO" merge-base --is-ancestor HEAD "$new"; then
    git -C "$REPO" merge -q --ff-only --autostash "$new" || {
      echo "Could not apply GitHub's changes."; needs+=("GitHub's changes could not be applied"); return 2; }
  else
    if ! git -C "$REPO" rebase -q --autostash "$new"; then
      git -C "$REPO" rebase --abort 2>/dev/null
      echo "Your changes clash with GitHub's. Kept yours; GitHub's were not applied."
      needs+=("your changes clash with GitHub's")
      return 2
    fi
  fi
  changed+=("$count change(s) from GitHub")
  echo "Applied $count change(s): now at $(git -C "$REPO" log -1 --format='%h %s')"
  return 0
}
