#!/bin/sh
# Assemble the same Serein sources for both Apple's SDK and the Linux renderer.
set -eu
checkout=${1:?pass the Serein checkout path}
target=${2:?pass the temporary package directory}
source_dir="$checkout/Packages/SignalUI/Sources/SignalUI"
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$target/Sources/CallDiagnostics" "$target/Tests/ScreenTests"
cp "$root"/Tests/SereinDiagnostics/*.swift "$target/Tests/ScreenTests/"
ln -s "$checkout/Packages/SignalI18n" "$target/SignalI18n"
cp "$source_dir/Calling/CallDiagnosticWindow.swift" "$source_dir/Theme/I18nEnvironment.swift" \
    "$source_dir/Theme/AxoColor.swift" "$source_dir/Theme/AxoFocusRing.swift" \
    "$source_dir/Theme/AxoShadow.swift" "$source_dir/Tokens/AxoTokens.generated.swift" \
    "$source_dir/Theme/AxoMotion.swift" "$source_dir/Axo/Status/AxoBaseSpinner.swift" \
    "$source_dir/Axo/AxoButton.swift" "$source_dir/Tokens/AxoSymbolDefs.generated.swift" \
    "$root"/Scripts/CallDiagnostics/*.swift "$target/Sources/CallDiagnostics/"
target_dir="$target/Sources/CallDiagnostics"
cp "$source_dir/Calling/ConfirmLeaveCallModal.swift" "$source_dir/Axo/AxoAlertDialog.swift" \
   "$source_dir/Axo/AxoConfirmDialog.swift" "$source_dir/Theme/CSSShapes.swift" \
   "$source_dir/Axo/AxoPopper.swift" "$target_dir/"
# The panel's optional live NSVisualEffectView is specific to AppKit.
awk '/^import AppKit/ || /\.background \{ if backdropBlur/ { print "#if canImport(AppKit)"; print; print "#endif"; next }
     /^struct WithinWindowBlur:/ { print "#if canImport(AppKit)"; blur = 1 }
     { print } END { if (!blur) exit 1; print "#endif" }' \
    "$source_dir/Axo/AxoBaseDialog.swift" > "$target_dir/AxoBaseDialog.swift"
# Copy the alert's actual scrolling, height limit and variant implementations.
awk 'BEGIN { print "import SwiftUI\npublic enum AxoDialog {" }
     /^    public enum ActionVariant:/ || /^    struct (HeightLimited|TopAligned|AxoScrollContainer)[<:]/ { inside = 1; count++ }
     inside { print } /^    }$/ { inside = 0 }
     END { print "}"; if (count != 4) exit 1 }' "$source_dir/Axo/AxoDialog.swift" > "$target_dir/AxoDialog.swift"
# AxoButton uses the type scale. The rest of AxoType.swift defines a CoreText modifier.
awk '/^public struct AxoType: / { print "import SwiftUI"; inside = 1 }
     inside { print } inside && /^}$/ { complete = 1; exit } END { if (!complete) exit 1 }' \
    "$source_dir/Theme/AxoType.swift" > "$target_dir/AxoType.swift"
mkdir -p "$target_dir/Fonts"
cp "$source_dir"/Resources/Fonts/Inter-*.ttf "$source_dir/Resources/Fonts/SignalSymbolsVariable.ttf" "$target_dir/Fonts/"
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
                      targets: [.executableTarget(name: "CallDiagnostics", dependencies: dependencies, resources: [.copy("Fonts")]),
                                .testTarget(name: "ScreenTests", dependencies: ["CallDiagnostics"] + dependencies)])
SWIFT
