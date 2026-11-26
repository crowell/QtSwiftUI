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
ln -s "$checkout/Packages/SignalText" "$target/SignalText"
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
# Use the editor’s original crop transform and Canvas background renderer in the cross-platform raster tests.
editor="$source_dir/Components/MediaEditor"
{
    echo 'import SwiftUI'
    declarations '^public struct MediaEditorImageState:' 1 "$editor/MediaEditorModel.swift"
    echo 'extension EditorBackgroundFixture {'
    awk '/^    func drawBackground\(/ {inside=1; count++} inside {print} /^    }$/ {inside=0}
         END {if (count!=1 || inside) exit 1}' "$editor/MediaEditorCanvas.swift"
    echo '}'
} > "$target/Tests/ScreenTests/EditorBackground.swift"
{
    echo 'import SwiftUI'
    echo 'import CodecCore'
    declarations '^struct (PlaybackButton|AudioWaveformBars):|^public struct AudioWaveform:' 3 "$source_dir/Components/Conversation/Message/MessageAudio.swift"
    declarations '^public struct MessageAttachment:' 1 "$source_dir/Components/Conversation/Message/MessageAttachment.swift"
    declarations '^enum QuoteMIME ' 1 "$source_dir/Components/Conversation/Quote.swift"
    declarations '^public struct RGBAImage:|^public final class RGBAAnimation:' 2 "$source_dir/Theme/PixelImage.swift"
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
lighthouse="$checkout/Signal-Desktop/fixtures/tina-rolf-269345-unsplash.jpg"
if [ -f "$lighthouse" ]; then cp "$lighthouse" "$target_dir/Media/"; fi
# The QR card's production PNG exporter uses its own encoder and MediaEditorExport's
# pixel reader. Substitute the portable font shaper for CoreText and bridge CFData on Linux.
qr="$source_dir/Components/QRCode"
cp "$qr/QrCode.swift" "$qr/QRCodeGenerator.swift" "$qr/BrandedQRCode.swift" "$target_dir/"
awk '/CSSTextLayout.make\(runs:/ {print "        AxoFonts.width(text, style: style)"; count++; next}
     {print} END {if (count != 1) exit 1}' "$qr/UsernameLinkCard.swift" > "$target_dir/UsernameLinkCard.swift"
{
    echo 'import SwiftUI'
    declarations '^public enum UsernameLinkColor:' 1 "$source_dir/Components/UsernameLinkEditor.swift"
    echo 'import CodecCore'
    echo 'import CoreFoundation'
    echo 'enum MediaEditorExport {'
    awk '/^    static func pixels\(_ image: CGImage\)/ {inside=1; count++}
         inside && /let data = image.dataProvider/ {
            print "#if os(Linux)\n        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32, let data = image.dataProvider?.data else { return nil }\n#else"
            print; print "#endif"; next }
         inside && /let bytes = \[UInt8\]\(data\)/ {
            print "#if os(Linux)\n        let bytes = UnsafeBufferPointer(start: CFDataGetBytePtr(data), count: CFDataGetLength(data))\n#else"
            print; print "#endif"; bytes++; next }
         inside {print} /^    }$/ {inside=0} END {if (count != 1 || bytes != 1 || inside) exit 1}' \
        "$source_dir/Components/MediaEditor/MediaEditorExport.swift"
    echo '}'
} > "$target_dir/UsernameCardExport.swift"
sed 's/@testable import SignalUI/@testable import CallDiagnostics/' \
    "$checkout/Packages/SignalUI/Tests/SignalUITests/Components/UsernameLinkCardTests.swift" > "$target/Tests/ScreenTests/UsernameLinkCardTests.swift"
# Assemble Serein's source selector and its static snapshot inputs. Only the optional
# bundle-icon lookup needs AppKit. The picker receives thumbnails from its caller.
{
    echo 'import SwiftUI'
    echo 'import SignalI18n'
    declarations '^public struct PresentableSource:' 1 "$source_dir/Calling/ScreenShare.swift"
    declarations '^public struct CallingSelectPresentingSourcesModal:|^struct (SourceCard|SourceThumbnail|AspectBox):' 4 "$source_dir/Calling/ScreenShareViews.swift" |
        awk '/if let icon = ScreenShareCapture.icon/ { print "#if canImport(AppKit)"; icon=1 }
             {print} icon && /^                    }/ { print "#endif"; icon=0; count++ }
             END { if (icon || count != 1) exit 1 }'
    echo '#if canImport(AppKit)'
    echo 'import AppKit'
    echo 'enum ScreenShareCapture {'
    awk '/^    @MainActor public static func icon\(bundleId:/ {inside=1; count++} inside {print}
         /^    }/ {inside=0} END {if (count != 1 || inside) exit 1}' "$source_dir/Calling/ScreenShare.swift"
    echo '}'
    echo '#endif'
} > "$target_dir/ScreenSharePicker.swift"
{
    echo 'import SwiftUI'
    echo 'extension ScreenSharePreview { static let sources: [PresentableSource] = {'
    awk '/^        let screen = pngFixture/ {inside=1; count++}
         inside {print} /^        \]$/ && inside {inside=0}
         END {if (count != 1 || inside) exit 1}' "$checkout/Packages/SignalUI/Tests/SignalUITests/Calling/ScreenShareSnapshotTests.swift"
    echo 'return sources }() }'
} > "$target_dir/ScreenShareSources.swift"
for thumbnail in presenting-source-screen.png presenting-source-window.png; do
    if [ -f "$checkout/Signal-Desktop/fixtures/$thumbnail" ]; then cp "$checkout/Signal-Desktop/fixtures/$thumbnail" "$target_dir/Media/"; fi
done
cp "$source_dir/Components/Stickers/StickerManager.swift" "$source_dir/Axo/AxoModalStack.swift" "$target_dir/"
# Keep the pack preview's native clipboard operation on each desktop.
awk '/^import AppKit$/ { print "#if os(Linux)\nimport QtBridge\n#else\nimport AppKit\n#endif"; next }
     /NSPasteboard.general.clearContents/ { print "#if os(Linux)\n        qs_clipboard_text(Self.link(packId: pack.id, packKey: pack.key))\n#else" }
     { print } /NSPasteboard.general.setString/ { print "#endif"; count++ }
     END { if (count != 1) exit 1 }' "$source_dir/Components/Stickers/StickerPreviewModal.swift" > "$target_dir/StickerPreviewModal.swift"
# The shared CSSText adapter shapes the two-line caption. Keep the actual stacked button and its two Layout types.
awk '/^struct LineClampText:/ { found=1; exit }
     /^import CoreText$/ {next}
     /LineClampText\(label,/ {print "                    CSSText(label, style: CSSTextStyle(AxoType.caption.weight(500)), alignment: .center).lineLimit(2)"; count++; next}
     {print} END {if (!found || count != 1) exit 1}' "$source_dir/Axo/AxoStackedButton.swift" > "$target_dir/AxoStackedButton.swift"
{
    echo 'import SwiftUI'
    declarations '^public struct OfficialChatInlineBadge:' 1 "$source_dir/Components/ConversationList/BaseConversationListItem.swift"
    echo 'extension StickerSamples {'
    awk '/^    static func pack\(/ {found=1} /^    static var stories:/ {exit} found {print}
         END {if (!found) exit 1}' "$checkout/Packages/SignalUI/Tests/SignalUITests/Components/Stickers/StickerManagerTests.swift"
    echo '}'
} > "$target_dir/StickerManagerSamples.swift"
for cover in kitten-1-64-64.jpg kitten-2-64-64.jpg kitten-3-64-64.jpg; do
    if [ -f "$checkout/Signal-Desktop/fixtures/$cover" ]; then cp "$checkout/Signal-Desktop/fixtures/$cover" "$target_dir/Media/"; fi
done
cp "$source_dir/Components/LightboxZoom.swift" "$target_dir/"
# Assemble the photo viewer from the original screen. The live video branch uses
# the app’s Metal and AVFAudio playback engine and is outside this photo fixture.
awk '
    /^\/\/\/ Chromium.s native media controls/ {exit}
    /public var player: VideoPlaybackEngine/ || /self.player = player/ {next}
    {sub(/, player: VideoPlaybackEngine\? = nil/, "")}
    /^            case \.video:$/ {video=1; next}
    video && /^            case \.unsupportedImage:/ {print "            case .video: unsupported(\"movie\", label: i18n(\"icu:unsupportedAttachment\"))"; video=0; branches++}
    /if isViewOnce, current\?\.kind == \.video, let player/ {time=1; next}
    time && /^            }/ {time=0; timers++; next}
    !video && !time {print}
    END {if (branches!=1 || timers!=1) exit 1}
' "$source_dir/Components/Lightbox.swift" > "$target_dir/Lightbox.swift"
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
# The color-editor dialog uses the actual header, tab, scroll and action implementations.
# Two unrelated slot types use Serein's CoreText-only measurement helpers.
awk '/^    public struct (BodyTitle|FooterContent):/ { skip=1; count++ }
     !skip { print } /^    }$/ { skip=0 } END { if (count!=2) exit 1 }' \
    "$source_dir/Axo/AxoDialog.swift" > "$target_dir/AxoDialog.swift"
cp "$source_dir/Components/Select.swift" "$source_dir/Components/DisappearingTimeDialog.swift" "$target_dir/"
cp "$source_dir/Axo/AxoTabs.swift" "$source_dir/Components/CustomColorEditor.swift" \
   "$source_dir/Components/Conversation/ExpireTimer.swift" "$source_dir/Tokens/AxoTokens.swift" \
   "$source_dir/Tokens/AxoTokensTables.generated.swift" "$target_dir/"
# Inline text uses this CoreText width calculation elsewhere. The editor renders the
# full MessageMetadata body and measures it through SwiftUI layout.
awk '/^    @MainActor func width\(i18n:/ { skip=1; count++ }
     !skip { print } /^    }$/ { skip=0 } END { if (count!=1) exit 1 }' \
    "$source_dir/Components/Conversation/Message/MessageMetadata.swift" > "$target_dir/MessageMetadata.swift"
{
    echo 'import SwiftUI'
    echo 'import SignalI18n'
    declarations '^extension RGBA ' 1 "$source_dir/Components/Conversation/Quote.swift"
    declarations '^public enum BubbleColor:|^struct BubbleFill:' 2 "$source_dir/Components/Conversation/Message/Message.swift"
    declarations '^struct UndimmedButtonStyle:' 1 "$source_dir/Calling/CallingButton.swift"
    declarations '^extension FormatTimestamp ' 2 "$source_dir/Components/Conversation/TimelineDateHeader.swift"
    declarations '^public enum FormatTimestamp ' 1 "$source_dir/Components/LeftPaneDialogs.swift"
    awk '/^public enum MessageDirection:/ { print; count++ } END { if (count!=1) exit 1 }' "$source_dir/Components/Conversation/MessageTextRenderer.swift"
    awk 'BEGIN { print "extension EnvironmentValues {" } /@Entry public var chatColorViewport:/ { print; count++ }
         END { print "}"; if (count!=1) exit 1 }' "$source_dir/Components/Conversation/Message/Message.swift"
} > "$target_dir/EditorSupport.swift"
cp "$source_dir/Theme/I18nRichText.swift" "$source_dir/Calling/CallQualitySurveyDialog.swift" "$source_dir/Axo/AxoCheckbox.swift" "$source_dir/Axo/AxoSwitch.swift" "$target_dir/"
cp "$source_dir/Components/ChatColorPicker.swift" "$source_dir/Axo/AxoContainer.swift" \
   "$source_dir/Axo/Items/AxoClickableItem.swift" "$target_dir/"
cp "$source_dir/Components/Preferences/PreferencesCallsPage.swift" "$source_dir/Components/Preferences/PreferencesList.swift" \
   "$source_dir/Components/CallingDeviceSelectionItems.swift" "$source_dir/Axo/AxoPanel.swift" "$source_dir/Axo/AxoScrollArea.swift" \
   "$source_dir/Axo/Items/AxoSwitchItem.swift" "$source_dir/Axo/Items/AxoSelectItem.swift" "$source_dir/Axo/Items/AxoList.swift" "$target_dir/"
cp "$source_dir/Components/Avatar.swift" "$source_dir/Theme/StaticAwareScrollView.swift" "$target_dir/"
{
    echo 'import SwiftUI'
    echo 'import SignalI18n'
    declarations '^public struct CallingConversation:' 1 "$source_dir/Calling/CallingModels.swift"
    declarations '^public struct ConversationAvatarData |^struct ListAvatar:' 2 "$source_dir/Components/ConversationList/BaseConversationListItem.swift"
    awk '/^public enum Call(Type|Direction):/ { print; count++ } END { if (count!=2) exit 1 }' "$source_dir/Components/Conversation/Notifications/CallingNotification.swift"
    declarations '^public enum CallStatus:' 1 "$source_dir/Components/Conversation/Notifications/CallingNotification.swift"
    declarations '^extension AvatarStrings ' 1 "$source_dir/Components/ConversationList/BaseConversationListItem.swift"
    declarations '^public struct ComposeStepButton:' 1 "$source_dir/Components/ConversationList/ComposeRows.swift"
    declarations '^struct ClearFilterButton:' 1 "$source_dir/Components/ConversationList/ConversationList.swift"
    declarations '^public struct I18n:' 1 "$source_dir/Components/SmallDialogs.swift"
    declarations '^public struct SearchInput<|^extension EnvironmentValues |^extension SearchInput where' 3 "$source_dir/Components/SearchInput.swift"
    declarations '^public struct ListTile<|^extension EnvironmentValues ' 2 "$source_dir/Components/ListTile.swift"
} > "$target_dir/CallsHistory.swift"
# Replace CoreText font measurement in the select trigger with the portable font metrics.
sed -e '/^import CoreText$/d' -e 's/CSSTextStyle(text).ctFont/AxoFonts.interMetrics(size: text.size)/' \
    -e 's/AxoSymbol.style(size: iconSize, weight: 400).ctFont/AxoFonts.metrics(family: "Signal Symbols", size: iconSize)/' \
    -e 's/CTFontGetAscent(\([ts]\))/\1.ascent/g' -e 's/CTFontGetDescent(\([ts]\))/\1.descent/g' \
    "$source_dir/Axo/AxoSelect.swift" > "$target_dir/AxoSelect.swift"
declarations '^public enum AxoInlinePiece:' 1 "$source_dir/Axo/Chat/AxoInlineFlow.swift" > "$target_dir/InlinePiece.swift"
awk 'BEGIN { print "extension SettingsModel {" } /^    static let microphones =/ { inside=1; count++ }
     inside && /^$/ { inside=0 } inside { print } END { print "}"; if (count!=1 || inside) exit 1 }' \
    "$checkout/Packages/SignalUI/Tests/SignalUITests/Components/Preferences/PreferencesTests.swift" > "$target_dir/SettingsDevices.swift"
cp "$source_dir/Calling/CallLinkDetails.swift" "$source_dir/Components/Conversation/ConversationDetails/CallHistoryGroupPanelSection.swift" \
   "$source_dir/Components/EditNicknameAndNoteModal.swift" "$source_dir/Axo/AxoAvatar.swift" "$source_dir/Axo/Items/AxoTextItem.swift" \
   "$source_dir/Axo/AxoThemeOverride.swift" "$source_dir/Axo/AxoContactName.swift" \
   "$source_dir/Axo/Fields/AxoBaseField.swift" "$source_dir/Axo/Fields/AxoFieldGroup.swift" "$source_dir/Axo/Fields/AxoTextField.swift" \
   "$source_dir/Axo/Items/AxoFieldList.swift" "$source_dir/Axo/Items/AxoItem.swift" "$target_dir/"
{
    echo 'import SwiftUI'
    echo 'import SignalI18n'
    declarations '^func callLinkColor[(]' 1 "$source_dir/Components/Conversation/Message/MessageLinkPreview.swift"
    declarations '^public enum SharedGroupNames |^extension SharedGroupNames ' 2 "$source_dir/Components/Conversation/ConversationHero.swift"
    declarations '^public struct CallLink(EditModal|AddNameModal|PendingParticipantModal):|^struct CallLinkURLButton:' 4 "$source_dir/Calling/CallLinkModals.swift"
    awk 'BEGIN {print "enum CallingNotification {"} /^    static func directText\(/ { inside=1; count++ }
         inside { print } /^    }$/ { inside=0 } END {print "}"; if (count!=1 || inside) exit 1}' \
        "$source_dir/Components/Conversation/Notifications/CallingNotification.swift"
} > "$target_dir/CallLinkModals.swift"
awk 'BEGIN { print "import SwiftUI\nextension CallLinkModel {" } /^    static let now =/ {copy=1; count++}
     copy {print} /^    nonisolated static let fun =/ {copy=0} END {print "}"; if (count!=1 || copy) exit 1}' \
    "$checkout/Packages/SignalUI/Tests/SignalUITests/Calling/CallLinkDetailsTests.swift" > "$target_dir/CallLinkSample.swift"
cp "$source_dir/Components/Conversation/AboutContactModal.swift" "$source_dir/Components/Conversation/Emojify.swift" \
   "$source_dir/Components/Fun/EmojiData.swift" "$source_dir/Resources/emoji-data.json" "$target_dir/"
{
    echo 'import Foundation'
    echo 'import SwiftUI'
    echo 'import SignalText'
    echo 'import SignalI18n'
    declarations '^extension RichText ' 1 "$source_dir/Components/Conversation/Notifications/ChatEventNotifications.swift"
    declarations '^public struct Linkify:' 1 "$source_dir/Components/Conversation/Linkify.swift"
    awk 'BEGIN {print "enum CSSTextLayout {"} /^    static func isEmoji\(/ {inside=1; count++}
         inside {print} /^    }$/ {inside=0} END {print "}"; if (count!=1) exit 1}' "$source_dir/Theme/CSSText.swift"
    awk 'BEGIN {print "extension EnvironmentValues {"} /@Entry public var brandLogo:/ {print; count++}
         END {print "}"; if (count!=1) exit 1}' "$source_dir/Theme/PixelImage.swift"
} > "$target_dir/ContactText.swift"
# Route the two desktop URL launches through SwiftUI's injectable application action.
{
    cat "$source_dir/Components/About.swift"
    declarations '^public struct NotePreviewModal:' 1 "$source_dir/Components/SmallDialogs.swift"
} > "$target/ContactDialogs.swift"
awk '!/^import AppKit$/ {printLine=$0; gsub(/NSWorkspace.shared.open/, "openURL", printLine); print printLine
     if (/^public struct (About|NotePreviewModal):/) {print "    @Environment(\\.openURL) private var openURL"; count++}}
     END {if (count!=2) exit 1}' "$target/ContactDialogs.swift" > "$target_dir/ContactDialogs.swift"
cp "$source_dir/Components/Inbox.swift" "$source_dir/Components/NavTabs.swift" "$target_dir/"
{
    echo 'import SwiftUI'
    declarations '^struct LeftPaneEmptyView<' 1 "$source_dir/Components/LeftPane/LeftPane.swift"
    echo 'struct EmptyChatsPreview: View {'
    echo '    @Environment(\.i18n) var i18n'
    echo '    var body: some View {'
    awk '/^        return AnyView\(LeftPaneEmptyView \{/ {inside=1; count++}
         inside {print} /^        \}\)/ {inside=0}
         END {if (count!=1 || inside) exit 1}' "$source_dir/Components/LeftPane/LeftPaneInboxHelper.swift"
    echo '    }'
    echo '}'
} > "$target_dir/EmptyChats.swift"
cp "$source_dir/Calling/CallsTab.swift" "$source_dir/Components/NavSidebar.swift" "$target_dir/"
# Keep all original item slots and use portable font metrics for the icon baseline.
awk '!/^import CoreText$/ {
         if (/let font = CSSTextStyle.*\.ctFont/) { print "            let font = AxoFonts.interMetrics(size: size)"; metrics++; next }
         gsub(/CTFontGetAscent\(font\)/, "font.ascent"); gsub(/CTFontGetDescent\(font\)/, "font.descent")
         gsub(/CTFontGetXHeight\(font\)/, "font.xHeight"); print }
     END { if (metrics!=1) exit 1 }' "$source_dir/Axo/Items/AxoBaseItem.swift" > "$target_dir/AxoBaseItem.swift"
awk 'BEGIN { print "extension ChatColorPickerPreview {" } /^    static let customColors:/ { inside=1; count++ }
     inside { print } /^    ]$/ { inside=0 } END { print "}"; if (count!=1 || inside) exit 1 }' \
    "$checkout/Packages/SignalUI/Tests/SignalUITests/Components/ChatColorPickerTests.swift" > "$target_dir/PickerColors.swift"
# AxoButton uses the type scale. The rest of AxoType.swift defines a CoreText modifier.
awk '/^public struct AxoType: / { print "import SwiftUI"; inside = 1 }
     inside { print } inside && /^}$/ { complete = 1; exit } END { if (!complete) exit 1 }' \
    "$source_dir/Theme/AxoType.swift" > "$target_dir/AxoType.swift"
mkdir -p "$target_dir/Fonts"
cp "$source_dir"/Resources/Fonts/Inter-*.ttf "$source_dir/Resources/Fonts/SignalSymbolsVariable.ttf" "$source_dir"/Resources/Fonts/SignalEmoji*.ttf "$target_dir/Fonts/"
if [ "$(uname -s)" = Linux ]; then cp "$root/Package.resolved" "$target/Package.resolved"; fi
cat > "$target/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
var packages: [Package.Dependency] = [.package(path: "SignalI18n"), .package(path: "SignalText"), .package(path: "SignalCodecs")]
var dependencies: [Target.Dependency] = [.product(name: "SignalI18n", package: "SignalI18n"),
    .product(name: "SignalText", package: "SignalText"), .product(name: "CodecCore", package: "SignalCodecs"), .product(name: "ImagePNG", package: "SignalCodecs"),
    .product(name: "ImageBMP", package: "SignalCodecs"), .product(name: "ImageJPEG", package: "SignalCodecs"), .product(name: "EncodePNG", package: "SignalCodecs")]
#if os(Linux)
packages.append(.package(name: "QtSwiftUI", path: "/src"))
dependencies.append(.product(name: "SwiftUI", package: "QtSwiftUI"))
#endif
let package = Package(name: "CallDiagnostics", platforms: [.macOS("27.0")], dependencies: packages,
                      targets: [.executableTarget(name: "CallDiagnostics", dependencies: dependencies, resources: [.copy("Fonts"), .copy("Media"), .copy("emoji-data.json")]),
                                .testTarget(name: "ScreenTests", dependencies: ["CallDiagnostics"] + dependencies)])
SWIFT
