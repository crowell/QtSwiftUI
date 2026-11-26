#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
for file in Examples/*/*.swift Tests/EventLoop/Sources/EventLoopProbe/Probe.swift; do
    xcrun swiftc -typecheck -swift-version 6 -parse-as-library "$file"
done
if [ "$#" -gt 0 ]; then
    d="$1/Packages/SignalUI/Sources/SignalUI"
    preview=$(mktemp -d)
    trap 'rm -rf "$preview"' EXIT
    sh Scripts/extract-key-illustration.sh "$d/Components/KeyTransparencyIllustration.swift" "$preview/Keys.swift"
    xcrun swiftc -typecheck -swift-version 6 -parse-as-library Scripts/SereinExample.swift Scripts/AccountArtwork.swift \
        Scripts/KeyArtwork.swift "$preview/Keys.swift" "$d/Axo/AxoContainer.swift" \
        "$d/Theme/CSSGrid.swift" "$d/Theme/CSSFlex.swift" "$d/Theme/AxoColor.swift" "$d/Theme/AxoTheme.swift" \
        "$d/Theme/CSSShapes.swift" "$d/Components/QRCode/QRCodeGenerator.swift" "$d/Components/QRCode/QrCode.swift" \
        "$d/Axo/SVGPathData.swift" "$d/Components/Preferences/SignalLoginIllustration.swift"
    sh Scripts/prepare-diagnostics.sh "$(cd "$1" && pwd)" "$preview/diagnostics"
    if [ -f "$PWD/Screenshots/username-card.png" ]; then export QTSWIFTUI_UBUNTU_USERNAME_CARD="$PWD/Screenshots/username-card.png"; fi
    swift test --package-path "$preview/diagnostics"
fi
