import QtBridge

@_spi(Qt) public enum QtTextLayout {
    public struct Line: Sendable {
        /// Range in the original UTF-16 string, excluding any paragraph separator.
        public let range: NSRange
        public let width: CGFloat
        public let advance: CGFloat
        public let height: CGFloat
    }

    public static func lines(in text: AttributedString, font: Font, tracking: CGFloat = 0,
                             width: CGFloat? = nil, breaksLongWords: Bool = false) -> [Line] {
        guard !text.characters.isEmpty else { return [] }
        let paragraph = qs_text_paragraph(font.qtFamily, font.size, font.qtWeight, font.slanted ? 1 : 0, tracking)
        defer { qs_paragraph_free(paragraph) }
        for run in text.runs {
            let value = String(text[run.range].characters)
            let face = run.font
            value.withCString { bytes in
                qs_paragraph_append(paragraph, bytes, value.utf8.count, face?.qtFamily ?? "", Double(face?.size ?? 0),
                                    face?.qtWeight ?? -1, face?.slanted == true ? 1 : 0, Double(run.tracking ?? run.kern ?? .nan))
            }
        }
        var lines: [Line] = []
        withUnsafeMutablePointer(to: &lines) { result in
            qs_paragraph_measure(paragraph, width ?? -1, breaksLongWords ? 1 : 0, result) { context, start, length, width, advance, height in
                context!.assumingMemoryBound(to: [Line].self).pointee.append(
                    Line(range: NSRange(location: Int(start), length: Int(length)), width: width, advance: advance, height: height))
            }
        }
        return lines
    }
}
