# shellcheck shell=bash
# When a file arrived where it is, for the rules that act on age (the
# Downloads sorter, the first-open check after installs).
#
# The modification time is never used: it travels with the file. Archive
# Utility, ditto, AirDrop, installers and `curl -R` all keep the time the file
# had elsewhere, so a file that arrived a minute ago can look years old.
# macOS records the moment an item was added to its folder
# (kMDItemDateAdded, set again when it is moved into another folder). When
# that is not known, the inode's change time stands in: it is set whenever
# the file is created, written, renamed or has its attributes changed, cannot
# be set back by any program, and is never earlier than the file's birth
# time, so it can only make a file look younger than it is, never older.

# file_changed PATH: the inode change time, in seconds since 1970.
file_changed() {
  perl -e 'my @s = lstat shift or exit 1; print $s[10], "\n"' "$1"
}

# date_added PATH: when PATH arrived in its folder, in seconds since 1970.
date_added() {
  local raw t
  raw="$(mdls -raw -name kMDItemDateAdded "$1" 2>/dev/null)"
  # mdls prints "2026-10-31 09:15:02 +0000", or "(null)" when not known.
  t="$(perl -MTime::Local -e '
    my ($s) = @ARGV;
    $s =~ /^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d) ([+-])(\d\d)(\d\d)$/ or exit 1;
    my $t = timegm($6, $5, $4, $3, $2 - 1, $1);
    my $off = ($8 * 3600 + $9 * 60) * ($7 eq "-" ? -1 : 1);
    print $t - $off, "\n";' "$raw" 2>/dev/null)"
  if [[ "$t" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$t"
    return 0
  fi
  file_changed "$1"
}
