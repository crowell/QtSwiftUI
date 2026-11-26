#include "QtBridge.h"
#include "TextParagraph.hpp"
#include "TextElision.hpp"
#include "TextFormat.hpp"
#include <QAbstractTextDocumentLayout>
#include <QGuiApplication>
#include <QTextBlock>
#include <QWidget>
#include <cmath>

void qs_canvas_text_append(void *target, const char *utf8, size_t count, const char *link, const char *foreground,
                           const char *background, const char *family, double size, int weight, int italic,
                           int underline, const char *underlineColor, int strike, const char *strikeColor, double spacing) {
    auto &paragraph = *static_cast<QSTextParagraph *>(target);
    bool customStrike;
    const auto format = swiftTextFormat(paragraph.document.defaultFont(), QGuiApplication::palette(), link, foreground,
                                        background, family, size, weight, italic, underline, underlineColor,
                                        strike, strikeColor, spacing, customStrike);
    paragraph.customStrikes |= customStrike;
    paragraph.cursor.insertText(QString::fromUtf8(utf8, qsizetype(count)), format);
}

void qs_canvas_text_outline(QSTextParagraph *paragraph, const char *color, double width) {
    QPen pen(QColor(QString::fromUtf8(color)), width, Qt::SolidLine, Qt::SquareCap, Qt::MiterJoin);
    pen.setMiterLimit(4);
    QTextCharFormat format;
    format.setTextOutline(pen);
    QTextCursor cursor(&paragraph->document);
    cursor.select(QTextCursor::Document);
    cursor.mergeCharFormat(format);
}

QSCanvasTextMetrics qs_canvas_text_fit(QSTextParagraph *paragraph, double width, double height, int alignment,
                                       double spacing, int limit, QSTextTruncation mode) {
    auto &doc = paragraph->document;
    const bool constrained = std::isfinite(width) && width < QWIDGETSIZE_MAX;
    auto option = doc.defaultTextOption();
    option.setAlignment(Qt::AlignAbsolute | (alignment < 0 ? Qt::AlignLeft : alignment > 0 ? Qt::AlignRight : Qt::AlignHCenter));
    option.setWrapMode(constrained ? QTextOption::WrapAtWordBoundaryOrAnywhere : QTextOption::NoWrap);
    doc.setDefaultTextOption(option);
    if (spacing > 0 && std::isfinite(spacing)) {
        QTextCursor blocks(&doc);
        blocks.select(QTextCursor::Document);
        QTextBlockFormat format;
        format.setLineHeight(spacing, QTextBlockFormat::LineDistanceHeight);
        blocks.mergeBlockFormat(format);
    }
    doc.setTextWidth(constrained ? qMax(1.0, width) : -1);
    (void)doc.size();
    int visible = 0;
    for (auto block = doc.begin(); block.isValid(); block = block.next()) {
        const auto *layout = block.layout();
        const auto top = doc.documentLayout()->blockBoundingRect(block).top();
        for (int i = 0; i < layout->lineCount(); ++i) {
            const auto line = layout->lineAt(i);
            if ((limit > 0 && visible >= limit) || (visible && top + line.y() + line.height() > height))
                break;
            ++visible;
        }
        if ((limit > 0 && visible >= limit) || top + layout->boundingRect().height() >= height) break;
    }
    const auto elide = mode == QSTruncateHead ? Qt::ElideLeft : mode == QSTruncateMiddle ? Qt::ElideMiddle : Qt::ElideRight;
    paragraph->display = elidedDocument(doc, constrained ? qMax(1.0, width) : doc.idealWidth() + 1, qMax(1, visible), elide);
    auto &display = paragraph->visible();
    QSCanvasTextMetrics metrics{};
    bool first = true;
    for (auto block = display.begin(); block.isValid(); block = block.next()) {
        const auto top = display.documentLayout()->blockBoundingRect(block).top();
        const auto *layout = block.layout();
        for (int i = 0; i < layout->lineCount(); ++i) {
            const auto line = layout->lineAt(i);
            const auto y = top + line.y();
            metrics.width = qMax(metrics.width, std::ceil(line.naturalTextWidth()));
            metrics.height = qMax(metrics.height, std::ceil(y + line.height()));
            metrics.lastBaseline = y + line.ascent();
            if (first) { metrics.firstBaseline = metrics.lastBaseline; first = false; }
        }
    }
    if (constrained) metrics.width = qMin(metrics.width, qMax(0.0, width));
    return metrics;
}
