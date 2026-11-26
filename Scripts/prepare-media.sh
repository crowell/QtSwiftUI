#!/bin/sh
# Assemble Serein's media renderer and account-key view with their production fonts and exporters.
set -eu
serein=$(cd "${1:?pass the Serein Linux checkout}" && pwd)
work=${2:?pass an empty package directory}
root=$(cd "$(dirname "$0")/.." && pwd)
src="$serein/Packages/SignalUI/Sources/SignalUI"
target="$work/Sources/MediaCheck"
mkdir -p "$target"
cp "$root/Scripts/MediaCheck/Package.swift" "$work/"
cp "$root/Scripts/MediaCheck/Check.swift" "$target/"
ln -s "$root" "$work/QtSwiftUI"
ln -s "$serein/Packages/SignalCodecs" "$work/SignalCodecs"
ln -s "$serein/Packages/SignalI18n" "$work/SignalI18n"
for file in Theme/AxoColor Theme/AxoFonts Theme/AxoType Theme/AxoShadow Theme/CSSText Theme/FontMetrics Theme/CSSInlineTail \
            Tokens/AxoTokens.generated Components/Fun/EmojiData Axo/Chat/AxoInlineFlow Linux/LineClampText+Qt Linux/AxoInlineFlowText+Qt Linux/CSSText+Qt \
            Theme/CSSShapes Theme/AxoMotion Theme/I18nEnvironment Tokens/LegacyColors.generated Components/LegacyType Components/CSSBlockText Components/IdenticonSVG \
            Components/MediaEditor/MediaEditorModel Components/MediaEditor/MediaEditorCanvas Components/MediaEditor/MediaEditorExport Linux/MediaEditorText+Qt Components/Conversation/Emojify Tokens/AxoSymbolDefs.generated Axo/AxoSymbol \
            Components/Preferences/AccountKeysPDF Components/Preferences/SignalLoginIllustration Axo/SVGPathData Theme/SignalIcon Tokens/SignalIcons.generated \
            Axo/AxoButton Axo/Status/AxoBaseSpinner Theme/CASpin Theme/AxoFocusRing; do
    ln -sf "$src/$file.swift" "$target/"
done

sed '/^public enum PromptOSAuthResult:/,$d' "$src/Components/Preferences/SignalAccountKeys.swift" > "$target/SignalAccountKeys.swift"
{ echo 'import Foundation'; echo 'import CodecCore'; awk '/^public struct RGBAImage:|^public final class RGBAAnimation:/{take=1} take {print} /^}/{take=0}' "$src/Theme/PixelImage.swift"; } > "$target/RGBAImage.swift"
cp -R "$src/Resources/Fonts" "$target/"
cp "$src/Resources/emoji-data.json" "$target/"
