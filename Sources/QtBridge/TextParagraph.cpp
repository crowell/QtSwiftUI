#include "QtBridge.h"
#include "RegisteredFonts.hpp"
#include "TextParagraph.hpp"
#include "TextFormat.hpp"
#include <QTextBlock>
#include <algorithm>
#include <cmath>

void qs_paragraph_append(QSTextParagraph *paragraph, const char *text, size_t length, const char *family,
                         double size, int weight, int italic, double spacing) {
    QTextCharFormat format;
    if (size > 0) {
        auto font = resolveFont(paragraph->document.defaultFont(), QString::fromUtf8(family), weight, italic);
        font.setPixelSize(qMax(1, qRound(size)));
        font.setLetterSpacing(QFont::AbsoluteSpacing, paragraph->tracking);
        format.setFont(font);
    }
    setRunSpacing(format, spacing);
    auto string = QString::fromUtf8(text, qsizetype(length));
    if (string.isEmpty()) return;
    // QTextDocument stores CRLF as one paragraph separator. Keep public ranges
    // in original UTF-16 offsets, including a CRLF split across styled runs.
    const int base = paragraph->cursor.position();
    if (paragraph->endedWithCR && string.front() == QChar::LineFeed) {
        paragraph->collapsedSeparators.append(base);
        string.remove(0, 1);
    }
    paragraph->endedWithCR = string.endsWith(QChar::CarriageReturn);
    int removed = 0;
    for (auto at = string.indexOf("\r\n"); at >= 0; at = string.indexOf("\r\n", at + 2))
        paragraph->collapsedSeparators.append(base + int(at) + 1 - removed++);
    string.replace("\r\n", "\n");
    paragraph->cursor.insertText(string, format);
}

void qs_paragraph_measure(QSTextParagraph *paragraph, double width, int breakWords, void *context, QSMeasuredLine receive) {
    auto &document = paragraph->document;
    QTextOption option;
    const bool wrapped = std::isfinite(width) && width >= 0;
    option.setWrapMode(wrapped ? (breakWords ? QTextOption::WrapAtWordBoundaryOrAnywhere : QTextOption::WordWrap) : QTextOption::NoWrap);
    document.setDefaultTextOption(option);
    document.setTextWidth(wrapped ? width : -1);
    (void)document.size();
    auto sourceOffset = [&](int position) -> int {
        const auto &separators = paragraph->collapsedSeparators;
        return position + int(std::upper_bound(separators.begin(), separators.end(), position) - separators.begin());
    };
    for (auto block = document.begin(); block.isValid(); block = block.next()) {
        const auto *layout = block.layout();
        for (int i = 0; i < layout->lineCount(); ++i) {
            const auto line = layout->lineAt(i);
            const int position = block.position() + line.textStart();
            const int start = sourceOffset(position);
            receive(context, start, sourceOffset(position + line.textLength()) - start, line.naturalTextWidth(),
                    line.horizontalAdvance(), line.height());
        }
    }
}

void qs_paragraph_free(QSTextParagraph *paragraph) { delete paragraph; }
