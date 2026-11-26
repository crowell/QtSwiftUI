#pragma once
#include "TextElision.hpp"
#include <QLabel>
#include <QFontMetricsF>

class PlainLabel final : public QLabel {
public:
    explicit PlainLabel(QWidget *parent) : QLabel(parent) {
        setTextFormat(Qt::PlainText);
        setMargin(0);
    }

    void setSource(const QString &value) {
        if (value == source) return;
        source = value;
        dirty = true;
        setText(value);
    }

    QString intrinsicText(int limit, Qt::TextElideMode mode) const {
        if (limit <= 0 || !source.contains('\n')) return source;
        int end = -1;
        for (int line = 0; line < limit; ++line) {
            end = source.indexOf('\n', end + 1);
            if (end < 0) return source;
        }
        QString prefix = source.left(end);
        if (mode == Qt::ElideRight) prefix.append(QChar(0x2026));
        return prefix;
    }

    void display(int limit, Qt::TextElideMode mode) {
        if (!dirty && previousWidth == width() && previousFont == font() && previousLimit == limit && previousMode == mode) return;
        previousWidth = width();
        previousFont = font();
        previousLimit = limit;
        previousMode = mode;
        dirty = false;
        QString visible = source;
        if (limit == 1 && !source.contains('\n') && !source.contains(QChar::LineSeparator)) {
            const int natural = fontMetrics().boundingRect(QRect(0, 0, 1000000, 1000000),
                                                           Qt::TextExpandTabs | Qt::TextDontClip, source).width();
            if (natural > width()) visible = QFontMetricsF(font()).elidedText(source, mode, width(), Qt::TextExpandTabs);
        } else if (limit > 0) {
            QTextDocument original;
            original.setDocumentMargin(0);
            original.setDefaultFont(font());
            QTextOption option;
            option.setWrapMode(wordWrap() ? QTextOption::WrapAtWordBoundaryOrAnywhere : QTextOption::NoWrap);
            original.setDefaultTextOption(option);
            original.setPlainText(source);
            if (auto shortened = elidedDocument(original, width(), limit, mode)) visible = shortened->toPlainText();
        }
        if (text() != visible) setText(visible);
    }

    QString source;
private:
    QFont previousFont;
    int previousWidth = -1, previousLimit = 0;
    Qt::TextElideMode previousMode = Qt::ElideRight;
    bool dirty = true;
};
