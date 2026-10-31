#!/usr/bin/env bash
# Makes a home-like folder for the journeys: the usual top-level folders, files
# of many kinds with names search and sort can work on, a Trash with items in
# it, a fake Google Drive, app-cache clutter that search must leave out, and
# the settings the notch app and the themes read.
#
#   bash tests/journeys/make-fixture.sh DIR
#
# DIR is emptied first. Every name is generic test data.

set -euo pipefail

dest="${1:?usage: make-fixture.sh DIR}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

case "$dest" in
  /|"$HOME"|"$HOME/") echo "make-fixture.sh: refusing to use $dest" >&2; exit 1 ;;
esac
rm -rf "$dest"
mkdir -p "$dest"
cd "$dest"

# A 1x1 PNG, so Quick Look and thumbnails have a real image.
png_b64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

# file PATH [BYTES]: a file with a line of text, padded to BYTES.
file() {
  local path="$1" bytes="${2:-0}"
  mkdir -p "$(dirname "$path")"
  printf 'Journey fixture: %s\n' "$(basename "$path")" > "$path"
  if [ "$bytes" -gt 0 ]; then
    head -c "$bytes" /dev/zero | tr '\0' 'x' >> "$path"
  fi
}

pdf() {
  mkdir -p "$(dirname "$1")"
  printf '%%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Kids [] /Count 0 >> endobj\ntrailer << /Root 1 0 R >>\n%%%%EOF\n' > "$1"
}

image() {
  mkdir -p "$(dirname "$1")"
  printf '%s' "$png_b64" | openssl base64 -d -A > "$1"
}

archive() {
  mkdir -p "$(dirname "$1")"
  if command -v zip >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp -d)"
    printf 'inside the archive\n' > "$tmp/inside.txt"
    (cd "$tmp" && zip -q "archive.zip" inside.txt)
    mv "$tmp/archive.zip" "$1"
    rm -rf "$tmp"
  else
    file "$1"
  fi
}

mkdir -p Desktop Documents Downloads Movies Music Pictures Public .Trash

# The project folder search is tested on: many kinds, names in several cases.
p="Documents/Projects/Conj Flap"
file "$p/Lid Study - CONJ.docx"
file "$p/conj_storyboard.pptx"
pdf  "$p/Conj Flap protocol.pdf"
file "$p/conj measurements.xlsx"
printf 'eye,width\nleft,4.1\nright,3.9\n' > "$p/conj data.csv"
file "$p/conj notes.txt"
image "$p/conj figure.png"
image "$p/conj photo.jpg"
file "$p/conj clip.mov" 2048
archive "$p/conj archive.zip"
printf 'x <- c(1, 2, 3)\nmean(x)\n' > "$p/conj_analysis.R"
printf 'def width(a, b):\n    return a - b\n' > "$p/conj_model.py"
file "$p/Drafts/v1/conj draft v1.docx"
file "$p/Drafts/v2/conj draft v2.docx"
file "Documents/Projects/Lid Repair/lid repair outline.docx"
file "Documents/Projects/Lid Repair/Drafts/lid outline v1.docx"
# Matches by content only: name matches must come before it.
mkdir -p "Documents/Meetings"
printf 'Agenda: conj flap results, next steps.\n' > "Documents/Meetings/meeting minutes.txt"

# Sorting: names, dates and sizes chosen so a single sort key mixes folders
# with files (Finder's default) and "Keep Folders on Top" visibly changes it.
s="Documents/Sorting"
file "$s/Alpha notes.txt" 1000
mkdir -p "$s/Bravo folder";  file "$s/Bravo folder/inside bravo.txt" 10
file "$s/Charlie data.csv" 50000
mkdir -p "$s/Delta folder";  file "$s/Delta folder/inside delta.txt" 10
file "$s/Echo slides.pptx" 5000
pdf  "$s/Foxtrot paper.pdf"
touch -t 202401051200 "$s/Alpha notes.txt"
touch -t 202403011200 "$s/Bravo folder"
touch -t 202402011200 "$s/Charlie data.csv"
touch -t 202301011200 "$s/Delta folder"
touch -t 202404011200 "$s/Echo slides.pptx"
touch -t 202201011200 "$s/Foxtrot paper.pdf"

# File operations happen here.
o="Documents/Journey Ops"
file "$o/notes.txt"
pdf  "$o/report.pdf"
file "$o/Move Me.txt"

# Enough other files that a search has something to skip.
for year in 2021 2022 2023 2024 2025; do
  for n in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20; do
    file "Documents/Archive/$year/record-$year-$n.txt"
  done
done

file "Desktop/Desktop conj sticky.txt"
file "Desktop/todo.txt"
mkdir -p "Desktop/Screenshots"
image "Desktop/Screenshots/screen 1.png"
pdf  "Downloads/conjunctiva review.pdf"
pdf  "Downloads/receipt.pdf"
archive "Downloads/sample data.zip"
image "Pictures/holiday.png"

# The Trash, so it can be opened and searched from.
file ".Trash/old conj draft.docx"
file ".Trash/trashed conj note.txt"
file ".Trash/scratch.txt"

# A Google Drive account as Drive for desktop mounts it.
d="Library/CloudStorage/GoogleDrive-journey@example.com"
file "$d/My Drive/Conj Drive notes.docx"
file "$d/My Drive/Shared plan.pdf"
mkdir -p "$d/Shared drives"

# App data that search must never show.
file "Library/Caches/com.example.app/conj-cache.db"
file "Library/Application Support/com.example.app/conj-state.json"
file ".cache/conj-junk.tmp"
file "Documents/Projects/Conj Flap/node_modules/conj-module/index.js"

# Theme and notch app settings, as setup leaves them.
mkdir -p .local/state/grand-line .grand-line/config .config/grand-line/iceberg/widgets
cp -R "$repo/config/themes" .grand-line/config/themes
printf 'graphite\n' > .local/state/grand-line/theme
cat > .config/grand-line/iceberg/iceberg.toml <<'EOF'
# Only the battery and one widget, so the panel shows exactly these sections
# and nothing asks for calendar or reminders access.
external_displays = "none"
open_on = "hover"
hover_delay = 0.1
close_delay = 0.3
live_activity = false
launch_at_login = false
builtin = ["battery"]
EOF
cat > .config/grand-line/iceberg/widgets/journey.toml <<'EOF'
title = "Journey"
icon = "checkmark.circle"
command = "echo journey-ok"
refresh = "on open"
EOF

echo "Fixture ready: $dest"
