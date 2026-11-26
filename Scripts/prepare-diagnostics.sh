#!/bin/sh
# Assemble the same Serein sources for both Apple's SDK and the Linux renderer.
set -eu
checkout=${1:?pass the Serein checkout path}
target=${2:?pass the temporary package directory}
source_dir="$checkout/Packages/SignalUI/Sources/SignalUI"
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$target/Sources/CallDiagnostics" "$target/Tests/ScreenTests"
cp "$root/Tests/SereinDiagnostics/ScreenTests.swift" "$target/Tests/ScreenTests/"
ln -s "$checkout/Packages/SignalI18n" "$target/SignalI18n"
cp "$source_dir/Calling/CallDiagnosticWindow.swift" "$source_dir/Theme/I18nEnvironment.swift" \
    "$source_dir/Theme/AxoColor.swift" "$root"/Scripts/CallDiagnostics/*.swift "$target/Sources/CallDiagnostics/"
# Only the generated color extension is used by this screen.
sed -n '/^extension AxoColor {$/,/^}$/p' "$source_dir/Tokens/AxoTokens.generated.swift" > "$target/Sources/CallDiagnostics/Colors.swift"
test -s "$target/Sources/CallDiagnostics/Colors.swift"
cat > "$target/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
var packages: [Package.Dependency] = [.package(path: "SignalI18n")]
var dependencies: [Target.Dependency] = [.product(name: "SignalI18n", package: "SignalI18n")]
#if os(Linux)
packages.append(.package(name: "QtSwiftUI", path: "/src"))
dependencies.append(.product(name: "SwiftUI", package: "QtSwiftUI"))
#endif
let package = Package(name: "CallDiagnostics", platforms: [.macOS("27.0")], dependencies: packages,
                      targets: [.executableTarget(name: "CallDiagnostics", dependencies: dependencies),
                                .testTarget(name: "ScreenTests", dependencies: ["CallDiagnostics"] + dependencies)])
SWIFT
