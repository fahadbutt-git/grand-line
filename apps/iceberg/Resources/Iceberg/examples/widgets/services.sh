#!/bin/sh
# Prints {"text","icon","color"} for Iceberg: Docker and Ollama on or off.
# Docker's state is the flag file bin/toggle keeps; Ollama runs as the
# launchd job grand-line.ollama (see lib/toggle-state.sh).
flags="$HOME/.local/state/grand-line/toggles"

docker=off
[ -f "$flags/docker" ] && docker=on
ollama=off
launchctl list grand-line.ollama >/dev/null 2>&1 && ollama=on

color=muted
icon=shippingbox
if [ "$docker" = on ] || [ "$ollama" = on ]; then
  color=highlight
  icon=shippingbox.fill
fi
printf '{"text":"Docker %s, AI %s","icon":"%s","color":"%s"}\n' "$docker" "$ollama" "$icon" "$color"
