# shellcheck shell=bash
# Your own details: name, email, email sign-off and signature, and the place
# the weather notice reports. They live only on this Mac, in
# ~/.config/grand-line/personal.env, never in the repo. Setup asks for them
# once; edit the file to change them, then run `grandline update`.
#
# The file is KEY=value lines. In SIGNATURE, \n starts a new line.

PERSONAL_FILE="${GRAND_LINE_PERSONAL:-$HOME/.config/grand-line/personal.env}"

# personal_get KEY: print its value, or nothing.
personal_get() {
  [[ -f "$PERSONAL_FILE" ]] || return 0
  local v
  v="$(sed -n "s/^$1=//p" "$PERSONAL_FILE" | tail -1)"
  v="${v#\"}"; v="${v%\"}"
  printf '%s' "$v"
}

# personal_ask: ask for each detail once, when someone is at the keyboard.
# Nothing is asked in a dry run, on CI, or when the file already exists.
personal_ask() {
  [[ -f "$PERSONAL_FILE" || "${DRY_RUN:-0}" == 1 || ! -t 0 ]] && return 0
  local name email signoff signature line place lat lon found
  printf '\nA few details for your git commits, email shortcuts and weather.\n'
  printf 'They stay on this Mac only. Press Return to skip any of them.\n\n'
  read -r -p "  Full name: " name
  read -r -p "  Email for git commits: " email
  read -r -p "  First name for the ;br sign-off [${name%% *}]: " signoff
  signoff="${signoff:-${name%% *}}"
  printf '  Signature for ;sig, one line at a time, empty line to finish:\n'
  signature=""
  while read -r -p "    " line && [[ -n "$line" ]]; do
    signature="${signature:+$signature\\n}$line"
  done
  read -r -p "  Town or city for the weather: " place
  if [[ -n "$place" ]]; then
    # Open-Meteo's geocoder (free, no account) turns the name into coordinates.
    found="$(curl -fsS --max-time 8 -G "https://geocoding-api.open-meteo.com/v1/search" \
      --data-urlencode "name=$place" --data count=1 2>/dev/null \
      | jq -r '.results[0] | "\(.latitude) \(.longitude)"' 2>/dev/null)"
    read -r lat lon <<<"$found"
    if [[ ! "$lat" =~ ^-?[0-9.]+$ ]]; then
      read -r -p "  Could not look that up. Latitude and longitude (e.g. 51.5 -0.13): " lat lon
    fi
  fi
  mkdir -p "$(dirname "$PERSONAL_FILE")"
  ( umask 077
    {
      echo "# Your details, used by setup only on this Mac. Edit, then run: grandline update"
      echo "NAME=$name"
      echo "EMAIL=$email"
      echo "SIGNOFF=$signoff"
      echo "SIGNATURE=$signature"
      echo "LOCATION=${lat:+$lat $lon $place}"
    } > "$PERSONAL_FILE" )
  printf '\n  Saved to %s\n\n' "$PERSONAL_FILE"
}

# personal_espanso FILE: write the email shortcuts from your details.
# Writes nothing (and removes an old copy) when there are none.
personal_espanso() {
  local out="$1" signoff signature
  signoff="$(personal_get SIGNOFF)"; signature="$(personal_get SIGNATURE)"
  if [[ -z "$signoff$signature" ]]; then
    [[ -f "$out" ]] && move_to_trash "$out"
    return 0
  fi
  {
    echo "# Written by setup from $PERSONAL_FILE. Change that file, not this one."
    echo "matches:"
    [[ -n "$signoff" ]] && printf '  - trigger: ";br"\n    replace: "Best regards,\\n%s"\n' "${signoff//\"/\\\"}"
    [[ -n "$signature" ]] && printf '  - trigger: ";sig"\n    replace: "%s"\n' "${signature//\"/\\\"}"
  } > "$out"
}
