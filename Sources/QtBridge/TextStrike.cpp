#include "TextStrike.hpp"
#include <QAbstractTextDocumentLayout>
#include <QFontMetricsF>
#include <QPalette>
#include <QTextBlock>
#include <QTextLayout>
#include <algorithm>

namespace {
constexpr int strikeStyle = QTextFormat::UserProperty + 1;
constexpr int strikeInk = QTextFormat::UserProperty + 2;

void drawRun(QPainter &painter, const QTextLayout &layout, const QTextLine &line,
             int first, int end, qreal y) {
    // Logical neighbors can occupy separate visual spans when the run includes bidi text.
    QList<QPair<qreal, qreal>> spans;
    for (int at = first; at < end; at = layout.nextCursorPosition(at)) {
        qreal a = line.cursorToX(at, QTextLine::Leading), b = line.cursorToX(at, QTextLine::Trailing);
        if (a != b) spans.append({qMin(a, b), qMax(a, b)});
    }
    std::sort(spans.begin(), spans.end());
    for (int i = 0; i < spans.size();) {
        const qreal left = spans[i].first;
        qreal right = spans[i++].second;
        while (i < spans.size() && spans[i].first <= right + 0.5) right = qMax(right, spans[i++].second);
        painter.drawLine(QPointF(left, y), QPointF(right, y));
    }
}
}

bool setStrikeFormat(QTextCharFormat &format, int style, const QString &color) {
    if (!style) return false;
    if (style == Qt::SolidLine && color.isEmpty()) {
        format.setFontStrikeOut(true);
        return false;
    }
    format.setProperty(strikeStyle, style);
    if (!color.isEmpty()) format.setProperty(strikeInk, QColor(color));
    return true;
}

void drawTextStrikes(QPainter &painter, QTextDocument &document, const QPalette &palette) {
    for (auto block = document.begin(); block.isValid(); block = block.next()) {
        const auto *layout = block.layout();
        painter.save();
        painter.translate(document.documentLayout()->blockBoundingRect(block).topLeft());
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            const auto format = fragment.charFormat();
            if (!format.hasProperty(strikeStyle)) continue;
            QColor color = format.property(strikeInk).value<QColor>();
            if (!color.isValid()) color = format.foreground().style() == Qt::NoBrush ? palette.color(QPalette::Text) : format.foreground().color();
            const QFontMetricsF metrics(format.font().resolve(document.defaultFont()));
            painter.setPen(QPen(color, metrics.lineWidth(), Qt::PenStyle(format.intProperty(strikeStyle)), Qt::FlatCap));
            const int first = fragment.position() - block.position(), end = first + fragment.length();
            for (int i = 0; i < layout->lineCount(); ++i) {
                const auto line = layout->lineAt(i);
                const int begin = qMax(first, line.textStart()), stop = qMin(end, line.textStart() + line.textLength());
                if (begin < stop) drawRun(painter, *layout, line, begin, stop, line.y() + line.ascent() - metrics.strikeOutPos());
            }
        }
        painter.restore();
    }
}
