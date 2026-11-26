#pragma once
#include <QPlainTextEdit>
#include <QScrollBar>
#include <QSignalBlocker>
#include <QTextCursor>

class PlainTextEditor final : public QPlainTextEdit {
public:
    explicit PlainTextEditor(QWidget *parent) : QPlainTextEdit(parent) {
        setFrameShape(QFrame::NoFrame);
        document()->setDocumentMargin(0);
        setViewportMargins(5, 0, 5, 0);
        setTabChangesFocus(false);
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
