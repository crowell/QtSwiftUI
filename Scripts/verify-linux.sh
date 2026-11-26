#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p Screenshots
docker build -t qtswiftui-examples .
for app in Conversation Controls; do
    filename=$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')
    docker run --rm --network none --mount "type=bind,src=$PWD/Screenshots,dst=/out" \
        -e "QTSWIFTUI_SCREENSHOT=/out/$filename.png" qtswiftui-examples ".build/debug/$app"
done
if [ "$#" -gt 0 ]; then
    checkout=$(cd "$1" && pwd)
    docker run --rm --network none --mount "type=bind,src=$checkout,dst=/serein,readonly" \
        --mount "type=bind,src=$PWD/Screenshots,dst=/out" -e QTSWIFTUI_SCREENSHOT=/out/serein-components.png \
        qtswiftui-examples sh Scripts/verify-serein.sh /serein
fi
