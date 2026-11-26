#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sdk=$(xcrun --show-sdk-path)
target="$(uname -m)-apple-macos$(xcrun --show-sdk-version)"
dir="$PWD/.build/api-inventory"
mkdir -p "$dir/linux"
for module in SwiftUI SwiftUICore; do
    mkdir -p "$dir/apple/$module"
    xcrun swift-symbolgraph-extract -module-name "$module" -target "$target" -sdk "$sdk" \
        -skip-synthesized-members -output-dir "$dir/apple/$module"
done
docker build -t qtswiftui-examples .
docker run --rm --network none --mount "type=bind,src=$dir/linux,dst=/out" qtswiftui-examples sh -ec '
    swift package dump-symbol-graph --skip-synthesized-members
    find .build -name "SwiftUI*.symbols.json" -exec cp {} /out/ \;
'
python3 Scripts/api-inventory.py "$dir/apple" "$dir/linux" "$@"
