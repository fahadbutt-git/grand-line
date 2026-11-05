# shellcheck shell=bash
# grandline:unattended
# The package no longer installs or updates the open-source office apps
# (WordCraft, GridCraft and DeckCraft from ArtCraft, and LibreOffice): Microsoft
# Word, Excel and PowerPoint are yours to install, and become the defaults for
# their documents once they are. FilmCraft and PdfCraft are still managed.
#
# Nothing is deleted or moved out of /Applications: copies already installed
# stay as they are. What the ArtCraft step remembered about the three apps
# (installed path, release, Team ID, refused release) moves aside, so nothing
# in the package reads it as an app it manages. Safe to run any number of times.
source "$GRAND_LINE_REPO/lib/bin-common.sh"

from="$GRAND_LINE_STATE/artcraft"
to="$GRAND_LINE_STATE/unmanaged/artcraft"
status=0
for app in WordCraft GridCraft DeckCraft; do
  for f in "$from/$app".*; do
    [[ -f "$f" ]] || continue
    [[ -e "$to/${f##*/}" ]] && continue   # an earlier run kept it already
    mkdir -p "$to" && mv "$f" "$to/" || status=1
  done
done

echo "Grand Line no longer installs or updates WordCraft, GridCraft, DeckCraft or LibreOffice; copies you have stay where they are, and Word, Excel and PowerPoint open documents once you install them."
exit "$status"
