#!/bin/sh
set -eu
app=${1:?pass the built ComposerCheck executable}
log=$(mktemp)
SEREIN_COMPOSER_VERIFY=1 QT_QPA_PLATFORM=xcb stdbuf -oL "$app" > "$log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; rm -f "$log"' EXIT
window=$(timeout 12 xdotool search --sync --name 'Serein.*Message composer' | head -1)
xdotool windowfocus --sync "$window"
sleep 0.3
xdotool mousemove --window "$window" 85 47 click 1
xdotool key ctrl+End
xdotool type ' Yes'
xdotool key Return
sleep 0.2
xdotool key ctrl+Home
xdotool key --repeat 9 Right
xdotool key BackSpace Return
sleep 0.2
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if grep -q "Verified composer submission 2" "$log"; then cat "$log"; exit 0; fi
    sleep 0.1
done
cat "$log"
exit 1
