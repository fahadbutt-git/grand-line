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

# The last commit from GitHub this Mac applied, per clone, one
# "git-dir<TAB>sha" line each. It is what a rewritten history is judged
# against, so a fetch made by anything else (grandline publish, lazygit,
# git pull) never hides a force-push.
UPSTREAM_APPLIED="${GRAND_LINE_UPSTREAM_APPLIED:-${GRAND_LINE_STATE:-$HOME/.local/state/grand-line}/upstream-applied}"
# What the unattended run last told you about, so it says it once.
UPDATE_TOLD="${GRAND_LINE_UPDATE_TOLD:-${GRAND_LINE_STATE:-$HOME/.local/state/grand-line}/update-told}"

# upstream_applied_get REPO: the recorded commit, or nothing.
upstream_applied_get() {
  local key; key="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  [[ -f "$UPSTREAM_APPLIED" ]] || return 1
  awk -F'\t' -v k="$key" '$1 == k { sha = $2 } END { if (sha == "") exit 1; print sha }' "$UPSTREAM_APPLIED"
}

# upstream_applied_set REPO SHA
upstream_applied_set() {
  local key tmp; key="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  mkdir -p "$(dirname "$UPSTREAM_APPLIED")" || return 1
  tmp="$UPSTREAM_APPLIED.$$"
  { [[ -f "$UPSTREAM_APPLIED" ]] && awk -F'\t' -v k="$key" '$1 != k' "$UPSTREAM_APPLIED"
    printf '%s\t%s\n' "$key" "$2"; } > "$tmp" && mv -f "$tmp" "$UPSTREAM_APPLIED"
}

# upstream_applied_seed REPO UPSTREAM: with no record yet (a Mac updated
# before the record existed), the newest value the remote-tracking ref had
# that this clone's HEAD contains, from that ref's reflog.
upstream_applied_seed() {
  local sha
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    git -C "$1" merge-base --is-ancestor "$sha" HEAD 2>/dev/null && { echo "$sha"; return 0; }
  done < <(git -C "$1" reflog show -n 50 --format=%H "$2" -- 2>/dev/null)
  return 1
}

# tell_once KEY MESSAGE: adds MESSAGE to needs, except that the unattended
# run (STRICT=1) leaves it out when it already told you about KEY.
tell_once() {
  if [[ "${STRICT:-1}" == 1 && "$(cat "$UPDATE_TOLD" 2>/dev/null)" == "$1" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$UPDATE_TOLD")" && printf '%s\n' "$1" > "$UPDATE_TOLD"
  needs+=("$2")
}

# package_update REPO: fetch, check every new commit, then apply them.
# Returns 0 when the package is current, 2 when something waits for you, 1
# when GitHub could not be reached. With STRICT=1 (no one at the keyboard)
# only trusted commits are applied, only by fast-forward (never a rebase, so
# no commit is rewritten or signed again), and nothing is asked. Adds to the
# caller's arrays changed (what it applied) and needs (what waits for you).
package_update() {
  local REPO="$1" branch upstream new count untrusted dirty applied head own
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || return 0
  branch="$(git -C "$REPO" branch --show-current)"
  upstream="$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || {
    echo "No GitHub copy to update from${branch:+ for branch $branch}."; return 0; }
  # Read before the fetch, so the reflog seed still sees the old value.
  applied="$(upstream_applied_get "$REPO")" || applied="$(upstream_applied_seed "$REPO" "$upstream")" || applied=""
  if ! git -C "$REPO" fetch -q "${upstream%%/*}"; then
    echo "Could not reach GitHub."; return 1
  fi
  new="$(git -C "$REPO" rev-parse -q --verify "$upstream^{commit}")" || return 1
  head="$(git -C "$REPO" rev-parse -q --verify HEAD)" || return 1

  count="$(git -C "$REPO" rev-list --count "HEAD..$new")"
  if [[ "$count" == 0 ]]; then
    upstream_applied_set "$REPO" "$new"
    echo "The package is up to date."
    return 0
  fi

  # GitHub's history only ever grows. When the last commit this Mac applied
  # from it is no longer in it, the history was rewritten, and nothing is
  # applied. (Once you have moved this clone off that commit yourself, it is
  # no longer what the update builds on.)
  if [[ -n "$applied" ]] && git -C "$REPO" merge-base --is-ancestor "$applied" HEAD 2>/dev/null \
     && ! git -C "$REPO" merge-base --is-ancestor "$applied" "$new" 2>/dev/null; then
    echo "GitHub's copy was rewritten (force-pushed): the commit this Mac last applied from it is gone, so nothing was applied. Check it before updating:"
    echo "  git -C $REPO log --oneline $applied...$new"
    echo "When you are sure, and have no changes of your own: git -C $REPO reset --keep $new"
    tell_once "rewritten $applied" "GitHub's copy was rewritten; check it before updating"
    return 2
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

  dirty="$(git -C "$REPO" status --porcelain --untracked-files=no)"
  if ! git -C "$REPO" merge-base --is-ancestor HEAD "$new"; then
    own="$(git -C "$REPO" rev-list --count "$new..HEAD")"
    if [[ "${STRICT:-1}" == 1 ]]; then
      # Putting your commits on top of GitHub's rewrites them, and with
      # commit signing on it would ask for your key. That waits for you.
      echo "This Mac has $own commit(s) of its own that GitHub does not have, so nothing was applied. Run update in a terminal to put them on top of GitHub's."
      tell_once "own-commits $head" "this Mac has commits of its own; run update in a terminal to apply GitHub's changes"
      return 2
    fi
    # Your own commits not yet on GitHub are replayed on top of GitHub's
    # (signed again, as you sign, so your other Macs still trust them).
    if ! git -C "$REPO" rebase -q --autostash "$new"; then
      git -C "$REPO" rebase --abort 2>/dev/null
      echo "Your changes clash with GitHub's. Kept yours; GitHub's were not applied."
      needs+=("your changes clash with GitHub's")
      return 2
    fi
  elif [[ "${STRICT:-1}" == 1 ]]; then
    # Unattended, edits not saved in git are never stashed or touched.
    if ! git -C "$REPO" merge -q --ff-only "$new" 2>/dev/null; then
      if [[ -n "$dirty" ]]; then
        echo "Edits on this Mac (not saved in git) touch the same files, so nothing was applied:"
        printf '%s\n' "$dirty" | sed 's/^/  /'
        needs+=("your unsaved edits in $REPO block the update")
      else
        echo "Could not apply GitHub's changes."; needs+=("GitHub's changes could not be applied")
      fi
      return 2
    fi
  else
    git -C "$REPO" merge -q --ff-only --autostash "$new" || {
      echo "Could not apply GitHub's changes."; needs+=("GitHub's changes could not be applied"); return 2; }
  fi
  upstream_applied_set "$REPO" "$new"
  rm -f "$UPDATE_TOLD"
  changed+=("$count change(s) from GitHub")
  echo "Applied $count change(s): now at $(git -C "$REPO" log -1 --format='%h %s')"
  return 0
}
