#!/bin/bash
# Captures the website screenshots from Baplet's demo mode (see DemoMode.swift).
# Opens windows and full-screen alerts on screen: it counts down HEADS_UP seconds first so the
# owner can minimise their windows. A dark backdrop is placed behind each scene by demo mode.
# For every scene and appearance it launches the built binary directly (not `open`, since a
# normal Baplet may be running with the same bundle id), waits for the demo window, captures it
# with its shadow, kills only that process and converts the PNG to WebP in site/assets/screenshots.
# Usage: scripts/screenshots.sh [scene ...]   (default: every scene below)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/DerivedData/Build/Products/Debug/Baplet.app/Contents/MacOS/Baplet"
OUT="$ROOT/site/assets/screenshots"
SCENES=(menu today alert-popup alert-glass alert-bold alert-warm welcome-theme)
[[ $# -gt 0 ]] && SCENES=("$@")
read -r -a APPEARANCES <<< "${APPEARANCES:-dark}"
HEADS_UP="${HEADS_UP:-10}"
MAX_WIDTH=1600

TMP="$(mktemp -d)"
PID=""

# Kills the demo process that is currently running, if any.
stop_demo() {
	if [[ -n "$PID" ]]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; PID=""; fi
}

# Stops the demo process and removes temporary files on exit.
cleanup() {
	stop_demo
	rm -rf "$TMP"
}
trap cleanup EXIT

# Prints the window id of process $1 (compiled once from window-id.swift), empty if none yet.
window_id() {
	"$TMP/window-id" "$1"
}

# Crops the PNG $2 in place to a centred 1600x1000 region when scene $1 is a full-screen alert,
# so the card is readable once the shot is shown at carousel size. Other scenes are left alone.
crop_fullscreen() {
	case "$1" in
		alert-glass | alert-bold | alert-warm)
			magick "$2" -gravity center -crop 1600x1000+0+0 +repage "$2" ;;
	esac
}

# Captures scene $1 in appearance $2 to site/assets/screenshots/<scene>-<appearance>.webp.
capture() {
	local scene=$1 appearance=$2 id=""
	"$BIN" -BapletDemo YES -BapletDemoScene "$scene" -BapletDemoAppearance "$appearance" >/dev/null 2>&1 &
	PID=$!
	for _ in $(seq 1 50); do
		id="$(window_id "$PID")"
		[[ -n "$id" ]] && break
		sleep 0.2
	done
	if [[ -z "$id" ]]; then echo "  no window for $scene ($appearance)" >&2; stop_demo; return 1; fi
	sleep 1.5
	id="$(window_id "$PID")"
	screencapture -x -l"$id" "$TMP/$scene-$appearance.png"
	stop_demo
	crop_fullscreen "$scene" "$TMP/$scene-$appearance.png"
	magick "$TMP/$scene-$appearance.png" -resize "${MAX_WIDTH}x>" -quality 85 -define webp:alpha-quality=95 "$OUT/$scene-$appearance.webp"
	echo "  $scene-$appearance.webp"
}

mkdir -p "$OUT"
make -C "$ROOT" build
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swiftc -O "$ROOT/scripts/window-id.swift" -o "$TMP/window-id"

# Counts down HEADS_UP seconds in the terminal before the first window appears.
heads_up() {
	echo "Baplet demo windows will appear in $HEADS_UP seconds — minimise your windows now."
	for ((i = HEADS_UP; i > 0; i--)); do printf '\r  %2d… ' "$i"; sleep 1; done
	printf '\r  capturing\n'
}

heads_up
failed=()
for scene in "${SCENES[@]}"; do
	for appearance in "${APPEARANCES[@]}"; do
		capture "$scene" "$appearance" || capture "$scene" "$appearance" || failed+=("$scene-$appearance")
	done
done
[[ ${#failed[@]} -eq 0 ]] || { echo "Failed: ${failed[*]}" >&2; exit 1; }
