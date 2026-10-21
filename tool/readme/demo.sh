#!/usr/bin/env bash
#
# README demo GIF without touching the mouse or keyboard (conventions/readme-guide.md §4). macOS only.
#
#   tool/readme/demo.sh
#
# Snapdock can't film its own overlay or dock (they are excluded from capture on purpose), and clicking
# through a flow needs someone at the keyboard. Instead a DEBUG build plays the dock's usage by itself —
# new captures arrive, the thumbnails change size, the dock folds into a pill and back
# (lib/dev/demo_runner.dart) — while the system's `screencapture` films a strip at the top of the screen.
# Every capture in it is a sample picture drawn by demo_assets.py.
#
# The app runs as a copy with its own bundle id, so your real Snapdock, its settings and its captures
# are left alone. A neutral backdrop covers the filmed strip so nothing behind it is recorded.
# Needs Screen Recording permission for the terminal app, ffmpeg, Pillow, and Xcode.
#
# From jejezz/application-release-templates common/ @ conventions-v1, extended for Snapdock.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$root/tool/readme"
app_id="art.zoomon.snapdock.demo"
seconds=16      # filmed; the demo itself plays for about 14 s after the backdrop is up
keep=13.4       # seconds of it kept: the backdrop stays up for a few seconds past the end, then goes
work="$(mktemp -d)"
store="$HOME/Library/Application Support/$app_id/captures"
pid=""

cleanup() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  defaults delete "$app_id" >/dev/null 2>&1 || true
  rm -rf "${store:?}" "${work:?}"
  rmdir "$HOME/Library/Application Support/$app_id" 2>/dev/null || true
}
trap cleanup EXIT

cd "$root"
echo "building the debug app…"
flutter build macos --debug >/dev/null
cp -R build/macos/Build/Products/Debug/Snapdock.app "$work/Snapdock-demo.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $app_id" "$work/Snapdock-demo.app/Contents/Info.plist"
codesign --force --deep -s - "$work/Snapdock-demo.app" >/dev/null 2>&1

python3 "$here/demo_assets.py" "$store" "$work/samples" --count 4
rect="$(swift "$here/demo_rect.swift" 760 150)"
echo "filming $rect"

defaults write "$app_id" flutter.theme_mode -string light
defaults write "$app_id" flutter.app_locale -string en
defaults write "$app_id" flutter.dock_mode -bool true
defaults write "$app_id" flutter.dock_collapsed -bool false
defaults write "$app_id" flutter.dock_size -int 1

mkdir -p "$work/signal"
SNAPDOCK_DEMO=1 SNAPDOCK_DEMO_RECT="$rect" SNAPDOCK_DEMO_SAMPLES="$work/samples" SNAPDOCK_DEMO_SIGNAL="$work/signal" \
  "$work/Snapdock-demo.app/Contents/MacOS/Snapdock" >/dev/null 2>&1 &
pid=$!

for _ in $(seq 1 120); do
  [ -f "$work/signal/ready" ] && break
  sleep 0.25
done
[ -f "$work/signal/ready" ] || { echo "the demo never started" >&2; exit 1; }

screencapture -x -v -V"$seconds" -R"$rect" "$work/demo.mov"
[ -f "$work/signal/done" ] || echo "warning: the demo had not finished when filming stopped" >&2

mkdir -p "$root/docs/screenshots/raw"
# Keep only the part where the backdrop is up, so nothing behind it can end up in the GIF.
ffmpeg -loglevel error -y -i "$work/demo.mov" -t "$keep" "$root/docs/screenshots/raw/demo.mov"
"$here/capture.sh" gif "$root/docs/screenshots/raw/demo.mov"
