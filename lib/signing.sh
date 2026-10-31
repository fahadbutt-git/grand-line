# shellcheck shell=bash
# A stable code-signing identity for the package's own apps (Nexus, Sight,
# Iceberg), so macOS permissions (Accessibility, Calendars, Automation)
# survive every rebuild.
#
# macOS ties a permission to an app's "designated requirement". An ad-hoc
# signature's requirement is the hash of that one build, so every rebuild
# looks like a new app and the permissions are asked for again. Signed with
# this identity, the requirement names the certificate instead:
#   identifier "com.grandline.sight" and certificate leaf = H"<sha1>"
# so a rebuild keeps them.
#
# What protects the permissions is the private key, so it is kept apart:
#   - its own keychain, ~/Library/Keychains/grand-line-signing.keychain-db,
#     locked after each use and after 5 minutes, never in the search list
#   - the keychain password is random and stored only in the login keychain
#   - the key is imported non-extractable (it cannot be exported) and its
#     partition list allows only Apple's own tools, so of the programs on the
#     Mac only /usr/bin/codesign signs with it
#   - the certificate is for code signing only, trusted for that by this user
# Passwords are given to the security tool on its standard input, never on a
# command line, where any account could read them with ps.
# A process running as you can still ask security and codesign to sign, as
# the package's own update does. That is why the unattended update builds only
# signature-checked commits from a clean tree (bin/update, lib/update-trust.sh).
#
# signing_ensure and signing_create need lib/common.sh (run, ok, warn, info,
# have, move_to_trash); the rest needs nothing else, so commands can use it.

SIGN_NAME="Grand Line Local Signing"
SIGN_KEYCHAIN="${GRAND_LINE_SIGN_KEYCHAIN:-$HOME/Library/Keychains/grand-line-signing.keychain-db}"
SIGN_LOGIN_KEYCHAIN="${GRAND_LINE_LOGIN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
SIGN_SERVICE="grand-line-signing-keychain"
SIGN_DAYS=3650

# The OpenSSL to make the key with: Apple's LibreSSL, then any other.
signing_openssl() {
  if [[ -x /usr/bin/openssl ]]; then echo /usr/bin/openssl; else command -v openssl; fi
}

# signing_identity: print the identity's SHA-1 (as codesign takes it), or
# fail when there is none. Reading certificates needs no password.
signing_identity() {
  [[ -f "$SIGN_KEYCHAIN" ]] && command -v security >/dev/null 2>&1 || return 1
  local hash
  hash="$(security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null \
    | awk -v n="\"$SIGN_NAME\"" 'index($0, n) && $2 ~ /^[0-9A-Fa-f]{40}$/ { print $2; exit }')"
  [[ -n "$hash" ]] || return 1
  printf '%s\n' "$hash" | tr 'a-f' 'A-F'
}

# security_stdin: run security commands given on standard input, one per
# line, so passwords never appear in a process list.
security_stdin() {
  security -i >/dev/null 2>&1
}

signing_password() {
  security find-generic-password -a "$(id -un)" -s "$SIGN_SERVICE" -w "$SIGN_LOGIN_KEYCHAIN" 2>/dev/null
}

signing_unlock() {
  local pw
  pw="$(signing_password)" || return 1
  [[ -n "$pw" ]] || return 1
  printf 'unlock-keychain -p %s "%s"\n' "$pw" "$SIGN_KEYCHAIN" | security_stdin
}

signing_lock() {
  [[ -f "$SIGN_KEYCHAIN" ]] && command -v security >/dev/null 2>&1 && security lock-keychain "$SIGN_KEYCHAIN" >/dev/null 2>&1
  return 0
}

# signing_create: make the keychain, key and certificate. Only setup run by
# you calls it (never the unattended update): a new identity means each app
# asks for its permissions once more.
signing_create() {
  local ssl work pw p12pw status=1
  ssl="$(signing_openssl)" || return 1
  [[ -n "$ssl" ]] || return 1
  work="$(umask 077 && mktemp -d)" || return 1
  pw="$("$ssl" rand -hex 32)" && p12pw="$("$ssl" rand -hex 16)" || { rm -rf "$work"; return 1; }
  cat > "$work/req.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $SIGN_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  (
    umask 077
    cd "$work" || exit 1
    "$ssl" req -x509 -newkey rsa:3072 -sha256 -nodes -days "$SIGN_DAYS" -config req.cnf \
      -keyout key.pem -out cert.pem >/dev/null 2>&1 || exit 1
    # The older PKCS#12 format, which the security tool reads with any OpenSSL.
    export P12PW="$p12pw"
    "$ssl" pkcs12 -export -name "$SIGN_NAME" -inkey key.pem -in cert.pem -out id.p12 -passout env:P12PW \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1 \
      || "$ssl" pkcs12 -export -name "$SIGN_NAME" -inkey key.pem -in cert.pem -out id.p12 -passout env:P12PW >/dev/null 2>&1
  ) || { rm -rf "$work"; return 1; }

  # The password goes to the login keychain first, so a keychain is never
  # made that nothing can open.
  {
    printf 'add-generic-password -U -a "%s" -s %s -l "%s" -T /usr/bin/security -w %s "%s"\n' \
      "$(id -un)" "$SIGN_SERVICE" "Grand Line signing keychain" "$pw" "$SIGN_LOGIN_KEYCHAIN"
    printf 'create-keychain -p %s "%s"\n' "$pw" "$SIGN_KEYCHAIN"
    printf 'unlock-keychain -p %s "%s"\n' "$pw" "$SIGN_KEYCHAIN"
    printf 'import "%s" -k "%s" -f pkcs12 -x -T /usr/bin/codesign -P %s\n' "$work/id.p12" "$SIGN_KEYCHAIN" "$p12pw"
    printf 'set-key-partition-list -S apple-tool:,apple: -s -k %s "%s"\n' "$pw" "$SIGN_KEYCHAIN"
  } | security_stdin
  # Locks after 5 minutes unused and when the Mac sleeps.
  security set-keychain-settings -l -u -t 300 "$SIGN_KEYCHAIN" >/dev/null 2>&1
  if signing_identity >/dev/null; then
    status=0
    # Trusted for code signing by this user only. macOS asks for your
    # password to change trust, so only when you are at the keyboard.
    if [[ "$CI_MODE" != 1 && "${GRAND_LINE_UNATTENDED:-0}" != 1 && -t 0 ]]; then
      info "macOS may ask for your password to trust the package's signing certificate."
      security add-trusted-cert -p codeSign -k "$SIGN_KEYCHAIN" "$work/cert.pem" >/dev/null 2>&1 \
        || info "The certificate was not marked trusted. Signing works without it."
    fi
  fi
  signing_lock
  rm -rf "$work"
  return "$status"
}

# signing_ensure: the identity, made once. Prints nothing when it exists.
# Fails when there is none and none could be made; the apps are then signed
# ad hoc, as before, and ask for their permissions after each rebuild.
signing_ensure() {
  if [[ "$DRY_RUN" == 1 ]]; then
    run "create the code-signing identity \"$SIGN_NAME\" in $SIGN_KEYCHAIN (once)"
    return 0
  fi
  have security && have codesign || return 1
  signing_identity >/dev/null && return 0
  [[ "${GRAND_LINE_UNATTENDED:-0}" == 1 ]] && return 1
  # A keychain from a run that stopped half way holds no usable key.
  if [[ -e "$SIGN_KEYCHAIN" ]]; then
    security delete-generic-password -a "$(id -un)" -s "$SIGN_SERVICE" "$SIGN_LOGIN_KEYCHAIN" >/dev/null 2>&1
    move_to_trash "$SIGN_KEYCHAIN"
  fi
  if signing_create; then
    ok "Made the code-signing identity \"$SIGN_NAME\" (apps keep their permissions across updates)"
    return 0
  fi
  warn "Could not make the code-signing identity. The apps are signed ad hoc and ask for their permissions again after each update."
  return 1
}

# sign_code PATH [ENTITLEMENTS] [BUNDLE ID]: sign with hardened runtime, with
# the identity when there is one, otherwise ad hoc. With a bundle id, the
# designated requirement pins the certificate itself (its hash, not its name).
sign_code() {
  local path="$1" ent="${2:-}" id="${3:-}" hash args
  args=(--force --options runtime)
  [[ -n "$ent" && -f "$ent" ]] && args+=(--entitlements "$ent")
  if hash="$(signing_identity)"; then
    signing_unlock || return 1
    args+=(--timestamp=none --keychain "$SIGN_KEYCHAIN" --sign "$hash")
    [[ -n "$id" ]] && args+=(-r "=designated => identifier \"$id\" and certificate leaf = H\"$(printf '%s' "$hash" | tr 'A-F' 'a-f')\"")
  else
    args+=(--sign -)
  fi
  codesign "${args[@]}" "$path" >/dev/null 2>&1
}

# signing_check APP: hardened runtime is on and, when the identity exists,
# the designated requirement names its certificate. Prints what is wrong.
signing_check() {
  local app="$1" hash detail req
  detail="$(codesign -d --verbose=2 "$app" 2>&1)"
  if ! printf '%s\n' "$detail" | grep -qE 'flags=0x[0-9a-f]+\([^)]*runtime'; then
    echo "$app is not signed with hardened runtime"; return 1
  fi
  hash="$(signing_identity)" || return 0
  hash="$(printf '%s' "$hash" | tr 'A-F' 'a-f')"
  req="$(codesign -d -r- "$app" 2>&1)"
  case "$req" in
    *"certificate leaf = H\"$hash\""*|*"certificate root = H\"$hash\""*) return 0 ;;
  esac
  echo "$app is not signed with \"$SIGN_NAME\": $req"
  return 1
}
