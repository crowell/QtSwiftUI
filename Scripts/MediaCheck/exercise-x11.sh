#!/bin/sh
set -eu
app=${1:?pass the MediaCheck executable}
out=${2:?pass an empty output directory}
mkdir -p "$out"
test ! -e "$out/Signal_AccountKeys.pdf"
SEREIN_EXPORT_DIR="$out" QT_QPA_PLATFORM=xcb "$app" > "$out/window.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
window=$(timeout 20 xdotool search --sync --name '^Serein$' | head -1)
xdotool windowfocus --sync "$window"
xdotool mousemove --window "$window" 214 292 click 1
for attempt in $(seq 1 40); do
    if [ -s "$out/Signal_AccountKeys.pdf" ]; then break; fi
    sleep 0.1
done
for pdf in "$out/reference.pdf" "$out/Signal_AccountKeys.pdf"; do
    test "$(head -c 4 "$pdf")" = "%PDF"
done
