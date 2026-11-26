#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
d="${1:?pass the Serein checkout path}/Packages/SignalUI/Sources/SignalUI"
mkdir -p .build/artwork
sh Scripts/extract-key-illustration.sh "$d/Components/KeyTransparencyIllustration.swift" .build/artwork/Keys.swift
xcrun swiftc -parse-as-library -swift-version 6 Tests/ArtworkReference/Reference.swift Scripts/AccountArtwork.swift \
    Scripts/KeyArtwork.swift .build/artwork/Keys.swift \
    "$d/Theme/AxoColor.swift" "$d/Axo/SVGPathData.swift" "$d/Components/Preferences/SignalLoginIllustration.swift" \
    -o .build/artwork/reference
.build/artwork/reference Screenshots/account-artwork.png .build/artwork/apple.png
.build/artwork/reference Screenshots/key-transparency.png .build/artwork/keys-apple.png --keys
