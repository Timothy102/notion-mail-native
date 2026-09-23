#!/bin/sh
# Builds once, then snapshots every screen in light and dark into <dir> (default: snapshots/).
# Usage: scripts/snap.sh [dir] [screens...]   e.g. scripts/snap.sh /tmp/snaps inbox thread
set -e
cd "$(dirname "$0")/.."
out="${1:-snapshots}"
[ $# -gt 0 ] && shift
screens="${*:-inbox rows toast empty thread thread-selected thread-long palette-thread search-loading html attachments labels invite reply compose compose-draft palette search sidebar calendar settings integrations notion-save notion-link syncing offline syncfailed}"
mkdir -p "$out"
swift build --product Mail
bin="$(swift build --product Mail --show-bin-path)/Mail"
for screen in $screens; do
  for theme in light dark; do
    MAIL_DEMO=1 MAIL_SCREEN="$screen" MAIL_THEME="$theme" MAIL_SNAPSHOT="$out/$screen-$theme.png" \
      MAIL_WINDOW="${MAIL_WINDOW:-1280x800}" "$bin"
    echo "$out/$screen-$theme.png"
  done
done
