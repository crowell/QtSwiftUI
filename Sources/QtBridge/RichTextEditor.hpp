#pragma once
#include "PlainTextEditor.hpp"
#include "TextFormat.hpp"
#include <QTextBlock>

// The document stores the Swift attribute identifier in its native character format.
// Qt carries that identifier through input, deletion and undo, including attributes it cannot paint.
class RichTextEditor final : public PlainTextEditor {
public:
    using PlainTextEditor::PlainTextEditor;
    static constexpr int attributeID = QTextFormat::UserProperty + 20;

    void define(int id, QTextCharFormat format) {
        format.setProperty(attributeID, id);
        formats.insert(id, format);
    }
    void begin() { pending.clear(); }
    void append(const QString &text, int id) { pending.append({text, id}); }
    void finish() {
        const QSignalBlocker blocker(this);
        const int previousAnchor = textCursor().anchor(), previousPosition = textCursor().position();
        QString next;
        for (const auto &run : pending) next += run.first;
        const bool replace = value() != next;
        if (!initialized) setUndoRedoEnabled(false);
        QTextCursor edit(document());
        edit.beginEditBlock();
        if (replace) {
            edit.select(QTextCursor::Document);
            edit.removeSelectedText();
            for (const auto &run : pending) edit.insertText(run.first, formats.value(run.second));
        } else {
            int position = 0;
            for (const auto &run : pending) {
                edit.setPosition(position);
                position += run.first.size();
                edit.setPosition(position, QTextCursor::KeepAnchor);
                edit.setCharFormat(formats.value(run.second));
            }
        }
        edit.endEditBlock();
        if (!initialized) setUndoRedoEnabled(true);
        if (replace || !initialized) {
            const int end = document()->characterCount() - 1;
            QTextCursor cursor(document());
            cursor.setPosition(initialized ? qMin(previousAnchor, end) : end);
            cursor.setPosition(initialized ? qMin(previousPosition, end) : end, QTextCursor::KeepAnchor);
            setTextCursor(cursor);
        }
        initialized = true;
        pending.clear();
    }
    void typing(int id) {
        const auto format = formats.value(id);
        if (textCursor().hasSelection() || currentCharFormat() == format) return;
        const QSignalBlocker blocker(this);
        setCurrentCharFormat(format);
    }
    void read(void *context, QSEditorRun receive) const {
        const auto emitRun = [=](const QString &text, const QTextCharFormat &format) {
            const auto bytes = text.toUtf8();
            receive(context, format.intProperty(attributeID), bytes.constData(), size_t(bytes.size()));
        };
        for (auto block = document()->begin(); block.isValid(); block = block.next()) {
            if (block.position()) emitRun(QStringLiteral("\n"), block.charFormat());
            for (auto it = block.begin(); !it.atEnd(); ++it) {
                const auto fragment = it.fragment();
                emitRun(fragment.text(), fragment.charFormat());
            }
        }
    }
private:
    QHash<int, QTextCharFormat> formats;
    QList<QPair<QString, int>> pending;
    bool initialized = false;
};
