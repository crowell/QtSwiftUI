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
timeout 10 "$probe" --windows > "$tmp/windows"
test "$(grep -Fxc 'Second window opened with 1' "$tmp/windows")" -eq 1
grep -Fx 'Second window observed shared state after first closed' "$tmp/windows"
timeout 10 "$probe" --settings > "$tmp/settings"
grep -Fx 'Opened settings from a presented scene' "$tmp/settings"
if grep -Fq 'Unexpected initial window' "$tmp/settings"; then exit 1; fi
XDG_CONFIG_HOME="$tmp/config" timeout 10 "$probe" --stored > "$tmp/storage-first"
XDG_CONFIG_HOME="$tmp/config" timeout 10 "$probe" --stored > "$tmp/storage-second"
grep -Fx 'Stored count 0 -> 1' "$tmp/storage-first"
grep -Fx 'Stored count 1 -> 2' "$tmp/storage-second"
