#!/bin/sh
# Builds once, then snapshots every screen in light and dark into <dir> (default: snapshots/).
# Usage: scripts/snap.sh [dir] [screens...]   e.g. scripts/snap.sh /tmp/snaps inbox thread
set -e
cd "$(dirname "$0")/.."
out="${1:-snapshots}"
[ $# -gt 0 ] && shift
screens="${*:-signin inbox rows toast empty thread thread-selected thread-long palette-thread search-loading html html-images html-wide attachments labels invite reply reply-quotes quotes quotes-expanded quotes-text quotes-text-expanded compose compose-draft palette search sidebar calendar account-menu account-menu-photo account-switcher settings settings-account settings-account-photo settings-signature settings-appearance settings-shortcuts integrations notion-save notion-link syncing loading loading-empty loading-indeterminate synced offline syncfailed signedout}"
mkdir -p "$out"
swift build --product Mail
bin="$(swift build --product Mail --show-bin-path)/Mail"
for screen in $screens; do
  window="${MAIL_WINDOW:-1280x800}"
  [ "$screen" = html-wide ] && window="${MAIL_WINDOW:-1100x700}"
  for theme in light dark; do
    MAIL_DEMO=1 MAIL_SCREEN="$screen" MAIL_THEME="$theme" MAIL_SNAPSHOT="$out/$screen-$theme.png" \
      MAIL_WINDOW="$window" "$bin"
    echo "$out/$screen-$theme.png"
  done
done
