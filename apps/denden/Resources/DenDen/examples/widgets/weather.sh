#!/bin/sh
# Prints {"text","icon"} for Den Den: the temperature and the sky now.
# Location: LOCATION="lat lon Place" in ~/.config/grand-line/personal.env.
# Setup asks for your town once, the first time it runs (lib/personal.sh); no
# command asks again, so to add it later put a line like
# LOCATION="51.5 -0.13 London" in that file. Nothing about the place is stored here.
set -f

loc=""
env_file="$HOME/.config/grand-line/personal.env"
if [ -f "$env_file" ]; then
  loc=$(sed -n 's/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}LOCATION=//p' "$env_file" | tail -n 1 | tr -d "\"'")
fi

# shellcheck disable=SC2086 # split "lat lon Place" into words on purpose
set -- $loc
if [ $# -lt 2 ]; then
  echo '{"text":"Add your town","icon":"location.slash","color":"muted"}'
  exit 0
fi
lat=$1
lon=$2
case "$lat$lon" in
  *[!0-9.-]*) echo '{"text":"Bad LOCATION","icon":"location.slash","color":"muted"}'; exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || { echo '{"text":"Needs jq","icon":"exclamationmark.triangle","color":"muted"}'; exit 0; }

json=$(curl -fsS --max-time 8 "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code,is_day&timezone=auto" 2>/dev/null) || {
  echo '{"text":"Offline","icon":"wifi.slash","color":"muted"}'
  exit 0
}
temp=$(printf '%s' "$json" | jq -r '.current.temperature_2m | round')
code=$(printf '%s' "$json" | jq -r '.current.weather_code')
day=$(printf '%s' "$json" | jq -r '.current.is_day')

# WMO weather codes, as in the package's own weather notice.
if [ "$code" -eq 0 ] 2>/dev/null; then sky="clear"; icon="sun.max"; [ "$day" = 0 ] && icon="moon.stars"
elif [ "$code" -le 3 ] 2>/dev/null; then sky="cloudy"; icon="cloud.sun"; [ "$day" = 0 ] && icon="cloud.moon"
elif [ "$code" -le 48 ] 2>/dev/null; then sky="fog"; icon="cloud.fog"
elif [ "$code" -le 67 ] 2>/dev/null; then sky="rain"; icon="cloud.rain"
elif [ "$code" -le 77 ] 2>/dev/null; then sky="snow"; icon="cloud.snow"
elif [ "$code" -le 82 ] 2>/dev/null; then sky="showers"; icon="cloud.heavyrain"
elif [ "$code" -le 86 ] 2>/dev/null; then sky="snow"; icon="cloud.snow"
else sky="storms"; icon="cloud.bolt.rain"
fi

printf '{"text":"%s°C %s","icon":"%s"}\n' "$temp" "$sky" "$icon"
