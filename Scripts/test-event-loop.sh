#!/bin/sh
set -eu
swift build --package-path Tests/EventLoop
probe=$(swift build --package-path Tests/EventLoop --show-bin-path)/EventLoopProbe
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
QTSWIFTUI_SCREENSHOT="$tmp/probe.png" QTSWIFTUI_CAPTURE_DELAY_MS=700 timeout 10 "$probe" > "$tmp/log"
cat "$tmp/log"
grep -Fx 'Appeared at 260 x 100' "$tmp/log"
grep -Fx 'Observed Waiting -> Ready' "$tmp/log"
grep -Fx 'Timeline reached its scheduled date' "$tmp/log"
test -s "$tmp/probe.png"
