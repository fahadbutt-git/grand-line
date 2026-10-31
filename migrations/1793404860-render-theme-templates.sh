# shellcheck shell=bash
# Theme colours are now rendered from templates into
# ~/.local/state/mac-setup/current/theme/. Applies the current theme once,
# so tmux, btop, lazygit and Claude Code get its colours too.
source "$MAC_SETUP_REPO/lib/bin-common.sh"

theme="$(cat "$MAC_SETUP_STATE/theme" 2>/dev/null)"
[[ -n "$theme" ]] || exit 0
# Paper was replaced by Daylight.
[[ -f "$MAC_SETUP_REPO/config/themes/$theme.theme" ]] || theme=daylight
MAC_SETUP_NO_APPLEEVENTS=1 "$MAC_SETUP_REPO/bin/theme" set "$theme" --no-wallpaper
