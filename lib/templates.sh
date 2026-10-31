# shellcheck shell=bash
# Theme templates, as in Omarchy: every file in config/themed/NAME.tpl is
# rendered to NAME with the active theme's values. A {{ KEY }} placeholder
# takes any KEY= line of the theme file, plus NAME (the theme's file name)
# and COLOR0 to COLOR15 (the PALETTE, in order). Values are bare hex, so a
# template writes #{{ TERM_BG }} where the app wants a leading #.
# Sourced by bin/theme and the tests.

# render_templates THEME_FILE NAME OUT_DIR TEMPLATE_DIR...
# A template in an earlier folder wins over one of the same name in a later
# folder, so pass the user's folder first. One awk process renders them all.
render_templates() {
  local theme="$1" name="$2" out="$3" dir tpl base seen=" "
  local pairs=()
  shift 3
  for dir in "$@"; do
    for tpl in "$dir"/*.tpl; do
      [[ -f "$tpl" ]] || continue
      base="${tpl##*/}"; base="${base%.tpl}"
      [[ "$seen" == *" $base "* ]] && continue
      seen="$seen$base "
      pairs+=("$tpl" "$out/$base")
    done
  done
  mkdir -p "$out" || return 1
  [[ ${#pairs[@]} -gt 0 ]] || return 0
  awk -v theme="$theme" -v name="$name" '
    function render(line,    out, open, stop, token) {
      out = ""
      while ((open = index(line, "{{")) > 0) {
        stop = index(substr(line, open + 2), "}}")
        if (stop == 0) break
        token = substr(line, open + 2, stop - 1)
        gsub(/^[ \t]+|[ \t]+$/, "", token)
        if (token in values) out = out substr(line, 1, open - 1) values[token]
        else out = out substr(line, 1, open + stop + 2)
        line = substr(line, open + stop + 3)
      }
      return out line
    }
    BEGIN {
      values["NAME"] = name
      while ((getline row < theme) > 0) {
        if (row !~ /^[A-Z_][A-Z0-9_]*=/) continue
        key = substr(row, 1, index(row, "=") - 1)
        value = substr(row, index(row, "=") + 1)
        sub(/[ \t]+#.*$/, "", value)
        gsub(/^"|"$/, "", value)
        values[key] = value
      }
      close(theme)
      n = split(values["PALETTE"], colours, " ")
      for (i = 1; i <= n; i++) values["COLOR" (i - 1)] = colours[i]
      for (i = 1; i < ARGC; i += 2) {
        template = ARGV[i]; output = ARGV[i + 1]
        printf "" > output
        while ((getline line < template) > 0) print render(line) > output
        close(template); close(output)
      }
      exit
    }' "${pairs[@]}"
}
