#!/bin/sh
# Installs (or updates) Menu OTP from its latest GitHub release:
#
#   sh <(curl -fsSL https://otp.iambrian.com/install.sh)
#
# It downloads the .dmg, checks it against the SHA-256 GitHub publishes for it, copies
# the app into /Applications (quitting a running copy first), clears the quarantine
# flag that would otherwise make macOS block the unnotarized app, and opens it.
#
# Environment, for testing without touching the real app:
#   MENU_OTP_INSTALL_DIR   install somewhere other than /Applications
#   MENU_OTP_NO_OPEN=1     don't open the app afterwards
set -eu

REPO="iambriansreed/menu-otp"
APP_NAME="Menu OTP"
INSTALL_DIR="${MENU_OTP_INSTALL_DIR:-/Applications}"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"

say() { printf '%s\n' "$*"; }
fail() {
    printf 'Menu OTP install failed: %s\n' "$*" >&2
    exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "Menu OTP is a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Menu OTP needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."

# Everything temporary goes here, and goes away however the script ends, including a
# mounted disk image
work="$(mktemp -d)"
mounted=""
cleanup() {
    if [ -n "$mounted" ]; then hdiutil detach -quiet "$mounted" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

say "Finding the latest release..."
release="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")" ||
    fail "couldn't reach GitHub."
# The JSON is read with sed rather than jq, which macOS doesn't ship. Each value this
# needs is on its own line in GitHub's pretty-printed response.
url="$(printf '%s\n' "$release" | sed -n 's/.*"browser_download_url": *"\([^"]*\.dmg\)".*/\1/p' | head -1)"
digest="$(printf '%s\n' "$release" | sed -n 's/.*"digest": *"sha256:\([0-9a-f]*\)".*/\1/p' | head -1)"
tag="$(printf '%s\n' "$release" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$url" ] || fail "the latest release has no .dmg."

say "Downloading $APP_NAME ${tag#v}..."
curl -fsSL -o "$work/MenuOTP.dmg" "$url" || fail "the download failed."

# GitHub computes this digest itself when the release asset is uploaded. A mismatch
# means a corrupted or tampered download; never install that.
if [ -n "$digest" ]; then
    actual="$(shasum -a 256 "$work/MenuOTP.dmg" | cut -d' ' -f1)"
    [ "$actual" = "$digest" ] || fail "the download's checksum doesn't match GitHub's ($actual, expected $digest)."
    say "Checksum verified."
else
    say "GitHub published no checksum for this release; skipping verification."
fi

# Mounted out of sight (no Finder window, no desktop icon) at a folder of our own
mounted="$work/mount"
mkdir "$mounted"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mounted" "$work/MenuOTP.dmg" ||
    { mounted=""; fail "couldn't open the disk image."; }
[ -d "$mounted/$APP_NAME.app" ] || fail "the disk image has no $APP_NAME.app."

# A running copy of *this* app would keep using the old binary while its files are
# replaced. Matched by its full path, so a copy running from anywhere else (a
# developer's demo build, a test install) is left alone.
BINARY="$APP_PATH/Contents/MacOS/MenuOTP"
# pgrep never matches itself; -f compares the whole command line, anchored at its start
is_running() { pgrep -qf "^$BINARY"; }
if is_running; then
    say "Quitting the running $APP_NAME..."
    osascript -e "tell application \"$APP_PATH\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        is_running || break
        sleep 0.5
    done
fi

# /Applications is writable by admin accounts; anyone else is asked for a password
SUDO=""
mkdir -p "$INSTALL_DIR" 2>/dev/null || true
if [ ! -w "$INSTALL_DIR" ]; then
    say "Installing into $INSTALL_DIR needs an administrator password."
    SUDO="sudo"
fi

say "Installing to $APP_PATH..."
$SUDO rm -rf "$APP_PATH"
$SUDO ditto "$mounted/$APP_NAME.app" "$APP_PATH"
# The app isn't notarized, so a quarantined copy is blocked at first launch. curl
# doesn't set the flag, but a copy that was downloaded in a browser before might
# still carry it.
$SUDO xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

say "Installed $APP_NAME ${tag#v}."
if [ "${MENU_OTP_NO_OPEN:-}" != "1" ]; then
    open "$APP_PATH"
    say "It's in your menu bar. Choose \"$APP_NAME Settings...\" there to add accounts."
fi
