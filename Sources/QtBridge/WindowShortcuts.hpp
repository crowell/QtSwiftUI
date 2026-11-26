#pragma once
#include <QAbstractButton>
#include <QHash>
#include <QPointer>
#include <QPushButton>
#include <QShortcut>
#include <QWidget>

class WindowShortcuts {
    struct Binding {
        QShortcut *shortcut;
        QPointer<QAbstractButton> target;
    };
    QHash<QKeySequence, Binding> bindings;

    struct KeyMapping { char32_t scalar; Qt::Key qt; };
    static constexpr KeyMapping special[] = {
        {0x08, Qt::Key_Backspace}, {0x09, Qt::Key_Tab}, {0x0d, Qt::Key_Return}, {0x1b, Qt::Key_Escape},
        {0xf700, Qt::Key_Up}, {0xf701, Qt::Key_Down}, {0xf702, Qt::Key_Left}, {0xf703, Qt::Key_Right},
        {0xf728, Qt::Key_Delete}, {0xf729, Qt::Key_Home}, {0xf72b, Qt::Key_End}, {0xf72c, Qt::Key_PageUp},
        {0xf72d, Qt::Key_PageDown}, {0xf739, Qt::Key_Clear}
    };
    static Qt::Key specialKey(char32_t character, bool mirror) {
        if (mirror && character == 0xf702) return Qt::Key_Right;
        if (mirror && character == 0xf703) return Qt::Key_Left;
        for (auto mapping : special) if (mapping.scalar == character) return mapping.qt;
        return static_cast<Qt::Key>(QChar::toUpper(character));
    }

public:
    static QString characters(int key, const QString &text) {
        if (key == Qt::Key_Enter) key = Qt::Key_Return;
        if (key == Qt::Key_Backtab) key = Qt::Key_Tab;
        for (auto mapping : special) if (mapping.qt == key) return QString::fromUcs4(&mapping.scalar, 1);
        if (key >= Qt::Key_F1 && key <= Qt::Key_F35) {
            const char32_t scalar = 0xf704 + key - Qt::Key_F1;
            return QString::fromUcs4(&scalar, 1);
        }
        if (key > 0 && key <= 0x10ffff) {
            const char32_t scalar = QChar::toLower(static_cast<char32_t>(key));
            return QString::fromUcs4(&scalar, 1);
        }
        return text;
    }
    void begin() {
        for (auto &binding : bindings) binding.target.clear();
    }
    static QKeySequence sequenceFor(const QString &character, int flags, bool mirror) {
        const auto scalars = character.normalized(QString::NormalizationForm_C).toUcs4();
        // Qt's key events expose Shift, Control, Alt, Meta and the keypad flag.
        if (scalars.size() != 1 || (flags & ~62) != 0) return {};
        Qt::KeyboardModifiers modifiers;
        if (flags & 2) modifiers |= Qt::ShiftModifier;
        if (flags & 4) modifiers |= Qt::ControlModifier;
        if (flags & 8) modifiers |= Qt::AltModifier;
        if (flags & 16) modifiers |= Qt::MetaModifier;
        if (flags & 32) modifiers |= Qt::KeypadModifier;
        return QKeySequence(QKeyCombination(modifiers, specialKey(scalars.first(), mirror)));
    }
    void add(QWidget *window, QAbstractButton *button, const QString &character, int flags, bool automatic) {
        if (auto *push = qobject_cast<QPushButton *>(button))
            push->setDefault(character == QStringLiteral("\r") && flags == 0);
        const auto sequence = sequenceFor(character, flags, automatic && button->isRightToLeft());
        if (!button->isEnabled() || sequence.isEmpty()) return;
        auto it = bindings.find(sequence);
        if (it == bindings.end()) {
            auto *shortcut = new QShortcut(sequence, window);
            it = bindings.insert(sequence, {shortcut, nullptr});
            QObject::connect(shortcut, &QShortcut::activated, window, [this, sequence] {
                const auto target = bindings.value(sequence).target;
                if (target && target->isEnabled() && target->isVisible()) target->click();
            });
        }
        // Registration follows the Swift view tree, including keyed collections.
        if (!it->target) it->target = button;
    }
    void finish() {
        for (auto it = bindings.begin(); it != bindings.end();) {
            if (it->target) { ++it; continue; }
            delete it->shortcut;
            it = bindings.erase(it);
        }
    }
};
