# shellcheck shell=bash
# grandline:unattended
# Code now lives in ~/Code instead of ~/Developer (setup makes ~/Code). An
# empty ~/Developer goes to the Trash. One with anything in it, even hidden
# files, is left exactly as it is, with one line suggesting its contents move
# to ~/Code. Nothing is deleted. Safe to run any number of times.
source "$GRAND_LINE_REPO/lib/bin-common.sh"

old="$HOME/Developer"
# Only a real folder: a link someone made is theirs to keep.
[[ -d "$old" && ! -L "$old" ]] || exit 0
# A folder that cannot be read counts as not empty.
contents="$(ls -A "$old" 2>/dev/null)" || contents="unreadable"
if [[ -z "$contents" ]]; then
  move_to_trash "$old" && echo "Moved the empty ~/Developer folder to the Trash. Code now lives in ~/Code."
  exit
fi
echo "Code now lives in ~/Code, but ~/Developer still has files in it: move them to ~/Code when convenient."
exit 0
