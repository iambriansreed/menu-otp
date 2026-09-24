#!/bin/sh
# VoiceOver checks: opens the demo app's Settings and reads it the way VoiceOver does,
# from another process, through the accessibility API (app/scripts/a11y-check.swift).
#
# This can't be part of --self-test: SwiftUI only builds the accessibility elements for
# its own controls once an outside assistive client starts asking, so the app looking
# at itself sees just the few AppKit-backed views.
#
# Needs the terminal running it to be allowed under System Settings → Privacy &
# Security → Accessibility (the checker says so and exits 3 if it isn't), so it can't
# run in CI. Like --self-test it opens windows and takes focus while it runs.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! BUILD_LOG="$("$ROOT/scripts/bundle.sh" debug 2>&1)"; then
    echo "$BUILD_LOG" >&2
    exit 1
fi
CHECKER="$ROOT/build/a11y-check"
swiftc -O -o "$CHECKER" "$ROOT/scripts/a11y-check.swift"

# Its own demo data directory (and so its own instance lock), fresh each run
export MENU_OTP_DEMO_DATA_DIR="${TMPDIR:-/tmp}/menu-otp-demo-a11y"
export MENU_OTP_DEMO_FILE="${MENU_OTP_DEMO_FILE:-$ROOT/scripts/demo-data.txt}"
rm -rf "$MENU_OTP_DEMO_DATA_DIR"
APP="$ROOT/build/Menu OTP.app/Contents/MacOS/MenuOTP"

"$APP" >/dev/null 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT INT TERM
"$CHECKER" --ready "$PID"
# A second launch finds the first holding the lock and asks it to open Settings, the
# same path as opening the app again from Finder
"$APP" >/dev/null 2>&1
"$CHECKER" "$PID"
