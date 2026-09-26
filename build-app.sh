#!/bin/sh
set -eu
cd "$(dirname "$0")"
SIGNING_IDENTITY="${GESTURE_CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    IDENTITIES=$(security find-identity -v -p codesigning)
    SIGNING_IDENTITY=$(printf '%s\n' "$IDENTITIES" | awk '/Apple Development:/ { print $2; exit }')
    if [ -z "$SIGNING_IDENTITY" ]; then
        SIGNING_IDENTITY=$(printf '%s\n' "$IDENTITIES" | awk '/^[[:space:]]*[0-9]+\)/ { print $2; exit }')
    fi
fi
if [ -z "$SIGNING_IDENTITY" ]; then
    printf '%s\n' 'No valid code-signing identity found. Install an Apple Development certificate or set GESTURE_CODESIGN_IDENTITY.' >&2
    exit 1
fi
swift build -c release
APP="build/Minority.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/GestureControl "$APP/Contents/MacOS/GestureControl"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" --identifier com.local.gesture-control "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "Built $APP"
