# shellcheck shell=bash
# grandline:unattended
# Iceberg has a Pomodoro timer, and a new install shows it in the panel.
# On a Mac set up earlier whose iceberg.toml lists what the panel shows
# (panel = [...]), this adds "pomodoro" to that list, after "today" (or at
# the end when "today" is not there). Only that list changes: every other
# line, and your comments, stay as they are. A file without a panel list
# already shows the new default, and a list that names "pomodoro" is left
# alone, so it is safe to run again. Turn it off in Iceberg's Settings.
source "$GRAND_LINE_REPO/lib/bin-common.sh"

file="$HOME/.config/grand-line/iceberg/iceberg.toml"
[[ -f "$file" ]] || exit 0

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

# The first top-level panel = [...] (one line or several). Names have no
# brackets in them, so the list ends at the first "]".
perl -0777 -pe '
  s{^([ \t]*panel[ \t]*=[ \t]*\[)([^\]]*)\]}{
    my ($head, $body) = ($1, $2);
    if ($body =~ /(["\x27])pomodoro\1/) { }
    elsif ($body =~ /(["\x27])today\1/) { $body =~ s/(["\x27])today\1/$1today$1, "pomodoro"/; }
    elsif ($body =~ /["\x27]/) { $body =~ s/(.*["\x27])/$1, "pomodoro"/s; }
    else { $body = "\"pomodoro\"" . $body; }
    "$head$body]";
  }me;
' < "$file" > "$work/new" || exit 1

if cmp -s "$file" "$work/new"; then exit 0; fi
# Written through the file itself, so a link to it stays a link.
cat "$work/new" > "$file" || exit 1
echo "Iceberg shows the new Pomodoro timer in the panel (turn it off in Iceberg's Settings)"
