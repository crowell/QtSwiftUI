#!/bin/sh
# Run inside the Linux image. Serein is mounted read-only.
set -eu
checkout=${1:?pass the Serein checkout path}
preview=$(mktemp -d)
trap 'rm -rf "$preview"' EXIT
source_dir="$checkout/Packages/SignalUI/Sources/SignalUI"
mkdir -p "$preview/Sources/DevicePreview"
for source in Axo/AxoContainer Theme/CSSGrid Theme/CSSFlex Theme/AxoColor Theme/AxoTheme Theme/CSSShapes Components/QRCode/QRCodeGenerator Components/QRCode/QrCode Axo/SVGPathData Components/Preferences/SignalLoginIllustration; do
    cp "$source_dir/$source.swift" "$preview/Sources/DevicePreview/"
done
cp /src/Scripts/SereinExample.swift /src/Scripts/AccountArtwork.swift /src/Scripts/KeyArtwork.swift "$preview/Sources/DevicePreview/"
sh /src/Scripts/extract-key-illustration.sh "$source_dir/Components/KeyTransparencyIllustration.swift" \
    "$preview/Sources/DevicePreview/KeyTransparencyIllustration.swift"
cat > "$preview/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "DevicePreview",
    dependencies: [.package(name: "QtSwiftUI", path: "/src")],
    targets: [.executableTarget(name: "DevicePreview", dependencies: [.product(name: "SwiftUI", package: "QtSwiftUI")])]
)
SWIFT
swift build --package-path "$preview"
binary=$(swift build --package-path "$preview" --show-bin-path)/DevicePreview
"$binary"
if [ -n "${QTSWIFTUI_SCREENSHOT:-}" ]; then
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/account-artwork.png" "$binary" --artwork
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/key-transparency.png" "$binary" --keys
fi

diagnostics="$preview/diagnostics"
sh /src/Scripts/prepare-diagnostics.sh "$checkout" "$diagnostics"
if [ -n "${QTSWIFTUI_SCREENSHOT:-}" ]; then
    export QTSWIFTUI_FOLDER_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_TYPING_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_HEADER_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_TIMELINE_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_MUTE_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_USERNAME_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_SHARE_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_STICKER_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_TIMER_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_LIGHTBOX_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_CALLS_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_REQUEST_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_LINK_SCREENS="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_HISTORY_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_SETTINGS_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_SURVEY_REFERENCE="$(dirname "$QTSWIFTUI_SCREENSHOT")"
    export QTSWIFTUI_GALLERY_MENU_CAPTURE="$(dirname "$QTSWIFTUI_SCREENSHOT")/media-gallery-sort.png"
fi
swift test --package-path "$diagnostics"
binary=$(swift build --package-path "$diagnostics" --show-bin-path)/CallDiagnostics
if [ -n "${QTSWIFTUI_SCREENSHOT:-}" ]; then
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/recording-draft.png" "$binary" --recording-draft
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/voice-recording.png" "$binary" --recording
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/discard-recording.png" "$binary" --discard-recording
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/data-usage-settings.png" "$binary" --data-usage-settings
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/conversation-typing.png" "$binary" --typing --still
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/conversation-header.png" "$binary" --conversation
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/conversation-timeline.png" "$binary" --timeline
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/mute-until.png" "$binary" --mute-until
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/username-link.png" "$binary" --username-link
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/username-card-preview.png" "$binary" --username-card
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/share-picker.png" "$binary" --share-picker
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/stickers.png" "$binary" --stickers
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/disappearing-timer.png" "$binary" --disappearing-timer
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/lightbox.png" "$binary" --lightbox
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/calls-tab.png" "$binary" --calls-tab
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/chat-folders.png" "$binary" --chat-folders
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/calling-lobby.png" "$binary" --calling-lobby
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/shortcut-guide.png" "$binary" --shortcut-guide
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/inbox.png" "$binary" --inbox
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/about.png" "$binary" --about
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/about-contact.png" "$binary" --about-contact
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/note-preview.png" "$binary" --note-preview
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/join-request.png" "$binary" --join-request
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/call-link.png" "$binary" --call-link
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/nickname-and-note.png" "$binary" --nickname
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/call-history.png" "$binary" --call-history
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/call-settings.png" "$binary" --call-settings
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/call-quality-survey.png" "$binary" --call-survey
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/chat-color-picker.png" "$binary" --color-picker
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/custom-color-editor.png" "$binary" --color-editor
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/media-gallery-populated.png" "$binary" --gallery-media
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/media-gallery.png" "$binary" --gallery
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/call-diagnostics.png" "$binary"
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/confirm-leave-call.png" "$binary" --leave-call
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/call-participants.png" "$binary" --call-participants
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/backup-import.png" "$binary" --backup-import
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/link-qr.png" "$binary" --link-qr
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/link-device.png" "$binary" --link-device
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/link-error.png" "$binary" --link-error
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/clearing-data.png" "$binary" --clearing-data --still
    QTSWIFTUI_SCREENSHOT="$(dirname "$QTSWIFTUI_SCREENSHOT")/clearing-data-ar.png" "$binary" --clearing-data --arabic --still
else
    "$binary"
fi
