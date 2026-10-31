# shellcheck shell=bash
# Theme colours are now rendered from templates into
# ~/.local/state/grand-line/current/theme/. Applies the current theme once,
# so tmux, btop, lazygit and Claude Code get its colours too.
source "$GRAND_LINE_REPO/lib/bin-common.sh"

theme="$(cat "$GRAND_LINE_STATE/theme" 2>/dev/null)"
[[ -n "$theme" ]] || exit 0
# Paper was replaced by Daylight.
[[ -f "$GRAND_LINE_REPO/config/themes/$theme.theme" ]] || theme=daylight
GRAND_LINE_NO_APPLEEVENTS=1 "$GRAND_LINE_REPO/bin/theme" set "$theme" --no-wallpaper
