#!/bin/sh
# Run inside the Linux image. Serein is mounted read-only.
set -eu
checkout=${1:?pass the Serein checkout path}
preview=$(mktemp -d)
trap 'rm -rf "$preview"' EXIT
source_dir="$checkout/Packages/SignalUI/Sources/SignalUI"
mkdir -p "$preview/Sources/DevicePreview"
for source in Axo/AxoContainer Theme/CSSGrid Theme/CSSFlex Theme/AxoColor Theme/AxoTheme Theme/CSSShapes Components/QRCode/QRCodeGenerator Components/QRCode/QrCode; do
    cp "$source_dir/$source.swift" "$preview/Sources/DevicePreview/"
done
cp /src/Scripts/SereinExample.swift "$preview/Sources/DevicePreview/"
cat > "$preview/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "DevicePreview",
    dependencies: [.package(name: "QtSwiftUI", path: "/src")],
    targets: [.executableTarget(name: "DevicePreview", dependencies: [.product(name: "SwiftUI", package: "QtSwiftUI")])]
)
SWIFT
swift run --package-path "$preview" DevicePreview
