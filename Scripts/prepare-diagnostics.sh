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
codecs="$checkout/Packages/SignalCodecs"
if [ "$(uname -s)" = Linux ]; then
    mkdir -p "$target/SignalCodecs"
    cp -R "$codecs/Sources" "$target/SignalCodecs/"
    ln -s "$codecs/Package.swift" "$target/SignalCodecs/Package.swift"
    ln -s "$codecs/Tests" "$target/SignalCodecs/Tests"
    # Serein's codec math uses the same scoped C functions from Linux libm.
    sed 's/Darwin\./Glibc./g' "$codecs/Sources/CodecCore/Math/LibM.swift" > "$target/SignalCodecs/Sources/CodecCore/Math/LibM.swift"
else
    ln -s "$codecs" "$target/SignalCodecs"
fi
cp "$source_dir/Calling/CallDiagnosticWindow.swift" "$source_dir/Theme/I18nEnvironment.swift" \
    "$source_dir/Theme/AxoColor.swift" "$source_dir/Theme/AxoFocusRing.swift" \
    "$source_dir/Theme/AxoShadow.swift" "$source_dir/Tokens/AxoTokens.generated.swift" \
    "$source_dir/Theme/AxoMotion.swift" "$source_dir/Axo/Status/AxoBaseSpinner.swift" \
    "$source_dir/Axo/AxoButton.swift" "$source_dir/Tokens/AxoSymbolDefs.generated.swift" \
    "$root"/Scripts/CallDiagnostics/*.swift "$target/Sources/CallDiagnostics/"
target_dir="$target/Sources/CallDiagnostics"
cp "$source_dir/Axo/Internal/AxoBaseSegmentedControl.swift" "$source_dir/Axo/AxoSegmentedControl.swift" \
   "$source_dir/Axo/AxoBadge.swift" "$source_dir/Theme/CSSFlex.swift" \
   "$source_dir/Components/Conversation/MediaGallery/MediaGalleryEmptyState.swift" \
   "$source_dir/Components/Conversation/MediaGallery/MediaGridItem.swift" \
   "$source_dir/Components/Conversation/MediaGallery/AttachmentSection.swift" "$target_dir/"
cp "$source_dir/Axo/AxoBaseMenu.swift" "$source_dir/Axo/AxoDropdownMenu.swift" "$source_dir/Axo/AxoIconButton.swift" "$target_dir/"
# The empty-gallery fixture uses the production panel and all of its header controls.
awk 'BEGIN { print "import SwiftUI\nimport SignalI18n" }
     /^public enum MediaSortOrder:/ { print; count++ }
     /^public struct (ConversationPanel<|MediaGalleryPanelHeader:)/ { inside=1; count++ }
     inside { print } /^}$/ { inside=0 } END { if (count!=3) exit 1 }' \
    "$source_dir/Components/Conversation/MediaGallery/MediaGallery.swift" > "$target_dir/GalleryPanel.swift"
awk 'BEGIN { print "extension AxoSymbol {" }
     /^    public static func (icon|inlineGlyph)\(/ { inside=1; count++ }
     inside { print } /^    }$/ { inside=0 } END { print "}"; if (count!=2) exit 1 }' \
    "$source_dir/Axo/AxoSymbol.swift" > "$target_dir/SymbolLookup.swift"
cp "$source_dir/Axo/Chat/AxoChatDateSection.swift" "$source_dir/Axo/AxoColorSlider.swift" "$target_dir/"
cp "$source_dir/Calling/CallingAudioIndicator.swift" "$source_dir/Theme/SignalIcon.swift" \
   "$source_dir/Axo/SVGPathData.swift" "$source_dir/Tokens/SignalIcons.generated.swift" \
   "$source_dir/Tokens/LegacyColors.generated.swift" "$target_dir/"
cp "$source_dir/Calling/ConfirmLeaveCallModal.swift" "$source_dir/Axo/AxoAlertDialog.swift" \
   "$source_dir/Axo/AxoConfirmDialog.swift" "$source_dir/Theme/CSSShapes.swift" \
   "$source_dir/Axo/AxoPopper.swift" "$target_dir/"
cp "$source_dir/Components/Slider.swift" "$source_dir/Components/CompositionRecordingDraft.swift" \
   "$source_dir/Components/SpinnerV2.swift" "$source_dir/Components/Conversation/Message/WaveformScrubber.swift" "$target_dir/"
# The draft reuses these declarations from the larger attachment and message views.
declarations() {
    awk -v pattern="$1" -v expected="$2" '$0 ~ pattern { inside=1; count++ }
        inside { print } /^}$/ { inside=0 } END { if (count != expected || inside) exit 1 }' "$3"
}
{
    echo 'import SwiftUI'
    echo 'import CodecCore'
    declarations '^struct (PlaybackButton|AudioWaveformBars):|^public struct AudioWaveform:' 3 "$source_dir/Components/Conversation/Message/MessageAudio.swift"
    declarations '^public struct MessageAttachment:' 1 "$source_dir/Components/Conversation/Message/MessageAttachment.swift"
    declarations '^enum QuoteMIME ' 1 "$source_dir/Components/Conversation/Quote.swift"
    declarations '^public struct RGBAImage:|^public final class RGBAAnimation:' 2 "$source_dir/Theme/PixelImage.swift"
    declarations '^public func formatFileSize[(]' 1 "$source_dir/Theme/I18nRichText.swift"
    declarations '^public struct ImageOrBlurhash:' 1 "$source_dir/Components/Conversation/ConversationImage.swift"
} > "$target_dir/DraftAudioSupport.swift"
# Keep Serein's image fitting, snapping and animation. Paint the decoded RGBA bytes
# through SwiftUI.Image on both platforms so the comparison can run without Metal.
{
    echo 'import SwiftUI'
    declarations '^struct AnimationSchedule:|^public struct PixelImage:|^struct AnimatedPixelImage:' 3 "$source_dir/Theme/PixelImage.swift"
    awk '/^public enum ObjectFit:/ { print; count++ } END { if (count != 1) exit 1 }' "$source_dir/Theme/PixelImage.swift"
} > "$target/PixelImageSource.swift"
awk '/^            Rectangle\(\)$/ { replacing=1; next }
     replacing && /\.float\(Float\(displayScale\)\)\)\)/ {
         print "            raster.frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)"
         replacing=0; count++; next }
     !replacing { print } END { if (count != 1 || replacing) exit 1 }' "$target/PixelImageSource.swift" > "$target_dir/PixelImage.swift"
gallery_tests="$checkout/Packages/SignalUI/Tests/SignalUITests/Components/MediaGallery"
cp "$gallery_tests/AttachmentSectionFixtures.swift" "$target_dir/"
mkdir -p "$target_dir/Media"
# Standalone Serein checkouts also carry a decoded frame of the cat GIF.
photo="$checkout/Signal-Desktop/fixtures/cat-screenshot-3x4.png"
if [ ! -f "$photo" ]; then photo="$checkout/Packages/SignalUI/Tests/SignalUITests/Fixtures/cat-gif-frame0.png"; fi
cp "$photo" "$target_dir/Media/cat-screenshot-3x4.png"
# Serein observes AppKit's app-deactivation notification to save the recording draft.
# The Linux scene supplies the same transition from Qt window and application events.
awk '/^public struct CompositionRecording: View/ { print; print "#if os(Linux)\n    @Environment(\\.scenePhase) var phase\n#endif"; next }
     /NSApplication.didResignActiveNotification/ {
         print "#if os(Linux)\n        .onChange(of: phase) { old, new in if old == .active && new != .active { saveDraftRecordingIfNeeded() } }\n#else"
         print; print "#endif"; found=1; next }
     { print } END { if (!found) exit 1 }' "$source_dir/Components/CompositionRecording.swift" > "$target_dir/CompositionRecording.swift"
awk 'BEGIN { print "import Foundation" } /^func durationToPlaybackText\(/ { inside=1 }
     inside { print } inside && /^}$/ { done=1; exit } END { if (!done) exit 1 }' \
    "$source_dir/Components/Conversation/Message/MessageAudio.swift" > "$target_dir/PlaybackTime.swift"
awk 'BEGIN { print "import SwiftUI\nextension EnvironmentValues {" } /@Entry public var conversationListNow:/ { print; found=1 }
     END { print "}"; if (!found) exit 1 }' "$source_dir/Components/ConversationList/BaseConversationListItem.swift" > "$target_dir/RecordingClock.swift"
cp "$source_dir/Components/ClearingData.swift" "$source_dir/Components/ProgressBar.swift" "$target_dir/"
cp "$source_dir/Axo/AxoBrand.swift" "$source_dir/Axo/AxoDragRegion.swift" \
   "$source_dir/Components/Button.swift" "$source_dir/Components/Spinner.swift" \
   "$source_dir/Components/LegacyType.swift" "$source_dir/Components/LegacyIcon.swift" "$target_dir/"
awk 'BEGIN { print "import SwiftUI" } /^public struct TitlebarDragArea:/{ found=1 }
     found { print } END { if (!found) exit 1 }' "$source_dir/Components/App.swift" > "$target_dir/TitlebarDragArea.swift"
# Dispatch the two AppKit URL calls through the desktop environment on Linux.
awk '/^import AppKit/ { print "#if canImport(AppKit)"; print; print "#endif"; next }
     /^public struct InstallScreenErrorStep:/ { print; print "#if os(Linux)\n    @Environment(\\.openURL) var openURL\n#endif"; next }
     /NSWorkspace.shared.open/ { print "#if os(Linux)"; line=$0; gsub(/NSWorkspace.shared.open/, "openURL", line)
         print line; print "#else"; print; print "#endif"; next }
     { print }' "$source_dir/Components/InstallScreen/InstallScreen.swift" > "$target_dir/InstallScreen.swift"
{ echo '#if canImport(AppKit)'; cat "$source_dir/Theme/CASpin.swift"; echo '#endif'; } > "$target_dir/CASpin.swift"
# Exercise the exact hidden keyboard controls from the Serein call lobby.
awk 'BEGIN { print "import SwiftUI\nstruct LobbyKeyboardControls: View {"
             print "    var hasLocalVideo: Bool, hasLocalAudio: Bool"
             print "    var setLocalVideo: (Bool) -> Void, setLocalAudio: (Bool) -> Void"
             print "    var body: some View {" }
     /^            Group \{/ { group=$0; next }
     /Button\(""\) \{ setLocalVideo/ { print group; emit=1 }
     emit { print }
     emit && /\.accessibilityHidden\(true\)/ { done=1; exit }
     END { print "    }\n}"; if (!done) exit 1 }' "$source_dir/Calling/CallingLobby.swift" > "$target_dir/LobbyKeyboardControls.swift"
# CallingAudioIndicator shares this color initializer with the call controls.
awk '/^extension Color \{/ { print "import SwiftUI"; inside = 1 }
     inside { print } inside && /^}$/ { complete = 1; exit } END { if (!complete) exit 1 }' \
    "$source_dir/Calling/CallingButton.swift" > "$target_dir/CallingColor.swift"
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
if [ "$(uname -s)" = Linux ]; then cp "$root/Package.resolved" "$target/Package.resolved"; fi
cat > "$target/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
var packages: [Package.Dependency] = [.package(path: "SignalI18n"), .package(path: "SignalCodecs")]
var dependencies: [Target.Dependency] = [.product(name: "SignalI18n", package: "SignalI18n"),
    .product(name: "CodecCore", package: "SignalCodecs"), .product(name: "ImagePNG", package: "SignalCodecs"),
    .product(name: "ImageBMP", package: "SignalCodecs")]
#if os(Linux)
packages.append(.package(name: "QtSwiftUI", path: "/src"))
dependencies.append(.product(name: "SwiftUI", package: "QtSwiftUI"))
#endif
let package = Package(name: "CallDiagnostics", platforms: [.macOS("27.0")], dependencies: packages,
                      targets: [.executableTarget(name: "CallDiagnostics", dependencies: dependencies, resources: [.copy("Fonts"), .copy("Media")]),
                                .testTarget(name: "ScreenTests", dependencies: ["CallDiagnostics"] + dependencies)])
SWIFT
