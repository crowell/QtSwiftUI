#!/bin/sh
# Assemble Serein's live Linux composer with its production fonts and styles.
set -eu
serein=$(cd "${1:?pass the Serein Linux checkout}" && pwd)
work=${2:?pass an empty package directory}
root=$(cd "$(dirname "$0")/.." && pwd)
src="$serein/Packages/SignalUI/Sources/SignalUI"
target="$work/Sources/ComposerCheck"
mkdir -p "$target"
cp "$root/Scripts/ComposerCheck/Package.swift" "$work/"
cp "$root/Scripts/ComposerCheck/Check.swift" "$target/"
ln -s "$root" "$work/QtSwiftUI"
ln -s "$serein/Packages/SignalCodecs" "$work/SignalCodecs"
ln -s "$serein/Packages/SignalI18n" "$work/SignalI18n"
for file in Theme/AxoColor Theme/AxoFonts Theme/AxoType Theme/AxoShadow Theme/CSSText Theme/FontMetrics Theme/CSSInlineTail \
            Tokens/AxoTokens.generated Components/Fun/EmojiData Axo/Chat/AxoInlineFlow Linux/LineClampText+Qt Linux/AxoInlineFlowText+Qt Linux/CSSText+Qt \
            Theme/AxoMotion Theme/I18nEnvironment Tokens/LegacyColors.generated Components/LegacyType Components/CompositionInput Components/ComposerDraft \
            Linux/ComposerController+Linux Linux/ComposerTextView+Linux Components/Conversation/Emojify Tokens/AxoSymbolDefs.generated Axo/AxoSymbol; do
    ln -sf "$src/$file.swift" "$target/"
done
awk '/^public struct MentionSuggestions:/{skip=1} !skip {print} /^}/{skip=0}' "$src/Components/ComposerController.swift" > "$target/ComposerController.swift"
{ echo 'import Foundation'; awk '/^public struct BodyRange:/{take=1} take {print} /^}/{take=0}' "$src/Components/Conversation/BodyRanges.swift"; } > "$target/BodyRange.swift"
{ echo 'import Foundation'; echo 'import CodecCore'; awk '/^public struct RGBAImage:|^public final class RGBAAnimation:/{take=1} take {print} /^}/{take=0}' "$src/Theme/PixelImage.swift"; } > "$target/RGBAImage.swift"
cp -R "$src/Resources/Fonts" "$target/"
cp "$src/Resources/emoji-data.json" "$target/"
