#pragma once
#include "SubmitKeyEditor.hpp"
#include <QPlainTextEdit>
#include <QScrollBar>
#include <QSignalBlocker>
#include <QTextCursor>
#include <QTextBlock>
#include <QKeyEvent>
#include <functional>

class PlainTextEditor : public SubmitKeyEditor<QPlainTextEdit> {
public:
    explicit PlainTextEditor(QWidget *parent) : SubmitKeyEditor(parent) {
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
        connect(verticalScrollBar(), &QScrollBar::valueChanged, this,
                &PlainTextEditor::revealFittingLines, Qt::QueuedConnection);
    }
    void resizeEvent(QResizeEvent *event) override {
        QPlainTextEdit::resizeEvent(event);
        revealFittingLines();
    }
    void revealFittingLines() {
        // A fixed-size field grows after its edit notification. Qt can still be
        // scrolled to a wrapped line from the previous, narrower viewport.
        if (!submit || !verticalScrollBar()->value()) return;
        qreal height = 0;
        for (auto block = document()->begin(); block.isValid(); block = block.next()) {
            height += blockBoundingRect(block).height();
            if (height > viewport()->height()) return;
        }
        verticalScrollBar()->setValue(0);
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

};
