#pragma once
#include <QPlainTextEdit>
#include <QScrollBar>
#include <QSignalBlocker>
#include <QTextCursor>
#include <QTextLayout>
#include <QKeyEvent>
#include <functional>
#include <cmath>

class PlainTextEditor : public QPlainTextEdit {
public:
    explicit PlainTextEditor(QWidget *parent) : QPlainTextEdit(parent) {
        setFrameShape(QFrame::NoFrame);
        document()->setDocumentMargin(0);
        setViewportMargins(5, 0, 5, 0);
        setTabChangesFocus(false);
    }

    std::function<void()> submit;
    void configureField() {
        setViewportMargins(0, 0, 0, 0);
        setTabChangesFocus(true);
        setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
        setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    }
    double fieldHeight(double width, int minimum, int maximum) const {
        const int margins = frameWidth() * 2;
        int lines = 0;
        const QString displayed = document()->isEmpty() ? placeholderText() : value();
        for (const auto &paragraph : displayed.split(QChar::LineFeed)) {
            QTextLayout layout(paragraph, font());
            layout.setTextOption(document()->defaultTextOption());
            layout.beginLayout();
            int count = 0;
            while (true) {
                auto line = layout.createLine();
                if (!line.isValid()) break;
                line.setLineWidth(width < 0 || !std::isfinite(width) ? 1e7 : qMax(1.0, width - margins));
                ++count;
                if (maximum > 0 && lines + count >= maximum) break;
            }
            layout.endLayout();
            lines += qMax(1, count);
            if (maximum > 0 && lines >= maximum) break;
        }
        return qMax(minimum, lines) * fontMetrics().lineSpacing() + margins;
    }
    void keyPressEvent(QKeyEvent *event) override {
        if (submit && (event->key() == Qt::Key_Return || event->key() == Qt::Key_Enter)) {
            if (event->modifiers() & (Qt::ShiftModifier | Qt::AltModifier)) insertPlainText(QStringLiteral("\n"));
            else submit();
            event->accept();
            return;
        }
        QPlainTextEdit::keyPressEvent(event);
    }

    QString value() const {
        // toPlainText() also converts nonbreaking spaces to ordinary spaces.
        return document()->toRawText().replace(QChar::ParagraphSeparator, QChar::LineFeed);
    }

    void applyText(const QString &next) {
        if (value() == next) return;
        const QSignalBlocker block(this);
        const auto previous = textCursor();
        const int position = previous.position(), anchor = previous.anchor();
        const int scroll = verticalScrollBar()->value();
        setPlainText(next);
        auto cursor = textCursor();
        const int end = document()->characterCount() - 1;
        cursor.setPosition(qMin(end, anchor));
        cursor.setPosition(qMin(end, position), QTextCursor::KeepAnchor);
        setTextCursor(cursor);
        verticalScrollBar()->setValue(scroll);
    }

    QByteArray utf8;
};
