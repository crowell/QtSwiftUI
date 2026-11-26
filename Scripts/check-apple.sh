#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
for file in Examples/*/*.swift Tests/EventLoop/Sources/EventLoopProbe/Probe.swift; do
    xcrun swiftc -typecheck -swift-version 6 -parse-as-library "$file"
done
if [ "$#" -gt 0 ]; then
    d="$1/Packages/SignalUI/Sources/SignalUI"
    xcrun swiftc -typecheck -swift-version 6 -parse-as-library Scripts/SereinExample.swift Scripts/AccountArtwork.swift "$d/Axo/AxoContainer.swift" \
        "$d/Theme/CSSGrid.swift" "$d/Theme/CSSFlex.swift" "$d/Theme/AxoColor.swift" "$d/Theme/AxoTheme.swift" \
        "$d/Theme/CSSShapes.swift" "$d/Components/QRCode/QRCodeGenerator.swift" "$d/Components/QRCode/QrCode.swift" \
        "$d/Axo/SVGPathData.swift" "$d/Components/Preferences/SignalLoginIllustration.swift"
fi
